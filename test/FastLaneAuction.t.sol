// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/FastLaneAuction.sol";

contract FastLaneAuctionTest is Test {
    FastLaneAuction auction;

    address owner = address(69);
    address wMatic = address(100);

    function setUp() public {
        vm.prank(owner);
        auction = new FastLaneAuction(wMatic);

        vm.label(owner, "owner");
        vm.label(wMatic, "WMATIC");
        vm.label(address(auction), "FastLaneAuction");
    }

    function testExample() public {
        assertTrue(true);
    }
}
