// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/legacy/FastLaneLegacyAuction.sol";

import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "contracts/interfaces/IWMatic.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";


// 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889 - Mumbai WMATIC
// 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270 - Polygon Mainnet WMATIC

abstract contract PFLHelper is Test, FastLaneEvents {

    using Address for address payable;
    FastLaneLegacyAuction public FLA;
    address constant MUMBAI_MATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address constant OPS_ADDRESS = address(0xBEEF);
    WMATIC public wMatic;

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

    address public REFUND_RECIPIENT = 0xFdE9601264EBB3B664B7E37E9D3487D8fabB9001;

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

    // function logReads(address addr) public {
    //     (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(
    //         address(addr)
    //     );
    //     for (uint256 i; i < reads.length; i++) {
    //         emit log_uint(uint256(reads[i]));
    //     }
    // }

    function _calculateCuts(uint256 amount,uint256 fee) internal pure returns (uint256 vCut, uint256 flCut) {
        vCut = (amount * (1000000 - fee)) / 1000000;
        flCut = amount - vCut;
    }

    function setUpMaticAndFastlane(bool noAuction) public returns (address) {
        // Obtained from
        // emit log_bytes(bytecode); of vm.getCode("Wmatic.sol")
        bytes memory bytecode = hex"60c0604052600d60808190527f57726170706564204d617469630000000000000000000000000000000000000060a090815261003e91600091906100a3565b506040805180820190915260068082527f574d4154494300000000000000000000000000000000000000000000000000006020909201918252610083916001916100a3565b506002805460ff1916601217905534801561009d57600080fd5b5061013e565b828054600181600116156101000203166002900490600052602060002090601f016020900481019282601f106100e457805160ff1916838001178555610111565b82800160010185558215610111579182015b828111156101115782518255916020019190600101906100f6565b5061011d929150610121565b5090565b61013b91905b8082111561011d5760008155600101610127565b90565b6106568061014d6000396000f3006080604052600436106100925760003560e01c63ffffffff16806306fdde031461009c578063095ea7b31461012657806318160ddd1461015e57806323b872dd146101855780632e1a7d4d146101af578063313ce567146101c757806370a08231146101f257806395d89b4114610213578063a9059cbb14610228578063d0e30db014610092578063dd62ed3e1461024c575b61009a610273565b005b3480156100a857600080fd5b506100b16102c2565b6040805160208082528351818301528351919283929083019185019080838360005b838110156100eb5781810151838201526020016100d3565b50505050905090810190601f1680156101185780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34801561013257600080fd5b5061014a600160a060020a0360043516602435610350565b604080519115158252519081900360200190f35b34801561016a57600080fd5b506101736103b6565b60408051918252519081900360200190f35b34801561019157600080fd5b5061014a600160a060020a03600435811690602435166044356103bb565b3480156101bb57600080fd5b5061009a6004356104ef565b3480156101d357600080fd5b506101dc610584565b6040805160ff9092168252519081900360200190f35b3480156101fe57600080fd5b50610173600160a060020a036004351661058d565b34801561021f57600080fd5b506100b161059f565b34801561023457600080fd5b5061014a600160a060020a03600435166024356105f9565b34801561025857600080fd5b50610173600160a060020a036004358116906024351661060d565b33600081815260036020908152604091829020805434908101909155825190815291517fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c9281900390910190a2565b6000805460408051602060026001851615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103485780601f1061031d57610100808354040283529160200191610348565b820191906000526020600020905b81548152906001019060200180831161032b57829003601f168201915b505050505081565b336000818152600460209081526040808320600160a060020a038716808552908352818420869055815186815291519394909390927f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925928290030190a350600192915050565b303190565b600160a060020a0383166000908152600360205260408120548211156103e057600080fd5b600160a060020a038416331480159061041e5750600160a060020a038416600090815260046020908152604080832033845290915290205460001914155b1561047e57600160a060020a038416600090815260046020908152604080832033845290915290205482111561045357600080fd5b600160a060020a03841660009081526004602090815260408083203384529091529020805483900390555b600160a060020a03808516600081815260036020908152604080832080548890039055938716808352918490208054870190558351868152935191937fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef929081900390910190a35060019392505050565b3360009081526003602052604090205481111561050b57600080fd5b33600081815260036020526040808220805485900390555183156108fc0291849190818181858888f1935050505015801561054a573d6000803e3d6000fd5b5060408051828152905133917f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65919081900360200190a250565b60025460ff1681565b60036020526000908152604090205481565b60018054604080516020600284861615610100026000190190941693909304601f810184900484028201840190925281815292918301828280156103485780601f1061031d57610100808354040283529160200191610348565b60006106063384846103bb565b9392505050565b6004602090815260009283526040808420909152908252902054815600a165627a7a723058206118e6580df80a8af43aaa932ff4545b6c57ca46d1b8c249807304c1f63050280029";
        
        address maticAddress;
        assembly {
            maticAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        vm.etch(MUMBAI_MATIC, maticAddress.code);

        vm.prank(OWNER);

        if (noAuction == false) {
            FLA = new FastLaneLegacyAuction(OWNER);

            vm.prank(OWNER);
            FLA.initialSetupAuction(MUMBAI_MATIC, OPS_ADDRESS, OWNER);
            return address(FLA);
        }
        
        return address(0);
    }

    function setUpBiddersSearchersWallets() public {
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
}
contract PFLAuctionTest is PFLHelper {



    function setUp() public {
  

        setUpMaticAndFastlane(false);
        setUpBiddersSearchersWallets();
        // address owner = FLA.owner();
        // console2.log("FLA OWNER:", owner);


        // console2.log("FLA deployed at:", address(FLA));
        // console2.log("WMATIC deployed at:", MUMBAI_MATIC);

        
    }

    function testStartStopNoBidAuction() public {
        console2.log("Sender", msg.sender);
        vm.startPrank(OWNER);
        // vm.record();

        FLA.startAuction();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 2);
        assertEq(FLA.getActivePrivilegesAuctionNumber(), 1);

        address starter = vm.addr(420);
        vm.expectEmit(true, false, false, false);
        emit AuctionStarterSet(starter);
        FLA.setStarter(starter);

        vm.stopPrank();
        vm.expectRevert(FastLaneEvents.PermissionNotOwnerNorStarter.selector);
        FLA.startAuction();

        vm.startPrank(starter);

        FLA.startAuction();
        FLA.endAuction();

        assertTrue(FLA.auction_number() == 3);
        assertEq(FLA.getActivePrivilegesAuctionNumber(), 2);
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
        assertTrue(st.activeAtAuctionRound == 1);
        assertTrue(st.inactiveAtAuctionRound == FLA.MAX_AUCTION_VALUE());
        assertTrue(st.kind == statusType.OPPORTUNITY);

        FLA.startAuction();
        FLA.enableValidatorAddress(VALIDATOR2);
        Status memory stVal2 = FLA.getStatus(VALIDATOR2);
        
        assertTrue(stVal2.activeAtAuctionRound == 2);
        assertTrue(stVal2.inactiveAtAuctionRound == FLA.MAX_AUCTION_VALUE());
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
        vm.expectRevert(FastLaneEvents.PermissionOnlyFromPayorEoa.selector);
        FLA.submitBid(auctionWrongSearchableBid);
        
        // Attempts to bid from OPPORTUNITY2 which has not been enabled yet
        vm.expectRevert(FastLaneEvents.PermissionMustBeValidator.selector);
        FLA.submitBid(auctionWrongValidatorBid);
        
        vm.expectRevert(FastLaneEvents.PermissionInvalidOpportunityAddress.selector);
        FLA.submitBid(auctionWrongOpportunityBid);

        vm.expectRevert(FastLaneEvents.InequalityTooLow.selector);
        FLA.submitBid(auctionWrongIncrementBid);

        vm.stopPrank(); // Not BIDDER1 anymore
        
        vm.startPrank(auctionRightMinimumBidWithSearcher.searcherPayableAddress);

        // Missing approval
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Approve as the Payable
        wMatic.approve(address(FLA), 2**256 - 1);

        // First correct bid 
        uint balanceBefore = wMatic.balanceOf(auctionRightMinimumBidWithSearcher.searcherPayableAddress);

        vm.expectEmit(true, true, true, true, address(FLA));
        emit BidAdded(BIDDER1, VALIDATOR1, OPPORTUNITY1, FLA.bid_increment(), 1);
        // Check event
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Check Top Bid
        {
            (uint256 topBidAmount, uint128 currentAuctionNumber) = FLA.findLiveAuctionTopBid(VALIDATOR1, OPPORTUNITY1);
            assertEq(topBidAmount, FLA.bid_increment());
            assertEq(currentAuctionNumber, 1);
        }

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

        vm.expectRevert(FastLaneEvents.InequalityTooLow.selector);
        FLA.submitBid(auctionWrongDoubleSelfBidWithSearcherTooLow);

        vm.expectRevert(FastLaneEvents.InequalityAlreadyTopBidder.selector);
        FLA.submitBid(auctionWrongDoubleSelfBidWithSearcherEnough);
  

        vm.stopPrank();

        // There was a bid valid before of FLA.bid_increment().
        // First we don't top it, then we do, but with an empty bank account. Both reverting.
        vm.startPrank(auctionWrongBrokeBidderBidTooLow.searcherPayableAddress);
        wMatic.approve(address(FLA), 2**256 - 1);
        vm.expectRevert(FastLaneEvents.InequalityTooLow.selector);
        FLA.submitBid(auctionWrongBrokeBidderBidTooLow);
       
        vm.expectRevert(FastLaneEvents.InequalityNotEnoughFunds.selector);
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

        // Check Top Bid
        {
            (uint256 topBidAmount, uint128 currentAuctionNumber) = FLA.findLiveAuctionTopBid(VALIDATOR1, OPPORTUNITY1);
            assertEq(topBidAmount, FLA.bid_increment()*2);
            assertEq(currentAuctionNumber, 1);
        }
        FLA.endAuction();
        assertTrue(wMatic.balanceOf(OWNER) == cut);

        // Check Winner
        {
            (bool hasWinner, address winner, uint128 winningAuctionNumber) = FLA.findFinalizedAuctionWinnerAtAuction(1,VALIDATOR1, OPPORTUNITY1);
            assertEq(hasWinner, true);
            assertEq(winner, BIDDER2);
            assertEq(winningAuctionNumber, 1);
        }
        {
            (bool hasWinner, address winner, uint128 winningAuctionNumber) = FLA.findLastFinalizedAuctionWinner(VALIDATOR1, OPPORTUNITY1);
            assertEq(hasWinner, true);
            assertEq(winner, BIDDER2);
            assertEq(winningAuctionNumber, 1);
        }
        // Check inexistant winner
        {
            (bool hasWinner, address winner, uint128 winningAuctionNumber) = FLA.findFinalizedAuctionWinnerAtAuction(1,VALIDATOR1, OPPORTUNITY3);
            assertEq(hasWinner, false);
            assertEq(winner, address(0));
            assertEq(winningAuctionNumber, 1);
        }

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
        vm.expectRevert(FastLaneEvents.PermissionMustBeValidator.selector);
        FLA.redeemOutstandingBalance(BIDDER3);

        // Try to get the cash before the end
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneEvents.InequalityNothingToRedeem.selector);

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
        vm.expectRevert(FastLaneEvents.InequalityNothingToRedeem.selector);

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
        vm.expectRevert(FastLaneEvents.InequalityNothingToRedeem.selector);

        FLA.redeemOutstandingBalance(VALIDATOR1);

        // Finish draining validator4 so everyone is paid
        FLA.redeemOutstandingBalance(VALIDATOR4);
        assertTrue(wMatic.balanceOf(address(FLA)) == 0); // Everyone got paid, no more wMatic hanging in the contract
    }

    function testBidIncrement() public {
        vm.startPrank(OWNER);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);
        FLA.setMinimumBidIncrement(1000*10**18);
        FLA.startAuction();
        Bid memory bidTooLow = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, 100);
        vm.stopPrank();
        vm.startPrank(bidTooLow.searcherPayableAddress);
        wMatic.approve(address(FLA), 2**256 - 1);
        vm.expectRevert(FastLaneEvents.InequalityTooLow.selector);
        FLA.submitBid(bidTooLow);
        vm.stopPrank();
        vm.prank(OWNER);
        FLA.setMinimumBidIncrement(99);
        vm.startPrank(bidTooLow.searcherPayableAddress);
        FLA.submitBid(bidTooLow);
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
        vm.expectRevert(FastLaneEvents.PermissionInvalidOpportunityAddress.selector);
        FLA.disableOpportunityAddress(OPPORTUNITY4);

        // Re-enable 1 while not live
        FLA.enableOpportunityAddress(OPPORTUNITY1);

        FLA.enableValidatorAddress(VALIDATOR1);

        vm.expectRevert(FastLaneEvents.PermissionMustBeValidator.selector);
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
        vm.expectRevert(FastLaneEvents.InequalityValidatorDisabledAtTime.selector);
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
        vm.expectRevert(FastLaneEvents.InequalityValidatorDisabledAtTime.selector);
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        // Re-enable while live
        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        FLA.enableValidatorAddress(VALIDATOR1);

        // Should still be locked until next auction
        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneEvents.InequalityValidatorNotEnabledYet.selector);

        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.startAuction();

        // Now we can submit again
        vm.stopPrank();
        vm.prank(SEARCHER_ADDRESS1);
        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        vm.startPrank(OWNER);
        FLA.disableOpportunityAddress(OPPORTUNITY1);
        FLA.endAuction();
        FLA.startAuction();
        
        vm.stopPrank();
        vm.prank(SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneEvents.InequalityOpportunityDisabledAtTime.selector);

        FLA.submitBid(auctionRightMinimumBidWithSearcher);

        vm.prank(OWNER);
        FLA.enableOpportunityAddress(OPPORTUNITY1);
        vm.prank(SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneEvents.InequalityOpportunityNotEnabledYet.selector);

        FLA.submitBid(auctionRightMinimumBidWithSearcher);

    }

    function testPausedState() public {
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, false, false, address(FLA));
        emit PausedStateSet(true);
        FLA.setPausedState(true);
        FLA.startAuction();
        vm.expectRevert(FastLaneEvents.PermissionPaused.selector);
        Bid memory auctionRightMinimumBidWithSearcher = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, 2000*10**18);
        FLA.submitBid(auctionRightMinimumBidWithSearcher);
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
        vm.expectRevert(FastLaneEvents.PermissionMustBeValidator.selector);
        FLA.setValidatorPreferences(0, address(0));


        vm.startPrank(VALIDATOR1);
        address validatorPayableUpdated = 0x8e5f4552091a69125d5DfCb7B8C2659029395Bdf;
        uint128 updatedAmountTooLow = 4000;
        vm.expectRevert(FastLaneEvents.InequalityTooLow.selector);
        FLA.setValidatorPreferences(updatedAmountTooLow, validatorPayableUpdated);

        uint128 updatedAmount = 5000*10**18;

        vm.expectRevert(FastLaneEvents.InequalityAddressMismatch.selector);
        FLA.setValidatorPreferences(updatedAmount, address(FLA));


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

    // Avoid foundry stack too deep
    function _splitTestGelatoPreStartChecker() internal {
                {
         (bool canExec, bytes memory execPayload) = FLA.checker();

         assertTrue(canExec == false);
         assertTrue(execPayload.length == 0); 
        }


         FLA.startAuction();
         FLA.endAuction(); // auction_index == 2

        {
         (bool canExec, bytes memory execPayload) = FLA.checker();

         assertTrue(canExec == false);
         assertTrue(execPayload.length == 0); 
        }

         FLA.startAuction();

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
        
        _splitTestGelatoPreStartChecker(); // auction_index == 2

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

         // Validator 4 will get his threshold met directly
         Bid memory bid4 = Bid(VALIDATOR4, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, minAutoship);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid4);

        // Check validatorsactiveAtAuctionRound
        {
        address[] memory prevRoundAddrs = FLA.getValidatorsactiveAtAuctionRound(2);

        // Should have 4 validators active
        assertEq(prevRoundAddrs.length,4);
        }


        // Verify checker still doesn't run
        {
         (bool canExecR1, bytes memory execPayloadR1) = FLA.checker();

         assertTrue(canExecR1 == false);
         assertTrue(execPayloadR1.length == 0); 
        }
        // Turn off checker

        vm.startPrank(OWNER);
        FLA.setOffchainCheckerDisabledState(true);
        FLA.endAuction(); // auction_index == 3
        FLA.startAuction();

        // Verify checker still doesn't run even if it could from balances
        {
         (bool canExecR2, bytes memory execPayloadR2) = FLA.checker();

         assertTrue(canExecR2 == false);
         assertTrue(execPayloadR2.length == 0); 
        }

        // New bid on new auction_number so balances of VALIDATOR1 are moved to outstanding.
        // Should not impact anything
        vm.stopPrank();
         _approveAndSubmitBid(SEARCHER_ADDRESS1,bid1);
        vm.startPrank(OWNER);
        // Turn it back on and witness payments of 2
        FLA.setOffchainCheckerDisabledState(false);

        {
            ValidatorBalanceCheckpoint memory vCheckOngoing = FLA.getCheckpoint(VALIDATOR1);
            assertTrue(vCheckOngoing.outstandingBalance >= amount1);
        }

        {
        (bool hasJobs,) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, true);
        }

        (bool canExec, bytes memory execPayload) = FLA.checker();

         assertTrue(canExec == true);
         assertTrue(execPayload.length > 0);
        

        vm.stopPrank();
        vm.startPrank(OPS_ADDRESS);
        {
        // Validator 1 and 3 should have been autoshipped
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR1, 3, 2000 * (10**18), vm.addr(1), OPS_ADDRESS);
        
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR3, 3, 6000 * (10**18), vm.addr(3), OPS_ADDRESS);


        (bool success,) = address(FLA).call(execPayload);
         assertTrue(success);
        }
    
        // Call it again and witness payment of 1
        {
            (bool hasJobs4,) = FLA.getAutopayJobs(2, 2);
            assertEq(hasJobs4, true);

            (bool canExec4, bytes memory execPayload4) = FLA.checker();

             assertTrue(canExec4 == true);
             assertTrue(execPayload4.length > 0);
            // Validator 4 will get autoship
            vm.expectEmit(true, true, true, true, address(FLA));
            emit ValidatorWithdrawnBalance(VALIDATOR4, 3, 2000 * (10**18), VALIDATOR4, OPS_ADDRESS);

            (bool success,) = address(FLA).call(execPayload4);
            assertTrue(success);

            // No more folks to handle
            (bool canExec5,) = FLA.checker();
            assertTrue(canExec5 == false);
        }


    }

    function testRedeemableOutstanding() public {

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
        uint128 amount2 = minAutoship*2; // Autoship at 4k
        FLA.enableValidatorAddressWithPreferences(VALIDATOR2, amount2, VALIDATOR2);

         // Now the opp
         FLA.enableOpportunityAddress(OPPORTUNITY1);
        
        _splitTestGelatoPreStartChecker(); // auction_index == 2

         vm.stopPrank();
         // Validator 1 will get his threshold met directly
         Bid memory bid1 = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount1);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid1);

         // Validator 2 will get his threshold met in 2 steps
         Bid memory bid2 = Bid(VALIDATOR2, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount2/2);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid2);

        // Check validatorsactiveAtAuctionRound
        {
        address[] memory prevRoundAddrs = FLA.getValidatorsactiveAtAuctionRound(2);

        // Should have 2 validators active
        assertEq(prevRoundAddrs.length,2);
        }


        // Verify checker still doesn't run
        {
         (bool canExec1, bytes memory execPayload1) = FLA.checker();

         assertTrue(canExec1 == false);
         assertTrue(execPayload1.length == 0); 
        }

        (bool hasJobs, address[] memory autopayRecipients) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, false);
        assertEq(autopayRecipients[0],address(0));
        assertEq(autopayRecipients[1],address(0));

        vm.startPrank(OWNER);
        FLA.endAuction(); // auction_index == 3
        FLA.startAuction();

        {
            ValidatorBalanceCheckpoint memory vCheckOngoing = FLA.getCheckpoint(VALIDATOR1);
            assertEq(vCheckOngoing.pendingBalanceAtlastBid, amount1);
        }

        {
            ValidatorPreferences memory valPrefs = FLA.getPreferences(VALIDATOR2);
            assertEq(valPrefs.minAutoshipAmount, 4000 * (10**18));

            ValidatorBalanceCheckpoint memory vCheckOngoing = FLA.getCheckpoint(VALIDATOR2);
            assertEq(vCheckOngoing.pendingBalanceAtlastBid, amount2/2);
            assertEq(vCheckOngoing.outstandingBalance, 0);
            // Forge coverage being drunk ? Says checkRedeemableOutstanding never branches out
            // Making _checkRedeemableOutstanding -> checkRedeemableOutstanding (public) and testing
            // both variations still trips out coverage
            // bool isRedeemable = FLA.checkRedeemableOutstanding(vCheckOngoing, valPrefs.minAutoshipAmount);
            // assertEq(isRedeemable, false);
        }



        
        (hasJobs, autopayRecipients) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, true);
        assertEq(autopayRecipients[0],VALIDATOR1);
        assertEq(autopayRecipients[1],address(0));
        

        (bool canExec, bytes memory execPayload) = FLA.checker();

         assertTrue(canExec == true);
         assertTrue(execPayload.length > 0);
        

        vm.stopPrank();
        vm.startPrank(OPS_ADDRESS);
        {
        // Validator 1 should have been autoshipped
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR1, 3, 2000 * (10**18), vm.addr(1), OPS_ADDRESS);
        
        (bool success,) = address(FLA).call(execPayload);
         assertTrue(success);
        }

        (hasJobs,autopayRecipients) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, false);
        assertEq(autopayRecipients[0],address(0));
        assertEq(autopayRecipients[1],address(0));

        vm.stopPrank();
        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.startAuction();
        vm.stopPrank();

        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid2);

        (hasJobs,autopayRecipients) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, false);
        assertEq(autopayRecipients[0],address(0));
        assertEq(autopayRecipients[1],address(0));

        vm.startPrank(OWNER);
        FLA.endAuction();
        FLA.startAuction();

        (hasJobs,autopayRecipients) = FLA.getAutopayJobs(2, 2);
        assertEq(hasJobs, true);
        assertEq(autopayRecipients[0],VALIDATOR2);
        assertEq(autopayRecipients[1],address(0));

        {
            ValidatorBalanceCheckpoint memory vCheckOngoing = FLA.getCheckpoint(VALIDATOR2);
            assertEq(vCheckOngoing.pendingBalanceAtlastBid, amount2/2);
            assertEq(vCheckOngoing.outstandingBalance, amount2/2);
            // bool isRedeemable = FLA.checkRedeemableOutstanding(vCheckOngoing, 4000*10**18);
            // assertEq(isRedeemable, true);
        }

        (canExec, execPayload) = FLA.checker();

         assertTrue(canExec == true);
         assertTrue(execPayload.length > 0);
        

        vm.stopPrank();
        vm.startPrank(OPS_ADDRESS);
        {
        // Validator 2 should have been autoshipped
        vm.expectEmit(true, true, true, true, address(FLA));
        emit ValidatorWithdrawnBalance(VALIDATOR2, 5, 4000 * (10**18), VALIDATOR2, OPS_ADDRESS);
        
        (bool success,) = address(FLA).call(execPayload);
         assertTrue(success);
        }

    }

    function testReinitSetup() public {
        vm.expectRevert(FastLaneEvents.TimeAlreadyInit.selector);
        vm.prank(OWNER);
        FLA.initialSetupAuction(vm.addr(1),OPS_ADDRESS, VALIDATOR2);
    }

    function testAutoshipThreshold() public {
        vm.startPrank(OWNER);
        uint128 minAutoship = 10000*10**18;
        vm.expectEmit(true, false, false, false, address(FLA));
        emit MinimumAutoshipThresholdSet(minAutoship);
        FLA.setMinimumAutoShipThreshold(minAutoship);
    }

    function testGasChecker() public {

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

        // Now the opp
         FLA.enableOpportunityAddress(OPPORTUNITY1);
        
        _splitTestGelatoPreStartChecker(); // auction_index == 2

         vm.stopPrank();
         // Validator 1 will get his threshold met directly
         Bid memory bid1 = Bid(VALIDATOR1, OPPORTUNITY1, BIDDER1, SEARCHER_ADDRESS1, amount1);
        _approveAndSubmitBid(SEARCHER_ADDRESS1,bid1);

        // Check validatorsactiveAtAuctionRound
        {
        address[] memory prevRoundAddrs = FLA.getValidatorsactiveAtAuctionRound(2);

        // Should have 1 validator active
        assertEq(prevRoundAddrs.length,1);
        }


        // Verify checker still doesn't run
        {
         (bool canExecR1, bytes memory execPayloadR1) = FLA.checker();

         assertTrue(canExecR1 == false);
         assertTrue(execPayloadR1.length == 0); 
        }
        // Turn off checker with gas

        vm.startPrank(OWNER);
        vm.expectEmit(true, false, false, false, address(FLA));
        emit ResolverMaxGasPriceSet(0);
        FLA.setResolverMaxGasPrice(0);
        
        FLA.endAuction(); // auction_index == 3
        FLA.startAuction();

        vm.expectEmit(true, false, false, false, address(FLA));
        emit OpsSet(vm.addr(1337));
        FLA.setOps(vm.addr(1337));
        vm.stopPrank();

        vm.startPrank(vm.addr(1337));
        // Verify checker still doesn't run even if it could from balances
        (bool canExec, bytes memory execPayload) = FLA.checker();

        assertTrue(canExec == false);
        assertTrue(execPayload.length == 0);

        address[] memory recipients = new address[](2);
        recipients[1] = vm.addr(1);
        vm.expectRevert(FastLaneEvents.TimeGasNotSuitable.selector);

        FLA.processAutopayJobs(recipients);
        
        vm.stopPrank();
        vm.prank(OWNER);
        FLA.setResolverMaxGasPrice(10*10**18);

        vm.startPrank(vm.addr(1337));
        (canExec, execPayload) = FLA.checker();
        assertTrue(canExec == true);
    }

    function testEmergencyWithdraw() public {
        vm.deal(address(FLA),10*10**18);
        
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, false, false, address(FLA));
        emit WithdrawStuckNativeToken(OWNER, 10*10**18);
        FLA.withdrawStuckNativeToken(10*10**18);
        assertEq(OWNER.balance, 10*10**18);

        MockERC20 token = new MockERC20("Token", "TKN", 18);
        token.mint(address(FLA), 1e18);

        vm.expectEmit(true, true, true, false, address(FLA));
        emit WithdrawStuckERC20(address(FLA), OWNER, 1e18);
        FLA.withdrawStuckERC20(address(token));
        assertEq(token.balanceOf(OWNER), 1e18);
        assertEq(token.balanceOf(address(FLA)), 0);

        vm.expectRevert(FastLaneEvents.InequalityWrongToken.selector);
        FLA.withdrawStuckERC20(address(wMatic));
    }

    function testBidToken() public {
        vm.startPrank(OWNER);
        address badToken = address(0);
        vm.expectRevert(FastLaneEvents.GeneralFailure.selector);
        FLA.setBidToken(badToken);
    }

    function testFeeUpdate() public {
        vm.startPrank(OWNER);
        uint24 abusiveFee = 1300000;
        vm.expectRevert(FastLaneEvents.InequalityTooHigh.selector);
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
