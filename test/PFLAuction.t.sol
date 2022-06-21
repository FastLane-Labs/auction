// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "contracts/interfaces/IWMatic.sol";

// 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889 - Mumbai WMATIC
// 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270 - Polygon Mainnet WMATIC

abstract contract PFLHelper is Test, FastLaneEvents {
    address public OWNER = 0xa401DCcD23DCdbc7296bDfb8A6c8d61106711CA6;

    address public BIDDER1 = 0xc71E2Df87C93bC3Ddba80e14406F3880E3D19D3e;
    address public BIDDER2 = 0x174237f20a0925d5eFEA401e5279181f0b7515EE;
    address public BIDDER3 = 0xFba52cDB2B36eCc27ac229b8feb2455B6aE3014b;
    address public BIDDER4 = 0xc4208Be0F01C8DBB57D0269887ccD5D269dEFf3B;

    address public VALIDATOR1 = 0x8149d8a0aCE8c058a679a1Fd4257aA1F1d2b9103;
    address public VALIDATOR2 = 0x161c3421Da27CD26E3c46Eb5711743343d17352d;
    address public VALIDATOR3 = 0x60d86bBFD061A359fd3B3E6Ef422b74B886f9a4a;
    address public VALIDATOR4 = 0x68F248c6B7820B191E4ed18c3d618ba7aC527C99;

    address public OPPORTUNITY1 = 0x8af6F6CA42171fc823619AC33a9A6C1892CA980B;
    address public OPPORTUNITY2 = 0x6eD132ea309B432FD49C9e70bc4F8Da429022F77;
    address public OPPORTUNITY3 = 0x8fcB7fb5e84847029Ba3e055BE46b86a4693AE40;
    address public OPPORTUNITY4 = 0x29D59575e85282c05112BEEC53fFadE66d3c7CD1;

    address public BROKE_BIDDER = 0xD057089743dc1461b1099Dee7A8CB848E361f6d9;
    address public BROKE_SEARCHER = 0xD057089743dc1461b1099Dee7A8CB848E361f6d9;

    address public SEARCHER_ADDRESS1 =  0x14BA06E061ada0443dbE5c7617A529Dd791c3146;
    address public SEARCHER_ADDRESS2 =  0x428a87F9c0ed1Bb9cdCE42f606e030ba40a525f3;
    address public SEARCHER_ADDRESS3 =  0x791e001586B75B8880bC6D02f2Ee19D42ec23E18;
    address public SEARCHER_ADDRESS4 =  0x4BF8fC74846da2dc54cCfd1f4fFac595939399e4;


    address[] public BIDDERS = [BIDDER1, BIDDER2, BIDDER3, BIDDER4];

    address[] public SEARCHERS = [SEARCHER_ADDRESS1, SEARCHER_ADDRESS2, SEARCHER_ADDRESS3, SEARCHER_ADDRESS4];

    address[] public VALIDATORS = [
        VALIDATOR1,
        VALIDATOR2,
        VALIDATOR3,
        VALIDATOR4
    ];
    address[] public OPPORTUNITIES = [
        OPPORTUNITY1,
        OPPORTUNITY2,
        OPPORTUNITY3,
        OPPORTUNITY4
    ];

    constructor() {}

    function logReads(address addr) public {
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(
            address(addr)
        );
        for (uint256 i; i < reads.length; i++) {
            emit log_uint(uint256(reads[i]));
        }
    }
}

