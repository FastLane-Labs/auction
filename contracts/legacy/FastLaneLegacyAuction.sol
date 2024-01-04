//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/utils/Address.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";


/// @notice Auction bid struct
/// @dev Current owners need to allow opportunity and validator addresses to participate beforehands
/// @param validatorAddress Validator selected for the bid
/// @param opportunityAddress Opportunity selected for the bid
/// @param searcherContractAddress Contract that will be submitting transactions to `opportunityAddress`
/// @param searcherPayableAddress Searcher submitting the bid (currently restricted to msg.sender)
/// @param bidAmount Value of the bid
struct Bid {
    address validatorAddress;
    address opportunityAddress;
    address searcherContractAddress;
    address searcherPayableAddress;
    uint256 bidAmount;
}

/// @notice The type of a Status struct validator or opportunity
enum statusType {
    INVALID, // 0
    VALIDATOR, // 1 
    OPPORTUNITY // 2
}

/// @notice Status of validator or opportunity
/// @dev Status cannot be flipped for the current round, an opportunity or validator set up as inactive will always be able to receive bids until the end of the round it was triggered.
/// @param activeAtAuctionRound Auction round where entity will be enabled
/// @param inactiveAtAuctionRound Auction round at which entity will be disabled
/// @param kind From {statusType} 
struct Status {
    uint128 activeAtAuctionRound;
    uint128 inactiveAtAuctionRound;
    statusType kind;  
}


/// @notice Validator Balance Checkpoint
/// @dev By default checkpoints are checked every block by ops to see if there is amount to be paid ( > minAmount or > minAmoutForValidator)
/// @param pendingBalanceAtlastBid Deposits at `lastBidReceivedAuction`
/// @param outstandingBalance Balance accumulated between `lastWithdrawnAuction` and `lastBidReceivedAuction`
/// @param lastWithdrawnAuction Round when the validator withdrew
/// @param lastBidReceivedAuction Last auction around a bid was received for this validator
struct ValidatorBalanceCheckpoint {
    uint256 pendingBalanceAtlastBid;
    uint256 outstandingBalance;
    uint128 lastWithdrawnAuction;
    uint128 lastBidReceivedAuction;
}

/// @notice Validator Balances Shipping Preferences
/// @dev minAutoshipAmount will always be superseeded by contract level minAutoShipThreshold if lower
/// @param minAutoshipAmount Validator desired autoship threshold 
/// @param validatorPayableAddress Validator desired payable address
struct ValidatorPreferences {
    uint256 minAutoshipAmount;
    address validatorPayableAddress;
}


abstract contract FastLaneEvents {
    /***********************************|
    |             Events                |
    |__________________________________*/

    event MinimumBidIncrementSet(uint256 amount);
    event FastLaneFeeSet(uint256 amount);
    event BidTokenSet(address indexed token);
    event PausedStateSet(bool state);
    event OpsSet(address ops);
    event MinimumAutoshipThresholdSet(uint128 amount);
    event ResolverMaxGasPriceSet(uint128 amount);
    event AutopayBatchSizeSet(uint16 batch_size);
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
        address destination,
        address indexed caller

    );
    event AuctionStarted(uint128 indexed auction_number);

    event AuctionEnded(uint128 indexed auction_number);

    event AuctionStarterSet(address indexed starter);

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

    event ValidatorPreferencesSet(address indexed validator, uint256 minAutoshipAmount, address validatorPayableAddress);

    error GeneralFailure();                            // E-000 // 0x2192efec

    error PermissionPaused();                          // E-101 // 0xeaa8b1af
    error PermissionNotOwner();                        // E-102 // 0xf599ea9e
    error PermissionOnlyFromPayorEoa();                // E-103 // 0x13272381
    error PermissionMustBeValidator();                 // E-104 // 0x4f4e9f3f
    error PermissionInvalidOpportunityAddress();       // E-105 // 0xcf440a8e
    error PermissionOnlyOps();                         // E-106 // 0x68da148f
    error PermissionNotOwnerNorStarter();              // E-107 // 0x8b4fb0bf
    error PermissionNotAllowed();                      // E-108 // 0xba6c5093

    error InequalityInvalidIndex();                    // E-201 // 0x102bd785
    error InequalityAddressMismatch();                 // E-202 // 0x17de231a
    error InequalityTooLow();                          // E-203 // 0x470b0adc
    error InequalityAlreadyTopBidder();                // E-204 // 0xeb14a775
    error InequalityNotEnoughFunds();                  // E-206 // 0x4587f24a
    error InequalityNothingToRedeem();                 // E-207 // 0x77a3b272
    error InequalityValidatorDisabledAtTime();         // E-209 // 0xa1ec46e6
    error InequalityOpportunityDisabledAtTime();       // E-210 // 0x8c81d8e9
    error InequalityValidatorNotEnabledYet();          // E-211 // 0x7a956c2e
    error InequalityOpportunityNotEnabledYet();        // E-212 // 0x333108d7
    error InequalityTooHigh();                         // E-213 // 0xfd11d092
    error InequalityWrongToken();                      // E-214 // 0xc9db890c

    error TimeNotWhenAuctionIsLive();                  // E-301 // 0x76a79c50
    error TimeNotWhenAuctionIsStopped();               // E-302 // 0x4eaf4896
    error TimeGasNotSuitable();                        // E-307 // 0xdd980aae
    error TimeAlreadyInit();                           // E-308 // 0xef34ca5c

}   

