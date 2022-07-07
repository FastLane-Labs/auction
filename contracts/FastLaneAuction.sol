//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

// Until https://github.com/crytic/slither/issues/1226#issuecomment-1149340581 resolves
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

struct Bid {
    address validatorAddress;
    address opportunityAddress;
    address searcherContractAddress;
    address searcherPayableAddress;
    uint256 bidAmount;
}

enum statusType {
    INVALID, // 0
    VALIDATOR, // 1 
    OPPORTUNITY // 2
}


struct Status {
    uint128 activeAtAuction;
    uint128 inactiveAtAuction;
    statusType kind;  
}

struct ValidatorBalanceCheckpoint {
    // Deposits at {lastBidReceivedAuction}
    uint256 pendingBalanceAtlastBid;

    // Balance accumulated between {lastWithdrawnAuction} and {lastBidReceivedAuction}
    uint256 outstandingBalance;
    uint128 lastWithdrawnAuction;

    // Last auction a bid was received for this validator
    uint128 lastBidReceivedAuction;
}

struct ValidatorPreferences {
    uint256 minAutoshipAmount;
    address autoshipAddress;
}


abstract contract FastLaneEvents {
    /***********************************|
    |             Events                |
    |__________________________________*/

    event MaxLaneFeeSet(uint256 amount);
    event MinimumBidIncrementSet(uint256 amount);
    event FastLaneFeeSet(uint256 amount);
    event BidTokenSet(address indexed token);
    event PausedStateSet(bool state);
    event OpportunityAddressEnabled(
        address indexed opportunity,
        uint128 indexed auction_number
    );
    event OpportunityAddressDisabled(
        address indexed opportunity,
        uint128 indexed auction_number
    );
    event ValidatorAddressEnabled(
        address indexed validator,
        uint128 indexed auction_number
    );
    event ValidatorAddressDisabled(
        address indexed validator,
        uint128 indexed auction_number
    );
    event ValidatorWithdrawnBalance(
        address indexed validator,
        uint128 indexed auction_number,
        uint256 amount,
        address indexed caller

    );
    event AuctionStarted(uint128 indexed auction_number);

    event AuctionEnded(uint128 indexed auction_number);

    event WithdrawStuckERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
    event WithdrawStuckNativeToken(address indexed receiver, uint256 amount);
   
    event BidAdded(
        address bidder,
        address indexed validator,
        address indexed opportunity,
        uint256 amount,
        uint256 indexed auction_number
    );

    event ValidatorPreferencesSet(address indexed validator, uint256 minAutoshipAmount, address autoshipAddress);
}

