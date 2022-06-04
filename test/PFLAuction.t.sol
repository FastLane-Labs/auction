// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";

// 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889 - Mumbai WMATIC
// 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270 - Polygon Mainnet WMATIC

contract PFLAuctionTest is Test {
    FastLaneAuction public FLA;
    function setUp() public {
               vm.startPrank(0xa401DCcD23DCdbc7296bDfb8A6c8d61106711CA6);
                FLA = new FastLaneAuction(0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889);

    }

    function testExample() public {
        console2.log("Sender:",msg.sender);
        assertTrue(true);
    }
}
