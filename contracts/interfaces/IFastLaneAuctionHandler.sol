pragma solidity ^0.8.10;

interface IFastLaneAuctionHandler {
    event RelayFeeCollected(address indexed payor, address indexed payee, uint256 amount);
    event RelayFlashBid(
        address indexed sender,
        uint256 amount,
        bytes32 indexed oppTxHash,
        address indexed validator,
        address searcherContractAddress
    );
    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);
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

    function collectFees() external returns (uint256);
    function fulfilledAuctionsMap(bytes32) external view returns (uint256);
    function getValidatorBalance(address _validator) external view returns (uint256 _validatorBalance);
    function getValidatorPayee(address _validator) external view returns (address _payee);
    function getValidatorRecipient(address _validator) external view returns (address _recipient);
    function humanizeError(bytes memory _errorData) external pure returns (string memory decoded);
    function isPayeeTimeLocked(address _validator) external view returns (bool _isTimeLocked);
    function isValidPayee(address _validator, address _payee) external view returns (bool _valid);
    function payValidatorFee(address _payor) external payable;
    function simulateFlashBid(
        uint256 _bidAmount,
        bytes32 _oppTxHash,
        address _searcherToAddress,
        bytes memory _searcherCallData
    ) external payable;
    function submitFlashBid(
        uint256 _bidAmount,
        bytes32 _oppTxHash,
        address _searcherToAddress,
        bytes memory _searcherCallData
    ) external payable;
    function syncStuckNativeToken() external;
    function updateValidatorPayee(address _payee) external;
    function validatorsBalanceMap(address) external view returns (uint256);
    function validatorsTotal() external view returns (uint256);
    function withdrawStuckERC20(address _tokenAddress) external;
}
