// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "contracts/legacy/FastLaneLegacyAuction.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/legacy/FastLaneLegacyAuction.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PFLHelper} from "./PFLAuction.t.sol";

contract PFLDeployTest is Test, PFLHelper {
    FastLaneLegacyAuction public fastlaneImplementation;
    address constant foundryFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant expectedImplementationAddress = 0x111bE7a544ba60D162f5d75Ea6bdA7254D650D8b;
    address expectedProxyAddress = 0xfa571A11e01d7759B816B41B5018432B2D202043;
    address constant eoa = 0x1BA0f96bf6b26df11a58553c6db9a0314938Cf70;
    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Initialized(uint8 version);

    bytes32 implementationSaltStr = 0x2141af04bf09baab736a447148a230ae150f8f6fc929d6c6f2ccc364f364fb5a;
    bytes32 proxySaltStr = 0xb225d27dc65c353234f5c8ec7c01d2a08967b60d774b801949184d7dfe8a1b9f;
        
    function setUp() public {

        // Deploy impl as foundry factory with salt
        vm.prank(foundryFactory);
        fastlaneImplementation = new FastLaneLegacyAuction{salt: implementationSaltStr}(eoa);

        console2.log("Implementation Deployed at:");
        console2.log(address(fastlaneImplementation));
        console2.log(address(fastlaneImplementation).code.length);
        console2.log("------------------------------------");
    }

    function _ignoretestDeploy() public {


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

    //     function testUpgrade() public {
        
    //     bytes memory encodedPostProxyDeployCall = abi.encodeWithSignature("initialize(address)", eoa);

    //     vm.prank(foundryFactory);
    //     ERC1967Proxy proxy = new ERC1967Proxy{salt: proxySaltStr}(address(fastlaneImplementation), encodedPostProxyDeployCall); 
       
    //     console2.log("Deployed Proxy @:");
    //     address deployedProxyAddress = address(proxy);
    //     console2.log(deployedProxyAddress);
    //     console2.log("------------------------------------");

    //     assertEq(deployedProxyAddress,expectedProxyAddress, "Addresses mismatch");

    //     vm.prank(eoa);
    //     address STARTER_ROLE = msg.sender;
    //     (bool successInitialSetupAuction, bytes memory returnSetupData) = deployedProxyAddress.call(abi.encodeWithSignature("initialSetupAuction(address,address,address)", STARTER_ROLE, STARTER_ROLE, STARTER_ROLE));
        
    //     console2.log("initialSetupAuction call:");
    //     console2.log(successInitialSetupAuction);
    //     console2.log(string(returnSetupData));

    //     assertTrue(successInitialSetupAuction);

    //     // V2 Impl
    //     bytes32 implementationV2SaltStrV2 = "V2";
    //     // Deploy impl as foundry factory with salt
    //     vm.prank(foundryFactory);
    //     FastLaneLegacyAuction fastlaneV2ImplementationV2 = new FastLaneLegacyAuction{salt: implementationV2SaltStrV2}(eoa); // 0x368845aff2b7051c33ca5db927eceb6e54efce5c

    //     vm.prank(eoa);
    //     vm.expectEmit(true, true, true, true);
    //     emit Upgraded(address(fastlaneV2ImplementationV2));
    //     (bool successUpgrade, bytes memory returnUpgradeData) = deployedProxyAddress.call(abi.encodeWithSignature("upgradeTo(address)", address(fastlaneV2ImplementationV2)));
        
    //     assertTrue(successUpgrade);

    //     vm.startPrank(eoa);
    //     vm.expectEmit(true, true, true, true, address(deployedProxyAddress));
    //     emit OpsSet(eoa);
    //     (bool successCallAsOwner,) = deployedProxyAddress.call(abi.encodeWithSignature("setOps(address)", address(eoa)));
        
    //     assertTrue(successCallAsOwner);

    //     vm.expectEmit(true, true, true, true, address(deployedProxyAddress));
    //     emit OwnershipTransferred(eoa, VALIDATOR1);
    //     (bool successCallTransfer,) = deployedProxyAddress.call(abi.encodeWithSignature("transferOwnership(address)", address(VALIDATOR1)));
        
    //     assertTrue(successCallTransfer);
    // }
}