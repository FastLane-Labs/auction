// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/legacy/FastLaneLegacyAuction.sol";


import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "contracts/interfaces/IWMatic.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

import { PFLHelper } from "./legacy-test/PFLAuction.t.sol";

import "contracts/auction-handler/FastLaneAuctionHandler.sol";

import { SearcherContractExample } from "contracts/searcher-direct/FastLaneSearcherDirect.sol";

contract PFLAuctionHandlerTest is PFLHelper, FastLaneAuctionHandlerEvents {

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
            vm.label(currentBidder,string.concat("BIDDER",Strings.toString(i+1)));
            vm.label(currentSearcher,string.concat("SEARCHER",Strings.toString(i+1)));
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
        vm.label(VALIDATOR1,"VALIDATOR1");
        vm.label(USER,"USER");
        console.log("Block Coinbase: %s",block.coinbase);
        vm.warp(1641070800);
    }

    function testSubmitFlashBid() public {

        vm.deal(SEARCHER_ADDRESS1, 150 ether);

        uint256 bidAmount = 0.001 ether;
        bytes32 oppTx = bytes32("tx1");

        // Deploy Searcher Wrapper as SEARCHER_ADDRESS1
        vm.startPrank(SEARCHER_ADDRESS1);
        SearcherContractExample SCE = new SearcherContractExample();
        vm.stopPrank();

        address to = address(SCE);

        address expectedAnAddress = vm.addr(12);
        uint256 expectedAnAmount = 1337;

        // Simply abi encode the args we want to forward to the searcher contract so it can execute them 
        bytes memory searcherCallData = abi.encodeWithSignature("doStuff(address,uint256)", expectedAnAddress, expectedAnAmount);

        console.log("Tx origin: %s", tx.origin);
        console.log("Address this: %s", address(this));
        console.log("Address PFR: %s", address(PFR));
        console.log("Owner SCE: %s", SCE.owner());

        vm.startPrank(SEARCHER_ADDRESS1,SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBid(bidAmount, oppTx, address(0),  searcherCallData);

        bidAmount = 2 ether;

        SCE.setPFLAuctionAddress(address(0));
        vm.expectRevert(bytes("InvalidPermissions"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);
        // Authorize Relay as Searcher
        SCE.setPFLAuctionAddress(address(PFR));

        // Authorize test address as EOA
        SCE.approveFastLaneEOA(address(this));

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 0"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);

        // Can oddly revert with "EvmError: OutOfFund".
        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 1000000000000000000"));
        console.log("Balance SCE: %s", to.balance);
        PFR.submitFlashBid{value: 1 ether}(bidAmount, oppTx, to,  searcherCallData);


        vm.expectEmit(true, true, true, true);
        emit RelayFlashBid(SEARCHER_ADDRESS1, bidAmount, oppTx, VALIDATOR1, address(SCE));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, oppTx, to,  searcherCallData);

        // Check Balances
        console.log("Balance PFR: %s", address(PFR).balance);
        assertEq(bidAmount, address(PFR).balance);

        // Verify `doStuff` got hit
        assertEq(expectedAnAddress, SCE.anAddress());
        assertEq(expectedAnAmount, SCE.anAmount());

        // Replay attempt
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelayAuctionBidReceivedLate.selector);
        PFR.submitFlashBid{value: 5 ether}(bidAmount, oppTx, to,  searcherCallData);

        // Not winner
        vm.expectRevert(abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelayAuctionSearcherNotWinner.selector, bidAmount - 1, bidAmount));
        PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, oppTx, to,  searcherCallData);

        // Failed searcher call inside their contract
        bytes memory searcherFailCallData = abi.encodeWithSignature("doFail()");
        // Will fail as Error(string), thereafter encoded through the custom error RelaySearcherCallFailure
        // 0x291bc14c0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000006408c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f4641494c5f4f4e5f505552504f5345000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

        // To recover:
        // Remove selector 0x291bc14c
        // bytes memory z = hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000006408c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f4641494c5f4f4e5f505552504f5345000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        // abi.decode(z,(bytes)); // 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f4641494c5f4f4e5f505552504f53450000000000000000000000000000000000
        // Remove selector 0x08c379a
        // bytes memory d = hex"00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f4641494c5f4f4e5f505552504f53450000000000000000000000000000000000"
        // abi.decode(d,(string)) -> FAIL_ON_PURPOSE

        // Helper: PFR.humanizeError()
 
        {
        bytes memory encoded = abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelaySearcherCallFailure.selector, abi.encodeWithSignature("Error(string)","FAIL_ON_PURPOSE"));
        
        console.logBytes(encoded);
        console.log(PFR.humanizeError(encoded));

        // Decode error
        assertEq(PFR.humanizeError(encoded), "FAIL_ON_PURPOSE");

        vm.expectRevert(abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelaySearcherCallFailure.selector, abi.encodeWithSignature("Error(string)","FAIL_ON_PURPOSE")));
        PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, bytes32("willfailtx"), to,  searcherFailCallData);

        }
    }

    function testWrongSearcherRepay() public {

        uint256 bidAmount = 2 ether;

        vm.startPrank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);

        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        // Searcher BSFFLC contract forgot to implement fastLaneCall(uint256,address,bytes)
        BrokenSearcherForgotFastLaneCallFn BSFFLC = new BrokenSearcherForgotFastLaneCallFn();
        vm.expectRevert();
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BSFFLC),  searcherUnusedData);

        // Searcher BSFFLC contract implemented `fastLaneCall` but forgot to return (bool, bytes);
        BrokenSearcherForgotReturnBoolBytes BSFRBB = new BrokenSearcherForgotReturnBoolBytes();
        vm.expectRevert();
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BSFRBB),  searcherUnusedData);


        // Searcher implemented but doesn't manage to repay the relay
        BrokenSearcherRepayer BRP = new BrokenSearcherRepayer();
        vm.expectRevert(abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelayNotRepaid.selector, bidAmount, 0));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRP),  searcherUnusedData);

        // Searcher implemented but doesn't manage to repay the relay in full
        BrokenSearcherRepayerPartial BRPP = new BrokenSearcherRepayerPartial();
        vm.deal(address(BRPP), 10 ether);
        vm.expectRevert(abi.encodeWithSelector(FastLaneAuctionHandlerEvents.RelayNotRepaid.selector, bidAmount, 1 ether));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRPP),  searcherUnusedData);
        
    }

    function testSimulateFlashBid() public {
        vm.startPrank(SEARCHER_ADDRESS1,SEARCHER_ADDRESS1);
        SearcherRepayerEcho SRE = new SearcherRepayerEcho();

        uint256 bidAmount = 0.00002 ether;
        bytes32 oppTx = bytes32("fakeTx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        vm.expectEmit(true, true, true, true);
        emit RelaySimulatedFlashBid(SEARCHER_ADDRESS1, bidAmount, oppTx, block.coinbase, address(SRE));
        PFR.simulateFlashBid{value: 5 ether}(bidAmount, oppTx, address(SRE),  searcherUnusedData);
        vm.stopPrank();

        vm.prank(SEARCHER_ADDRESS1,SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneAuctionHandlerEvents.RelaySearcherWrongParams.selector);
        PFR.simulateFlashBid{value: 5 ether}(bidAmount, oppTx, address(0),  searcherUnusedData);
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
        PFR.submitFlashBid{value: bidAmount}(bidAmount, bytes32("randomTx"), address(SRE),  searcherUnusedData);
    }

    function testCollectFees() public {
        vm.deal(SEARCHER_ADDRESS1, 100 ether);

        uint256 bidAmount = 2 ether;
        uint256 expectedValidatorPayout = bidAmount - 1;
        bytes32 oppTx = bytes32("tx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        SearcherRepayerEcho SRE = new SearcherRepayerEcho();

        vm.prank(SEARCHER_ADDRESS1, SEARCHER_ADDRESS1);
        PFR.submitFlashBid{value: bidAmount}(bidAmount, bytes32("randomTx"), address(SRE),  searcherUnusedData);

        uint256 snap = vm.snapshot();

        // As V1 pay itself
        uint256 balanceBefore = VALIDATOR1.balance;
        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, expectedValidatorPayout, VALIDATOR1);

        vm.prank(VALIDATOR1);
        uint256 returnedAmountPaid = PFR.collectFees();
        uint256 actualAmountPaid = VALIDATOR1.balance - balanceBefore;

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
        assertEq(payee,address(0));
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
        vm.expectRevert("payee is time locked");
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
        vm.expectRevert("payee is time locked");
        PFR.collectFees();

        // Fast forward
        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, expectedValidatorPayout, SEARCHER_ADDRESS2);
        PFR.collectFees();
    }

    function testPayValidatorFeeRevertsWithZeroValue() public {
        vm.prank(USER);
        vm.expectRevert("msg.value = 0");
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
        vm.expectRevert("invalid msg.sender"); // reverts in validPayee modifier
        PFR.updateValidatorPayee(USER);
    }

    function testValidatorCannotSetPayeeIfZeroBalance() public {
        assertTrue(PFR.getValidatorBalance(VALIDATOR1) == 0);
        vm.prank(VALIDATOR1);
        vm.expectRevert("invalid msg.sender");
        PFR.updateValidatorPayee(PAYEE1);
    }

    function testPayeeCannotSetPayeeIfBeforeTimelock() public {
        // Prep validator balance in contract - must be positive to change payee
        _donateOneWeiToValidatorBalance();

        vm.prank(VALIDATOR1);
        PFR.updateValidatorPayee(PAYEE1);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);

        vm.prank(PAYEE1);
        vm.expectRevert("payee is time locked");
        PFR.updateValidatorPayee(PAYEE2);
        assertEq(PFR.getValidatorPayee(VALIDATOR1), PAYEE1);
    }

    function testSyncNativeTokenCanOnlyBeCalledByValidators() public {
        _donateOneWeiToValidatorBalance();
        uint256 stuckNativeAmount = 1 ether;
        vm.prank(USER);
        address(PFR).call{value: stuckNativeAmount}("");

        vm.prank(USER);
        vm.expectRevert("only active validators");
        PFR.syncStuckNativeToken();

        uint256 validatorBalanceBefore = PFR.getValidatorBalance(VALIDATOR1);
        vm.prank(VALIDATOR1);
        PFR.syncStuckNativeToken();
        uint256 validatorBalanceAfter = PFR.getValidatorBalance(VALIDATOR1);
        assertEq(validatorBalanceAfter - validatorBalanceBefore, stuckNativeAmount);
    }

    function testSyncNativeTokenDoesNotIncreaseBalanceIfNoExcess() public {
        _donateOneWeiToValidatorBalance();
        uint256 auctionContractBalanceBefore = address(PFR).balance;
        uint256 validatorBalanceBefore = PFR.getValidatorBalance(VALIDATOR1);
        vm.prank(VALIDATOR1);
        PFR.syncStuckNativeToken();
        uint256 auctionContractBalanceAfter = address(PFR).balance;
        uint256 validatorBalanceAfter = PFR.getValidatorBalance(VALIDATOR1);
        assertEq(validatorBalanceBefore, validatorBalanceAfter);
        assertEq(auctionContractBalanceBefore, auctionContractBalanceAfter);
    }

    function testWithdrawStuckERC20CanOnlyBeCalledByValidators() public {
        _donateOneWeiToValidatorBalance();
        uint256 stuckERC20Amount = 1 ether;
        MockERC20 mockToken = new MockERC20("MockToken", "MT", 18);
        mockToken.mint(USER, stuckERC20Amount);
        vm.prank(USER);
        mockToken.transfer(address(PFR), stuckERC20Amount);

        vm.prank(USER);
        vm.expectRevert("only active validators");
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
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable /* returns (bool, bytes memory) <- FORGOTTEN */ {
    }
}


// Purpose is to do nothing, hence not repaying the relay
contract BrokenSearcherRepayer {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        return (true,bytes("ok"));
    }
}

// Purpose is only repay partially the relay
contract BrokenSearcherRepayerPartial {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        bool success;
        uint256 amount = 1 ether;
        address to = msg.sender;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true,bytes("ok"));
    }
}


contract SearcherRepayerEcho {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        bool success;
        address to = msg.sender;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, _bidAmount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true,bytes("ok"));
    }
}


contract SearcherRepayerEvilEcho {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        bool success;
        address payable to = payable(msg.sender);

        FastLaneAuctionHandler(to).collectFees();
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, _bidAmount, 0, 0, 0, 0)
        }

  

        require(success, "ETH_TRANSFER_FAILED");

        
        return (true,bytes("ok"));
    }
}

contract SearcherRepayerOverpayerDouble {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        bool success;
        uint256 amount = _bidAmount * 2;
        address to = msg.sender;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true,bytes("ok"));
    }
}