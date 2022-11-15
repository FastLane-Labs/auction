// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";


import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "contracts/interfaces/IWMatic.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

import { PFLHelper } from "./PFLAuction.t.sol";

import "contracts/jit-relay/FastLaneRelay.sol";

import { SearcherContractExample } from "contracts/jit-searcher/FastLaneSearcherWrapper.sol";

contract PFLRelayTest is PFLHelper, FastLaneRelayEvents {
    FastLaneRelay PFR;
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
        vm.prank(OWNER);

        uint24 stakeShare = 50_000;
        // Use PFL_VAULT as vault for repay checks
        PFR = new FastLaneRelay(stakeShare, 1 ether, false);
        brokenUniswap = new BrokenUniswap();

        vm.deal(address(brokenUniswap), 100 ether);
        vm.coinbase(VALIDATOR1);
        vm.label(VALIDATOR1,"VALIDATOR1");
        vm.label(OWNER,"OWNER");
        console.log("Block Coinbase: %s",block.coinbase);
    }

    function testSubmitFlashBid() public {

        vm.deal(SEARCHER_ADDRESS1, 100 ether);

        uint256 bidAmount = 0.001 ether;
        bytes32 oppTx = bytes32("tx1");

        // Deploy Searcher Wrapper as SEARCHER_ADDRESS1
        vm.prank(SEARCHER_ADDRESS1);

        SearcherContractExample SCE = new SearcherContractExample();

        address to = address(SCE);

        address expectedAnAddress = vm.addr(12);
        uint256 expectedAnAmount = 1337;

        // Simply abi encode the args we want to forward to the searcher contract so it can execute them 
        bytes memory searcherCallData = abi.encodeWithSignature("doStuff(address,uint256)", expectedAnAddress, expectedAnAmount);

        console.log("Tx origin: %s", tx.origin);
        console.log("Address this: %s", address(this));
        console.log("Address PFR: %s", address(PFR));
        console.log("Owner SCE: %s", SCE.owner());

        vm.prank(SEARCHER_ADDRESS1);

        vm.expectRevert(FastLaneRelayEvents.RelayPermissionNotFastlaneValidator.selector);
        PFR.submitFlashBid(bidAmount, oppTx, to, searcherCallData);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit RelayValidatorEnabled(VALIDATOR1, VALIDATOR1);
        PFR.enableRelayValidator(VALIDATOR1, VALIDATOR1);

        vm.startPrank(SEARCHER_ADDRESS1);
        vm.expectRevert(FastLaneRelayEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);
        vm.expectRevert(FastLaneRelayEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBid(bidAmount, oppTx, address(0),  searcherCallData);
        vm.expectRevert(FastLaneRelayEvents.RelaySearcherWrongParams.selector);
        PFR.submitFlashBid(0.001 ether, oppTx, to,  searcherCallData);

        bidAmount = 2 ether;

        vm.expectRevert(bytes("InvalidPermissions"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);
        // Authorize Relay as Searcher
        SCE.setPFLAuctionAddress(address(PFR));

        // Authorize test address as EOA
        SCE.approveFastLaneEOA(address(this));

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 0"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 1000000000000000000"));
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

        // Stake Share & Validator paid
        (uint256 vC, uint256 sC) = _calculateCuts(bidAmount, PFR.flStakeShareRatio()); 
        assertEq(sC, PFR.getCurrentStakeBalance());
        assertEq(vC, PFR.getValidatorBalance(block.coinbase));
        assertEq(sC+vC, bidAmount);

        console.log("Balance Stake: %s", PFR.getCurrentStakeBalance());
        console.log("Balance Coinbase: %s",  PFR.getValidatorBalance(block.coinbase));

        // Replay attempt
        vm.expectRevert(FastLaneRelayEvents.RelayAuctionBidReceivedLate.selector);
        PFR.submitFlashBid{value: 5 ether}(bidAmount, oppTx, to,  searcherCallData);

        // Not winner
        vm.expectRevert(abi.encodeWithSelector(FastLaneRelayEvents.RelayAuctionSearcherNotWinner.selector, bidAmount - 1, bidAmount));
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
        bytes memory encoded = abi.encodeWithSelector(FastLaneRelayEvents.RelaySearcherCallFailure.selector, abi.encodeWithSignature("Error(string)","FAIL_ON_PURPOSE"));
        
        console.logBytes(encoded);
        console.log(PFR.humanizeError(encoded));

        // Decode error
        assertEq(PFR.humanizeError(encoded), "FAIL_ON_PURPOSE");

        vm.expectRevert(abi.encodeWithSelector(FastLaneRelayEvents.RelaySearcherCallFailure.selector, abi.encodeWithSignature("Error(string)","FAIL_ON_PURPOSE")));
        PFR.submitFlashBid{value: 5 ether}(bidAmount - 1, bytes32("willfailtx"), to,  searcherFailCallData);

        }
    }

    function testWrongSearcherRepay() public {

        vm.prank(OWNER);
        PFR.enableRelayValidator(VALIDATOR1, VALIDATOR1);

        uint256 bidAmount = 2 ether;

        vm.prank(SEARCHER_ADDRESS1);

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
        vm.expectRevert(abi.encodeWithSelector(FastLaneRelayEvents.RelayNotRepaid.selector, bidAmount, 0));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRP),  searcherUnusedData);

        // Searcher implemented but doesn't manage to repay the relay in full
        BrokenSearcherRepayerPartial BRPP = new BrokenSearcherRepayerPartial();
        vm.deal(address(BRPP), 10 ether);
        vm.expectRevert(abi.encodeWithSelector(FastLaneRelayEvents.RelayNotRepaid.selector, bidAmount, 1 ether));
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(BRPP),  searcherUnusedData);
        
    }


    function testEnableValidator() public {
        vm.startPrank(OWNER);
        vm.expectRevert(FastLaneRelayEvents.RelayCannotBeZero.selector);
        PFR.enableRelayValidator(VALIDATOR1, address(0));
    }

    function testPayValidator() public {

        vm.deal(SEARCHER_ADDRESS1, 100 ether);

        uint256 bidAmount = 2 ether;
        bytes32 oppTx = bytes32("tx1");
        bytes memory searcherUnusedData = abi.encodeWithSignature("unused()");

        vm.prank(OWNER);
        PFR.enableRelayValidator(VALIDATOR1, VALIDATOR1);
        SearcherRepayerEcho SRE = new SearcherRepayerEcho();

        vm.prank(SEARCHER_ADDRESS1);
        PFR.submitFlashBid{value: 5 ether}(bidAmount, bytes32("randomTx"), address(SRE),  searcherUnusedData);

        uint256 snap = vm.snapshot();

        vm.prank(VALIDATOR2);
        vm.expectRevert(FastLaneRelayEvents.RelayPermissionUnauthorized.selector);
        PFR.payValidator(VALIDATOR1);

        

        vm.prank(VALIDATOR1);
        vm.expectEmit(true, true, true, true);
        emit RelayProcessingPaidValidator(VALIDATOR1, 1.9 ether, VALIDATOR1);

        uint256 balanceBefore = VALIDATOR1.balance;
        PFR.payValidator(VALIDATOR1);

        // Validator actually got paid
        assertEq(VALIDATOR1.balance, balanceBefore + 1.9 ether);
        
        assertEq(0, PFR.validatorsTotal());

        // Again
        vm.prank(VALIDATOR1);
        uint256 payableBalance = PFR.payValidator(VALIDATOR1);
        assertEq(0, payableBalance);

        // Back to pre-payment. VALIDATOR1 has 1.9 matic to withdraw.
        vm.revertTo(snap);

        // As SEARCHER_2 try to update VALIDATOR1 payee, no-no.
        vm.prank(SEARCHER_ADDRESS2);
        vm.expectRevert(FastLaneRelayEvents.RelayPermissionUnauthorized.selector);
        PFR.updateValidatorPayee(VALIDATOR1, SEARCHER_ADDRESS2);

        // Legit update
        vm.prank(VALIDATOR1);

        vm.expectEmit(true, true, true, true);
        emit RelayValidatorPayeeUpdated(VALIDATOR1, SEARCHER_ADDRESS2, VALIDATOR1);

        PFR.updateValidatorPayee(VALIDATOR1, SEARCHER_ADDRESS2);

    }

    function testOwnerOnly() public {
        vm.startPrank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit RelayPausedStateSet(true);
        PFR.setPausedState(true);
         

        vm.expectRevert(FastLaneRelayEvents.RelayPermissionPaused.selector);
        PFR.payValidator(vm.addr(3333));
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