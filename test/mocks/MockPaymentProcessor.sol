//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IPaymentProcessor} from "../../contracts/interfaces/IPaymentProcessor.sol";

contract MockPaymentProcessor is IPaymentProcessor {

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public totalAmount;
    address public validator;
    bytes public data;

    function payValidator(
        address _validator,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _totalAmount,
        bytes calldata _data
    ) external {
        // Checking all data passed correctly to PaymentProcessor,
        // Including the validator address decoded from data
        validator = _validator;
        totalAmount = _totalAmount;
        startBlock = _startBlock;
        endBlock = _endBlock;
        data = _data;
    }
}