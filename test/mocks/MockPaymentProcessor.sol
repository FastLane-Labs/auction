//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IPaymentProcessor} from "../../contracts/interfaces/IPaymentProcessor.sol";

contract MockPaymentProcessor is IPaymentProcessor {

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public totalAmount;
    uint256 public customAllocation;
    address public validator;

    function payValidator(
        uint256 startBlock,
        uint256 endBlock,
        uint256 totalAmount,
        uint256 customAllocation,
        bytes calldata data
    ) external payable {
        // Checking all data passed correctly to PaymentProcessor,
        // Including the validator address decoded from data
        validator = abi.decode(data, (address));
        totalAmount = totalAmount;
        customAllocation = customAllocation;
        startBlock = startBlock;
        endBlock = endBlock;
    }
}