// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";

import "openzeppelin-contracts/contracts/utils/Strings.sol";
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

    function _calculateCuts(uint256 amount,uint256 fee) internal pure returns (uint256 vCut, uint256 flCut) {
        vCut = (amount * (1000000 - fee)) / 1000000;
        flCut = amount - vCut;
    }
}

contract PFLAuctionTest is Test, PFLHelper {
    using Address for address payable;
    FastLaneAuction public FLA;
    address constant MUMBAI_MATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    WMATIC public wMatic;


    function setUp() public {
  

        bytes memory bytecode = abi.encodePacked(vm.getCode("WMatic.sol"));
        address maticAddress;
        assembly {
            maticAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        vm.etch(MUMBAI_MATIC, maticAddress.code);

        vm.prank(OWNER);
        
        FLA = new FastLaneAuction(MUMBAI_MATIC);

        console2.log("FLA deployed at:", address(FLA));
        console2.log("WMATIC deployed at:", MUMBAI_MATIC);
        wMatic = WMATIC(MUMBAI_MATIC);

        for (uint256 i = 0; i < BIDDERS.length; i++) {
            address currentBidder = BIDDERS[i];
            address currentSearcher = SEARCHERS[i];
            vm.label(currentBidder,string.concat("BIDDER",Strings.toString(i+1)));
            vm.label(currentSearcher,string.concat("SEARCHER",Strings.toString(i+1)));
            uint256 soonWMaticBidder = (10 ether * (i + 1));
            uint256 soonWMaticSearcher = (33 ether * (i + 1));

            vm.deal(currentBidder, soonWMaticBidder + 1);
            vm.deal(currentSearcher, soonWMaticSearcher + 1);

            vm.prank(currentBidder);
            wMatic.deposit{value: soonWMaticBidder}();
            vm.prank(currentSearcher);
            wMatic.deposit{value: soonWMaticSearcher}();
            // console2.log(
            //     "[amount Bidder] :",
            //     i+1,
            //     " -> ",
            //     wMatic.balanceOf(currentBidder)
            // );
            // console2.log(
            //     "[amount Searcher] :",
            //     i+1,
            //     " -> ",
            //     wMatic.balanceOf(currentSearcher)
            // );
        }
    }

    function testStartStopNoBidAuction() public {
        console2.log("Sender", msg.sender);
        vm.startPrank(OWNER);
        // vm.record();

        FLA.startAuction();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 2);
    }

    function testStartProcessStopMultipleEmptyAuctions() public {
        vm.startPrank(OWNER);
        // vm.record();

        vm.expectEmit(true, true, false, false);
        emit OpportunityAddressEnabled(OPPORTUNITY1,1);
        FLA.enableOpportunityAddress(OPPORTUNITY1);

        vm.expectEmit(true, true, false, false);
        emit ValidatorAddressEnabled(VALIDATOR1, 1);
        FLA.enableValidatorAddress(VALIDATOR1);

        FLA.startAuction();
        // Now live, delay to next
        vm.expectEmit(true, true, false, false);
        emit OpportunityAddressEnabled(OPPORTUNITY2,2);
        FLA.enableOpportunityAddress(OPPORTUNITY2);
        
        vm.expectEmit(true, true, false, false);
        emit ValidatorAddressEnabled(VALIDATOR2, 2);
        FLA.enableValidatorAddress(VALIDATOR2);

        FLA.endAuction();

        FLA.startAuction();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 3);
    }
    function testValidatorCheckpoint() public {
        vm.startPrank(OWNER);

        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);

        ValidatorBalanceCheckpoint memory vCheck = FLA.getCheckpoint(VALIDATOR1);

        assertTrue(vCheck.pendingBalanceAtlastBid == 0);
        assertTrue(vCheck.outstandingBalance == 0);
        assertTrue(vCheck.lastWithdrawnAuction == 0);
        assertTrue(vCheck.lastBidReceivedAuction == 0);

        Status memory st = FLA.getStatus(OPPORTUNITY1);
        assertTrue(st.activeAtAuction == 1);
        assertTrue(st.inactiveAtAuction == FLA.MAX_AUCTION_VALUE());
        assertTrue(st.kind == statusType.OPPORTUNITY);

        FLA.startAuction();
        FLA.enableValidatorAddress(VALIDATOR2);
        Status memory stVal2 = FLA.getStatus(VALIDATOR2);
        
        assertTrue(stVal2.activeAtAuction == 2);
        assertTrue(stVal2.inactiveAtAuction == FLA.MAX_AUCTION_VALUE());
        assertTrue(stVal2.kind == statusType.VALIDATOR);

    }

    function testStartProcessSingleOutBidAuction() public {
        vm.startPrank(OWNER);

        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);

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
        Bid memory auctionWrongDoubleSelfBidWithSearcherEnough = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment() * 2);

        Bid memory auctionWrongBrokeBidderBidTooLow = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_BIDDER, 8*10**18);
        Bid memory auctionWrongBrokeBidderBidEnough = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_BIDDER, FLA.bid_increment() * 2);

        // Bid memory auctionWrongBrokeSearcherBid = Bid(VALIDATOR1, OPPORTUNITY1, BROKE_BIDDER, BROKE_SEARCHER, 8*10**18);

        Bid memory auctionRightOutbidsTopBidderFirstPair = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER2, SEARCHER_ADDRESS2, FLA.bid_increment() * 2);
       
        // Bid should be coming from EOA that's paying aka BIDDER1 from line 186.
        vm.expectRevert(bytes("FL:E-103"));
        FLA.submitBid(auctionWrongSearchableBid);
        
        // Attempts to bid from OPPORTUNITY2 which has not been enabled yet
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

        // Check checkpoint and cuts
        ValidatorBalanceCheckpoint memory vCheck = FLA.getCheckpoint(VALIDATOR1);

        (uint256 vCut,uint256 flCut) = _calculateCuts(auctionRightMinimumBidWithSearcher.bidAmount, FLA.fast_lane_fee());
        assertTrue(vCheck.pendingBalanceAtlastBid == vCut);
        assertTrue(vCheck.outstandingBalance == 0);
        assertTrue(vCheck.lastWithdrawnAuction == 0);
        assertTrue(vCheck.lastBidReceivedAuction == 1);

        assertTrue(FLA.outstandingFLBalance() == flCut);

        // Check balances
        assertEq(wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress), balanceBefore - auctionRightMinimumBidWithSearcher.bidAmount);
        assertEq(wMatic.balanceOf(address(FLA)), auctionRightMinimumBidWithSearcher.bidAmount);

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
        
        vm.startPrank(auctionRightOutbidsTopBidderFirstPair.searcherPayableAddress);

        // Approve as the Payable
        wMatic.approve(address(FLA), 2**256 - 1);


        uint balanceBeforeOfFirstBidder = wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress);
        uint balanceBeforeOfUpcomingBidder = wMatic.balanceOf(auctionRightOutbidsTopBidderFirstPair.searcherPayableAddress);
        uint outstandingFLBalanceBeforeOutbidding = FLA.outstandingFLBalance();

        vm.expectEmit(true, true, true, true, address(FLA));
        emit BidAdded(BIDDER2, VALIDATOR1, OPPORTUNITY1, FLA.bid_increment() * 2, 1);
        FLA.submitBid(auctionRightOutbidsTopBidderFirstPair);

        // Check refund since we have an existing bid
        uint balanceAfterOfFirstBidder = wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress);
        // Bidder1 is whole again
        assertTrue(balanceAfterOfFirstBidder == balanceBeforeOfFirstBidder + auctionRightMinimumBidWithSearcher.bidAmount);

        // Bidder2 balance was taken
        uint balanceAfterOfUpcomingBidder = wMatic.balanceOf(auctionRightOutbidsTopBidderFirstPair.searcherPayableAddress);
        assertTrue(balanceAfterOfUpcomingBidder == balanceBeforeOfUpcomingBidder - auctionRightOutbidsTopBidderFirstPair.bidAmount);

        // And into the contract
        assertEq(wMatic.balanceOf(address(FLA)), auctionRightOutbidsTopBidderFirstPair.bidAmount);

        // Get updated checkpoint
        vCheck = FLA.getCheckpoint(VALIDATOR1);
        (uint256 vCut2,uint256 flCut2) = _calculateCuts(auctionRightOutbidsTopBidderFirstPair.bidAmount, FLA.fast_lane_fee());
        assertTrue(vCheck.pendingBalanceAtlastBid == vCut2);
        assertTrue(vCheck.outstandingBalance == 0);
        assertTrue(vCheck.lastWithdrawnAuction == 0);
        assertTrue(vCheck.lastBidReceivedAuction == 1);

        assertTrue(FLA.outstandingFLBalance() == outstandingFLBalanceBeforeOutbidding - flCut + flCut2);


        vm.stopPrank();
        vm.startPrank(OWNER);

        uint cut = FLA.outstandingFLBalance();
        FLA.endAuction();
        assertTrue(wMatic.balanceOf(OWNER) == cut);
    }

    function _approveAndSubmitBid(address who, Bid memory bid) internal {
        vm.startPrank(who);
        wMatic.approve(address(FLA), 2**256 - 1);
        FLA.submitBid(bid);
        vm.stopPrank();
    }

    function testValidatorWithdrawals() public {
        vm.startPrank(OWNER);

        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);

        FLA.startAuction();

        FLA.enableOpportunityAddress(OPPORTUNITY3);
        FLA.enableValidatorAddress(VALIDATOR3);

        FLA.enableOpportunityAddress(OPPORTUNITY4);
        FLA.enableValidatorAddress(VALIDATOR4);

        FLA.endAuction();
        FLA.startAuction();

        assertTrue(FLA.auction_number() == 2);

        vm.stopPrank();
       
        
        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());
        Bid memory auctionRightOutbidsTopBidderFirstPair = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER2, SEARCHER_ADDRESS2, FLA.bid_increment() * 2);

        Bid memory auction2ndPairMinimumBidWithSearcher = Bid(VALIDATOR3, OPPORTUNITY3, BIDDER3, SEARCHER_ADDRESS3, FLA.bid_increment());
        Bid memory auction2ndPairOutbidsTopBidder2ndPair = Bid(VALIDATOR3, OPPORTUNITY3, BIDDER4, SEARCHER_ADDRESS4, FLA.bid_increment() * 2);
        
        Bid memory auction3rdPairValidator4MinimumBidWithSearcher = Bid(VALIDATOR4, OPPORTUNITY4, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());

        _approveAndSubmitBid(SEARCHER_ADDRESS1,auctionRightMinimumBidWithSearcher);
        _approveAndSubmitBid(SEARCHER_ADDRESS2,auctionRightOutbidsTopBidderFirstPair);


        // That outbit will be claimed later after 
        _approveAndSubmitBid(SEARCHER_ADDRESS3,auction2ndPairMinimumBidWithSearcher);
        _approveAndSubmitBid(SEARCHER_ADDRESS4,auction2ndPairOutbidsTopBidder2ndPair);

        // That bid will be claimed partially during an ongoing auction 
        _approveAndSubmitBid(SEARCHER_ADDRESS1,auction3rdPairValidator4MinimumBidWithSearcher);


        vm.prank(BIDDER3);
        vm.expectRevert(bytes("FL:E-104"));
        FLA.redeemOutstandingBalance(BIDDER3);

        // Try to get the cash before the end
        vm.prank(VALIDATOR1);
        vm.expectRevert(bytes("FL:E-207"));
        FLA.redeemOutstandingBalance(VALIDATOR1);

        vm.prank(OWNER);
        FLA.endAuction();

        // Now we can claim
        vm.startPrank(VALIDATOR1);
        ValidatorBalanceCheckpoint memory vCheck = FLA.getCheckpoint(VALIDATOR1);
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR1, 3, vCheck.pendingBalanceAtlastBid, VALIDATOR1, VALIDATOR1);
        FLA.redeemOutstandingBalance(VALIDATOR1);
        assertTrue(wMatic.balanceOf(VALIDATOR1) == vCheck.pendingBalanceAtlastBid);

        // Only once
        vm.expectRevert(bytes("FL:E-207"));
        FLA.redeemOutstandingBalance(VALIDATOR1);

        vm.stopPrank();
        vm.prank(OWNER);

        // We go again and bid on a validator that didn't redeem anything the previous auction
        FLA.startAuction();

        
        // This moves pendingBalanceAtlastBid to outstandingBalance, before setting a new pendingBalanceAtlastBid
        _approveAndSubmitBid(SEARCHER_ADDRESS3,auction2ndPairMinimumBidWithSearcher);
        _approveAndSubmitBid(SEARCHER_ADDRESS4,auction2ndPairOutbidsTopBidder2ndPair);

        // Bidding again on an unclaimed yet pair, and trying to claim for this validator now
        _approveAndSubmitBid(SEARCHER_ADDRESS1,auction3rdPairValidator4MinimumBidWithSearcher);

        // Claim while the auction still goes on for auction3rdPairValidator4MinimumBidWithSearcher
        vm.startPrank(VALIDATOR4);
        ValidatorBalanceCheckpoint memory vCheckOngoing = FLA.getCheckpoint(VALIDATOR4);
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR4, 3, vCheckOngoing.outstandingBalance, VALIDATOR4, VALIDATOR4);
        FLA.redeemOutstandingBalance(VALIDATOR4);
        assertTrue(wMatic.balanceOf(VALIDATOR4) == vCheckOngoing.outstandingBalance);

        vm.stopPrank();
        vm.prank(OWNER);
        FLA.endAuction();

        // Now we can claim
        vm.startPrank(VALIDATOR3);
        ValidatorBalanceCheckpoint memory vCheckLate = FLA.getCheckpoint(VALIDATOR3);
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR3, 4, vCheckLate.pendingBalanceAtlastBid + vCheckLate.outstandingBalance, VALIDATOR3, VALIDATOR3);
        FLA.redeemOutstandingBalance(VALIDATOR3);
        assertTrue(wMatic.balanceOf(VALIDATOR3) == vCheckLate.pendingBalanceAtlastBid + vCheckLate.outstandingBalance);

        // Only once
        vm.expectRevert(bytes("FL:E-207"));
        FLA.redeemOutstandingBalance(VALIDATOR1);

        // Finish draining validator4 so everyone is paid
        FLA.redeemOutstandingBalance(VALIDATOR4);
        assertTrue(wMatic.balanceOf(address(FLA)) == 0); // Everyone got paid, no more wMatic hanging in the contract
    }

    function testEnabledDisabledPairs() public {
        vm.startPrank(OWNER);

        // Enabling disabling opp or validator during auction not live
        // Should be no problem
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        vm.expectEmit(true, true, false, false, address(FLA));
        emit OpportunityAddressDisabled(OPPORTUNITY1, 1);
        FLA.disableOpportunityAddress(OPPORTUNITY1);



        // Disabling unseen opportunity should revert
        vm.expectRevert(bytes("FL:E-105"));
        FLA.disableOpportunityAddress(OPPORTUNITY4);

        // Re-enable 1 while not live
        FLA.enableOpportunityAddress(OPPORTUNITY1);

        FLA.enableValidatorAddress(VALIDATOR1);

        vm.expectRevert(bytes("FL:E-104"));
        FLA.disableValidatorAddress(VALIDATOR2);


        // Auction is now live, disables should be delayed
        FLA.startAuction();

        vm.expectEmit(true, true, false, false, address(FLA));
        emit OpportunityAddressDisabled(OPPORTUNITY1, 2);
        FLA.disableOpportunityAddress(OPPORTUNITY1);

        vm.expectEmit(true, true, false, false, address(FLA));
        emit ValidatorAddressDisabled(VALIDATOR1, 2);
        FLA.disableValidatorAddress(VALIDATOR1);

        // Should still be able to bid and outbid
        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());
        Bid memory auctionRightOutbidsTopBidderFirstPair = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER2, SEARCHER_ADDRESS2, FLA.bid_increment() * 2);

        vm.stopPrank();

        _approveAndSubmitBid(SEARCHER_ADDRESS1,auctionRightMinimumBidWithSearcher);
        _approveAndSubmitBid(SEARCHER_ADDRESS2,auctionRightOutbidsTopBidderFirstPair);


        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.startAuction();

        // Not anymore
        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(bytes("FL:E-209"));
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        vm.stopPrank();
        vm.startPrank(OWNER);


        assertTrue(FLA.auction_number() == 2);

        // Doesn't impact validator collecting
        ValidatorBalanceCheckpoint memory vCheck = FLA.getCheckpoint(VALIDATOR1);

        FLA.redeemOutstandingBalance(VALIDATOR1);
        assertTrue(wMatic.balanceOf(VALIDATOR1) == vCheck.pendingBalanceAtlastBid);
        

        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(bytes("FL:E-209"));
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Re-enable while live
        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);

        // Should still be locked until next auction
        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(bytes("FL:E-211"));
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.startAuction();

        // Now we can submit again
        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

    }

    function testValidatorsActive() public {
        //@todo: Code me.
        
    }

    function testValidatorPreferences() public {
        vm.startPrank(OWNER);
        
        uint24 fee = 50000*2; // 10%
        FLA.setFastlaneFee(fee);

        address validatorPayable = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
        uint128 amount = 3000*10**18;
        vm.expectEmit(true, true, false, false, address(FLA));
        emit ValidatorAddressEnabled(VALIDATOR1, 1);
        FLA.enableValidatorAddressWithPreferences(VALIDATOR1, amount, validatorPayable);

        vm.expectEmit(true, true, true, false, address(FLA));
        emit ValidatorPreferencesSet(VALIDATOR1, amount, validatorPayable);
        FLA.enableValidatorAddressWithPreferences(VALIDATOR1, amount, validatorPayable);

        vm.stopPrank();

        vm.prank(BIDDER1);
        vm.expectRevert(bytes("FL:E-104"));
        FLA.setValidatorPreferences(0, address(0));


        vm.startPrank(VALIDATOR1);
        address validatorPayableUpdated = 0x8e5f4552091a69125d5DfCb7B8C2659029395Bdf;
        uint128 updatedAmountTooLow = 4000;
        vm.expectRevert(bytes("FL:E-203"));
        FLA.setValidatorPreferences(updatedAmountTooLow, validatorPayableUpdated);

        uint128 updatedAmount = 5000*10**18;
        vm.expectEmit(true, true, true, false, address(FLA));
        emit ValidatorPreferencesSet(VALIDATOR1, updatedAmount, validatorPayableUpdated);
        FLA.setValidatorPreferences(updatedAmount, validatorPayableUpdated);

        // Now make a bid
        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.startAuction();
        vm.stopPrank();
        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());
        _approveAndSubmitBid(SEARCHER_ADDRESS1,auctionRightMinimumBidWithSearcher);

        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.redeemOutstandingBalance(VALIDATOR1);
        assertTrue(wMatic.balanceOf(validatorPayableUpdated) == 9000000000000000000);
    }
    function testGelatoAutoship() public {

        // Pump SEARCHER_ADDRESS1 balances since he'll be bidding on all validators
        vm.deal(SEARCHER_ADDRESS1,1000000*10**18);
        vm.prank(SEARCHER_ADDRESS1);
        wMatic.deposit{value: 1000000*10**18}();

        vm.startPrank(OWNER);
        uint24 fee = 0; // 0% so calculations are easier
        FLA.setFastlaneFee(fee);

        uint128 minAutoship = 2000 * (10**18);
        FLA.setMinimumAutoShipThreshold(minAutoship);

        // Force 2 payments per checker() call max
        FLA.setAutopayBatchSize(2);

        // First validator setup with enableValidatorAddressWithPreferences
        address validatorPayable1 = vm.addr(1);
        uint128 amount1 = minAutoship;
        FLA.enableValidatorAddressWithPreferences(VALIDATOR1, amount1, validatorPayable1);

        // 2nd validator setup with enableValidatorAddressWithPreferences as himself
        uint128 amount2 = minAutoship*2;
        FLA.enableValidatorAddressWithPreferences(VALIDATOR2, amount2, VALIDATOR2);

        // 3rd set up without autoship originally then adds it himself
        FLA.enableValidatorAddress(VALIDATOR3);
         uint128 amount3 = minAutoship*3;
         address validatorPayable3 = vm.addr(3);
         vm.stopPrank();
         vm.prank(VALIDATOR3);
         FLA.setValidatorPreferences(amount3, validatorPayable3);

         // 4th didn't ask for anything, he'll get default autoship
         vm.startPrank(OWNER);
         FLA.enableValidatorAddress(VALIDATOR4);
         
         // Now the opp
         FLA.enableOpportunityAddress(OPPORTUNITY1);

         (bool canExec, bytes memory execPayload) = FLA.checker();

         assertTrue(canExec == false);
         assertTrue(execPayload.length == 0); 

         FLA.startAuction();
         FLA.endAuction();

        (canExec, execPayload) = FLA.checker();

         assertTrue(canExec == false);
         assertTrue(execPayload.length == 0); 

         FLA.startAuction();

         vm.stopPrank();
         // Validator 1 will get his threshold met directly
         Bid memory bid1 = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount1);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid1);

         // Validator 2 will get his threshold met in 2 steps
         Bid memory bid2 = Bid(VALIDATOR2, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount2/2);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid2);

         // Validator 3 will get his threshold met directly
         Bid memory bid3 = Bid(VALIDATOR3, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount3);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid3);

         // Validator 2=4 will get his threshold met directly
         Bid memory bid4 = Bid(VALIDATOR4, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, minAutoship);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid4);

        // Check validatorsActiveAtAuction
        address[] memory prevRoundAddrs = FLA.getValidatorsActiveAtAuction(2);
        assertEq(prevRoundAddrs.length,4);

        // Verify checker still doesn't run

        // Turn off checker

        // Turn it back on and witness payments of 2

        // Call it again and witness payment of 1
        
        // Top the minimum to 10k
        vm.startPrank(OWNER);
        minAutoship = 10000*10**18;
        vm.expectEmit(true, false, false, false, address(FLA));
        emit MinimumAutoshipThresholdSet(minAutoship);
        FLA.setMinimumAutoShipThreshold(minAutoship);

    }
    function testUpgrade() public {
        //@todo: Maybe new file?
    }

    function testFeeUpdate() public {
        vm.startPrank(OWNER);
        uint24 abusiveFee = 1300000;
        vm.expectRevert(bytes("FL:E-213"));
        FLA.setFastlaneFee(abusiveFee);

        uint24 fee = 50000*2; // 10%
        FLA.setFastlaneFee(fee);

        FLA.enableValidatorAddress(VALIDATOR1);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.startAuction();
        vm.stopPrank();
        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, FLA.bid_increment());
        _approveAndSubmitBid(SEARCHER_ADDRESS1,auctionRightMinimumBidWithSearcher);

        vm.startPrank(OWNER);
        FLA.endAuction();

        // Check checkpoint and cuts
        ValidatorBalanceCheckpoint memory vCheck = FLA.getCheckpoint(VALIDATOR1);
        (uint256 vCut, uint256 pflCut) = _calculateCuts(auctionRightMinimumBidWithSearcher.bidAmount,FLA.fast_lane_fee());

        assertTrue(vCheck.pendingBalanceAtlastBid == vCut);
        assertTrue(vCheck.outstandingBalance == 0);
        assertTrue(vCheck.lastWithdrawnAuction == 0);
        assertTrue(vCheck.lastBidReceivedAuction == 1);

        FLA.redeemOutstandingBalance(VALIDATOR1);

        vCheck = FLA.getCheckpoint(VALIDATOR1);
        assertTrue(vCheck.pendingBalanceAtlastBid == 0);
        assertTrue(vCheck.outstandingBalance == 0);
        assertTrue(vCheck.lastWithdrawnAuction == 2);
        assertTrue(vCheck.lastBidReceivedAuction == 1);

        assertTrue(wMatic.balanceOf(VALIDATOR1) == vCut);
        assertTrue(wMatic.balanceOf(VALIDATOR1) == 9000000000000000000);
        assertTrue(wMatic.balanceOf(OWNER) == 1000000000000000000);
        assertTrue(wMatic.balanceOf(OWNER) == pflCut);

    }
}