/// @title FastLaneAuction
/// @author Elyx0
/// @notice Fastlane.finance auction contract
contract FastLaneLegacyAuction is Initializable, OwnableUpgradeable , UUPSUpgradeable, ReentrancyGuard, FastLaneEvents {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeTransferLib for ERC20;

    ERC20 public bid_token;

    constructor(address _newOwner) {
        _transferOwnership(_newOwner);
        _disableInitializers();
    }

    function initialize(address _newOwner) public initializer {
        // __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(_newOwner);
    }

    function _authorizeUpgrade(address) internal virtual override onlyOwner() {}


    /// @notice Initializes the auction
    /// @dev Also sets bid increment, resolver max gas, fee, autoship and batch size.
    /// @param _initial_bid_token ERC20 address to use for the auction
    /// @param _ops Operators address for crontabs
    /// @param _starter Address allowed to start/stop rounds
    function initialSetupAuction(address _initial_bid_token, address _ops, address _starter) external onlyOwner {
        if (auctionInitialized) revert TimeAlreadyInit();
        setBidToken(_initial_bid_token);
        setOps(_ops);
        auction_number = 1;
        setMinimumBidIncrement(10* (10**18));
        setMinimumAutoShipThreshold(2000* (10**18));
        setResolverMaxGasPrice(200 gwei);
        setFastlaneFee(50000);
        setAutopayBatchSize(10); 
        setStarter(_starter);
        auctionInitialized = true;
    }

    /// @notice Gelato Ops Address
    address public ops;

    // Variables mutable by owner via function calls

    /// @notice Minimum bid increment required on top of from the current top bid for a pair
    uint256 public bid_increment = 10 * (10**18);


    /// @notice Minimum amount for Validator Preferences to get the profits airdropped
    uint128 public minAutoShipThreshold = 2000 * (10**18); // Validators balances > 2k should get auto-transfered

    /// @notice Current auction round, 
    /// @dev Offset by 1 so payouts are at 0. In general payouts are for round n-1.
    uint128 public auction_number = 1;

    uint128 public constant MAX_AUCTION_VALUE = type(uint128).max; // 2**128 - 1

    /// @notice Max gas price for ops to attempt autopaying pending balances over threshold
    uint128 public max_gas_price = 200 gwei;

    /// @notice Fee (out of one million)
    uint24 public fast_lane_fee = 50000; 

    /// @notice Number of validators to pay per gelato action
    uint16 public autopay_batch_size = 10;

    /// @notice Auction live status
    bool public auction_live = false;

    bool internal paused = false;

    /// @notice Ops crontab disabled
    bool internal _offchain_checker_disabled = false;

    /// @notice Tracks status of seen addresses and when they become eligible for bidding
    mapping(address => Status) internal statusMap;

    /// @notice Tracks bids per auction_number per pair
    mapping(uint256 => mapping(address => mapping(address => Bid)))
        internal auctionsMap;

    /// @notice Validators participating in the auction for a round
    mapping(uint128 => EnumerableSet.AddressSet) internal validatorsactiveAtAuctionRound;

    /// @notice Validators cuts to be withdraw or dispatched regularly
    mapping(address => ValidatorBalanceCheckpoint) internal validatorsCheckpoints;

    /// @notice Validator preferences for payment and min autoship amount
    mapping(address => ValidatorPreferences) internal validatorsPreferences;

    /// @notice Auto cleared by EndAuction every round
    uint256 public outstandingFLBalance = 0;

    /// @notice Start & Stop auction role
    address public auctionStarter;

    /// @notice Auction was initialized
    bool public auctionInitialized = false;

    /// @notice Internally updates a validator preference
    /// @dev Only callable by an already setup validator, and only for themselves via {setValidatorPreferences}
    /// @param _target Validator to update
    /// @param _minAutoshipAmount Amount desired before autoship kicks in
    /// @param _validatorPayableAddress Address the auction proceeds will go to for this validator
    function _updateValidatorPreferences(address _target, uint128 _minAutoshipAmount, address _validatorPayableAddress) internal {
        if(_minAutoshipAmount < minAutoShipThreshold) revert InequalityTooLow();
        if((_validatorPayableAddress == address(0)) || (_validatorPayableAddress == address(this))) revert InequalityAddressMismatch();
        
        validatorsPreferences[_target] = ValidatorPreferences(_minAutoshipAmount, _validatorPayableAddress);
        emit ValidatorPreferencesSet(_target,_minAutoshipAmount, _validatorPayableAddress);
    }

    /***********************************|
    |         Validator-only            |
    |__________________________________*/

    /// @notice Internally updates a validator preference
    /// @dev Only callable by an already setup validator via {onlyValidator}
    /// @param _minAutoshipAmount Amount desired before autoship kicks in
    /// @param _validatorPayableAddress Address the auction proceeds will go to for this validator
    function setValidatorPreferences(uint128 _minAutoshipAmount, address _validatorPayableAddress) external onlyValidator {
        _updateValidatorPreferences(msg.sender, _minAutoshipAmount, _validatorPayableAddress);
    }

    /***********************************|
    |             Owner-only            |
    |__________________________________*/

    /// @notice Defines the paused state of the Auction
    /// @dev Only owner
    /// @param _state New state
    function setPausedState(bool _state) external onlyOwner {
        paused = _state;
        emit PausedStateSet(_state);
    }

    /// @notice Sets minimum bid increment 
    /// @dev Used to avoid people micro-bidding up by .000000001
    /// @param _bid_increment New increment
    function setMinimumBidIncrement(uint256 _bid_increment) public onlyOwner {
        bid_increment = _bid_increment;
        emit MinimumBidIncrementSet(_bid_increment);
    }

    /// @notice Sets address of Ops
    /// @dev Ops is allowed to call {processAutopayJobs}
    /// @param _ops New operator of crontabs
    function setOps(address _ops) public onlyOwner {
        ops = _ops;
        emit OpsSet(_ops);
    }

    /// @notice Sets minimum balance a checkpoint must meet to be considered for autoship
    /// @dev This amount will always override validator preferences if greater
    /// @param _minAmount Minimum amount
    function setMinimumAutoShipThreshold(uint128 _minAmount) public onlyOwner {
        minAutoShipThreshold = _minAmount;
        emit MinimumAutoshipThresholdSet(_minAmount);
    }

    /// @notice Sets maximum network gas for autoship
    /// @dev Past this value autoship will have to be manually called until gwei goes lower or this gets upped
    /// @param _maxgas Maximum gas
    function setResolverMaxGasPrice(uint128 _maxgas) public onlyOwner {
        max_gas_price = _maxgas;
        emit ResolverMaxGasPriceSet(_maxgas);
    }

    /// @notice Sets the protocol fee (out of 1000000 (ie v2 fee decimals))
    /// @dev Initially set to 50000 (5%) For now we can't change the fee during an ongoing auction since the bids do not store the fee value at bidding time
    /// @param _fastLaneFee Protocl fee on bids
    function setFastlaneFee(uint24 _fastLaneFee)
        public
        onlyOwner
        notLiveStage
    {
        if (_fastLaneFee > 1000000) revert InequalityTooHigh();
        fast_lane_fee = _fastLaneFee;
        emit FastLaneFeeSet(_fastLaneFee);
    }

    /// @notice Sets the ERC20 token that is treated as the base currency for bidding purposes
    /// @dev Initially set to WMATIC, changing it is not allowed during auctions, special considerations must be taken care of if changing this value, such as paying all outstanding validators first to not mix ERC's.
    /// @param _bid_token_address Address of the bid token
    function setBidToken(address _bid_token_address)
        public
        onlyOwner
        notLiveStage
    {
        // Prevent QBridge Finance issues
        if (_bid_token_address == address(0)) revert GeneralFailure();
        bid_token = ERC20(_bid_token_address);
        emit BidTokenSet(_bid_token_address);
    }


    /// @notice Sets the auction starter role
    /// @dev Both owner and starter will be able to trigger starts/stops
    /// @param _starter Address of the starter role
    function setStarter(address _starter) public onlyOwner {
        auctionStarter = _starter;
        emit AuctionStarterSet(auctionStarter);
    }


    /// @notice Adds an address to the allowed entity mapping as opportunity
    /// @dev Should be a router/aggregator etc. Opportunities are queued to the next auction
    /// @dev Do not use on already enabled opportunity or it will be stopped for current auction round
    /// @param _opportunityAddress Address of the opportunity
    function enableOpportunityAddress(address _opportunityAddress)
        external
        onlyOwner
    {
        // Enable for after auction ends if live
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;
        statusMap[_opportunityAddress] = Status(target_auction_number, MAX_AUCTION_VALUE, statusType.OPPORTUNITY);
        emit OpportunityAddressEnabled(_opportunityAddress, target_auction_number);
    }

    /// @notice Disables an opportunity
    /// @dev If auction is live, only takes effect at next round
    /// @param _opportunityAddress Address of the opportunity
    function disableOpportunityAddress(address _opportunityAddress)
        external
        onlyOwner
    {
        Status storage existingStatus = statusMap[_opportunityAddress];
        if (existingStatus.kind != statusType.OPPORTUNITY) revert PermissionInvalidOpportunityAddress();
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;

        existingStatus.inactiveAtAuctionRound = target_auction_number;
        emit OpportunityAddressDisabled(_opportunityAddress, target_auction_number);
    }

    /// @notice Internal, enables a validator checkpoint
    /// @dev If auction is live, only takes effect at next round
    /// @param _validatorAddress Address of the validator
    function _enableValidatorCheckpoint(address _validatorAddress) internal {
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;
        statusMap[_validatorAddress] = Status(target_auction_number, MAX_AUCTION_VALUE, statusType.VALIDATOR);
        
        // Create the checkpoint for the Validator
        ValidatorBalanceCheckpoint memory valCheckpoint = validatorsCheckpoints[_validatorAddress];
        if (valCheckpoint.lastBidReceivedAuction == 0) {
            validatorsCheckpoints[_validatorAddress] = ValidatorBalanceCheckpoint(0, 0, 0, 0);
        } 
        emit ValidatorAddressEnabled(_validatorAddress, target_auction_number);
    }

    /// @notice Enables a validator checkpoint
    /// @dev If auction is live, only takes effect at next round
    /// @param _validatorAddress Address of the validator
    function enableValidatorAddress(address _validatorAddress)
        external
        onlyOwner
    {
       _enableValidatorCheckpoint(_validatorAddress);
    }

    /// @notice Enables a validator checkpoint and sets preferences
    /// @dev If auction is live, only takes effect at next round
    /// @param _validatorAddress Address of the validator
    /// @param _minAutoshipAmount Amount desired before autoship kicks in
    /// @param _validatorPayableAddress Address the auction proceeds will go to for this validator
    function enableValidatorAddressWithPreferences(address _validatorAddress, uint128 _minAutoshipAmount, address _validatorPayableAddress) 
        external
        onlyOwner
    {
            _enableValidatorCheckpoint(_validatorAddress);
            _updateValidatorPreferences(_validatorAddress, _minAutoshipAmount, _validatorPayableAddress);
    }

    /// @notice Disables a validator
    /// @dev If auction is live, only takes effect at next round
    /// @param _validatorAddress Address of the validator
    function disableValidatorAddress(address _validatorAddress)
        external
        onlyOwner
    {
        Status storage existingStatus = statusMap[_validatorAddress];
        if (existingStatus.kind != statusType.VALIDATOR) revert PermissionMustBeValidator();
        uint128 target_auction_number = auction_live ? auction_number + 1 : auction_number;

        existingStatus.inactiveAtAuctionRound = target_auction_number;
        emit ValidatorAddressDisabled(_validatorAddress, target_auction_number);
    }

    /// @notice Start auction round / Enable bidding
    /// @dev Both starter and owner roles are allowed to start
    function startAuction() external onlyStarterOrOwner notLiveStage {
        auction_live = true;
        emit AuctionStarted(auction_number);
    }

    /// @notice Ends an auction round
    /// @dev Ending an auction round transfers the cuts to PFL and enables validators to collect theirs from the auction that ended
    /// @dev Also enables fastlane privileges of pairs winners until endAuction gets called again at next auction round
    function endAuction()
        external
        onlyStarterOrOwner
        atLiveStage
        nonReentrant
        returns (bool)
    {

        auction_live = false;

        emit AuctionEnded(auction_number);

        // Increment auction_number so the checkpoints are available.
        ++auction_number;

        uint256 ownerBalance = outstandingFLBalance;
        outstandingFLBalance = 0;

        // Last for C-E-I.
        bid_token.safeTransfer(owner(), ownerBalance);

        return true;
    }

    /// @notice Sets autopay batch size
    /// @dev Defines the maximum number of addresses the ops will try to pay outstanding balances per block
    /// @param _size Size of the batch
    function setAutopayBatchSize(uint16 _size) public onlyOwner {
        autopay_batch_size = _size;
        emit AutopayBatchSizeSet(autopay_batch_size);
    }

    /// @notice Defines if the offchain checked is disabled
    /// @dev If true autoship will be disabled
    /// @param _state Disabled state
    function setOffchainCheckerDisabledState(bool _state) external onlyOwner {
        _offchain_checker_disabled = _state;
    }

    /// @notice Withdraws stuck matic
    /// @dev In the event people send matic instead of WMATIC we can send it back 
    /// @param _amount Amount to send to owner
    function withdrawStuckNativeToken(uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        if (address(this).balance >= _amount) {
            payable(owner()).sendValue(_amount);
            emit WithdrawStuckNativeToken(owner(), _amount);
        }
    }

    /// @notice Withdraws stuck ERC20
    /// @dev In the event people send ERC20 instead of bid_token ERC20 we can send them back 
    /// @param _tokenAddress Address of the stuck token
    function withdrawStuckERC20(address _tokenAddress)
        external
        onlyOwner
        nonReentrant
    {
        if (_tokenAddress == address(bid_token)) revert InequalityWrongToken();
        ERC20 oopsToken = ERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            oopsToken.safeTransfer(owner(), oopsTokenBalance);
            emit WithdrawStuckERC20(address(this), owner(), oopsTokenBalance);
        }
    }

    /// @notice Internal, receives a bid
    /// @dev Requires approval of this contract beforehands
    /// @param _currentTopBidAmount Value of the current top bid
    /// @param _currentTopBidSearcherPayableAddress Address of the current top bidder for that bid pair
    function _receiveBid(
        Bid memory bid,
        uint256 _currentTopBidAmount,
        address _currentTopBidSearcherPayableAddress
    ) internal {
        // Verify the bid exceeds previous bid + minimum increment
        if (bid.bidAmount < _currentTopBidAmount + bid_increment) revert InequalityTooLow();

        // Verify the new bidder isnt the previous bidder as self-spam protection
        if (bid.searcherPayableAddress == _currentTopBidSearcherPayableAddress) revert InequalityAlreadyTopBidder();

        // Verify the bidder has the balance.
        if (bid_token.balanceOf(bid.searcherPayableAddress) < bid.bidAmount) revert InequalityNotEnoughFunds();

        // Transfer the bid amount (requires approval)
        bid_token.safeTransferFrom(
            bid.searcherPayableAddress,
            address(this),
            bid.bidAmount
        );
    }

    /// @notice Internal, refunds previous top bidder
    /// @dev Be very careful about changing bid token to any ERC777
    /// @param bid Bid to refund
    function _refundPreviousBidder(Bid memory bid) internal {
        bid_token.safeTransfer(
            bid.searcherPayableAddress,
            bid.bidAmount
        );
    }

    /// @notice Internal, calculates cuts
    /// @dev vCut 
    /// @param amount Amount to calculates cuts from
    /// @return vCut validator cut
    /// @return flCut protocol cut
    function _calculateCuts(uint256 amount) internal view returns (uint256 vCut, uint256 flCut) {
        vCut = (amount * (1000000 - fast_lane_fee)) / 1000000;
        flCut = amount - vCut;
    }

    /// @notice Internal, calculates if a validator balance checkpoint is redeemable as of current auction_number against a certain amount
    /// @dev Not pure, depends of global auction_number, could be only outstandingBalance or outstandingBalance + pendingBalanceAtlastBid if last bid was at an oldest round than auction_number
    /// @param valCheckpoint Validator checkpoint to validate against `minAmount`
    /// @param minAmount Amount to calculates cuts from
    /// @return bool Is there balance to redeem for validator and amount at current auction_number
    function _checkRedeemableOutstanding(ValidatorBalanceCheckpoint memory valCheckpoint,uint256 minAmount) internal view returns (bool) {
        return valCheckpoint.outstandingBalance >= minAmount || ((valCheckpoint.lastBidReceivedAuction < auction_number) && ((valCheckpoint.pendingBalanceAtlastBid + valCheckpoint.outstandingBalance) >= minAmount));    
    }

    /// @notice Internal, attemps to redeem a validator outstanding balance to its validatorPayableAddress
    /// @dev Must be owed at least 1 of `bid_token`
    /// @param _outstandingValidatorWithBalance Validator address
    function _redeemOutstanding(address _outstandingValidatorWithBalance) internal {
        if (statusMap[_outstandingValidatorWithBalance].kind != statusType.VALIDATOR) revert PermissionMustBeValidator();
        ValidatorBalanceCheckpoint storage valCheckpoint = validatorsCheckpoints[_outstandingValidatorWithBalance];
       
        // Either we have outstandingBalance or we have pendingBalanceAtlastBid from previous auctions.
        if (!_checkRedeemableOutstanding(valCheckpoint, 1)) revert InequalityNothingToRedeem();

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

        address dst = _outstandingValidatorWithBalance;
        ValidatorPreferences memory valPrefs = validatorsPreferences[dst];
        if (valPrefs.validatorPayableAddress != address(0)) {
            dst = valPrefs.validatorPayableAddress;
        }

        bid_token.safeTransfer(
            dst,
            redeemable
        );

        emit ValidatorWithdrawnBalance(
            _outstandingValidatorWithBalance,
            auction_number,
            redeemable,
            dst,
            msg.sender
        );
    }

    /***********************************|
    |             Public                |
    |__________________________________*/


    /// @notice Bidding function for searchers to submit their bids
    /// @dev Each bid pulls funds on submission and searchers are refunded when they are outbid
    /// @param bid Bid struct as tuple (validatorAddress, opportunityAddress, searcherContractAddress ,searcherPayableAddress, bidAmount)
    function submitBid(Bid calldata bid)
        external
        atLiveStage
        whenNotPaused
        nonReentrant
    {
        // Verify that the bid is coming from the EOA that's paying
        if (msg.sender != bid.searcherPayableAddress) revert PermissionOnlyFromPayorEoa();

        Status memory validatorStatus = statusMap[bid.validatorAddress];
        Status memory opportunityStatus = statusMap[bid.opportunityAddress];

        // Verify that the opportunity and the validator are both participating addresses
        if (validatorStatus.kind != statusType.VALIDATOR) revert PermissionMustBeValidator();
        if (opportunityStatus.kind != statusType.OPPORTUNITY) revert PermissionInvalidOpportunityAddress();

        // We want auction_number be in the [activeAtAuctionRound - inactiveAtAuctionRound] window.
        // Verify not flagged as inactive
        if (validatorStatus.inactiveAtAuctionRound <= auction_number) revert InequalityValidatorDisabledAtTime();
        if (opportunityStatus.inactiveAtAuctionRound <= auction_number) revert InequalityOpportunityDisabledAtTime();

        // Verify still flagged active
        if (validatorStatus.activeAtAuctionRound > auction_number) revert InequalityValidatorNotEnabledYet();
        if (opportunityStatus.activeAtAuctionRound > auction_number) revert InequalityOpportunityNotEnabledYet();


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

        // Try adding to the validatorsactiveAtAuctionRound so the keeper can loop on it
        // EnumerableSet already checks key pre-existence
        validatorsactiveAtAuctionRound[auction_number].add(bid.validatorAddress);

        emit BidAdded(
            bid.searcherContractAddress,
            bid.validatorAddress,
            bid.opportunityAddress,
            bid.bidAmount,
            auction_number
        );
    }

    /// @notice Validators can always withdraw right after an amount is due
    /// @dev It can be during an ongoing auction with pendingBalanceAtlastBid being the current auction
    /// @dev Or lastBidReceivedAuction being a previous auction, in which case outstanding+pending can be withdrawn
    /// @dev _Anyone_ can initiate a validator to be paid what it's owed
    /// @param _outstandingValidatorWithBalance Redeems outstanding balance for a validator
    function redeemOutstandingBalance(address _outstandingValidatorWithBalance)
        external
        whenNotPaused
        nonReentrant
    {
        _redeemOutstanding(_outstandingValidatorWithBalance);
    }

    /***********************************|
    |       Public Resolvers            |
    |__________________________________*/

    /// @notice Gelato Offchain Resolver
    /// @dev Automated function checked each block offchain by Gelato Network if there is outstanding payments to process
    /// @return canExec Should the worker trigger
    /// @return execPayload The payload if canExec is true
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        if (_offchain_checker_disabled || paused  || tx.gasprice > max_gas_price) return (false, "");
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

    /// @notice Processes a list of addresses to transfer their outstanding balance
    /// @dev Genrally called by Ops with array length of autopay_batch_size
    /// @param autopayRecipients Array of recipents to consider for autopay
    function processAutopayJobs(address[] calldata autopayRecipients) external nonReentrant onlyOwnerStarterOps {
        // Reassert checks if insane spike between gelato trigger and tx picked up
        if (_offchain_checker_disabled || paused) revert PermissionPaused();
        if (tx.gasprice > max_gas_price) revert TimeGasNotSuitable();

        uint length = autopayRecipients.length;
        for (uint i = 0;i < length;) {
            if (autopayRecipients[i] != address(0)) {
                _redeemOutstanding(autopayRecipients[i]);
            }
            unchecked { ++i; }
        }
    }

    /***********************************|
    |             Views                 |
    |__________________________________*/

    /// @notice Returns if there is autopays to be done for given `_auction_index`
    /// @dev  Most likely called off chain by Gelato
    /// @param _batch_size Max recipients to return
    /// @param _auction_index Auction round
    /// @return hasJobs If there was jobs found to be done by ops
    /// @return autopayRecipients List of addresses eligible to be paid
    function getAutopayJobs(uint16 _batch_size, uint128 _auction_index) public view returns (bool hasJobs, address[] memory autopayRecipients) {
        autopayRecipients = new address[](_batch_size); // Filled with 0x0
        // An active validator means a bid happened so potentially balances were moved to outstanding while the bid happened
        EnumerableSet.AddressSet storage prevRoundAddrSet = validatorsactiveAtAuctionRound[_auction_index];
        uint16 assigned = 0;
        uint256 len = prevRoundAddrSet.length();
        for (uint256 i = 0; i < len; i++) {
            address current_validator = prevRoundAddrSet.at(i);
            ValidatorBalanceCheckpoint memory valCheckpoint = validatorsCheckpoints[current_validator];
            uint256 minAmountForValidator = minAutoShipThreshold >= validatorsPreferences[current_validator].minAutoshipAmount ? minAutoShipThreshold : validatorsPreferences[current_validator].minAutoshipAmount;
            if (_checkRedeemableOutstanding(valCheckpoint, minAmountForValidator)) {
                autopayRecipients[assigned] = current_validator;
                ++assigned;
            }
            if (assigned >= _batch_size) {
                break;
            }
        }
        hasJobs = assigned > 0;
    }

    /// @notice Gets the status of an address
    /// @dev Contains (activeAtAuctionRound, inactiveAtAuctionRound, statusType)
    /// @param _who Address we want the status of
    /// @return Status Status of the given address
    function getStatus(address _who) external view returns (Status memory) {
        return statusMap[_who];
    }

    /// @notice Gets the validators involved with a given auction
    /// @dev validatorsactiveAtAuctionRound being an EnumerableSet
    /// @param _auction_index Auction Round
    /// @return Array of validator addresses that received a bid during round `_auction_index`
    function getValidatorsactiveAtAuctionRound(uint128 _auction_index) external view returns (address[] memory) {
        return validatorsactiveAtAuctionRound[_auction_index].values();
    }


    /// @notice Gets the auction number for which the fast lane privileges are active
    /// @return auction round
    function getActivePrivilegesAuctionNumber() public view returns (uint128) {
        return auction_number - 1;
    }

    /// @notice Gets the checkpoint of an address
    /// @param _who Address we want the checkpoint of
    /// @return Validator checkpoint
    function getCheckpoint(address _who) external view returns (ValidatorBalanceCheckpoint memory) {
        return validatorsCheckpoints[_who];
    }
 
    /// @notice Gets the preferences of an address
    /// @param _who Address we want the preferences of
    /// @return Validator preferences
    function getPreferences(address _who) external view returns (ValidatorPreferences memory) {
        return validatorsPreferences[_who];
    }

    /// @notice Determines the current top bid of a pair for the current ongoing (live) auction
    /// @param _validatorAddress Validator for the given pair
    /// @param _opportunityAddress Opportunity for the given pair
    /// @return Tuple (bidAmount, auction_round)
    function findLiveAuctionTopBid(address _validatorAddress, address _opportunityAddress)
        external
        view
        atLiveStage
        returns (uint256, uint128)
    {
            Bid memory topBid = auctionsMap[auction_number][
                _validatorAddress
            ][_opportunityAddress];
            return (topBid.bidAmount, auction_number);
    }

    /// @notice Returns the top bid of a past auction round for a given pair
    /// @param _auction_index Auction round
    /// @param _validatorAddress Validator for the given pair
    /// @param _opportunityAddress Opportunity for the given pair
    /// @return Tuple (true|false, winningSearcher, auction_index)
    function findFinalizedAuctionWinnerAtAuction(
        uint128 _auction_index,
        address _validatorAddress,
        address _opportunityAddress
    ) public view
                returns (
            bool,
            address,
            uint128
        )
    {
        if (_auction_index >= auction_number) revert InequalityInvalidIndex();
        // Get the winning searcher
        address winningSearcher = auctionsMap[_auction_index][
            _validatorAddress
        ][_opportunityAddress].searcherContractAddress;

        // Check if there is a winning searcher (no bids mean the winner is address(0))
        if (winningSearcher != address(0)) {
            return (true, winningSearcher, _auction_index);
        } else {
            return (false, winningSearcher, _auction_index);
        }
    }

    /// @notice Returns the the winner of the last completed auction for a given pair
    /// @param _validatorAddress Validator for the given pair
    /// @param _opportunityAddress Opportunity for the given pair
    /// @return Tuple (true|false, winningSearcher, auction_index)
    function findLastFinalizedAuctionWinner(
        address _validatorAddress,
        address _opportunityAddress
    )
        external
        view
        returns (
            bool,
            address,
            uint128
        )
    {
        return findFinalizedAuctionWinnerAtAuction(getActivePrivilegesAuctionNumber(), _validatorAddress, _opportunityAddress);
    }

  /***********************************|
  |             Modifiers             |
  |__________________________________*/

    modifier notLiveStage() {
        if (auction_live) revert TimeNotWhenAuctionIsLive();
        _;
    }

    modifier atLiveStage() {
        if (!auction_live) revert TimeNotWhenAuctionIsStopped();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert PermissionPaused();
        _;
    }

    modifier onlyValidator() {
        if(statusMap[msg.sender].kind != statusType.VALIDATOR) revert PermissionMustBeValidator();
        _;
    }

    modifier onlyOwnerStarterOps() {
        if (msg.sender != ops && msg.sender != auctionStarter && msg.sender != owner()) revert PermissionOnlyOps();
        _;
    }

    modifier onlyStarterOrOwner() {
        if (msg.sender != auctionStarter && msg.sender != owner()) revert PermissionNotOwnerNorStarter();
        _;
    }
}
