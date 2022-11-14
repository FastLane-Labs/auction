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

import { FastLaneSearcherWrapper } from "contracts/jit-searcher/FastLaneSearcherWrapper.sol";

// Fake opportunity to backrun
contract BrokenUniswap {
    function sickTrade(uint256 unused) external {
        payable(msg.sender).transfer(address(this).balance / 2);
    }
}

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
            vm.deal(currentBidder, soonWMaticBidder + 1);
            vm.deal(currentSearcher, soonWMaticSearcher + 1);
        }
        vm.prank(OWNER);

        uint24 stakeShare = 50000;
        // Use PFL_VAULT as vault for repay checks
        PFR = new FastLaneRelay(stakeShare, 1 ether, false);
        brokenUniswap = new BrokenUniswap();

        vm.deal(address(brokenUniswap), 100 ether);
        vm.coinbase(VALIDATOR1);
        console.log("Block Coinbase: %s",block.coinbase);
    }

    function testSubmitFlashBid() public {
        uint256 bidAmount = 0.001 ether;
        bytes32 oppTx = bytes32("tx1");

        // Deploy Searcher Wrapper as SEARCHER_ADDRESS1
        vm.prank(SEARCHER_ADDRESS1);
        FastLaneSearcherWrapper FSW = new FastLaneSearcherWrapper();
        address to = address(FSW);

        address expectedAnAddress = vm.addr(12);
        uint256 expectedAnAmount = 1337;
        bytes memory searcherCallData = abi.encodeWithSignature("doStuff(address, uint256)", expectedAnAddress, expectedAnAmount);

        console.log("Tx origin: %s", tx.origin);
        console.log("Address this: %s", address(this));
        console.log("Address PFR: %s", address(PFR));
        console.log("Owner FSW: %s", FSW.owner());

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

        bidAmount = 2 ether;

        vm.expectRevert(bytes("InvalidPermissions"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);
        // Authorize Relay as Searcher
        FSW.setPFLAuctionAddress(address(PFR));

        // Authorize test address as EOA
        FSW.approveFastLaneEOA(address(this));

        vm.expectRevert(bytes("SearcherInsufficientFunds  2000000000000000000 0"));
        PFR.submitFlashBid(bidAmount, oppTx, to,  searcherCallData);



        vm.expectEmit(true, true, true, true);
        emit RelayFlashBid(SEARCHER_ADDRESS1, bidAmount, oppTx, VALIDATOR1, address(FSW));
        PFR.submitFlashBid{value: 2 ether}(bidAmount, oppTx, to,  searcherCallData);

        // Check Balances
    }


    function testEnableValidator() public {
        vm.startPrank(OWNER);
        vm.expectRevert(FastLaneRelayEvents.RelayCannotBeZero.selector);
        PFR.enableRelayValidator(VALIDATOR1, address(0));
    }

    function testPayValidator() public {

    }
}