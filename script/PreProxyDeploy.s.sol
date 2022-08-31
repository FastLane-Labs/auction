// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FastLaneFactory} from "contracts/FastLaneFactory.sol";

contract Deploy is Script {
    FastLaneFactory fastlaneFactoryV0;

    function run() public {

        vm.startBroadcast();
        bytes32 salt = bytes32("hello");
        FastLaneFactory FLF = new FastLaneFactory(salt);

        address deployed = FLF.fastlane();
        console2.log(address(FLF));
        console2.log(deployed);
    }

}