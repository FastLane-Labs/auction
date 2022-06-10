// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import "contracts/FastLaneAuction.sol";
import "contracts/test/TestWMatic.sol";

import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889 - Mumbai WMATIC
// 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270 - Polygon Mainnet WMATIC

abstract contract PFLHelper {
    address public OWNER = 0xa401DCcD23DCdbc7296bDfb8A6c8d61106711CA6;

    address public BIDDER1 = 0xc71E2Df87C93bC3Ddba80e14406F3880E3D19D3e;
    address public BIDDER2 = 0x174237f20a0925d5eFEA401e5279181f0b7515EE;
    address public BIDDER3 = 0xFba52cDB2B36eCc27ac229b8feb2455B6aE3014b;
    address public BIDDER4 = 0xc4208Be0F01C8DBB57D0269887ccD5D269dEFf3B;

    // @todo: Payable Addresses
    
    address[] public BIDDERS = [BIDDER1,BIDDER2,BIDDER3,BIDDER4];

    constructor() {

    }
}

contract PFLAuctionTest is Test, PFLHelper {

    using Address for address payable;
    FastLaneAuction public FLA;
    WMATIC public wMatic = new WMATIC();

    function setUp() public {

        vm.prank(OWNER);
        FLA = new FastLaneAuction(wMatic);
        console2.log("FLA deployed at:",FLA);
        console2.log("WMATIC deployed at:",wMatic);

        for (uint i = 0; i< BIDDERS.length; ++i) {
            address currentBidder = BIDDERS[i];
            uint soonWMatic = (10 ether * i);
            vm.deal(currentBidder,soonWMatic + 1);
            vm.prank(currentBidder);
            wMatic.deposit{value: soonWMatic}();
            console2.log("amount Bidder-",i,wMatic.balanceOf(currentBidder));
        }

        // Fund useful accounts

    }

    function testStartProcessStopAuction() public {
        console2.log("Sender:",msg.sender);
        vm.startPrank(OWNER);
        FLA.startAuction();
        FLA.stopBidding();
        //FLA.processPartialAuctionResults();
        FLA.endAuction();

        assertTrue(true);
    }
}
