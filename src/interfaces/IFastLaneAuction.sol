//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFastLaneAuction {
    struct Bid {
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
        uint256 _index;
        bool _isInitialized;
    }

    //Variables mutable by owner via function calls
    function bid_token() external returns (IERC20 token);

    function bid_increment() external returns (uint256);

    function fast_lane_fee() external returns (uint256);

    function auction_live() external returns (bool);

    function processing_ongoing() external returns (bool);

    function auction_number() external returns (uint256);

    function current_balance() external returns (uint256);

    function owner() external returns (address);

    function WMATIC() external returns (address);

    //array and map declarations
    // address[] external opportunityAddressList;
    // mapping(address => initializedIndexAddress) opportunityAddressMap;

    // address[] external validatorAddressList;
    // mapping(address => initializedIndexAddress) validatorAddressMap;

    // mapping(uint256 => mapping(address => mapping(address => Bid))) currentAuctionMap;

    // mapping(uint256 => mapping(address => initializedAddress)) currentInitializedValidatorsMap;

    // mapping(uint256 => mapping(address => mapping(address => initializedAddress))) currentInitializedValOppMap;

    // mapping(uint256 => address[]) currentValidatorsArrayMap;
    // mapping(uint256 => uint256) currentValidatorsCountMap;

    // mapping(uint256 => mapping(address => address[])) currentPairsArrayMap;
    // mapping(uint256 => mapping(address => uint256)) currentPairsCountMap;

    // mapping(uint256 => mapping(address => mapping(address => address))) auctionResultsMap;

    // OWNER-ONLY CONTROL FUNCTIONS

    //set minimum bid increment to avoid people bidding up by .000000001
    function setMinimumBidIncrement(uint256 _bid_increment) external;

    //set the protocol fee (out of 1000000 (ie v2 fee decimals)).
    //Initially set to 50000 (5%)
    function setFastlaneFee(uint256 _fastLaneFee) external;

    //set the ERC20 token that is treated as the base currency for bidding purposes.
    //Initially set to WMATIC
    function setBidToken(address _bid_token_address) external;

    //add an address to the opportunity address array.
    //Should be a router/aggregator etc.
    function addOpportunityAddressToList(address opportunityAddress) external;

    //remove an address from the opportunity address array
    function removeOpportunityAddressFromList(address opportunityAddress)
        external;

    //add an address to the participating validator address array
    function addValidatorAddressToList(address validatorAddress) external;

    //remove an address from the participating validator address array
    function removeValidatorAddressFromList(address validatorAddress) external;

    //start auction / enable bidding
    //note that this also cleans out the bid history for the previous auction
    function startAuction() external;

    function stopBidding() external;

    //process auction results for a specific validator/opportunity pair. Cant do loops on all pairs due to size.
    //use view-only functions to get arrays of unprocessed pairs to submit as args for this function.
    function processPartialAuctionResults(
        address _validatorAddress,
        address _opportunityAddress
    ) external returns (bool isSuccessful);

    function finishAuctionProcess() external returns (bool);

    function emergencyWithdraw(address _tokenAddress) external;

    // external FACING FUNCTIONS

    //bidding function for searchers to submit their bids
    //note that each bid pulls funds on submission and that searchers are refunded when they are outbid
    function submit_bid(Bid calldata bid) external returns (bool);

    //external VIEW-ONLY FUNCTIONS (for frontend / backend)
    function find_auction_count()
        external
        view
        returns (uint256 _auction_number);

    //function for determining the current top bid for an ongoing (live) auction
    function find_top_bid(address validatorAddress, address opportunityAddress)
        external
        view
        returns (bool, uint256);

    //function for determining the winner of a completed auction
    function find_auction_winner(
        address validatorAddress,
        address opportunityAddress
    ) external view returns (bool, address);

    //function for getting the list of approved opportunity addresses
    function get_opportunity_list()
        external
        view
        returns (address[] memory _opportunityAddressList);

    //function for getting the list of participating validator addresses
    function get_validator_list()
        external
        view
        returns (address[] memory _validatorAddressList);

    function get_initialized_validators()
        external
        view
        returns (address[] memory _initializedValidatorList);

    function get_initialized_opportunities(address _validatorAddress)
        external
        view
        returns (address[] memory _initializedOpportunityList);

    function get_unprocessed_validators()
        external
        view
        returns (address[] memory);

    function get_unprocessed_opportunities(address _validatorAddress)
        external
        view
        returns (address[] memory);

    function check_if_pair_initialized(
        address _validatorAddress,
        address _opportunityAddress
    ) external view returns (bool isInitialized);

    function check_if_validator_initialized(address _validatorAddress)
        external
        view
        returns (bool isInitialized);
}
