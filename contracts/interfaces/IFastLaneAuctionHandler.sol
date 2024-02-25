pragma solidity ^0.8.10;

interface IFastLaneAuctionHandler {
    event CustomPaymentProcessorPaid(
        address indexed payor,
        address indexed payee,
        address indexed paymentProcessor,
        uint256 totalAmount,
        uint256 startBlock,
        uint256 endBlock
    );
    event RelayFastBid(
        address indexed sender,
        address indexed validator,
        bool success,
        uint256 bidAmount,
        address searcherContractAddress
    );
    event RelayFeeCollected(address indexed payor, address indexed payee, uint256 amount);
    event RelayFlashBid(
        address indexed sender,
        bytes32 indexed oppTxHash,
        address indexed validator,
        uint256 bidAmount,
        uint256 amountPaid,
        address searcherContractAddress
    );
    event RelayFlashBidWithRefund(
        address indexed sender,
        bytes32 indexed oppTxHash,
        address indexed validator,
        uint256 bidAmount,
        uint256 amountPaid,
        address searcherContractAddress,
        uint256 refundedAmount,
        address refundAddress
    );
    event RelayInvestigateOutcome(
        address indexed validator,
        address indexed sender,
        uint256 blockNumber,
        uint256 existingBidAmount,
        uint256 newBidAmount,
        uint256 existingGasPrice,
        uint256 newGasPrice
    );
    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);
    event RelayProcessingWithdrewStakeShare(address indexed recipient, uint256 amountWithdrawn);
    event RelaySimulatedFlashBid(
        address indexed sender,
        uint256 amount,
        bytes32 indexed oppTxHash,
        address indexed validator,
        address searcherContractAddress
    );
    event RelayValidatorPayeeUpdated(address validator, address payee, address indexed initiator);
    event RelayWithdrawStuckERC20(address indexed receiver, address indexed token, uint256 amount);
    event RelayWithdrawStuckNativeToken(address indexed receiver, uint256 amount);

    function clearValidatorPayee() external;
    function collectFees() external returns (uint256);
    function collectFeesCustom(address paymentProcessor, bytes memory data) external;
    function fastBidWrapper(
        address msgSender,
        uint256 fastPrice,
        address searcherToAddress,
        bytes memory searcherCallData
    ) external payable returns (uint256);
    function fulfilledAuctionsMap(bytes32) external view returns (uint256);
    function fulfilledPGAMap(uint256)
        external
        view
        returns (uint64 lowestGasPrice, uint64 lowestFastPrice, uint64 lowestTotalPrice);
    function getValidatorBalance(address _validator) external view returns (uint256 _validatorBalance);
    function getValidatorBlockOfLastWithdraw(address _validator) external view returns (uint256 _blockNumber);
    function getValidatorPayee(address _validator) external view returns (address _payee);
    function getValidatorRecipient(address _validator) external view returns (address _recipient);
    function isPayeeTimeLocked(address _validator) external view returns (bool _isTimeLocked);
    function isValidPayee(address _validator, address _payee) external view returns (bool _valid);
    function payValidatorFee(address _payor) external payable;
    function payeeMap(address) external view returns (address);
    function paymentCallback(address validator, address payee, uint256 amount) external;
    function simulateFlashBid(
        uint256 bidAmount,
        bytes32 oppTxHash,
        address searcherToAddress,
        bytes memory searcherCallData
    ) external payable;
    function submitFastBid(uint256 fastGasPrice, bool executeOnLoss, address searcherToAddress, bytes memory searcherCallData)
        external
        payable;
    function submitFlashBid(
        uint256 bidAmount,
        bytes32 oppTxHash,
        address searcherToAddress,
        bytes memory searcherCallData
    ) external payable;
    function submitFlashBidWithRefund(
        uint256 bidAmount,
        bytes32 oppTxHash,
        address refundAddress,
        address searcherToAddress,
        bytes memory searcherCallData
    ) external payable;
    function syncStuckNativeToken() external;
    function updateValidatorPayee(address _payee) external;
    function updateValidatorRefundShare(uint256 refundShare) external;
    function validatorsBalanceMap(address) external view returns (uint256);
    function validatorsRefundShareMap(address) external view returns (uint256);
    function validatorsTotal() external view returns (uint256);
    function withdrawStakeShare(address _recipient, uint256 _amount) external;
    function withdrawStuckERC20(address _tokenAddress) external;
}