contract PFLAuctionTest is Test, PFLHelper {
    using Address for address payable;
    FastLaneAuction public FLA;
    WMATIC public wMatic = WMATIC(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889);

    function setUp() public {
        vm.prank(OWNER);
        FLA = new FastLaneAuction(address(wMatic));
        console2.log("FLA deployed at:", address(FLA));
        console2.log("WMATIC deployed at:", address(wMatic));

        for (uint256 i = 0; i < BIDDERS.length; i++) {
            address currentBidder = BIDDERS[i];
            address currentSearcher = SEARCHERS[i];

            uint256 soonWMaticBidder = (10 ether * (i + 1));
            uint256 soonWMaticSearcher = (33 ether * (i + 1));

            vm.deal(currentBidder, soonWMaticBidder + 1);
            vm.deal(currentSearcher, soonWMaticSearcher + 1);

            vm.prank(currentBidder);
            wMatic.deposit{value: soonWMaticBidder}();
            vm.prank(currentSearcher);
            wMatic.deposit{value: soonWMaticSearcher}();
            console2.log(
                "[amount Bidder] :",
                i,
                " -> ",
                wMatic.balanceOf(currentBidder)
            );
            console2.log(
                "[amount Searcher] :",
                i,
                " -> ",
                wMatic.balanceOf(currentSearcher)
            );
        }
    }

    function testStartProcessStopNoBidAuction() public {
        console2.log("Sender", msg.sender);
        vm.startPrank(OWNER);
        // vm.record();

        FLA.startAuction();
        FLA.stopBidding();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 1);
    }

    function testStartProcessStopMultipleEmptyAuctions() public {
        vm.startPrank(OWNER);
        // vm.record();

        vm.expectEmit(true, false, false, false);
        emit OpportunityAddressAdded(OPPORTUNITY1,0);
        FLA.addOpportunityAddressToList(OPPORTUNITY1);

        vm.expectEmit(true, false, false, false);
        emit ValidatorAddressAdded(VALIDATOR1, 0);
        FLA.addValidatorAddressToList(VALIDATOR1);

        FLA.startAuction();
        FLA.stopBidding();
        FLA.endAuction();

        FLA.startAuction();
        FLA.stopBidding();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 2);
    }

    function testStartProcessSingleBidAuction() public {
        vm.startPrank(OWNER);

        FLA.addOpportunityAddressToList(OPPORTUNITY1);
        FLA.addValidatorAddressToList(VALIDATOR1);

        FLA.startAuction();

        vm.stopPrank();
        vm.startPrank(BIDDER1);

        // Bid { validatorAddress - opportunityAddress - searcherContractAddress - searcherPayableAddress - bidAmount}
        Bid memory auctionWrongSearchableBid = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, BIDDER2, 11*10**18);
        Bid memory auctionWrongOpportunityBid = Bid(VALIDATOR1, OPPORTUNITY2, BIDDER1, BIDDER1, 11*10**18);
        Bid memory auctionWrongValidatorBid = Bid(VALIDATOR2, OPPORTUNITY1, BIDDER1, BIDDER1, 11*10**18);
        Bid memory auctionWrongIncrementBid = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, BIDDER1, 8*10**18);

        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());
        
        Bid memory auctionWrongDoubleSelfBidWithSearcherTooLow = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment() + 1);
        Bid memory auctionWrongDoubleSelfBidWithSearcherEnough = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment() + FLA.bid_increment());

        Bid memory auctionWrongBrokeBidderBidTooLow = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_BIDDER, 8*10**18);
        Bid memory auctionWrongBrokeBidderBidEnough = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_BIDDER, FLA.bid_increment() + FLA.bid_increment());

        Bid memory auctionWrongBrokeSearcherBid = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_SEARCHER, 8*10**18);


        vm.expectRevert(bytes("FL:E-103"));
        FLA.submitBid(auctionWrongSearchableBid);
        
        vm.expectRevert(bytes("FL:E-104"));
        FLA.submitBid(auctionWrongValidatorBid);
        
        vm.expectRevert(bytes("FL:E-105"));
        FLA.submitBid(auctionWrongOpportunityBid);

        vm.expectRevert(bytes("FL:E-203"));
        FLA.submitBid(auctionWrongIncrementBid);

        vm.stopPrank(); // Not BIDDER1 anymore
        
        vm.startPrank(auctionRightMinimumBidWithSearcher.searcherPayableAddress);

        // Missing approval
        vm.expectRevert(bytes("SafeERC20: low-level call failed"));
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Approve as the Payable
        wMatic.approve(address(FLA), 2**256 - 1);

        // First correct bid 
        uint balanceBefore = wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress);

        vm.expectEmit(true, true, true, true, address(FLA));
        emit BidAdded(BIDDER1, VALIDATOR1, OPPORTUNITY1, FLA.bid_increment(), 1);
        // Check event
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Check balances
        assertEq(wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress), balanceBefore - auctionRightMinimumBidWithSearcher.bidAmount);
        assertEq(wMatic.balanceOf(address(FLA)), auctionRightMinimumBidWithSearcher.bidAmount);

        // Todo: Check mappings

        vm.expectRevert(bytes("FL:E-203"));
        FLA.submitBid(auctionWrongDoubleSelfBidWithSearcherTooLow);

        vm.expectRevert(bytes("FL:E-204"));
        FLA.submitBid(auctionWrongDoubleSelfBidWithSearcherEnough);
  

        vm.stopPrank();

        // There was a bid valid before of FLA.bid_increment().
        // First we don't top it, then we do, but with an empty bank account. Both reverting.
        vm.startPrank(auctionWrongBrokeBidderBidTooLow.searcherPayableAddress);
        wMatic.approve(address(FLA), 2**256 - 1);
        vm.expectRevert(bytes("FL:E-203"));
        FLA.submitBid(auctionWrongBrokeBidderBidTooLow);
       
        vm.expectRevert(bytes("FL:E-206"));
        FLA.submitBid(auctionWrongBrokeBidderBidEnough);

        vm.stopPrank();

        // Beat previous bid from another searcher on same pair

        // Check refund

        // Start another pair from another searcher

        // Beat the other searcher

        // Process results

        // Pay validators

        // Pay FLA.

        vm.startPrank(OWNER);

        FLA.stopBidding();
        FLA.endAuction();
        // Can't end while unprocessed
        vm.expectRevert(bytes("FL:E-306"));

        assertTrue(FLA.auction_number() == 1);
    }

    // Can't bid on removed opp after it was enabled then removed
    // Can't bid on validator after it was enabled then removed
    // Can't bid on validator after it was enabled then removed then enabled again
}
