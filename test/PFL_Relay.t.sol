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

import { MinimalSearcherContractContextOwnable } from "contracts/jit-searcher/MinimalSearcherContractContextOwnable.sol";
import { SearcherMinimalRawContract } from "contracts/jit-searcher/MinimalSearcherRawContract.sol";


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

        uint24 fee = 5000;
        // Use PFL_VAULT as vault for repay checks
        PFR = new FastLaneRelay(PFL_VAULT,fee);
        brokenUniswap = new BrokenUniswap();

        vm.deal(address(brokenUniswap), 100 ether);
        vm.coinbase(VALIDATOR1);
        console.log("Block Coinbase: %s",block.coinbase);
    }

    function testStartOrder() public {
        vm.startPrank(OWNER);

        PFR.enableRelayValidatorAddress(VALIDATOR1);

        uint256 _bidAmount = 100;
        bytes32 _oppTxHash = keccak256("opp"); // No need to keccak, just easy way to get bytes32

        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        
        // We will need to craft the arguments for `submitFlashBid` to call our MinimalSearcherContractContextOwnable
        MinimalSearcherContractContextOwnable MSCCO = new MinimalSearcherContractContextOwnable(address(PFR),PFL_VAULT);
        address _searcherToAddress = address(MSCCO);

        // Craft selector we intend `submitFlashBid` to call
        bytes4 selector = bytes4(keccak256("doMEV(address,uint256,uint256,bytes)"));

        // Encode random params for that selector
        address _paramsDoMEVcallTo = vm.addr(1337);
        uint256 _paramsDoMEVflags = 12345;
        uint256 _paramsDoMEVPaybackAmount = _bidAmount;
        // Encode anything here as it's not used anyways by MinimalSearcherContractContextOwnable (but could in your case)
        bytes memory _paramsDoMEVCalldataParams = abi.encodeWithSignature("SomeCall(uint256)", 11111);

        // Encode full calldata for doMEV(address,uint256,uint256,bytes)
        bytes memory _toForwardExecData = abi.encodeWithSelector(selector,_paramsDoMEVcallTo,_paramsDoMEVflags,_paramsDoMEVPaybackAmount,_paramsDoMEVCalldataParams);
       
  

        // Flash not repaid
        bytes memory transferErrorBytes = abi.encodeWithSignature("Error(string)","ETH_TRANSFER_FAILED");
        vm.expectRevert(abi.encodeWithSelector(FastLaneRelayEvents.RelaySearcherCallFailure.selector,transferErrorBytes));
        
        // No specific validator
        PFR.submitFlashBid(_bidAmount, _oppTxHash, address(0), _searcherToAddress, _toForwardExecData);
 

        vm.coinbase(VALIDATOR2);
        // Wrong coinbase
        vm.expectRevert(FastLaneRelayEvents.RelayPermissionNotFastlaneValidator.selector);
        PFR.submitFlashBid(_bidAmount, _oppTxHash, VALIDATOR2, _searcherToAddress, _toForwardExecData);

   
        // Mined by validator 1 when expecting 2, revert.
        vm.coinbase(VALIDATOR1);
        vm.expectRevert(FastLaneRelayEvents.RelayWrongSpecifiedValidator.selector);
        PFR.submitFlashBid(_bidAmount, _oppTxHash, VALIDATOR2, _searcherToAddress, _toForwardExecData);


        // Set specific validator to succeed
        vm.expectEmit(true, true, true, true);
        emit RelayFlashBid(SEARCHER_ADDRESS1,_bidAmount, _oppTxHash, VALIDATOR1, _searcherToAddress);

        uint256 balanceVaultBefore = PFL_VAULT.balance;
        // Pass the $, receive it back
        
        PFR.submitFlashBid{value:_bidAmount}(_bidAmount, _oppTxHash, VALIDATOR1, _searcherToAddress, _toForwardExecData);
        assertEq(PFL_VAULT.balance,balanceVaultBefore + _bidAmount);

    }

    function testStartRawSample() public {
        vm.startPrank(OWNER);
        PFR.enableRelayValidatorAddress(VALIDATOR1);

        uint256 _bidAmount = 100;
        bytes32 _oppTxHash = keccak256("opp"); // No need to keccak, just easy way to get bytes32

        vm.stopPrank();
        vm.startPrank(SEARCHER_ADDRESS1);
        
   
        bytes4 selector = bytes4(keccak256("doMEV(uint256,address,bytes)"));

        SearcherMinimalRawContract SMRC = new SearcherMinimalRawContract(address(PFR),PFL_VAULT);
        address _searcherToAddress = address(SMRC);

        uint256 _paramsDoMEVPaybackAmount = _bidAmount;
        // Encode a juicy call to be called
        bytes memory _paramsDoMEVencodedCall = abi.encodeWithSignature("sickTrade(uint256)", 0);

        // doMEV(uint256,address,bytes)
        address _paramsDoMEVtarget = address(brokenUniswap);
        bytes memory _toForwardExecData = abi.encodeWithSelector(selector,_paramsDoMEVPaybackAmount, _paramsDoMEVtarget, _paramsDoMEVencodedCall);

        // Pass the $, receive it back through target + encodedCall 
        uint256 balanceVaultBefore = PFL_VAULT.balance;

        PFR.submitFlashBid(_bidAmount, _oppTxHash, VALIDATOR1, _searcherToAddress, _toForwardExecData);

        assertEq(PFL_VAULT.balance,balanceVaultBefore + _bidAmount);

       
    }

}