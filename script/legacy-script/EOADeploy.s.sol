// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FastLaneLegacyAuction} from "../../contracts/legacy/FastLaneLegacyAuction.sol";

contract Deploy is Script {


    address public fastlane;

    mapping(uint256 => address) public gelatoOpsAddresses;
    mapping(uint256 => address) public wrappedNativeAddresses;


    function getArgs() public view returns (address initial_bid_token, address ops) {
        ops = gelatoOpsAddresses[block.chainid];
        initial_bid_token = wrappedNativeAddresses[block.chainid];
    }

    function run() public {

        gelatoOpsAddresses[1] = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
        gelatoOpsAddresses[137] = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;
        gelatoOpsAddresses[80001] = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;
        gelatoOpsAddresses[31337] = 0xB3f5503f93d5Ef84b06993a1975B9D21B962892F;

        wrappedNativeAddresses[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        wrappedNativeAddresses[137] = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        wrappedNativeAddresses[80001] = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        wrappedNativeAddresses[31337] = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;


        (address initial_bid_token, address ops) = getArgs();


        require(ops != address(0), "O(o)ps");
        require(initial_bid_token != address(0), "Wrapped");

        // Unusable until vm.remember: https://github.com/foundry-rs/foundry/pull/2299
        // uint256 deployerPrivateKey = vm.deriveKey(vm.envString("TESTNET_MNEMONIC"), 0);
        // vm.startBroadcast(vm.addr(deployerPrivateKey));

        vm.startBroadcast();
        fastlane = address(new FastLaneLegacyAuction(msg.sender));
        
        FastLaneLegacyAuction(fastlane).initialSetupAuction(initial_bid_token, ops, msg.sender);

        console2.log(fastlane);
    }

}