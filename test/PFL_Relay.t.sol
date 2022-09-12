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
contract PFLRelayTest is PFLHelper, FastLaneRelayEvents {
    FastLaneRelay PFR;
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
        // Use OPS_ADDRESS as vault for repay checks
        PFR = new FastLaneRelay(OPS_ADDRESS,fee);

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
        
        MinimalSearcherContractContextOwnable MSCCO = new MinimalSearcherContractContextOwnable(address(PFR),OPS_ADDRESS);
        address _searcherToAddress = address(MSCCO);
        bytes4 selector = bytes4(keccak256("doMEV(address,uint256,uint256,bytes)"));

        // Encode random params, only _bidAmount matters
        address _paramsDoMEVcallTo = vm.addr(1337);
        uint256 _paramsDoMEVflags = 12345;
        uint256 _paramsDoMEVPaybackAmount = _bidAmount;
        // Encode anything here as it's not used anyways by MinimalSearcherContractContextOwnable
        bytes memory _paramsDoMEVCalldataParams = abi.encodeWithSignature("SomeCall(uint256)", 11111);

        // doMEV(address,uint256,uint256,bytes)
        bytes memory _toForwardExecData = abi.encodeWithSelector(selector,_paramsDoMEVcallTo,_paramsDoMEVflags,_paramsDoMEVPaybackAmount,_paramsDoMEVCalldataParams);
       
        uint256 balanceVaultBefore = OPS_ADDRESS.balance;

        // Flash not repaid

        // bytes memory data = hex"08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000134554485f5452414e534645525f4641494c454400000000000000000000000000";
        // {
        //     (bytes4 sel, string memory rdat) = abi.decode(data,(bytes4, string));
        //     console.log("Rev: %s",rdat);
        // }
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

        // Pass the $, receive it back
        PFR.submitFlashBid{value:_bidAmount}(_bidAmount, _oppTxHash, VALIDATOR1, _searcherToAddress, _toForwardExecData);
        assertEq(OPS_ADDRESS.balance,balanceVaultBefore + _bidAmount);

    }

}