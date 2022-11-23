//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

// Example Contract that sends back _bidAmount to msg.sender
// It ignores _sender and _searcherCallData
// Used for testing purposes
contract SearcherHelperRepayerEcho {
    function fastLaneCall(
            address _sender,
            uint256 _bidAmount,
            bytes calldata _searcherCallData
    ) external payable returns (bool, bytes memory) {
        bool success;
        address to = msg.sender;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, _bidAmount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
        return (true,bytes("ok"));
    }
}