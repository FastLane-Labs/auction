// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "openzeppelin-contracts/contracts/utils/Strings.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "contracts/auction-handler/FastLaneAuctionHandler.sol";
import {SearcherContractExample} from "contracts/searcher-direct/FastLaneSearcherDirect.sol";
import {PFLHelper} from "test/helpers/PFLHelper.sol";
import {MockPaymentProcessor, MockPaymentProcessorBroken} from "./mocks/MockPaymentProcessor.sol";

contract PFLAuctionHandlerTest is PFLHelper, FastLaneAuctionHandlerEvents, Test {
    // TODO consider moving addrs to PFLAuction or another helper
    address constant PAYEE1 = address(0x8881);
    address constant PAYEE2 = address(0x8882);

    // USER replaces OWNER since Auction is no longer ownable
    address constant USER = address(0x9090);
    address constant SEARCHER_OWNER = address(0x9091);

    FastLaneAuctionHandler PFR;
    BrokenUniswap brokenUniswap;
    address PFL_VAULT = OPS_ADDRESS;

    function setUp() public {
        // Give money
        for (uint256 i = 0; i < BIDDERS.length; i++) {
            address currentBidder = BIDDERS[i];
            address currentSearcher = SEARCHERS[i];
            uint256 soonWMaticBidder = (10 ether * (i + 1));
            uint256 soonWMaticSearcher = (33 ether * (i + 1));
            vm.label(currentBidder, string.concat("BIDDER", Strings.toString(i + 1)));
            vm.label(currentSearcher, string.concat("SEARCHER", Strings.toString(i + 1)));
            vm.deal(currentBidder, soonWMaticBidder + 1);
            vm.deal(currentSearcher, soonWMaticSearcher + 1);
        }

        uint24 stakeShare = 50_000;
        // Use PFL_VAULT as vault for repay checks
        PFR = new FastLaneAuctionHandler();
        brokenUniswap = new BrokenUniswap();

        vm.deal(address(brokenUniswap), 100 ether);
        vm.deal(USER, 100 ether);
        vm.coinbase(VALIDATOR1);
        vm.label(VALIDATOR1, "VALIDATOR1");
        vm.label(VALIDATOR2, "VALIDATOR2");
        vm.label(USER, "USER");
        console.log("Block Coinbase: %s", block.coinbase);
        vm.warp(1641070800);
    }

    function testSubmitFlashBid() public {
        vm.deal(SEARCHER_ADDRESS1, 150 ether);

        uint256 bidAmount = 0.001 ether;
        bytes32 oppTx = bytes32("tx1");

        // Deploy Searcher Wrapper as SEARCHER_ADDRESS1
        vm.startPrank(SEARCHER_ADDRESS1);
        SearcherContractExample SCE = new SearcherContractExample();
        SearcherRepayerOverpayerDouble SCEOverpay = new SearcherRepayerOverpayerDouble();
        vm.stopPrank();

        address to = address(SCE);

        address expectedAnAddress = vm.addr(12);
        uint256 expectedAnAmount = 1337;

        // Simply abi encode the args we want to forward to the searcher contract so it can execute them
        bytes memory searcherCallData =
            abi.encodeWithSignature("doStuff(address,uint256)", expectedAnAddress, expectedAnAmount);

        console.log("Tx origin: %s", tx.origin);
        console.log("Address this: %s", address(this));
        console.log("Address PFR: %s", address(PFR));
        console.log("Owner SCE: %s", SCE.owner());

        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBid(bidAmount, oppTx, address(0), searcherCallData);

        bidAmount = 2 ether;

        SCE.setPFLAuctionAddress(address(0));
        vm.expectRevert(bytes("InvalidPermissions"));
        PFR.submitFlashBid(bidAmount, oppTx, to, searcherCallData);
        // Authorize Relay as Searcher
        SCE.setPFLAuctionAddress(address(PFR));

        // Authorize test address as EOA
        SCE.approveFastLaneEOA(address(this));

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 0"));
        PFR.submitFlashBid(bidAmount, oppTx, to, searcherCallData);

        // Can oddly revert with "EvmError: OutOfFund".
        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 1000000000000000000"));
        console.log("Balance SCE: %s", to.balance);
        PFR.submitFlashBid{value: 1 ether}(bidAmount, oppTx, to, searcherCallData);

        uint256 snap = vm.snapshot();

        vm.expectEmit(true, true, true, true);
        emit RelayFlashBid(SEARCHER_ADDRESS1, oppTx, VALIDATOR1, bidAmount, bidAmount, address(SCE));
        PFR.submitFlashBid{value: bidAmount}(bidAmount, oppTx, to, searcherCallData);

        // Check Balances
        console.log("Balance PFR: %s", address(PFR).balance);
        assertEq(bidAmount, address(PFR).balance);

        // Verify `doStuff` got hit
        assertEq(expectedAnAddress, SCE.anAddress());
        assertEq(expectedAnAmount, SCE.anAmount());

        // Replay attempt
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayAuctionBidReceivedLate.selector);
        PFR.submitFlashBid{value: 5 ether}(bidAmount, oppTx, to, searcherCallData);

        // Not winner
        vm.expectRevert(
            abi.encodeWithSelector(
                FastLaneAuctionHandlerEvents.RelayAuctionSearcherNotWinner.selector, bidAmount - 1, bidAmount
            )
        );
        PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, oppTx, to, searcherCallData);

        uint256 snap2 = vm.snapshot();

        vm.revertTo(snap);
        to = address(SCEOverpay);

        // Searcher overpays
        vm.expectEmit(true, true, true, true);
        emit RelayFlashBid(SEARCHER_ADDRESS1, oppTx, VALIDATOR1, 2.5 ether, 5 ether, address(SCEOverpay));
        PFR.submitFlashBid{value: 5 ether}(2.5 ether, oppTx, to, searcherCallData);

        vm.revertTo(snap2);
        to = address(SCE);

        // Failed searcher call inside their contract
        bytes memory searcherFailCallData = abi.encodeWithSignature("doFail()");
        {
            vm.expectRevert("FAIL_ON_PURPOSE");
            PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, bytes32("willfailtx"), to, searcherFailCallData);
        }
    }

    function testSubmitFlashBidWithRefund() public {
        vm.deal(SEARCHER_ADDRESS1, 150 ether);

        uint256 bidAmount = 0.001 ether;
        bytes32 oppTx = bytes32("tx1");

        // Deploy Searcher Wrapper as SEARCHER_ADDRESS1 and enable the validator
        vm.startPrank(SEARCHER_ADDRESS1);
        SearcherContractExample SCE = new SearcherContractExample();
        SearcherRepayerOverpayerDouble SCEOverpay = new SearcherRepayerOverpayerDouble();
        PFR.payValidatorFee{value: 1}(SEARCHER_ADDRESS1);
        vm.deal(address(PFR), 0); // fixes a test later down the line that checks auction contract balance
        vm.stopPrank();

        // Set the refund up
        vm.startPrank(VALIDATOR1); // should fail if validator is changing their own block
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayImmutableBlockAuthorRate.selector);
        PFR.updateValidatorRefundShare(0);
        vm.coinbase(address(0));
        PFR.updateValidatorRefundShare(5000); // 50%
        vm.coinbase(VALIDATOR1);
        vm.stopPrank();

        address to = address(SCE);

        address expectedAnAddress = vm.addr(12);
        uint256 expectedAnAmount = 1337;

        // Simply abi encode the args we want to forward to the searcher contract so it can execute them
        bytes memory searcherCallData = abi.encodeWithSignature("doStuff(address,uint256)", vm.addr(12), 1337);

        console.log("Tx origin: %s", tx.origin);
        console.log("Address this: %s", address(this));
        console.log("Address PFR: %s", address(PFR));
        console.log("Owner SCE: %s", SCE.owner());

        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBidWithRefund(bidAmount, oppTx, REFUND_RECIPIENT, address(0), searcherCallData);

        bidAmount = 2 ether;

        SCE.setPFLAuctionAddress(address(0));
        vm.expectRevert(bytes("InvalidPermissions"));
        PFR.submitFlashBidWithRefund(bidAmount, oppTx, REFUND_RECIPIENT, to, searcherCallData);
        // Authorize Relay as Searcher
        SCE.setPFLAuctionAddress(address(PFR));

        // Authorize test address as EOA
        SCE.approveFastLaneEOA(address(this));

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 0"));
        PFR.submitFlashBidWithRefund(bidAmount, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        // Can oddly revert with "EvmError: OutOfFund".
        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 1000000000000000000"));
        console.log("Balance SCE: %s", to.balance);
        PFR.submitFlashBidWithRefund{value: 1 ether}(bidAmount, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        uint256 snap = vm.snapshot();

        vm.expectEmit(true, true, true, true);
        emit RelayFlashBidWithRefund(
            SEARCHER_ADDRESS1, oppTx, VALIDATOR1, 2 ether, 2 ether, address(SCE), 1 ether, REFUND_RECIPIENT
        );
        PFR.submitFlashBidWithRefund{value: 5 ether}(2 ether, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        // Check Balances
        console.log("Balance PFR: %s", address(PFR).balance);
        assertEq(bidAmount / 2, address(PFR).balance);

        console.log("Balance refund recipient: %s", REFUND_RECIPIENT.balance);
        assertEq(bidAmount / 2, REFUND_RECIPIENT.balance);

        // Verify `doStuff` got hit
        assertEq(expectedAnAddress, SCE.anAddress());
        assertEq(expectedAnAmount, SCE.anAmount());

        // Replay attempt
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayAuctionBidReceivedLate.selector);
        PFR.submitFlashBidWithRefund{value: 5 ether}(bidAmount, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        // Not winner
        vm.expectRevert(
            abi.encodeWithSelector(
                FastLaneAuctionHandlerEvents.RelayAuctionSearcherNotWinner.selector, bidAmount - 1, bidAmount
            )
        );
        PFR.submitFlashBidWithRefund{value: 5 ether}(bidAmount - 1, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        uint256 snap2 = vm.snapshot();

        vm.revertTo(snap);
        to = address(SCEOverpay);

        // Searcher overpays
        vm.expectEmit(true, true, true, true);
        emit RelayFlashBidWithRefund(
            SEARCHER_ADDRESS1, oppTx, VALIDATOR1, 2.5 ether, 5 ether, address(SCEOverpay), 2.5 ether, REFUND_RECIPIENT
        );
        PFR.submitFlashBidWithRefund{value: 5 ether}(2.5 ether, oppTx, REFUND_RECIPIENT, to, searcherCallData);

        vm.revertTo(snap2);
        to = address(SCE);

        // Failed searcher call inside their contract
        bytes memory searcherFailCallData = abi.encodeWithSignature("doFail()");
        {
            vm.expectRevert("FAIL_ON_PURPOSE");
            PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, bytes32("willfailtx"), to, searcherFailCallData);
        }
    }

    function testCantExternalfastBidWrapper() public {
        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayMustBeSelf.selector);
        PFR.fastBidWrapper(address(0), 0, address(0), bytes("willfail"));
    }

    function testSubmitFastBid() public {
        vm.deal(SEARCHER_ADDRESS1, 150 ether);
        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);

        SearcherContractExample SCE = new SearcherContractExample();
        SCE.setPFLAuctionAddress(address(PFR));

        bytes memory searcherCallData = abi.encodeWithSignature("doStuff(address,uint256)", vm.addr(12), 1337);

        // RelaySearcherWrongParams revert
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.submitFastBid(20 gwei, false, address(PFR), searcherCallData); // searcherToAddress = PFR

        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.submitFastBid(20 gwei, false, SEARCHER_ADDRESS1, searcherCallData); // searcherToAddress = searcher's EOA

        vm.stopPrank();
    }

    function testWrongSearcherRepay() public {
        uint256 bidAmount = 2 ether;

        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);

        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        // Searcher BSFFLC contract forgot to implement fastLaneCall(uint256,address,bytes)
        BrokenSearcherForgotFastLaneCallFn BSFFLC = new BrokenSearcherForgotFastLaneCallFn();
        vm.expectRevert();
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BSFFLC), searcherUnusedData);

        // Searcher BSFFLC contract implemented `fastLaneCall` but forgot to return (bool, bytes);
        BrokenSearcherForgotReturnBoolBytes BSFRBB = new BrokenSearcherForgotReturnBoolBytes();
        vm.expectRevert();
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BSFRBB), searcherUnusedData);

        // Searcher implemented but doesn't manage to repay the relay
        BrokenSearcherRepayer BRP = new BrokenSearcherRepayer();
        vm.expectRevert(abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelayNotRepaid.selector, bidAmount, 0));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRP), searcherUnusedData);

        // Searcher implemented but doesn't manage to repay the relay in full
        BrokenSearcherRepayerPartial BRPP = new BrokenSearcherRepayerPartial();
        vm.deal(address(BRPP), 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelayNotRepaid.selector, bidAmount, 1 ether)
        );
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRPP), searcherUnusedData);
    }

    function testSimulateFlashBid() public {
        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        SearcherRepayerEcho SRE = new SearcherRepayerEcho();

        uint256 bidAmount = 0.00002 ether;
        bytes32 oppTx = bytes32("fakeTx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        vm.expectEmit(true, true, true, true);
        emit RelaySimulatedFlashBid(SEARCHER_ADDRESS1, bidAmount, oppTx, block.coinbase, address(SRE));
        PFR.simulateFlashBid{value: 5 ether}(bidAmount, oppTx, address(SRE), searcherUnusedData);
        vm.stopPrank();

        vm.prank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.simulateFlashBid{value: 5 ether}(bidAmount, oppTx, address(0), searcherUnusedData);
    }

    function testCollectReentrantFail() public {
        vm.deal(SEARCHER_ADDRESS1, 100 ether);

        uint256 bidAmount = 2 ether;
        uint256 expectedValidatorPayout = bidAmount - 1;
        bytes32 oppTx = bytes32("tx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        SearcherRepayerEvilEcho SRE = new SearcherRepayerEvilEcho();

        vm.prank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        vm.expectRevert();
        PFR.submitFlashBid{value: bidAmount}(bidAmount, bytes32("randomTx"), address(SRE), searcherUnusedData);
    }

    function testCollectFees() public {
        vm.deal(SEARCHER_ADDRESS1, 100 ether);
        address EXCESS_RECIPIENT = address(0);

        uint256 bidAmount = 2 ether;
        uint256 validatorCut = (bidAmount * (1_000_000 - 50_000)) / 1_000_000;
        uint256 excessBalance = bidAmount - validatorCut;
        uint256 expectedValidatorPayout = validatorCut - 1;
        bytes32 oppTx = bytes32("tx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        SearcherRepayerEcho SRE = new SearcherRepayerEcho();

        vm.prank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        PFR.submitFlashBid{value: bidAmount}(bidAmount, bytes32("randomTx"), address(SRE), searcherUnusedData);

        uint256 snap = vm.snapshot();

        // As V1 pay itself
        uint256 excessRecipientBalanceBefore = EXCESS_RECIPIENT.balance;
        uint256 balanceBefore = VALIDATOR1.balance;
        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, expectedValidatorPayout, VALIDATOR1);
        emit RelayProcessingExcessBalance(address(0), excessBalance);

        vm.prank(VALIDATOR1);
        
        uint256 returnedAmountPaid = PFR.collectFees();
        uint256 actualAmountPaid = VALIDATOR1.balance - balanceBefore;
        uint256 excessRecipientBalanceAfter = EXCESS_RECIPIENT.balance;

        // Excess balance was sent to the excess recipient
        assertEq(excessRecipientBalanceAfter - excessRecipientBalanceBefore, excessBalance);

        // Validator actually got paid as expected
        assertEq(returnedAmountPaid, expectedValidatorPayout);
        assertEq(actualAmountPaid, expectedValidatorPayout);
        assertEq(1, PFR.validatorsTotal()); // 1 left in validator balance for gas costs

        // Again
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayCannotBeZero.selector);
        PFR.collectFees();

        // Back to pre-payment. VALIDATOR1 has (2 ETH - 1) matic to withdraw.
        vm.revertTo(snap);
        snap = vm.snapshot();
        // As payee try to pay V1. Assume SEARCHER 4 is V1 payee but not yet set
        vm.startPrank(SEARCHER_ADDRESS4);
        address payee = PFR.getValidatorPayee(VALIDATOR1);
        assertEq(payee, address(0));
        bool valid = PFR.isValidPayee(VALIDATOR1, SEARCHER_ADDRESS4);
        assertEq(valid, false);
        bool isTimelocked = PFR.isPayeeTimeLocked(VALIDATOR1);
        assertEq(isTimelocked, false);
        vm.stopPrank();

        // Now set V1 payee to Searcher 4 properly
        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(SEARCHER_ADDRESS4);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), SEARCHER_ADDRESS4);

        isTimelocked = PFR.isPayeeTimeLocked(VALIDATOR1);
        assertEq(isTimelocked, true);

        // Payee fails because still timelocked
        vm.prank(SEARCHER_ADDRESS4);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeIsTimelocked.selector);
        PFR.collectFees();

        // Fast forward
        vm.warp(block.timestamp + 7 days);

        // Payee succeeds after time delay
        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, expectedValidatorPayout, SEARCHER_ADDRESS4);
        vm.prank(SEARCHER_ADDRESS4);
        PFR.collectFees();

        // Back to pre-payment. VALIDATOR1 has (2 ETH - 1) matic to withdraw.
        vm.revertTo(snap);
        snap = vm.snapshot();

        // Legit update
        vm.prank(VALIDATOR1);
        vm.expectEmit(true, true, true, true);
        emit RelayValidatorPayeeUpdated(VALIDATOR1, SEARCHER_ADDRESS2, VALIDATOR1);
        PFR.updateValidatorPayee(SEARCHER_ADDRESS2);

        // Now SEARCHER_2 must wait to be able to use his new payee status
        // Old payee invalid
        valid = PFR.isValidPayee(VALIDATOR1, SEARCHER_ADDRESS4);
        assertEq(valid, false);

        isTimelocked = PFR.isPayeeTimeLocked(VALIDATOR1);
        assertEq(isTimelocked, true);

        vm.startPrank(SEARCHER_ADDRESS2);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeIsTimelocked.selector);
        PFR.collectFees();

        // Fast forward
        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, expectedValidatorPayout, SEARCHER_ADDRESS2);
        PFR.collectFees();
    }

    function testUpdateValidatorPayeeRevertsIfAddressZero() public {
        _donateOneWeiToValidatorBalance();
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayCannotBeZero.selector);
        PFR.updateValidatorPayee(address(0));
    }

    function testUpdateValidatorPayeeRevertsIfAuctionAddress() public {
        _donateOneWeiToValidatorBalance();
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayCannotBeSelf.selector);
        PFR.updateValidatorPayee(address(PFR));
    }

    function testUpdateValidatorPayeeRevertsIfValidatorOrNewPayeeInPayeeMap() public {
        _donateOneWeiToValidatorBalance();
        vm.coinbase(VALIDATOR2);
        _donateOneWeiToValidatorBalance();
        vm.coinbase(VALIDATOR1);

        vm.label(PAYEE1, "PAYEE1");
        vm.label(PAYEE2, "PAYEE2");

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE1);

        vm.prank(PAYEE1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeUpdateInvalid.selector);
        PFR.updateValidatorPayee(PAYEE1);

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE2);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE2);

        vm.prank(PAYEE2);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE1);

        // Cant relinquish back to own validator
        vm.prank(PAYEE1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeUpdateInvalid.selector);
        PFR.updateValidatorPayee(VALIDATOR1);

        // Cant relinquish back to any validator in use
        vm.prank(PAYEE1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeUpdateInvalid.selector);
        PFR.updateValidatorPayee(VALIDATOR2);

        // Ensure it's not stuck
        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE2);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE2);

        vm.prank(PAYEE2);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE1);
    }

    function testClearPayeeAndHostilePayeeUpdate() public {
        _donateOneWeiToValidatorBalance();
        _donateOneWeiToValidatorBalance();
        vm.coinbase(VALIDATOR1);

        vm.label(PAYEE1, "PAYEE1");
        vm.label(PAYEE2, "PAYEE2");

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE1);

        uint256 snap = vm.snapshot();

        // Validator can clear and old Payee can't act anymore.

        vm.prank(VALIDATOR1);
        PFR.clearValidatorPayee();

        assertEq(PFR.getValidatorRecipient(VALIDATOR1), VALIDATOR1);

        vm.prank(PAYEE1);
        vm.expectRevert();
        PFR.collectFees();

        vm.prank(PAYEE1);
        vm.expectRevert();
        PFR.updateValidatorPayee(PAYEE2);

        vm.revertTo(snap);

        // Payee cant clear himself
        vm.prank(PAYEE1);
        vm.expectRevert();
        PFR.clearValidatorPayee();

        vm.prank(VALIDATOR1);
        PFR.clearValidatorPayee();

        // Validator can then assign anyone it sees fit
        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);

        // Validator trolls by assigning an upcoming but never seen yet
        // validator address as payee.
        // Locking its payeeMap : payeeMap[validator2] = validator1
        // formerPayee of v1 will be v2

        vm.prank(VALIDATOR1);

        // Things start getting weird
        PFR.updateValidatorPayee(VALIDATOR2); // V1 Time locks Validator2

        vm.warp(block.timestamp + 7 days);

        vm.coinbase(VALIDATOR2);
        _donateOneWeiToValidatorBalance();
        _donateOneWeiToValidatorBalance();

        vm.prank(VALIDATOR2);
        PFR.updateValidatorPayee(PAYEE2); // Actually updates VALIDATOR1, since PAYEE
        // So VALIDATOR2 payee is unchanged
        assertEq(PFR.getValidatorRecipient(VALIDATOR2), VALIDATOR2);

        vm.warp(block.timestamp + 7 days);

        // And then gets unlocked after 7d
        assertEq(PFR.getValidatorRecipient(VALIDATOR2), PAYEE2);

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        // To get things back
        vm.prank(VALIDATOR2);
        PFR.clearValidatorPayee();

        vm.prank(VALIDATOR2);
        PFR.updateValidatorPayee(PAYEE2);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR2), PAYEE2);
    }

    // NOTE: This is unreachable because getValidator is internal and
    //          only called when checks blocking this revert case have been passed
    // function testGetValidatorRevertsIfInvalidCaller() public {
    //     vm.startPrank(address(this));
    //     vm.expectRevert("Invalid validator");
    //     PFR.getValidator();
    // }

    function testPayValidatorFeeRevertsWithZeroValue() public {
        vm.prank(USER);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayValueIsZero.selector);
        PFR.payValidatorFee{value: 0}(SEARCHER_ADDRESS1);
    }

    function testValidatorCanSetPayee() public {
        assertTrue(PFR.getValidatorPayee(VALIDATOR1) != PAYEE1);
        // Prep validator balance in contract - must be positive to change payee
        _donateOneWeiToValidatorBalance();

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);
    }

    function testValidatorsPayeeCanSetPayee() public {
        // Prep validator balance in contract - must be positive to change payee
        _donateOneWeiToValidatorBalance();

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);

        // avoid payee is time locked revert
        vm.warp(block.timestamp + 6 days + 1);

        vm.prank(PAYEE1);
        PFR.updateValidatorPayee(PAYEE2);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE2);
    }

    function testRandomUserCannotSetValidatorsPayee() public {
        vm.prank(USER);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayInvalidSender.selector); // reverts in validPayee modifier
        PFR.updateValidatorPayee(USER);
    }

    function testValidatorCannotSetPayeeIfZeroBalance() public {
        assertTrue(PFR.getValidatorBalance(VALIDATOR1) == 0);
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayInvalidSender.selector);
        PFR.updateValidatorPayee(PAYEE1);
    }

    function testPayeeCannotSetPayeeIfBeforeTimelock() public {
        // Prep validator balance in contract - must be positive to change payee
        _donateOneWeiToValidatorBalance();

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);

        vm.prank(PAYEE1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayPayeeIsTimelocked.selector);
        PFR.updateValidatorPayee(PAYEE2);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);
    }

    function testWithdrawStuckERC20CanOnlyBeCalledByValidators() public {
        _donateOneWeiToValidatorBalance();
        uint256 stuckERC20Amount = 1 ether;
        MockERC20 mockToken = new MockERC20("MockToken", "MT", 18);
        mockToken.mint(USER, stuckERC20Amount);
        vm.prank(USER);
        mockToken.transfer(address(PFR), stuckERC20Amount);

        vm.prank(USER);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayNotActiveValidator.selector);
        PFR.withdrawStuckERC20(address(mockToken));

        uint256 validatorBalanceBefore = mockToken.balanceOf(address(VALIDATOR1));
        vm.prank(VALIDATOR1);
        PFR.withdrawStuckERC20(address(mockToken));
        uint256 validatorBalanceAfter = mockToken.balanceOf(address(VALIDATOR1));
        assertEq(validatorBalanceAfter - validatorBalanceBefore, stuckERC20Amount);
    }

    function testWithdrawStuckERC20DoesNotIncreaseBalanceIfNoExcess() public {
        _donateOneWeiToValidatorBalance();
        uint256 stuckERC20Amount = 1 ether;
        MockERC20 mockToken = new MockERC20("MockToken", "MT", 18);
        mockToken.mint(USER, stuckERC20Amount);
        uint256 auctionContractBalanceBefore = mockToken.balanceOf(address(PFR));
        uint256 validatorBalanceBefore = mockToken.balanceOf(address(VALIDATOR1));
        vm.prank(VALIDATOR1);
        PFR.withdrawStuckERC20(address(mockToken));
        uint256 auctionContractBalanceAfter = mockToken.balanceOf(address(PFR));
        uint256 validatorBalanceAfter = mockToken.balanceOf(address(VALIDATOR1));
        assertEq(validatorBalanceBefore, validatorBalanceAfter);
        assertEq(auctionContractBalanceBefore, auctionContractBalanceAfter);
    }

    function testGetValidatorRecipient() public {
        _donateOneWeiToValidatorBalance();
        // Returns validator if valid and no payee set
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), VALIDATOR1);

        // Returns payee if valid and payee set
        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        vm.warp(block.timestamp + 7 days);
        assertEq(PFR.getValidatorRecipient(VALIDATOR1), PAYEE1);
    }

    function testGetValidatorBlockOfLastWithdraw() public {
        // Setup for collectFees testing
        vm.deal(SEARCHER_ADDRESS1, 100 ether);
        uint256 bidAmount = 2 ether;
        uint256 expectedValidatorPayout = bidAmount - 1;
        bytes32 oppTx = bytes32("tx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");
        SearcherRepayerEcho SRE = new SearcherRepayerEcho();
        vm.prank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        PFR.submitFlashBid{value: bidAmount}(bidAmount, bytes32("randomTx"), address(SRE), searcherUnusedData);

        // Returns 0 if no withdraws
        assertEq(PFR.getValidatorBlockOfLastWithdraw(VALIDATOR1), 0);

        // Returns block number of last withdraw
        vm.prank(VALIDATOR1);
        PFR.collectFees();
        assertEq(PFR.getValidatorBlockOfLastWithdraw(VALIDATOR1), block.number);
    }

    // TODO handle uninitiatied validators not with startBlock == 0
    function testCollectFeesCustom() public {
        address ppAdmin = address(1234321); // PaymentProcessor admin
        uint256 expectedValidatorBalance = 1 ether - 1;

        // Set validator balance in auction handler to 1 ETH
        vm.prank(USER);
        PFR.payValidatorFee{value: 1 ether}(USER);
        assertEq(PFR.getValidatorBalance(VALIDATOR1), 1 ether);

        uint256 snap = vm.snapshot();

        // Testing a working Payment Processor
        vm.startPrank(ppAdmin);
        MockPaymentProcessor MPP = new MockPaymentProcessor();
        MPP.setPayee(ppAdmin); // Set ppAdmin as payee, will recieve ETH from AuctionHanlder
        vm.stopPrank();

        bytes memory addressData = abi.encode(VALIDATOR1);

        // Reverts if payment processor address is zero address
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayProcessorCannotBeZero.selector);
        PFR.collectFeesCustom(address(0), addressData);

        assertEq(ppAdmin.balance, 0, "Payee unexpectedly has ETH before"); // Payee has no ETH before

        vm.prank(VALIDATOR1);
        vm.expectEmit(true, true, false, true, address(PFR));
        emit CustomPaymentProcessorPaid({
            payor: VALIDATOR1,
            payee: ppAdmin,
            paymentProcessor: address(MPP),
            totalAmount: expectedValidatorBalance,
            startBlock: 0,
            endBlock: block.number
        });
        PFR.collectFeesCustom(address(MPP), addressData);

        assertEq(MPP.validator(), VALIDATOR1);
        assertEq(MPP.totalAmount(), expectedValidatorBalance);
        assertEq(MPP.startBlock(), 0);
        assertEq(MPP.endBlock(), block.number);
        assertEq(ppAdmin.balance, expectedValidatorBalance, "Payee did not get ETH");

        vm.revertTo(snap);

        // Testing a broken Payment Processor
        vm.startPrank(ppAdmin);
        MockPaymentProcessorBroken MPPB = new MockPaymentProcessorBroken();
        MPPB.setPayee(ppAdmin); // Set ppAdmin as payee, will recieve ETH from AuctionHanlder
        vm.stopPrank();

        assertEq(ppAdmin.balance, 0, "Payee has ETH before broken pp test");

        // Expected to revert due to paymentCallback not being called inside Payment Processor
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayCustomPayoutCantBePartial.selector);
        PFR.collectFeesCustom(address(MPPB), addressData);

        assertEq(ppAdmin.balance, 0, "Payee should still not have any ETH");
        // TODO remove either callbackLock or nonReentrant modifier in collectFeesCustom function
    }

    function testPaymentCallback() public {
        // NOTE: Positive case of paymentCallback tested above in testCollectFeesCustom.
        // Check paymentCallback reverts if not called by PaymentProcessor
        // during the collectFeesCustom function call:
        vm.prank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayUnapprovedReentrancy.selector);
        PFR.paymentCallback(VALIDATOR1, VALIDATOR1, 1 ether);
    }

    function testNonReentrantModifierBlocksAllReentrancy() public {
        // Try use collectFees to reenter from validatorPayee
        vm.prank(USER);
        PFR.payValidatorFee{value: 1 ether}(USER);
        ReenteringPayee payee = new ReenteringPayee();

        vm.startPrank(VALIDATOR1);
        PFR.updateValidatorPayee(address(payee));

        // Fast forward
        vm.warp(block.timestamp + 7 days);

        // This revert message comes from Solmate's SafeTransferLib, and is triggered by "REENTRANCY" revert
        // Use `forge test --match-test BlocksAllReentrancy -vvv` to see the inner revert message of "REENTRANCY"
        vm.expectRevert(bytes("ETH_TRANSFER_FAILED"));
        PFR.collectFees();
        vm.stopPrank();
    }

    function testLimitedAndPermittedReentrantModifiersBlockNonPaymentProcessorOnReenter() public {
        vm.prank(USER);
        PFR.payValidatorFee{value: 1 ether}(USER);

        address payee = address(1234321);
        AttackerPaymentProcessorStep1 attackerPP1 = new AttackerPaymentProcessorStep1();
        AttackerPaymentProcessorStep2 attackerPP2 = new AttackerPaymentProcessorStep2();

        attackerPP1.setAttacker2(address(attackerPP2));
        attackerPP1.setPayee(payee);

        vm.startPrank(VALIDATOR1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayUnapprovedReentrancy.selector);
        PFR.collectFeesCustom(address(attackerPP1), "");
        vm.stopPrank();
    }

    // Useful to get past the "validatorsBalanceMap[validator] > 0" checks
    function _donateOneWeiToValidatorBalance() internal {
        vm.prank(USER);
        PFR.payValidatorFee{value: 1}(USER);
    }
}

