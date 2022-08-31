// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FastLaneAuction} from "../contracts/FastLaneAuction.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {


    address public fastlaneImplementation;

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

        vm.startBroadcast();

        //bytes32 proxySaltStr = 0x023049182d9b870591683334cb8bdaf382f49ff092d076afb86b4dec503e30fc;
        bytes32 proxySaltStr = 0xdedd35ceaec8d2aae8506b7c1466e0e256b6576d4dbcf8560d4634bc01114856;
        bytes32 implementationSaltStr = "hello";

        address foundryFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        address eoa = msg.sender;


        console2.log("CREATE2 Implementation Predict Bytecode:");
        // Copy this into init_code_implementation.txt
        console2.logBytes(abi.encodePacked(type(FastLaneAuction).creationCode, abi.encode(eoa)));


        FastLaneAuction FLAImplementation = new FastLaneAuction{salt: implementationSaltStr}(eoa); // 0x2962a95ee7d5aef7205a944d6d5b25d68a510c68
        fastlaneImplementation = address(FLAImplementation); 

        console2.log("Implementation Deployed at:");
        console2.log(fastlaneImplementation);
        console2.log(fastlaneImplementation.code.length);
        console2.log("------------------------------------");

        console2.log("Current Sender:");
        console2.log(msg.sender);
        console2.log("------------------------------------");

        // Call that will be made after deploy of Proxy
        // will transfer ownership to `eoa` after receiving it from `foundryFactory`
        bytes memory encodedPostProxyDeployCall = abi.encodeWithSignature("initialize(address)", eoa);

        console2.log("encodedPostProxyDeployCall Bytecode:");
        console2.logBytes(encodedPostProxyDeployCall);



        console2.log("------------------------------------");
        ERC1967Proxy proxy = new ERC1967Proxy{salt: proxySaltStr}(fastlaneImplementation, encodedPostProxyDeployCall); 


        console2.log("Proxy Bytecode:");
        console2.logBytes(address(proxy).code);
        console2.log("------------------------------------");

        console2.log("CREATE2 Proxy Predict Bytecode:");
        // Copy this into init_code.txt
        console2.logBytes(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(fastlaneImplementation,encodedPostProxyDeployCall)));


        console2.log("Deployed Proxy @:");
        address deployedProxyAddress = address(proxy);
        console2.log(deployedProxyAddress);
        console2.log("------------------------------------");

        //address expectedProxyAddress = 0xfA571a11EB379578588920CA78FBf26C0b4956CC;
        address expectedProxyAddress = 0x1337Ac52169E2a97EBa85c736B6Ba435Ec93a543;
        require(deployedProxyAddress == expectedProxyAddress, "Wrong Addresses");

        // (bool successInitializeProxy,) = address(proxy).call(abi.encodeWithSignature("initialize()"));

        // Setup the FastlaneAuction through the proxy.
        address STARTER_ROLE = msg.sender; // Change me
        (bool successInitialSetupAuction, bytes memory returnSetupData) = deployedProxyAddress.call(abi.encodeWithSignature("initialSetupAuction(address,address,address)", initial_bid_token, ops, STARTER_ROLE));
        
        console2.log("initialSetupAuction call:");
        console2.log(successInitialSetupAuction);
        console2.log(string(returnSetupData));
        console2.log("------------------------------------");
        console2.log(fastlaneImplementation.code.length);
        console2.log("------------------------------------");

        require(successInitialSetupAuction,"Proxy calls fail");
    }

}