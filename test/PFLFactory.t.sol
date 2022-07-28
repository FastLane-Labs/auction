// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import {FastLaneFactory} from "contracts/FastLaneFactory.sol";

contract PFLFactoryTest is Test {
    
    function setUp() public {

    }

    function testCreateFastLane() public {
        address DEPLOYER = 0x1BA0f96bf6b26df11a58553c6db9a0314938Cf70;
        vm.prank(0x1BA0f96bf6b26df11a58553c6db9a0314938Cf70);
        console2.log(block.chainid);

        bytes32 salt = bytes32("hello");
        FastLaneFactory FLF = new FastLaneFactory(salt);
        address deployed = FLF.fastlane();

        (address ops, address initial_bid_token) = FLF.getArgs();
        console2.log(ops, initial_bid_token);
        (address predictedAddress, bool isDeployed) = FLF.getFastLaneContractBySalt(salt);

        console2.log(deployed);
        console2.log(predictedAddress);

        assertEq(deployed, 0xc4A187652BF4a552A74cebF183B62089010BEb53);
        assertEq(predictedAddress, deployed, "Predicted address does not match");
        
        assertEq(isDeployed, true, "No contract deployed at predicted address");
        
        // Call owner();
        (, bytes memory ownerData) = deployed.call(abi.encodeWithSelector(0x8da5cb5b));
        address owner = abi.decode(ownerData, (address));
        assertEq(owner, DEPLOYER);
    }

}