// Fake opportunity to backrun
contract BrokenUniswap {
    function sickTrade(uint256 unused) external {
        payable(msg.sender).transfer(address(this).balance / 2);
    }
}

// Purpose is to do nothing, hence not repaying the relay
contract BrokenSearcherForgotFastLaneCallFn {
    fallback() external payable {}
}

contract BrokenSearcherForgotReturnBoolBytes {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable /* returns (bool, bytes memory) <- FORGOTTEN */
    {}
}

// Purpose is to do nothing, hence not repaying the relay
contract BrokenSearcherRepayer {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable
        returns (bool, bytes memory)
    {
        return (true, bytes("ok"));
    }
}

// Purpose is only repay partially the relay
contract BrokenSearcherRepayerPartial {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable
        returns (bool, bytes memory)
    {
        bool success;
        uint256 amount = 1 ether;
        address to = msg.sender;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true, bytes("ok"));
    }
}

contract SearcherRepayerEcho {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable
        returns (bool, bytes memory)
    {
        bool success;
        address to = msg.sender;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, _bidAmount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true, bytes("ok"));
    }
}

contract SearcherRepayerEvilEcho {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable
        returns (bool, bytes memory)
    {
        bool success;
        address payable to = payable(msg.sender);

        FastLaneAuctionHandler(to).collectFees();
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, _bidAmount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true, bytes("ok"));
    }
}

