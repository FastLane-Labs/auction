// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.16 <0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FastLaneAuctionHandler} from "contracts/auction-handler/FastLaneAuctionHandler.sol";

contract Deploy is Script {
    function run() public {

        console.log("\n=== DEPLOYING FastLane Auction Handler 2.0 ===\n");

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address: \t\t\t\t", deployer);

        vm.startBroadcast(deployerPrivateKey);

        FastLaneAuctionHandler auction = new FastLaneAuctionHandler();

        vm.stopBroadcast();

        console2.log("FastLane Auction Handler deployed at: \t", address(auction));
    }

}