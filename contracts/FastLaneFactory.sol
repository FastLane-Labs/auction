//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import {FastLaneLegacyAuction} from "./legacy/FastLaneLegacyAuction.sol";


contract FastLaneFactory {

    address public fastlane;

    mapping(uint256 => address) public gelatoOpsAddresses;
    mapping(uint256 => address) public wrappedNativeAddresses;

    // Todo: Remove Unused
    bytes32 private constant INIT_CODEHASH = keccak256(type(FastLaneLegacyAuction).creationCode);

    event FastLaneCreated(address fastlaneContract);

    function _createFastLane(bytes32 _salt, address _initial_bid_token, address _ops) internal {
        
        // use CREATE2 so we can get a deterministic address based on the salt
        fastlane = address(new FastLaneLegacyAuction{salt: _salt}(msg.sender));

        // CREATE2 can return address(0), add a check to verify this isn't the case
        // See: https://eips.ethereum.org/EIPS/eip-1014
        require(fastlane != address(0), "Wrong init");
        emit FastLaneCreated(fastlane);

        FastLaneLegacyAuction(fastlane).initialSetupAuction(_initial_bid_token, _ops, msg.sender);

    }

    function getArgs() public view returns (address initial_bid_token, address ops) {
        ops = gelatoOpsAddresses[block.chainid];
        initial_bid_token = wrappedNativeAddresses[block.chainid];
    }

    constructor(bytes32 _salt) {
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

        _createFastLane(_salt, initial_bid_token, ops);
    }

    function getFastLaneContractBySalt(bytes32 _salt) external view returns(address predictedAddress, bool isDeployed){
        
        (address initial_bid_token, address ops) = getArgs();

        require(ops != address(0), "O(o)ps");
        require(initial_bid_token != address(0), "Wrapped");

        predictedAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            _salt,
            keccak256(abi.encodePacked(
                type(FastLaneLegacyAuction).creationCode
            )
        ))))));
        isDeployed = predictedAddress.code.length != 0;
    }

}