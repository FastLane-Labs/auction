//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);  // maybe use safetransfer? idk
}

struct Bid{
    address validatorAddress;
    address opportunityAddress;
    address searcherContractAddress;
    address searcherPayableAddress; // perhaps remove this - just require the bidding EOA to pay
    uint256 bidAmount;
}

struct initializedAddress {
    address _address;
    bool _isInitialized;
}

struct initializedIndexAddress {
    address _address;
    bool _previouslyInitialized;
    uint _index;
    bool _isInitialized;
}

contract fastLaneAuction {
    //Immutable variables
    address public immutable owner;
    address WMATIC;
    
    constructor()  {
        owner = msg.sender;
        WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        }
    
    //Variables mutable by owner via function calls
    IERC20 bid_token = IERC20(WMATIC);
    uint256 bid_increment = 10 * (10 ** 18); //minimum bid increment in WMATIC
    uint256 fast_lane_fee = 50000; //out of one million
    bool auction_live = false;
    bool processing_ongoing = false;
    uint256 auction_number = 0;
    uint256 current_balance = 0;

    //array and map declarations
    address[] public opportunityAddressList;
    mapping(address => initializedIndexAddress) opportunityAddressMap;

    address[] public validatorAddressList;
    mapping(address => initializedIndexAddress) validatorAddressMap;

    mapping(uint => mapping(address => mapping(address => Bid))) currentAuctionMap;

    mapping(uint => mapping(address => initializedAddress)) currentInitializedValidatorsMap;

    mapping(uint => mapping(address => mapping(address => initializedAddress))) currentInitializedValOppMap;

    mapping(uint => address[]) currentValidatorsArrayMap;
    mapping(uint => uint) currentValidatorsCountMap;
    
    mapping(uint => mapping(address => address[])) currentPairsArrayMap;
    mapping(uint => mapping(address => uint)) currentPairsCountMap;

    mapping(uint => mapping(address => mapping(address => address))) auctionResultsMap;

    // OWNER-ONLY CONTROL FUNCTIONS

    //set minimum bid increment to avoid people bidding up by .000000001
    function setMinimumBidIncrement(uint256 _bid_increment) 
        public {
            require(msg.sender == owner, 'no hack plz');
            bid_increment = _bid_increment;
        }
    
    //set the protocol fee (out of 1000000 (ie v2 fee decimals)).  
    //Initially set to 50000 (5%)
    function setFastlaneFee(uint256 _fastLaneFee) 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, '-.-');
            fast_lane_fee = _fastLaneFee;
        }
    
    //set the ERC20 token that is treated as the base currency for bidding purposes. 
    //Initially set to WMATIC
    function setBidToken(address _bid_token_address) 
        public {
            require(msg.sender == owner, 'no hack plz');
            bid_token = IERC20(_bid_token_address);
        }
    
    //add an address to the opportunity address array. 
    //Should be a router/aggregator etc.
    function addOpportunityAddressToList(address opportunityAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');

            initializedIndexAddress memory oldData = opportunityAddressMap[opportunityAddress];

            if (oldData._previouslyInitialized == true) {
                opportunityAddressList[oldData._index] = opportunityAddress;
                opportunityAddressMap[opportunityAddress] = initializedIndexAddress(opportunityAddress, true, oldData._index, true);
            
            } else {
                opportunityAddressList.push(opportunityAddress);
                uint listLength = opportunityAddressList.length;
                opportunityAddressMap[opportunityAddress] = initializedIndexAddress(opportunityAddress, true, listLength, true);
            }
        }
    
    //remove an address from the opportunity address array
    function removeOpportunityAddressFromList(address opportunityAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction ongoing');

            initializedIndexAddress memory oldData = opportunityAddressMap[opportunityAddress];

            delete opportunityAddressList[oldData._index];

            //remove the opportunity address from the array of participating validators
            opportunityAddressMap[opportunityAddress] = initializedIndexAddress(opportunityAddress, true, oldData._index, false);
        }
    
    //add an address to the participating validator address array
    function addValidatorAddressToList(address validatorAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');

            //see if its a reinit
            initializedIndexAddress memory oldData = validatorAddressMap[validatorAddress];

            if (oldData._previouslyInitialized == true) {
                validatorAddressList[oldData._index] = validatorAddress;
                validatorAddressMap[validatorAddress] = initializedIndexAddress(validatorAddress, true, oldData._index, true);
            
            } else {
                validatorAddressList.push(validatorAddress);
                uint listLength = validatorAddressList.length;
                validatorAddressMap[validatorAddress] = initializedIndexAddress(validatorAddress, true, listLength, true);
            }
        }
    
    //remove an address from the participating validator address array
    function removeValidatorAddressFromList(address validatorAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction ongoing');

            initializedIndexAddress memory oldData = validatorAddressMap[validatorAddress];

            delete validatorAddressList[oldData._index];

            //remove the validator address from the array of participating validators
            validatorAddressMap[validatorAddress] = initializedIndexAddress(validatorAddress, true, oldData._index, false);
        }
    
    //start auction / enable bidding
    //note that this also cleans out the bid history for the previous auction
    function startAuction() 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction already started');
            require(processing_ongoing == false, 'last auction results are unprocessed');

            // increment up the auction_count number
            auction_number++;

            // set initialized validators
            currentValidatorsCountMap[auction_number] = 0;

            //enable bidding
            auction_live = true;
        }
    
    function stopBidding() public {
        require(msg.sender == owner, 'no hack plz');
        require(auction_live == true, 'auction already stopped');

        //disable bidding
        auction_live = false;

        //enable result processing
        processing_ongoing = true;
    }

    
    function processPartialAuctionResults(address _validatorAddress, address _opportunityAddress)
        public returns(bool isSuccessful) {

            require(msg.sender == owner, 'no hack plz');

            // make sure we're not stopping too soon
            require(auction_live = false, 'on your own contract, too'); 
            require(processing_ongoing = true, 'processing must be ongoing');
            
            //make sure the pair hasnt already been processed
            require(currentInitializedValidatorsMap[auction_number][_validatorAddress]._isInitialized == true, 'validator already completely processed');
            require(currentInitializedValOppMap[auction_number][_validatorAddress][_opportunityAddress]._isInitialized == true, 'opp already processed');

            //find top bid for pairing
            Bid memory top_user_bid = currentAuctionMap[auction_number][_validatorAddress][_opportunityAddress];
            
            // mark things already updated
            if (currentPairsCountMap[auction_number][_validatorAddress] > 1) {

                //increment it down
                currentPairsCountMap[auction_number][_validatorAddress]--;

            } else if (currentPairsCountMap[auction_number][_validatorAddress] == 1) {
                
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
                    currentInitializedValidatorsMap[auction_number][_validatorAddress] = initializedAddress(_validatorAddress, false);
                    currentPairsCountMap[auction_number][_validatorAddress] = 0;
                }
                
            } else {
                isSuccessful = false;
            }

            if (isSuccessful == true ) {
                //mark it already updated
                currentInitializedValOppMap[auction_number][_validatorAddress][_opportunityAddress] = initializedAddress(_opportunityAddress, false);

                //handle the transfers
                bid_token.transferFrom(address(this), top_user_bid.validatorAddress, ((top_user_bid.bidAmount * 1000000) - fast_lane_fee) / 1000000);

                //update the auction contract
                auctionResultsMap[auction_number][_validatorAddress][_opportunityAddress] = top_user_bid.searcherContractAddress;
            }

            return isSuccessful;
        }
    
    function finishAuctionProcess() public returns(bool) {
        require(msg.sender == owner, 'no hack plz');

        // make sure we're not stopping too soon
        require(auction_live = false, 'on your own contract, too');

        // make sure processing is ongoing
        require(processing_ongoing = true, 'processing must be ongoing');

        // make sure all pairs have been processed first
        if (currentValidatorsCountMap[auction_number] < 1) {

            //transfer to PFL the sorely needed $ to cover our high infra costs
            bid_token.transferFrom(address(this), owner, bid_token.balanceOf(address(this)));

            processing_ongoing = false;
            current_balance = 0;
            return true;

        } else {
            return false;
        }
    }

    function emergencyWithdraw(address _tokenAddress) public {
        require(msg.sender == owner, 'no hack plz');

        IERC20 oopsToken = IERC20(_tokenAddress);
        uint oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            bid_token.transferFrom(address(this), owner, oopsTokenBalance);
        }
    }
    
    // PUBLIC FACING FUNCTIONS

    //bidding function for searchers to submit their bids
    //note that each bid pulls funds on submission and that searchers are not refunded for failed bids until they are outbid
    function submit_bid(Bid calldata bid)
        public returns (bool) {

            require(auction_live == true, 'auction is not currently live');

            //verify that the bid is coming from the EOA that's paying
            require(msg.sender == bid.searcherPayableAddress, 'Please only send bids from the payor EOA');

            //verify that the opportunity and the validator are both participating addresses
            require(validatorAddressMap[bid.validatorAddress]._isInitialized == true, 'invalid validator address');
            require(opportunityAddressMap[bid.opportunityAddress]._isInitialized  == true, 'invalid opportunity address - submit via discord');

            //Determine is pair is initialized
            bool is_validator_initialized = currentInitializedValidatorsMap[auction_number][bid.validatorAddress]._isInitialized;

            bool is_opportunity_initialized;
            if (is_validator_initialized) {
                is_opportunity_initialized = currentInitializedValOppMap[auction_number][bid.validatorAddress][bid.opportunityAddress]._isInitialized;
            } else {
                is_opportunity_initialized = false;
            }

            if (is_validator_initialized && is_opportunity_initialized) {
                Bid memory current_top_bid = currentAuctionMap[auction_number][bid.validatorAddress][bid.opportunityAddress];
                
                //verify the bid exceeds previous bid + minimum increment
                require(bid.bidAmount >= current_top_bid.bidAmount + bid_increment, 'bid too low');

                //verify the new bidder isnt the previous bidder
                require(bid.searcherPayableAddress != current_top_bid.searcherPayableAddress, 'you already are the top bidder');

                //verify the bidder has the balance.
                require(bid_token.balanceOf(bid.searcherPayableAddress) >= bid.bidAmount, 'no funny business');

                //TODO MAKE SURE THE EOA APPROVES THE AUCTION CONTRACT... FRONT END STUFF?

                //transfer the bid amount
                bid_token.transferFrom(bid.searcherPayableAddress, address(this), bid.bidAmount);
                require(bid_token.balanceOf(address(this)) == current_balance + bid.bidAmount, 'im not angry im just disappointed'); 

                //refund the previous top bid
                bid_token.transferFrom(address(this), current_top_bid.searcherPayableAddress, current_top_bid.bidAmount);
                require(bid_token.balanceOf(address(this)) == current_balance + bid.bidAmount - current_top_bid.bidAmount, 'im not angry im just disappointed');

                //update the existing Bid struct rather than adding a new one
                currentAuctionMap[auction_number][bid.validatorAddress][bid.opportunityAddress]= bid;
                current_balance = bid_token.balanceOf(address(this));
                return true;

            } else {
                    //verify the bidder has the balance.
                    require(bid_token.balanceOf(bid.searcherPayableAddress) >= bid.bidAmount, 'no funny business');

                    //TODO MAKE SURE THE EOA APPROVES THE AUCTION CONTRACT... FRONT END STUFF?

                    //transfer the bid amount
                    bid_token.transferFrom(bid.searcherPayableAddress, address(this), bid.bidAmount);
                    require(bid_token.balanceOf(address(this)) == current_balance + bid.bidAmount, 'im not angry im just disappointed'); 

                    if (is_validator_initialized == false) {
                        currentInitializedValidatorsMap[auction_number][bid.validatorAddress] = initializedAddress(bid.validatorAddress, true);
                        currentValidatorsArrayMap[auction_number].push(bid.validatorAddress);
                        currentValidatorsCountMap[auction_number]++;
                        currentPairsCountMap[auction_number][bid.validatorAddress] = 0;
                        }
                    
                    if (is_opportunity_initialized == false) {
                        currentInitializedValOppMap[auction_number][bid.validatorAddress][bid.opportunityAddress] = initializedAddress(bid.opportunityAddress, true);
                        currentPairsArrayMap[auction_number][bid.validatorAddress].push(bid.opportunityAddress);
                        currentPairsCountMap[auction_number][bid.validatorAddress]++;
                        }
                    
                    //update the existing Bid struct rather than adding a new one
                    currentAuctionMap[auction_number][bid.validatorAddress][bid.opportunityAddress] = bid;
                    current_balance = bid_token.balanceOf(address(this));
                    return true;
                }
            }

    //PUBLIC VIEW-ONLY FUNCTIONS (for frontend / backend)
    function find_auction_count() public view returns (uint _auction_number) {
        _auction_number = auction_number;
    }

    //function for determining the current top bid for an ongoing (live) auction
    function find_top_bid(address validatorAddress, address opportunityAddress)
        public view returns (bool, uint256) {

            //Determine is pair is initialized
            bool is_validator_initialized = currentInitializedValidatorsMap[auction_number][validatorAddress]._isInitialized;

            bool is_opportunity_initialized;
            
            if (is_validator_initialized) {
                is_opportunity_initialized = currentInitializedValOppMap[auction_number][validatorAddress][opportunityAddress]._isInitialized;
            } else {
                is_opportunity_initialized = false;
            }

            if (is_validator_initialized && is_opportunity_initialized) {
                Bid memory topBid = currentAuctionMap[auction_number][validatorAddress][opportunityAddress];
                return (true, topBid.bidAmount);
            } else {
                uint256 _zero = 0;
                return (false, _zero);
            }
        }

    //function for determining the winner of a completed auction
    function find_auction_winner(address validatorAddress, address opportunityAddress)
        public view returns (bool, address) {

            //get the winning searcher
            address winningSearcher = auctionResultsMap[auction_number][validatorAddress][opportunityAddress];

            //check if there is a winning searcher (no bids mean the winner is address(this))
            if (winningSearcher != address(this)) {
                return (true, winningSearcher);
            } else {
                return (false, winningSearcher);
            }
        }

    //function for getting the list of approved opportunity addresses
    function get_opportunity_list()
        public view returns (address[] memory _opportunityAddressList) {
            //might not be reliable - might run out of gas
            _opportunityAddressList = opportunityAddressList;
        }
    
    //function for getting the list of participating validator addresses
    function get_validator_list()
        public view returns (address[] memory _validatorAddressList) {
            //might not be reliable - might run out of gas
            _validatorAddressList = validatorAddressList;
        }

    function get_initialized_validators()
        public view returns (address[] memory _initializedValidatorList) {
            _initializedValidatorList = currentValidatorsArrayMap[auction_number];
        }
    
    function get_initialized_opportunities(address _validatorAddress)
        public view returns (address[] memory _initializedOpportunityList) {
            _initializedOpportunityList = currentPairsArrayMap[auction_number][_validatorAddress];
        }
    
    function get_unprocessed_validators()
        public view returns (address[] memory) {
            //MIGHT RUN OUT OF GAS - only use if convenient, do not rely on.

            address[] memory _unprocessedValidatorList;

            if (processing_ongoing == false) {
                return _unprocessedValidatorList;
            }

            uint _listIndex = 0;

            address[] memory _initializedValidatorList = currentValidatorsArrayMap[auction_number];

            for (uint256 i = 0 ; i < _initializedValidatorList.length; i++) {
                if (currentInitializedValidatorsMap[auction_number][_initializedValidatorList[i]]._isInitialized == true) {
                    _unprocessedValidatorList[_listIndex] = _initializedValidatorList[i];
                    _listIndex++;
                }
            }
            return _unprocessedValidatorList;
        }
    
    function get_unprocessed_opportunities(address _validatorAddress)
        public view returns (address[] memory) {
            //MIGHT RUN OUT OF GAS - only use if convenient, do not rely on.

            address[] memory _unprocessedOpportunityList;

            if (processing_ongoing == false) {
                return _unprocessedOpportunityList;
            }

            uint _listIndex = 0;

            address[] memory _initializedOpportunityList = currentPairsArrayMap[auction_number][_validatorAddress];
            
            for (uint256 i = 0 ; i < _initializedOpportunityList.length; i++) {
                if (currentInitializedValOppMap[auction_number][_validatorAddress][_initializedOpportunityList[i]]._isInitialized == true) {
                    _unprocessedOpportunityList[_listIndex] = _initializedOpportunityList[i];
                    _listIndex++;
                }
            }
            return _unprocessedOpportunityList;

        }
    
    function check_if_pair_initialized(address _validatorAddress, address _opportunityAddress)
        public view returns (bool isInitialized) {
            isInitialized = currentInitializedValOppMap[auction_number][_validatorAddress][_opportunityAddress]._isInitialized;

        }
    
    function check_if_validator_initialized(address _validatorAddress)
        public view returns (bool isInitialized) {
            isInitialized = currentInitializedValidatorsMap[auction_number][_validatorAddress]._isInitialized;
        }

}