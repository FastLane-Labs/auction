// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "contracts/FastLaneAuction.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PFLHelper} from "./PFLAuction.t.sol";

contract PFLDeployTest is Test, PFLHelper {
    FastLaneAuction public fastlaneImplementation;
    address constant foundryFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant expectedImplementationAddress = 0x2962A95eE7d5AEF7205A944D6d5b25D68a510c68;
    address constant eoa = 0x1BA0f96bf6b26df11a58553c6db9a0314938Cf70;
    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Initialized(uint8 version);

    function setUp() public {
        bytes32 implementationSaltStr = "hello";
        // Deploy impl as foundry factory with salt
        vm.prank(foundryFactory);
        fastlaneImplementation = new FastLaneAuction{salt: implementationSaltStr}(eoa);
        // 0x2962a95ee7d5aef7205a944d6d5b25d68a510c68
        console2.log("Implementation Deployed at:");
        console2.log(address(fastlaneImplementation));
        console2.log(address(fastlaneImplementation).code.length);
        console2.log("------------------------------------");
    }

    function testDeploy() public {
        bytes32 proxySaltStr = 0xdedd35ceaec8d2aae8506b7c1466e0e256b6576d4dbcf8560d4634bc01114856;
        

        // Call that will be made after deploy of Proxy
        // will transfer ownership to `eoa` after receiving it from `foundryFactory`
        bytes memory encodedPostProxyDeployCall = abi.encodeWithSignature("initialize(address)", eoa);

        vm.prank(foundryFactory);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(expectedImplementationAddress);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(0x0000000000000000000000000000000000000000, foundryFactory);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(foundryFactory, eoa);
        vm.expectEmit(true, true, true, true);
        emit Initialized(1);
        // emit Initialized
        ERC1967Proxy proxy = new ERC1967Proxy{salt: proxySaltStr}(address(fastlaneImplementation), encodedPostProxyDeployCall); 
       
        console2.log("Deployed Proxy @:");
        address deployedProxyAddress = address(proxy);
        console2.log(deployedProxyAddress);
        console2.log("------------------------------------");

        address expectedProxyAddress = 0x1337Ac52169E2a97EBa85c736B6Ba435Ec93a543;
        assertEq(deployedProxyAddress,expectedProxyAddress, "Addresses mismatch");

        vm.startPrank(eoa);
        address STARTER_ROLE = msg.sender;
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit BidTokenSet(STARTER_ROLE);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit OpsSet(STARTER_ROLE);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit MinimumBidIncrementSet(10000000000000000000);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit MinimumAutoshipThresholdSet(2000000000000000000000);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit ResolverMaxGasPriceSet(200000000000);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit FastLaneFeeSet(5000);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit AutopayBatchSizeSet(10);
        vm.expectEmit(true, true, true, false, expectedProxyAddress);
        emit AuctionStarterSet(STARTER_ROLE);
        (bool successInitialSetupAuction, bytes memory returnSetupData) = deployedProxyAddress.call(abi.encodeWithSignature("initialSetupAuction(address,address,address)", STARTER_ROLE, STARTER_ROLE, STARTER_ROLE));
        
        console2.log("initialSetupAuction call:");
        console2.log(successInitialSetupAuction);
        console2.log(string(returnSetupData));

        assertTrue(successInitialSetupAuction);
    }

        function testUpgrade() public {
        bytes32 proxySaltStr = 0xdedd35ceaec8d2aae8506b7c1466e0e256b6576d4dbcf8560d4634bc01114856;
        bytes memory encodedPostProxyDeployCall = abi.encodeWithSignature("initialize(address)", eoa);

        vm.prank(foundryFactory);
        ERC1967Proxy proxy = new ERC1967Proxy{salt: proxySaltStr}(address(fastlaneImplementation), encodedPostProxyDeployCall); 
       
        console2.log("Deployed Proxy @:");
        address deployedProxyAddress = address(proxy);
        console2.log(deployedProxyAddress);
        console2.log("------------------------------------");

        address expectedProxyAddress = 0x1337Ac52169E2a97EBa85c736B6Ba435Ec93a543;
        assertEq(deployedProxyAddress,expectedProxyAddress, "Addresses mismatch");

        vm.prank(eoa);
        address STARTER_ROLE = msg.sender;
        (bool successInitialSetupAuction, bytes memory returnSetupData) = deployedProxyAddress.call(abi.encodeWithSignature("initialSetupAuction(address,address,address)", STARTER_ROLE, STARTER_ROLE, STARTER_ROLE));
        
        console2.log("initialSetupAuction call:");
        console2.log(successInitialSetupAuction);
        console2.log(string(returnSetupData));

        assertTrue(successInitialSetupAuction);

        // V2 Impl
        bytes32 implementationV2SaltStrV2 = "V2";
        // Deploy impl as foundry factory with salt
        vm.prank(foundryFactory);
        FastLaneAuction fastlaneV2ImplementationV2 = new FastLaneAuction{salt: implementationV2SaltStrV2}(eoa); // 0x368845aff2b7051c33ca5db927eceb6e54efce5c

        vm.prank(eoa);
        vm.expectEmit(true, true, true, true);
        emit Upgraded(expectedImplementationAddress);
        (bool successUpgrade, bytes memory returnUpgradeData) = deployedProxyAddress.call(abi.encodeWithSignature("upgradeTo(address)", address(fastlaneV2ImplementationV2)));
        
        assertTrue(successUpgrade);

        vm.prank(eoa);
        vm.expectEmit(true, true, true, true, address(deployedProxyAddress));
        emit OpsSet(eoa);
        (bool successCallAsOwner,) = deployedProxyAddress.call(abi.encodeWithSignature("setOps(address)", address(eoa)));
        
        assertTrue(successCallAsOwner);
    }
}