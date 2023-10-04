//SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IPaymentProcessor} from "../../contracts/interfaces/IPaymentProcessor.sol";
import {IFastLaneAuctionHandler} from "../../contracts/interfaces/IFastLaneAuctionHandler.sol";

contract MockPaymentProcessor is IPaymentProcessor {

    address public payee; // Receives ETH from AuctionHandler

    // Test vars to verify data is passed correctly
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public totalAmount;
    address public validator;
    bytes public data;

    function setPayee(address _payee) external {
        payee = _payee;
    }

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

        IFastLaneAuctionHandler(msg.sender).paymentCallback(_validator, payee, _totalAmount);
    }
}

// Broken PaymentProcessor which does not call paymentCallback
contract MockPaymentProcessorBroken is IPaymentProcessor {

    address public payee; // Receives ETH from AuctionHandler

    // Test vars to verify data is passed correctly
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public totalAmount;
    address public validator;
    bytes public data;

    function setPayee(address _payee) external {
        payee = _payee;
    }

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

        // NOTE: The line below is intentionally not called to simulate a broken payment processor
        // IFastLaneAuctionHandler(msg.sender).paymentCallback(_validator, payee, _totalAmount);
    }
}
