//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPaymentProcessor {
    function payValidator(
        address validator,
        uint256 startBlock,
        uint256 endBlock,
        uint256 totalAmount,
        bytes calldata data
    ) external;
}
