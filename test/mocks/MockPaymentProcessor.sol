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
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _totalAmount,
        uint256 _customAllocation,
        bytes calldata _data
    ) external payable {
        // Checking all data passed correctly to PaymentProcessor,
        // Including the validator address decoded from data
        validator = abi.decode(_data, (address));
        totalAmount = _totalAmount;
        customAllocation = _customAllocation;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }
}