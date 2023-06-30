//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IPaymentProcessor {
    function payValidator(
        uint256 startBlock,
        uint256 endBlock,
        uint256 totalAmount,
        uint256 customAllocation,
        bytes calldata data
    ) external payable;
}