contract SearcherRepayerOverpayerDouble {
    function fastLaneCall(address _sender, uint256 _bidAmount, bytes calldata _searcherCallData)
        external
        payable
        returns (bool, bytes memory)
    {
        bool success;
        uint256 amount = _bidAmount * 2;
        address to = msg.sender;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true, bytes("ok"));
    }
}

contract ReenteringPayee {
    fallback() external payable {
        FastLaneAuctionHandler(payable(msg.sender)).collectFees();
    }

    receive() external payable {
        FastLaneAuctionHandler(payable(msg.sender)).collectFees();
    }
}

contract AttackerPaymentProcessorStep1 {
    address public attacker2;
    address public payee; // Receives ETH from AuctionHandler

    function setAttacker2(address _attacker2) external {
        attacker2 = _attacker2;
    }

    function setPayee(address _payee) external {
        payee = _payee;
    }

    function payValidator(
        address _validator,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _totalAmount,
        bytes calldata _data
    ) external {
        // Then calls to intermediate contract which calls back to auction handler to test reentrancy
        AttackerPaymentProcessorStep2(attacker2).reenterAuctionHandler(msg.sender, _validator, payee, _totalAmount);
    }
}

contract AttackerPaymentProcessorStep2 {
    function reenterAuctionHandler(
        address auctionHandlerAddress,
        address _validator,
        address payee,
        uint256 _totalAmount
    ) public {
        FastLaneAuctionHandler(payable(auctionHandlerAddress)).paymentCallback(_validator, payee, _totalAmount);
    }
}
