//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

struct Bid {
    address validatorAddress;
    address opportunityAddress;
    address searcherContractAddress;
    address searcherPayableAddress; // perhaps remove this - just require the bidding EOA to pay
    uint256 bidAmount;
}

struct InitializedAddress {
    address _address;
    bool _isInitialized;
}

struct InitializedIndexAddress {
    address _address;
    bool _previouslyInitialized;
    uint256 _index;
    bool _isInitialized;
}

contract FastLaneAuction is Ownable {

    using Address for address payable;
    using SafeERC20 for IERC20;

    IERC20 public bid_token;

    constructor(address initial_bid_token) {
        setBidToken(initial_bid_token);
    }

    //Variables mutable by owner via function calls
    // @audit Natspec everything
    uint256 public bid_increment = 10 * (10**18); //minimum bid increment in WMATIC
    uint256 public fast_lane_fee = 50000; //out of one million

    uint256 public auction_number = 0;
    uint128 public processing_batch_size = 100;
    bool public auction_live = false;
    bool public processing_ongoing = false;
    bool internal _paused;
    //array and map declarations


    address[] internal opportunityAddressList;
    mapping(address => InitializedIndexAddress) internal opportunityAddressMap;

    address[] internal validatorAddressList;
    mapping(address => InitializedIndexAddress) internal validatorAddressMap;

    mapping(uint256 => mapping(address => mapping(address => Bid)))
        internal currentAuctionMap;

    mapping(uint256 => mapping(address => InitializedAddress))
        internal currentInitializedValidatorsMap;

    mapping(uint256 => mapping(address => mapping(address => InitializedAddress)))
        internal currentInitializedValOppMap;

    mapping(uint256 => address[]) internal currentValidatorsArrayMap;
    mapping(uint256 => uint256) internal currentValidatorsCountMap;

    mapping(uint256 => mapping(address => address[]))
        internal currentPairsArrayMap;
    mapping(uint256 => mapping(address => uint256))
        internal currentPairsCountMap;

    mapping(uint256 => mapping(address => mapping(address => address)))
        internal auctionResultsMap;

    // Validators cuts to be withdraw or dispatched regularly
    mapping(address => uint256) public outstandingValidatorsBalance;
    uint256 public outstandingFLBalance;

    /***********************************|
    |             Events                |
    |__________________________________*/

    event MaxLaneFeeSet(uint256 amount);
    event MinimumBidIncrementSet(uint256 amount);
    event FastLaneFeeSet(uint256 amount);
    event BidTokenSet(address indexed token);
    event PausedStateSet(bool state);
    event OpportunityAddressAdded(address indexed router);
    event OpportunityAddressRemoved(address indexed router);
    event ValidatorAddressAdded(address indexed validator);
    event ValidatorAddressRemoved(address indexed validator);
    event ValidatorAddedBalance(address indexed validator, uint256 amount);
    event ValidatorWithdrawnBalance(address indexed validator, uint256 amount, address indexed caller);
    event AuctionStarted(uint256 indexed auction_number);
    event AuctionProcessingBiddingStopped(uint256 indexed auction_number);
    event AuctionPartiallyProcessed(uint256 indexed auction_number, address indexed validator, address opportunity, address indexed searcher);
    event AuctionEnded(uint256 indexed auction_number, uint256 amount);
    event WithdrawStuckERC20(address indexed receiver, address indexed token, uint256 amount);
    event WithdrawStuckNativeToken(address indexed receiver, uint256 amount);
    event BidAdded(address indexed bidder, address indexed validator, address indexed opportunity, uint256 amount, uint256 auction_number);
   
    /***********************************|
    |             Owner-only            |
    |__________________________________*/

    function setPausedState(bool state) external onlyOwner {
        _paused = state;
        emit PausedStateSet(state);
    }

    //set minimum bid increment to avoid people bidding up by .000000001
    function setMinimumBidIncrement(uint256 _bid_increment) public onlyOwner {
        bid_increment = _bid_increment;
        emit MinimumBidIncrementSet(_bid_increment);
    }

    //set the protocol fee (out of 1000000 (ie v2 fee decimals)).
    //Initially set to 50000 (5%)
    function setFastlaneFee(uint256 _fastLaneFee)
        public
        onlyOwner
        notLiveStage
    {
        fast_lane_fee = _fastLaneFee;
        emit FastLaneFeeSet(_fastLaneFee);
    }

    //set the ERC20 token that is treated as the base currency for bidding purposes.
    //Initially set to WMATIC
    function setBidToken(address _bid_token_address) public onlyOwner notLiveStage notProcessingStage {
        bid_token = IERC20(_bid_token_address);
        emit BidTokenSet(_bid_token_address);
    }

    //add an address to the opportunity address array.
    //Should be a router/aggregator etc.
    // @audit Adding any time can be a problem
    function addOpportunityAddressToList(address opportunityAddress)
        public
        onlyOwner
        notProcessingStage
    {
        InitializedIndexAddress memory oldData = opportunityAddressMap[
            opportunityAddress
        ];

        if (oldData._previouslyInitialized == true) {
            opportunityAddressList[oldData._index] = opportunityAddress;
            opportunityAddressMap[opportunityAddress] = InitializedIndexAddress(
                opportunityAddress,
                true,
                oldData._index,
                true
            );
        } else {
            opportunityAddressList.push(opportunityAddress);
            uint256 listLength = opportunityAddressList.length;
            opportunityAddressMap[opportunityAddress] = InitializedIndexAddress(
                opportunityAddress,
                true,
                listLength,
                true
            );
        }
        emit OpportunityAddressAdded(opportunityAddress);
    }

    //remove an address from the opportunity address array
    function removeOpportunityAddressFromList(address opportunityAddress)
        public
        onlyOwner
        notLiveStage
    {
        InitializedIndexAddress memory oldData = opportunityAddressMap[
            opportunityAddress
        ];

        delete opportunityAddressList[oldData._index];

        //remove the opportunity address from the array of participating validators
        opportunityAddressMap[opportunityAddress] = InitializedIndexAddress(
            opportunityAddress,
            true,
            oldData._index,
            false
        );
        emit OpportunityAddressRemoved(opportunityAddress);
    }

    //add an address to the participating validator address array
    function addValidatorAddressToList(address validatorAddress) public onlyOwner {

        //see if its a reinit
        InitializedIndexAddress memory oldData = validatorAddressMap[
            validatorAddress
        ];

        if (oldData._previouslyInitialized == true) {
            validatorAddressList[oldData._index] = validatorAddress;
            validatorAddressMap[validatorAddress] = InitializedIndexAddress(
                validatorAddress,
                true,
                oldData._index,
                true
            );
        } else {
            validatorAddressList.push(validatorAddress);
            uint256 listLength = validatorAddressList.length;
            validatorAddressMap[validatorAddress] = InitializedIndexAddress(
                validatorAddress,
                true,
                listLength,
                true
            );
        }
        emit ValidatorAddressAdded(validatorAddress);
    }

    //remove an address from the participating validator address array
    function removeValidatorAddressFromList(address validatorAddress) public onlyOwner notLiveStage {

        InitializedIndexAddress memory oldData = validatorAddressMap[
            validatorAddress
        ];

        delete validatorAddressList[oldData._index];

        //remove the validator address from the array of participating validators
        validatorAddressMap[validatorAddress] = InitializedIndexAddress(
            validatorAddress,
            true,
            oldData._index,
            false
        );
        emit ValidatorAddressRemoved(validatorAddress);
    }

    //start auction / enable bidding
    //note that this also cleans out the bid history for the previous auction
    function startAuction() external onlyOwner notLiveStage notProcessingStage {

        // increment up the auction_count number
        auction_number++;

        // set initialized validators
        currentValidatorsCountMap[auction_number] = 0;

        //enable bidding
        auction_live = true;

        emit AuctionStarted(auction_number);
    }

    function stopBidding() external onlyOwner atLiveStage {
        //disable bidding
        auction_live = false;

        //enable result processing
        processing_ongoing = true;

        emit AuctionProcessingBiddingStopped(auction_number);
    }

    // @audit What to do if a pair is locked forever
    function endAuction() external onlyOwner notLiveStage atProcessingStage returns (bool) {

        // make sure all pairs have been processed first
        if (currentValidatorsCountMap[auction_number] < 1) {
            //transfer to PFL the sorely needed $ to cover our high infra costs
            bid_token.transferFrom(
                address(this),
                owner(),
                outstandingFLBalance
            );

           
            emit AuctionEnded(auction_number, outstandingFLBalance);

            outstandingFLBalance = 0;
            processing_ongoing = false;
            
            return true;
        } else {
            return false;
        }
    }

    function setProcessingBatchSize(uint256 size) external onlyOwner {
        processing_batch_size = size;
    }

    // @audit Assuming owner() is to become a multisig, maybe safer to emergency withdraw to owner, than add a receiver param
    function withdrawStuckNativeToken(uint256 amount) external onlyOwner {
        if (address(this).balance >= amount) {
            payable(owner()).sendValue(amount);
            emit WithdrawStuckNativeToken(address(this), amount);
        }
    }
    
    // @audit Deny bid token? If somehow the processing stage is stuck/unfinalized by owner the bids are lost
    function withdrawStuckERC20(address _tokenAddress) external onlyOwner {

        IERC20 oopsToken = IERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            bid_token.transferFrom(address(this), owner(), oopsTokenBalance);
            emit WithdrawStuckERC20(address(this), owner(), oopsTokenBalance);
        }
    }

    /***********************************|
    |             Public                |
    |__________________________________*/

    //bidding function for searchers to submit their bids
    //note that each bid pulls funds on submission and that searchers are refunded when they are outbid
    function submitBid(Bid calldata bid) external atLiveStage whenNotPaused returns (bool) {

        //verify that the bid is coming from the EOA that's paying
        require(
            msg.sender == bid.searcherPayableAddress,
            "FL:E-103"
        );

        //verify that the opportunity and the validator are both participating addresses
        require(
            validatorAddressMap[bid.validatorAddress]._isInitialized == true,
            "FL:E-104"
        );
        require(
            opportunityAddressMap[bid.opportunityAddress]._isInitialized ==
                true,
            "FL:E-105"
        );

        //Determine if pair is initialized
        bool is_validator_initialized = currentInitializedValidatorsMap[
            auction_number
        ][bid.validatorAddress]._isInitialized;

        bool is_opportunity_initialized;
        if (is_validator_initialized) {
            is_opportunity_initialized = currentInitializedValOppMap[
                auction_number
            ][bid.validatorAddress][bid.opportunityAddress]._isInitialized;
        } else {
            is_opportunity_initialized = false;
        }

        if (is_validator_initialized && is_opportunity_initialized) {
            Bid memory current_top_bid = currentAuctionMap[auction_number][
                bid.validatorAddress
            ][bid.opportunityAddress];

            //verify the bid exceeds previous bid + minimum increment
            // @todo Discuss bid_increment() as a function to improve increment logic
            require(
                bid.bidAmount >= current_top_bid.bidAmount + bid_increment,
                "FL:E-203"
            );

            // @todo Discuss
            //verify the new bidder isnt the previous bidder
            require(
                bid.searcherPayableAddress !=
                    current_top_bid.searcherPayableAddress,
                "FL:E-204"
            );

            //verify the bidder has the balance.
            require(
                bid_token.balanceOf(bid.searcherPayableAddress) >=
                    bid.bidAmount,
                "FL:E-206"
            );

            uint256 balanceBefore = bid_token.balanceOf(address(this));
            //transfer the bid amount (requires approval)
            bid_token.transferFrom(
                bid.searcherPayableAddress,
                address(this),
                bid.bidAmount
            );

            // @audit TBD if balanceBefore + after checks are actual needed with native chain tokens
            require(
                bid_token.balanceOf(address(this)) ==
                    balanceBefore + bid.bidAmount,
                "FL:E-207"
            );

            balanceBefore = bid_token.balanceOf(address(this));

            // @audit ERC20 transfers of wMatic are safe
            // be very careful about changing bid token to any ERC777
            // refund the previous top bid
            bid_token.transferFrom(
                address(this),
                current_top_bid.searcherPayableAddress,
                current_top_bid.bidAmount
            );

             // @audit TBD if balanceBefore + after checks are actual needed with native chain tokens

            require(
                bid_token.balanceOf(address(this)) ==
                    balanceBefore + bid.bidAmount - current_top_bid.bidAmount,
                "FL:E-207"
            );

            //update the existing Bid mapping
            currentAuctionMap[auction_number][bid.validatorAddress][
                bid.opportunityAddress
            ] = bid;

            return true;
        } else {
            //verify the bidder has the balance.
            require(
                bid_token.balanceOf(bid.searcherPayableAddress) >=
                    bid.bidAmount,
                "FL:E-207"
            );

            uint256 balanceBefore = bid_token.balanceOf(address(this));

            //transfer the bid amount
            bid_token.transferFrom(
                bid.searcherPayableAddress,
                address(this),
                bid.bidAmount
            );
            require(
                bid_token.balanceOf(address(this)) ==
                    balanceBefore + bid.bidAmount,
                "FL:E-207"
            );

            // flag the validator / opportunity combination as initialized
            if (is_validator_initialized == false) {
                currentInitializedValidatorsMap[auction_number][
                    bid.validatorAddress
                ] = InitializedAddress(bid.validatorAddress, true);
                currentValidatorsArrayMap[auction_number].push(
                    bid.validatorAddress
                );
                // @audit Check increment
                currentValidatorsCountMap[auction_number]++;
                currentPairsCountMap[auction_number][bid.validatorAddress] = 0;
            }

            if (is_opportunity_initialized == false) {
                currentInitializedValOppMap[auction_number][
                    bid.validatorAddress
                ][bid.opportunityAddress] = InitializedAddress(
                    bid.opportunityAddress,
                    true
                );
                currentPairsArrayMap[auction_number][bid.validatorAddress].push(
                        bid.opportunityAddress
                    );
                currentPairsCountMap[auction_number][bid.validatorAddress]++;
            }

            //add the bid mapping
            currentAuctionMap[auction_number][bid.validatorAddress][
                bid.opportunityAddress
            ] = bid;

            emit BidAdded(bid.searcherContractAddress, bid.validatorAddress, bid.opportunityAddress, bid.bidAmount, auction_number);
            return true;
        }
    }

    //process auction results for a specific validator/opportunity pair. Cant do loops on all pairs due to size.
    //use view-only functions to get arrays of unprocessed pairs to submit as args for this function.
    function processPartialAuctionResults(
        address _validatorAddress,
        address _opportunityAddress
    ) external notLiveStage atProcessingStage returns (bool isSuccessful) {

        //make sure the pair hasnt already been processed
        require(
            currentInitializedValidatorsMap[auction_number][_validatorAddress]
                ._isInitialized == true,
            "FL:E-304"
        );
        require(
            currentInitializedValOppMap[auction_number][_validatorAddress][
                _opportunityAddress
            ]._isInitialized == true,
            "FL:E-305"
        );

        //find top bid for pairing
        Bid memory top_user_bid = currentAuctionMap[auction_number][
            _validatorAddress
        ][_opportunityAddress];

        require(
            top_user_bid.validatorAddress == _validatorAddress,
            "FL:E-202"
        );

        // mark things already updated
        if (currentPairsCountMap[auction_number][_validatorAddress] > 1) {
            //increment it down
            //the pairs / validator count maps are to make sure we dont miss payment on any validators before collecting the PFL fee
            currentPairsCountMap[auction_number][_validatorAddress]--;
        } else if (
            currentPairsCountMap[auction_number][_validatorAddress] == 1
        ) {
            if (currentValidatorsCountMap[auction_number] > 1) {
                currentValidatorsCountMap[auction_number]--;
                isSuccessful = true;
            } else if (currentValidatorsCountMap[auction_number] == 1) {
                currentValidatorsCountMap[auction_number] = 0;
                isSuccessful = true;
            } else {
                isSuccessful = false;
            }

            if (isSuccessful == true) {
                //since this is the last opp for this validator, uninitialize the validator from the current round's validator map
                currentInitializedValidatorsMap[auction_number][
                    _validatorAddress
                ] = InitializedAddress(_validatorAddress, false);
                currentPairsCountMap[auction_number][_validatorAddress] = 0;
            }
        } else {
            isSuccessful = false;
        }

        if (isSuccessful == true) {
            //mark it already updated
            currentInitializedValOppMap[auction_number][_validatorAddress][
                _opportunityAddress
            ] = InitializedAddress(_opportunityAddress, false);

            //handle the cuts
            uint256 cut = ((top_user_bid.bidAmount * 1000000) - fast_lane_fee) / 1000000;
            outstandingValidatorsBalance[top_user_bid.validatorAddress] += cut;
            emit ValidatorAddedBalance(top_user_bid.validatorAddress, cut);

            //update the auction results map
            auctionResultsMap[auction_number][_validatorAddress][
                _opportunityAddress
            ] = top_user_bid.searcherContractAddress;

            emit AuctionPartiallyProcessed(auction_number, _validatorAddress, _opportunityAddress, top_user_bid.searcherContractAddress);
        }

        return isSuccessful;
    }

    function redeemOutstandingBalance(address outstandingValidatorWithBalance) external {

        require(outstandingValidatorWithBalance != address(0), "FL-E-202");
        require(outstandingValidatorsBalance[outstandingValidatorWithBalance] > 0, "FL:E-207");

        uint256 outstandingAmount = outstandingValidatorsBalance[outstandingValidatorWithBalance];
        outstandingValidatorsBalance[outstandingValidatorWithBalance] = 0;

        bid_token.transferFrom(
            address(this),
            outstandingValidatorWithBalance,
            outstandingAmount
        );

        emit ValidatorWithdrawnBalance(outstandingValidatorWithBalance, outstandingAmount, msg.sender);
    }


    /***********************************|
    |             Resolvers             |
    |__________________________________*/

    /// @notice Gelato Offchain Resolver
    /// @dev Automated function checked each block by Gelato Network if there is a processing auction to finalize
    /// @return {bool} canExec - should the worker trigger, {bytes} execPayload - the payload if canExec is true
    function checker() external view returns (bool canExec, bytes memory execPayload)  {
        if (_paused || auction_live) return (false, "");
        
        // Go workers go
        if (processing_ongoing) {
            canExec = false;
            (hasJobs, _validatorsJobsList, _opportunitiesJobsList) = getPendingProcessingJobs();
            if (hasJobs) {
                canExec = true;
                execPayload = abi.encodeWithSelector(this.processPartialAuctionBatch.selector,_validatorsJobsList, _opportunitiesJobsList);
                return (canExec, execPayload);
            }
        }
        return (false, "");
    }


    /***********************************|
    |             Views                 |
    |__________________________________*/

    //function for determining the current top bid for an ongoing (live) auction
    function findTopBid(address validatorAddress, address opportunityAddress)
        public
        view
        returns (bool, uint256)
    {
        //Determine if pair is initialized
        bool is_validator_initialized = currentInitializedValidatorsMap[
            auction_number
        ][validatorAddress]._isInitialized;

        bool is_opportunity_initialized;

        if (is_validator_initialized) {
            is_opportunity_initialized = currentInitializedValOppMap[
                auction_number
            ][validatorAddress][opportunityAddress]._isInitialized;
        } else {
            is_opportunity_initialized = false;
        }

        //if it is initialized, grab the top bid amount from the bid struct
        if (is_validator_initialized && is_opportunity_initialized) {
            Bid memory topBid = currentAuctionMap[auction_number][
                validatorAddress
            ][opportunityAddress];
            return (true, topBid.bidAmount);
        } else {
            return (false, 0);
        }
    }

    //function for determining the winner of a completed auction
    function findAuctionWinner(
        address validatorAddress,
        address opportunityAddress
    ) public view returns (bool, address) {
        //get the winning searcher
        address winningSearcher = auctionResultsMap[auction_number][
            validatorAddress
        ][opportunityAddress];

        //check if there is a winning searcher (no bids mean the winner is address(this))
        if (winningSearcher != address(this)) {
            return (true, winningSearcher);
        } else {
            return (false, winningSearcher);
        }
    }

    // @audit Potentially Remove?
    //function for getting the list of approved opportunity addresses
    function getOpportunityList()
        public
        view
        returns (address[] memory _opportunityAddressList)
    {
        //might not be reliable - might run out of gas
        _opportunityAddressList = opportunityAddressList;
    }

    // @audit Potentially Remove?
    //function for getting the list of participating validator addresses
    function getValidatorList()
        public
        view
        returns (address[] memory _validatorAddressList)
    {
        //might not be reliable - might run out of gas
        _validatorAddressList = validatorAddressList;
    }

    // @audit Potentially Remove?
    function getInitializedValidators()
        public
        view
        returns (address[] memory _initializedValidatorList)
    {
        _initializedValidatorList = currentValidatorsArrayMap[auction_number];
    }

    function getInitializedOpportunities(address _validatorAddress)
        public
        view
        returns (address[] memory _initializedOpportunityList)
    {
        _initializedOpportunityList = currentPairsArrayMap[auction_number][
            _validatorAddress
        ];
    }

    // @audit Potentially Remove?
    function getUnprocessedValidators()
        public
        view
        returns (address[] memory)
    {
        //MIGHT RUN OUT OF GAS - only use if convenient, do not rely on.

        address[] memory _unprocessedValidatorList;

        if (processing_ongoing == false) {
            return _unprocessedValidatorList;
        }

        uint256 _listIndex = 0;

        address[] memory _initializedValidatorList = currentValidatorsArrayMap[
            auction_number
        ];

        for (uint256 i = 0; i < _initializedValidatorList.length; i++) {
            if (
                currentInitializedValidatorsMap[auction_number][
                    _initializedValidatorList[i]
                ]._isInitialized == true
            ) {
                _unprocessedValidatorList[
                    _listIndex
                ] = _initializedValidatorList[i];
                _listIndex++;
            }
        }
        return _unprocessedValidatorList;
    }

    // @audit Potentially Remove?
    function getUnprocessedOpportunities(address _validatorAddress)
        public
        view
        returns (address[] memory)
    {
        //MIGHT RUN OUT OF GAS - only use if convenient, do not rely on.

        address[] memory _unprocessedOpportunityList;

        if (processing_ongoing == false) {
            return _unprocessedOpportunityList;
        }

        uint256 _listIndex = 0;

        address[] memory _initializedOpportunityList = currentPairsArrayMap[
            auction_number
        ][_validatorAddress];

        for (uint256 i = 0; i < _initializedOpportunityList.length; i++) {
            if (
                currentInitializedValOppMap[auction_number][_validatorAddress][
                    _initializedOpportunityList[i]
                ]._isInitialized == true
            ) {
                _unprocessedOpportunityList[
                    _listIndex
                ] = _initializedOpportunityList[i];
                _listIndex++;
            }
        }
        return _unprocessedOpportunityList;
    }

    // @audit Potentially Remove?
    function checkIfPairInitialized(
        address _validatorAddress,
        address _opportunityAddress
    ) public view returns (bool isInitialized) {
        isInitialized = currentInitializedValOppMap[auction_number][
            _validatorAddress
        ][_opportunityAddress]._isInitialized;
    }
    // @audit Potentially Remove?
    function checkIfValidatorInitialized(address _validatorAddress)
        public
        view
        returns (bool isInitialized)
    {
        isInitialized = currentInitializedValidatorsMap[auction_number][
            _validatorAddress
        ]._isInitialized;
    }

  /***********************************|
  |             Modifiers             |
  |__________________________________*/

    modifier notLiveStage() {
        require(auction_live == false, "FL:E-301");
        _;
    }

    modifier atLiveStage() {
        require(auction_live == true, "FL:E-302");
        _;
    }

    modifier atProcessingStage() {
        require(processing_ongoing == true, "FL:E-303");
        _;
    }

    modifier notProcessingStage() {
        require(processing_ongoing == false, "FL:E-306");
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "FL:E-101");
        _;
    }
}
