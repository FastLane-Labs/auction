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

    //array and map declarations
    address[] public opportunityAddressList;
    address[] public validatorAddressList;

    mapping(address => mapping(address => Bid[])) currentAuctionMap;
    mapping(address => mapping(address => address)) auctionResultsMap;

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

            //add opportunity address to valid opportunity array
            opportunityAddressList.push(opportunityAddress);
        }
    
    //remove an address from the opportunity address array
    function removeOpportunityAddressFromList(address opportunityAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction ongoing');

            //remove the validator address from the array of participating validators
            int256 index = findElementIndexInArray(opportunityAddress, opportunityAddressList);
            if (index != -1) { 
                removeElementFromArray(uint256(index), opportunityAddressList);
            }

            //delete the opportunity from the auctionResultsMap and the currentAuctionMap to prevent state bloat
            for (uint256 x = 0 ; x < validatorAddressList.length; x++) {
               delete auctionResultsMap[validatorAddressList[x]][opportunityAddress];
               delete currentAuctionMap[validatorAddressList[x]][opportunityAddress];
            }
        }
    
    //add an address to the participating validator address array
    function addValidatorAddressToList(address validatorAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');

            //add validator to participating validator array
            validatorAddressList.push(validatorAddress);
        }
    
    //remove an address from the participating validator address array
    function removeValidatorAddressFromList(address validatorAddress) 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction ongoing');

            //remove the validator address from the array of participating validators
            int256 index = findElementIndexInArray(validatorAddress, validatorAddressList);
            if (index != -1) { 
                removeElementFromArray(uint256(index), validatorAddressList);
            }

            //delete the validator from the auctionResultsMap and the currentAuctionMap to prevent state bloat
            for (uint256 y = 0 ; y < opportunityAddressList.length; y++) {
               delete auctionResultsMap[validatorAddress][opportunityAddressList[y]];
               delete currentAuctionMap[validatorAddress][opportunityAddressList[y]];
            }
        }
    
    //start auction / enable bidding
    //note that this also cleans out the bid history for the previous auction
    function startAuction() 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == false, 'auction already started');

            //clear out the map of the last auction's bids
            for (uint256 x = 0 ; x < validatorAddressList.length; x++) {
                for (uint256 y = 0 ; y < opportunityAddressList.length; y++) {
                    delete currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]];
                }
            }
            //enable bidding
            auction_live = true;
        }
    
    //end auction / disable bidding
    function endAuction() 
        public {
            require(msg.sender == owner, 'no hack plz');
            require(auction_live == true, 'auction already ended');

            //disable bidding
            auction_live = false;
        }
    
    //process the results of the auction, set the winners into the contract's state, refund the losers, and send revenue to validators
    //note that this will clear out the state from the prior auction's results but will not clear out this auction's bidding data
    function processAuctionResults()
        public {
            require(msg.sender == owner, 'no hack plz');

            // make sure we're not stopping too soon
            require(auction_live = false, 'on your own contract, too'); 

            // update the results map
            for (uint256 x = 0 ; x < validatorAddressList.length; x++) {
                for (uint256 y = 0 ; y < opportunityAddressList.length; y++) {
                    //check and see if there are bids - otherwise, set the winner to address(this) as the null address
                    if (currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]].length > 0){
                        
                        //declare initial variables for top bid and index in list of winner
                        uint256 top_bid = 0;
                        uint256 winner_index = 0;

                        //iterate through the list of Bid structs to find the real winner
                        for (uint256 z = 0 ; z < currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]].length; z++) {
                            Bid memory user_bid = currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]][z];
                            if (user_bid.bidAmount > top_bid) {
                                top_bid = user_bid.bidAmount;
                                winner_index = z;
                            }
                        }
                        
                        //iterate through the list of Bid structs again to set the winner in the results map, refund the losers, and pay the validators
                        for (uint256 z = 0 ; z < currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]].length; z++) {
                            Bid memory user_bid = currentAuctionMap[validatorAddressList[x]][opportunityAddressList[y]][z];
                            
                            // make sure bid belongs to the winner
                            if (z == winner_index) {
                                //check and make sure the bid aligns with the state keys
                                if (user_bid.validatorAddress == validatorAddressList[x]) {
                                    //update the auction map and xfer the proceeds minus our fee to the validator
                                    auctionResultsMap[validatorAddressList[x]][opportunityAddressList[y]] = user_bid.searcherContractAddress;
                                    bid_token.transferFrom(address(this), user_bid.validatorAddress, ((user_bid.bidAmount * 1000000) - fast_lane_fee) / 1000000);
                                } 
                                //TODO handle situation in which bid validator address doesnt match state keys. we can always xfer the $ later.

                            // if not winner, refund the auction losers
                            } else {
                                bid_token.transferFrom(address(this), user_bid.searcherPayableAddress, user_bid.bidAmount);
                                //TODO explore taking a smalllll % of the failed bids as a fee too to decrease spam
                            }
                        }

                    // if there were no bids for the validator/opportunity pairing, set addressThis as the winner
                    } else {
                        auctionResultsMap[validatorAddressList[x]][opportunityAddressList[y]] = address(this);
                    }
                }
            }

            //At the end of processing, transfer the collected fees to owner. If an error was made, logs will be parsed on backend and owner will
            //transfer the surplus to the impacted address
            bid_token.transferFrom(address(this), owner, bid_token.balanceOf(address(this)));
        }

    // ARRAY AND MAP HELPER FUNCTIONS

    //TODO there's some int to uint fuckery in these that needs to be fixed
    function findElementIndexInArray(address element, address[] storage arr) 
        internal view returns(int256) {
            require(msg.sender == owner, 'no hack plz');
            for (uint256 i = 0 ; i < arr.length; i++) {
                if (arr[i] == element) {
                    return int256(i);
                }
            }
            return -1;
        }

    function removeElementFromArray(uint index, address[] storage arr) 
        internal {
            require(msg.sender == owner, 'no hack plz');
            if (index >= arr.length) return;

            for (uint i = index; i<arr.length-1; i++){
                arr[i] = arr[i+1];
            }
            delete arr[arr.length-1];
        }

    function verifyAddressInArray(address element, address[] storage arr) 
        internal view returns(bool) {
            require(msg.sender == owner, 'no hack plz');
            for (uint256 i = 0 ; i < arr.length; i++) {
                if (arr[i] == element) {
                    return true;
                }
            }
            return false;
        }

    // PUBLIC FACING FUNCTIONS

    //bidding function for searchers to submit their bids
    //note that each bid pulls funds on submission and that searchers are not refunded for failed bidsuntil the results are processed
    function submit_bid(Bid calldata bid, bool isIncrementalBid)
        public returns (bool result) {

            require(auction_live == true, 'auction is not currently live');

            //initiate starting balance for later security checks
            uint256 _startBalance = bid_token.balanceOf(address(this));
            result = false;

            //verify that the bid is coming from the EOA that's paying
            require(msg.sender == bid.searcherPayableAddress, 'Please only send bids from the payor EOA');

            //verify the bidder has the balance. If this is an incremental bid, the balance check will happen further into the function
            if (isIncrementalBid == false) {
                require(bid_token.balanceOf(bid.searcherPayableAddress) > bid.bidAmount, 'no funny business');
            }

            //verify that the opportunity and the validator are both participating addresses
            require(verifyAddressInArray(bid.validatorAddress, validatorAddressList) == true, 'that one is for VIPs only');
            require(verifyAddressInArray(bid.opportunityAddress, opportunityAddressList) == true, 'Submit this address via discord');


            //Access the array of bids for the targetted validator/opportunity pair
            Bid[] memory bidList = currentAuctionMap[bid.validatorAddress][bid.opportunityAddress];

            //check each existing bid and make sure the new bid is higher than existing + minimum bidding increment
            if (bidList.length > 0) {

                //set top bid amount variable (used for incremental bids)
                uint256 top_bid_amount = 0;
                uint256 bid_delta = 0;
                int incremental_bid_index = -1;

                for (uint256 i = 0 ; i < bidList.length; i++) {

                    //verify the bid amount exceeds the current bids
                    require(bidList[i].bidAmount + bid_increment < bid.bidAmount, 'bid too low');

                    //keep track of the top bid amount if this is an incremental bid
                    if (isIncrementalBid == true) {
                        if (bidList[i].bidAmount > top_bid_amount) {
                            top_bid_amount = bidList[i].bidAmount;
                        }
                    
                        //identify the original bid
                        if (bidList[i].searcherPayableAddress == bid.searcherPayableAddress &&
                            bidList[i].searcherContractAddress == bid.searcherContractAddress
                            ) {
                                //verify there aren't two incremental bids out there
                                require(incremental_bid_index == -1, 'hey now');

                                //grab the bid delta and check funding capacity
                                bid_delta = bid.bidAmount - bidList[i].bidAmount;
                                require(bid_delta >= bid_increment, 'bidding increment too small');
                                require(bid_token.balanceOf(bid.searcherPayableAddress) > bid_delta, 'no funny business');

                                //save the index of the original bid
                                incremental_bid_index = int(i);
                        }
                    }
                }

            //TODO MAKE SURE THE EOA APPROVES THE AUCTION CONTRACT... FRONT END STUFF?

            //handle fund transfers and state changes for incremental bids
            if (isIncrementalBid == true) {
                //verify the first bid was found
                require(incremental_bid_index != -1, 'initial bid not found - please save this TX Hash and contact fastlane support via discord');

                //for incremental bids, transfer the incremental increase amount
                bid_token.transferFrom(bid.searcherPayableAddress, address(this), bid_delta);
                require(bid_token.balanceOf(address(this)) == _startBalance + bid_delta, 'im not angry im just disappointed'); 

                //update the existing Bid struct rather than adding a new one
                currentAuctionMap[bid.validatorAddress][bid.opportunityAddress][uint256(incremental_bid_index)] = bid;
                result = true;
                return result;
            
            //handle fund transfers and state changes for initial bids
            } else {

                // transfer the bid amount in to the auction. We will hold funds for ALL bids and then return the losing bids at auction end
                bid_token.transferFrom(bid.searcherPayableAddress, address(this), bid.bidAmount);
                require(bid_token.balanceOf(address(this)) == _startBalance + bid.bidAmount, 'im not angry im just disappointed');

                // if there are existing bids, add this bid to the array, otherwise start a new array... or just push all? idk how to solidity
                currentAuctionMap[bid.validatorAddress][bid.opportunityAddress].push(bid);
                result = true;
                return result;
            }
        }
    }
}