contract FastLaneAuction is FastLaneEvents, Ownable, ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;


    IERC20 public bid_token;

    constructor(address initial_bid_token) {
        setBidToken(initial_bid_token);
    }

    //Variables mutable by owner via function calls
    // @audit Natspec everything
    uint256 public bid_increment = 10 * (10**18); //minimum bid increment in WMATIC
    uint256 public fast_lane_fee = 50000; //out of one million


    // Minimum for Validator Preferences
    uint256 public minFLShipBalance = 2000 * (10**18); // Validators balances > 2k should get auto-transfered

    uint128 public auction_number = 1;
    uint128 public constant MAX_AUCTION_VALUE = type(uint128).max; // 2**128 - 1
    uint16 public autopay_batch_size = 10;

    bool public auction_live = false;
    bool internal _paused;
    bool internal _offchain_checker_disabled = false;

    // Tracks status of seen addresses and when they become eligible for bidding
    mapping(address => Status) internal statusMap;

    mapping(uint256 => mapping(address => mapping(address => Bid)))
        internal auctionsMap;

    // Validators participating in the auction for a round
    mapping(uint128 => EnumerableSet.AddressSet) internal validatorsActiveAtAuction;

    // Validators cuts to be withdraw or dispatched regularly
    mapping(address => ValidatorBalanceCheckpoint) public validatorsCheckpoints;

    // Validator preferences for payment and min autoship amount
    mapping(address => ValidatorPreferences) public validatorsPreferences;

    // Auto cleared by EndAuction every round
    uint256 public outstandingFLBalance = 0;


    /***********************************|
    |         Validator-only            |
    |__________________________________*/

    function setValidatorPreferences(uint256 _minAutoshipAmount, address _autoshipAddress) external {
        require(_minAutoshipAmount > minFLShipBalance, "FL:E-203");
        require(_autoshipAddress != address(0), "FL:E-202");
        require(statusMap[msg.sender].kind == statusType.VALIDATOR, "FL:E-104");
        validatorsPreferences[msg.sender] = ValidatorPreferences(_minAutoshipAmount, _autoshipAddress);
        emit ValidatorPreferencesSet(msg.sender,_minAutoshipAmount, _autoshipAddress);
    }

    /***********************************|
    |             Owner-only            |
    |__________________________________*/

    function setPausedState(bool state) external onlyOwner {
        _paused = state;
        emit PausedStateSet(state);
    }

    // Set minimum bid increment to avoid people bidding up by .000000001
    function setMinimumBidIncrement(uint256 _bid_increment) external onlyOwner {
        bid_increment = _bid_increment;
        emit MinimumBidIncrementSet(_bid_increment);
    }

    // Set minimum balance
    function setMinimumFLShipBalance(uint256 _minAmount) external onlyOwner {
        minFLShipBalance = _minAmount;
    }

    // Set the protocol fee (out of 1000000 (ie v2 fee decimals)).
    // Initially set to 50000 (5%)
    function setFastlaneFee(uint256 _fastLaneFee)
        external
        onlyOwner
        notLiveStage
    {
        fast_lane_fee = _fastLaneFee;
        emit FastLaneFeeSet(_fastLaneFee);
    }

    // Set the ERC20 token that is treated as the base currency for bidding purposes.
    // Initially set to WMATIC
    function setBidToken(address _bid_token_address)
        public
        onlyOwner
        notLiveStage
    {
        bid_token = IERC20(_bid_token_address);
        emit BidTokenSet(_bid_token_address);
    }

    // Add an address to the opportunity address array.
    // Should be a router/aggregator etc.
    // Opportunities are queued to the next auction
    // Do not use on already enabled opportunity or it will be stopped for current auction round
    function enableOpportunityAddress(address opportunityAddress)
        external
        onlyOwner
    {
        // Enable for after auction ends if live
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;
        statusMap[opportunityAddress] = Status(target_auction_number, MAX_AUCTION_VALUE, statusType.OPPORTUNITY);
        emit OpportunityAddressEnabled(opportunityAddress, target_auction_number);
    }


    function disableOpportunityAddress(address opportunityAddress)
        external
        onlyOwner
    {
        Status storage existingStatus = statusMap[opportunityAddress];
        require(existingStatus.kind == statusType.OPPORTUNITY, "FL:E-105");
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;

        existingStatus.inactiveAtAuction = target_auction_number;
        emit OpportunityAddressDisabled(opportunityAddress, target_auction_number);
    }

    // Do not use on already enabled validator or it will be stopped for current auction round
    function enableValidatorAddress(address validatorAddress)
        external
        onlyOwner
    {
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;
        statusMap[validatorAddress] = Status(target_auction_number, MAX_AUCTION_VALUE, statusType.VALIDATOR);
        
        // Create the checkpoint for the Validator
        ValidatorBalanceCheckpoint memory valCheckpoint = validatorsCheckpoints[validatorAddress];
        if (valCheckpoint.lastBidReceivedAuction == 0) {
            validatorsCheckpoints[validatorAddress] = ValidatorBalanceCheckpoint(0, 0, 0, 0);
        } 
        emit ValidatorAddressEnabled(validatorAddress, target_auction_number);
    }

    //remove an address from the participating validator address array
    function disableValidatorAddress(address validatorAddress)
        external
        onlyOwner
    {
        Status storage existingStatus = statusMap[validatorAddress];
        require(existingStatus.kind == statusType.VALIDATOR, "FL:E-104");
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;

        existingStatus.inactiveAtAuction = target_auction_number;
        emit ValidatorAddressDisabled(validatorAddress, target_auction_number);
    }

    // Start auction / Enable bidding
    function startAuction() external onlyOwner notLiveStage {
        //enable bidding
        auction_live = true;
        emit AuctionStarted(auction_number);
    }

    function endAuction()
        external
        onlyOwner
        atLiveStage
        nonReentrant
        returns (bool)
    {

        auction_live = false;

        emit AuctionEnded(auction_number);

        // Increment auction_number so the checkpoints are available.
        auction_number++;

        uint256 ownerBalance = outstandingFLBalance;
        outstandingFLBalance = 0;

        //transfer to PFL the sorely needed $ to cover our high infra costs
        bid_token.safeTransferFrom(address(this), owner(), ownerBalance);

        return true;
    }

    function setAutopayBatchSize(uint16 size) external onlyOwner {
        autopay_batch_size = size;
    }

    function setOffchainCheckerDisabledState(bool state) external onlyOwner {
        _offchain_checker_disabled = state;
    }

    // @audit Assuming owner() is to become a multisig, maybe safer to emergency withdraw to owner, than add a receiver param
    function withdrawStuckNativeToken(uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (address(this).balance >= amount) {
            payable(owner()).sendValue(amount);
            emit WithdrawStuckNativeToken(address(this), amount);
        }
    }

    // @audit Deny bid token? If somehow the processing stage is stuck/unfinalized by owner the bids are lost
    function withdrawStuckERC20(address _tokenAddress)
        external
        onlyOwner
        nonReentrant
    {
        IERC20 oopsToken = IERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            bid_token.safeTransferFrom(address(this), owner(), oopsTokenBalance);
            emit WithdrawStuckERC20(address(this), owner(), oopsTokenBalance);
        }
    }

    function _receiveBid(
        Bid memory bid,
        uint256 currentTopBidAmount,
        address currentTopBidSearcherPayableAddress
    ) internal {
        // Verify the bid exceeds previous bid + minimum increment
        require(
            bid.bidAmount >= currentTopBidAmount + bid_increment,
            "FL:E-203"
        );

        // Verify the new bidder isnt the previous bidder as self-spam protection
        require(
            bid.searcherPayableAddress != currentTopBidSearcherPayableAddress,
            "FL:E-204"
        );

        // Verify the bidder has the balance.
        require(
            bid_token.balanceOf(bid.searcherPayableAddress) >= bid.bidAmount,
            "FL:E-206"
        );

        // Transfer the bid amount (requires approval)
        bid_token.safeTransferFrom(
            bid.searcherPayableAddress,
            address(this),
            bid.bidAmount
        );
    }

    function _refundPreviousBidder(Bid memory bid) internal {
        // Be very careful about changing bid token to any ERC777
        // Refund the previous top bid
        bid_token.safeTransferFrom(
            address(this),
            bid.searcherPayableAddress,
            bid.bidAmount
        );
    }

    function _calculateCuts(uint256 amount) internal view returns (uint256 vCut, uint256 flCut) {
        vCut = ((amount * 1000000) - fast_lane_fee) / 1000000;
        flCut = amount - vCut;
    }

    /***********************************|
    |             Public                |
    |__________________________________*/

    // Bidding function for searchers to submit their bids
    // Each bid pulls funds on submission and searchers are refunded when they are outbid
    function submitBid(Bid calldata bid)
        external
        atLiveStage
        whenNotPaused
        nonReentrant
    {
        // Verify that the bid is coming from the EOA that's paying
        require(msg.sender == bid.searcherPayableAddress, "FL:E-103");

        Status memory validatorStatus = statusMap[bid.validatorAddress];
        Status memory opportunityStatus = statusMap[bid.opportunityAddress];

        // Verify that the opportunity and the validator are both participating addresses
        require(validatorStatus.kind == statusType.VALIDATOR, "FL:E-104");
        require(opportunityStatus.kind == statusType.OPPORTUNITY, "FL:E-105");

        // Verify not flagged as inactive
        require(validatorStatus.inactiveAtAuction > auction_number, "FL:E-209");
        require(opportunityStatus.inactiveAtAuction > auction_number, "FL:E-210");

        // Verify still flagged active
        require(validatorStatus.activeAtAuction <= auction_number, "FL:E-211");
        require(opportunityStatus.activeAtAuction <= auction_number, "FL:E-212");

        // Figure out if we have an existing bid
        
        Bid memory current_top_bid = auctionsMap[auction_number][
                bid.validatorAddress
            ][bid.opportunityAddress];

        ValidatorBalanceCheckpoint storage valCheckpoint = validatorsCheckpoints[bid.validatorAddress];

        if ((valCheckpoint.lastBidReceivedAuction != auction_number) && (valCheckpoint.pendingBalanceAtlastBid > 0)) {
            // Need to move pending to outstanding
            valCheckpoint.outstandingBalance += valCheckpoint.pendingBalanceAtlastBid;
            valCheckpoint.pendingBalanceAtlastBid = 0;
        }
 
        // Update bid for pair
        auctionsMap[auction_number][bid.validatorAddress][
                bid.opportunityAddress
            ] = bid;

        if (current_top_bid.bidAmount > 0) {
            // Existing bid for this auction number && pair combo
            // Handle checkpoint cuts replacement
            (uint256 vCutPrevious, uint256 flCutPrevious) = _calculateCuts(current_top_bid.bidAmount);
            (uint256 vCut, uint256 flCut) = _calculateCuts(bid.bidAmount);

            outstandingFLBalance = outstandingFLBalance + flCut - flCutPrevious;
            valCheckpoint.pendingBalanceAtlastBid =  valCheckpoint.pendingBalanceAtlastBid + vCut - vCutPrevious;


            // Update the existing Bid mapping
            _receiveBid(
                bid,
                current_top_bid.bidAmount,
                current_top_bid.searcherPayableAddress
            );
            _refundPreviousBidder(current_top_bid);

           
        } else {
            // First bid on pair for this auction number
            // Update checkpoint if needed as another pair could have bid already for this auction number
            
            if (valCheckpoint.lastBidReceivedAuction != auction_number) {
                valCheckpoint.lastBidReceivedAuction = auction_number;
            }

            (uint256 vCutFirst, uint256 flCutFirst) = _calculateCuts(bid.bidAmount);

            // Handle cuts
            outstandingFLBalance += flCutFirst;
            valCheckpoint.pendingBalanceAtlastBid += vCutFirst;

             // Check balance
            _receiveBid(bid, 0, address(0));
            

        }

        // Try adding to the validatorsActiveAtAuction so the keeper can loop on it
        if (!validatorsActiveAtAuction[auction_number].contains(bid.validatorAddress)) {
            validatorsActiveAtAuction[auction_number].add(bid.validatorAddress);
        }

        emit BidAdded(
            bid.searcherContractAddress,
            bid.validatorAddress,
            bid.opportunityAddress,
            bid.bidAmount,
            auction_number
        );
    }


    // Validators can always withdraw right after an amount is due
    // It can be during an ongoing auction with pendingBalanceAtlastBid being the current auction
    // Or lastBidReceivedAuction being a previous auction, in which case outstanding+pending can be withdrawn
    function redeemOutstandingBalance(address outstandingValidatorWithBalance)
        external
        nonReentrant
    {
        require(statusMap[outstandingValidatorWithBalance].kind == statusType.VALIDATOR, "FL:E-104");
        ValidatorBalanceCheckpoint storage valCheckpoint = validatorsCheckpoints[outstandingValidatorWithBalance];
       
        // Either we have outstandingBalance or we have pendingBalanceAtlastBid from previous auctions.
        require(
               valCheckpoint.outstandingBalance > 0 || ((valCheckpoint.pendingBalanceAtlastBid > 0) && (valCheckpoint.lastBidReceivedAuction < auction_number)),
            "FL:E-207"
        );

        uint256 redeemable = 0;
        if (valCheckpoint.lastBidReceivedAuction < auction_number) {
            // We can redeem both
            redeemable = valCheckpoint.pendingBalanceAtlastBid + valCheckpoint.outstandingBalance;
            valCheckpoint.pendingBalanceAtlastBid = 0;
        } else {
            // Another bid was received in the current auction, profits were already moved
            // to outstandingBalance by the bidder
            redeemable = valCheckpoint.outstandingBalance;
        }

        // Clear outstanding in any case.
        valCheckpoint.outstandingBalance = 0;
        valCheckpoint.lastWithdrawnAuction = auction_number;


        bid_token.safeTransferFrom(
            address(this),
            outstandingValidatorWithBalance,
            redeemable
        );

        emit ValidatorWithdrawnBalance(
            outstandingValidatorWithBalance,
            auction_number,
            redeemable,
            msg.sender
        );
    }

    /***********************************|
    |       Public Resolvers            |
    |__________________________________*/

    /// @notice Gelato Offchain Resolver
    /// @dev Automated function checked each block offchain by Gelato Network if there is outstanding payments to process
    /// @return canExec - should the worker trigger
    /// @return execPayload - the payload if canExec is true
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        if (_offchain_checker_disabled || _paused  /*|| auction_live */) return (false, "");

        // Go workers go
            canExec = false;
            (
                bool hasJobs,
                address[] memory autopayRecipients
            ) = getAutopayJobs(autopay_batch_size, auction_number - 1);
            if (hasJobs) {
                canExec = true;
                execPayload = abi.encodeWithSelector(
                    this.processAutopayJobs.selector,
                    autopayRecipients
                );
                return (canExec, execPayload);
            }
        return (false, "");
    }

    function processAutopayJobs(address[] calldata autopayRecipients) external nonReentrant {
        // Recheck and Disperse.
    }

    function getAutopayJobs(uint256 batch_size, uint128 auction_index) public view returns (bool hasJobs, address[] memory autopayRecipients) {
        EnumerableSet.AddressSet storage prevRoundAddrSet = validatorsActiveAtAuction[auction_index];
        uint16 assigned = 0;
        uint256 len = prevRoundAddrSet.length();
        for (uint256 i = 0; i < len; i++) {
            address current_validator = prevRoundAddrSet.at(i);
            ValidatorBalanceCheckpoint memory valCheckpoint = validatorsCheckpoints[current_validator];
            if ((valCheckpoint.outstandingBalance >= validatorsPreferences[current_validator].minAutoshipAmount) && (valCheckpoint.outstandingBalance > minFLShipBalance)) {
                autopayRecipients[assigned++] = current_validator;
            }
            if (assigned >= batch_size) {
                break;
            }
        }
        hasJobs = autopayRecipients.length > 0;
    }



    /***********************************|
    |             Views                 |
    |__________________________________*/

    // Gets the status of an address
    function getStatus(address who) external view returns (Status memory) {
        return statusMap[who];
    }

    // Gets the auction number for which the fast lane privileges are active
    function getActivePrivilegesAuctionNumber() public view returns (uint128) {
        return auction_number - 1;
    }

    // Gets the checkpoint of an address
    function getCheckpoint(address who) external view returns (ValidatorBalanceCheckpoint memory) {
        return validatorsCheckpoints[who];
    }

    //function for determining the current top bid for an ongoing (live) auction
    function findLiveAuctionTopBid(address validatorAddress, address opportunityAddress)
        external
        view
        atLiveStage
        returns (uint256, uint256)
    {
            Bid memory topBid = auctionsMap[auction_number][
                validatorAddress
            ][opportunityAddress];
            return (topBid.bidAmount, auction_number);
    }

    function findFinalizedAuctionWinnerAtAuction(
        uint256 auction_index,
        address validatorAddress,
        address opportunityAddress
    ) public view
                returns (
            bool,
            address,
            uint256
        )
    {
        require(auction_index < auction_number,"FL-E:201");
        //get the winning searcher
        address winningSearcher = auctionsMap[auction_index][
            validatorAddress
        ][opportunityAddress].searcherContractAddress;

        //check if there is a winning searcher (no bids mean the winner is address(0))
        if (winningSearcher != address(0)) {
            return (true, winningSearcher, auction_index);
        } else {
            return (false, winningSearcher, auction_index);
        }
    }

    // Function for determining the winner of a completed auction
    function findLastFinalizedAuctionWinner(
        address validatorAddress,
        address opportunityAddress
    )
        external
        view
        returns (
            bool,
            address,
            uint256
        )
    {
        return findFinalizedAuctionWinnerAtAuction(getActivePrivilegesAuctionNumber(), validatorAddress, opportunityAddress);
    }

  /***********************************|
  |             Modifiers             |
  |__________________________________*/

    modifier notLiveStage() {
        require(!auction_live, "FL:E-301");
        _;
    }

    modifier atLiveStage() {
        require(auction_live, "FL:E-302");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "FL:E-101");
        _;
    }
}
