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

    address public BROKEBIDDER = 0xD057089743dc1461b1099Dee7A8CB848E361f6d9;


    address[] public BIDDERS = [BIDDER1, BIDDER2, BIDDER3, BIDDER4];
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
            uint256 soonWMatic = (10 ether * (i + 1));
            vm.deal(currentBidder, soonWMatic + 1);
            vm.prank(currentBidder);
            wMatic.deposit{value: soonWMatic}();
            console2.log(
                "[amount Bidder] :",
                i,
                " -> ",
                wMatic.balanceOf(currentBidder)
            );
        }

        // Fund useful accounts
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

        Bid memory auctionRightMinimumBid = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, BIDDER1, FLA.bid_increment());
        
        Bid memory auctionWrongDoubleSelfBid = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, BIDDER1, FLA.bid_increment() + 1);
        Bid memory auctionWrongBrokeBidderBid = Bid(VALIDATOR1, OPPORTUNITY1, BROKEBIDDER, BROKEBIDDER, 8*10**18);


        vm.expectRevert(bytes("FL:E-103"));
        FLA.submitBid(auctionWrongSearchableBid);
        
        vm.expectRevert(bytes("FL:E-104"));
        FLA.submitBid(auctionWrongValidatorBid);
        
        vm.expectRevert(bytes("FL:E-105"));
        FLA.submitBid(auctionWrongOpportunityBid);

        vm.expectRevert(bytes("FL:E-203"));
        FLA.submitBid(auctionWrongIncrementBid);

        
        // First correct bid 
        uint balanceBefore = wMatic.balanceOf(BIDDER1);

        vm.expectEmit(true, true, true, true, address(FLA));
        emit BidAdded(BIDDER1, VALIDATOR1, OPPORTUNITY1, FLA.bid_increment() + 1, 1);
   
        // Check event
        FLA.submitBid(auctionRightMinimumBid);

        // Check balances
        assertEq(wMatic.balanceOf(BIDDER1), balanceBefore - (FLA.bid_increment() + 1));
        assertEq(wMatic.balanceOf(address(FLA)), FLA.bid_increment() + 1);

        // Todo: Check mappings

        FLA.submitBid(auctionRightMinimumBid);
        vm.expectRevert(bytes("FL:E-203"));

        FLA.submitBid(auctionWrongDoubleSelfBid);
        vm.expectRevert(bytes("FL:E-204"));

        FLA.submitBid(auctionWrongBrokeBidderBid);
        vm.expectRevert(bytes("FL:E-206"));

        vm.stopPrank();
        vm.startPrank(OWNER);

        FLA.stopBidding();
        FLA.endAuction();
        // Can't end while unprocessed
        vm.expectRevert(bytes("FL:E-306"));

        assertTrue(FLA.auction_number() == 1);
    }
}
