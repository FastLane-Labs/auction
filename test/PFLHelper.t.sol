// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "contracts/interfaces/IWMatic.sol";
import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

abstract contract PFLHelper is Test {
    using Address for address payable;

    address constant MUMBAI_MATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
    address constant OPS_ADDRESS = address(0xBEEF);
    WMATIC public wMatic;

    address public OWNER = 0xa401DCcD23DCdbc7296bDfb8A6c8d61106711CA6;

    address public BIDDER1 = 0xc71E2Df87C93bC3Ddba80e14406F3880E3D19D3e;

    address public BIDDER2 = 0x174237f20a0925d5eFEA401e5279181f0b7515EE;
    address public BIDDER3 = 0xFba52cDB2B36eCc27ac229b8feb2455B6aE3014b;
    address public BIDDER4 = 0xc4208Be0F01C8DBB57D0269887ccD5D269dEFf3B;

    address public VALIDATOR1 = 0x8149d8a0aCE8c058a679a1Fd4257aA1F1d2b9103;
    address public VALIDATOR2 = 0x161c3421Da27CD26E3c46Eb5711743343d17352d;
    address public VALIDATOR3 = 0x60d86bBFD061A359fd3B3E6Ef422b74B886f9a4a;
    address public VALIDATOR4 = 0x68F248c6B7820B191E4ed18c3d618ba7aC527C99;

    address public OPPORTUNITY1 = 0x8af6F6CA42171fc823619AC33a9A6C1892CA980B;
    address public OPPORTUNITY2 = 0x6eD132ea309B432FD49C9e70bc4F8Da429022F77;
    address public OPPORTUNITY3 = 0x8fcB7fb5e84847029Ba3e055BE46b86a4693AE40;
    address public OPPORTUNITY4 = 0x29D59575e85282c05112BEEC53fFadE66d3c7CD1;

    address public BROKE_BIDDER = 0xD057089743dc1461b1099Dee7A8CB848E361f6d9;
    address public BROKE_SEARCHER = 0xD057089743dc1461b1099Dee7A8CB848E361f6d9;

    address public SEARCHER_ADDRESS1 = 0x14BA06E061ada0443dbE5c7617A529Dd791c3146;
    address public SEARCHER_ADDRESS2 = 0x428a87F9c0ed1Bb9cdCE42f606e030ba40a525f3;
    address public SEARCHER_ADDRESS3 = 0x791e001586B75B8880bC6D02f2Ee19D42ec23E18;
    address public SEARCHER_ADDRESS4 = 0x4BF8fC74846da2dc54cCfd1f4fFac595939399e4;

    address public REFUND_RECIPIENT = 0xFdE9601264EBB3B664B7E37E9D3487D8fabB9001;

    address[] public BIDDERS = [BIDDER1, BIDDER2, BIDDER3, BIDDER4];

    address[] public SEARCHERS = [SEARCHER_ADDRESS1, SEARCHER_ADDRESS2, SEARCHER_ADDRESS3, SEARCHER_ADDRESS4];

    address[] public VALIDATORS = [VALIDATOR1, VALIDATOR2, VALIDATOR3, VALIDATOR4];
    address[] public OPPORTUNITIES = [OPPORTUNITY1, OPPORTUNITY2, OPPORTUNITY3, OPPORTUNITY4];

    constructor() {}
}
