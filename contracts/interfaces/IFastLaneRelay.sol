pragma solidity ^0.8.10;

interface IFastLaneAuctionHandler {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RelayFlashBid(
        address indexed sender,
        uint256 amount,
        bytes32 indexed oppTxHash,
        address indexed validator,
        address searcherContractAddress
    );
    event RelayInitialized(uint24 initialStakeShare, uint256 minAmount, bool restrictEOA);
    event RelayMinAmountSet(uint256 minAmount);
    event RelayPausedStateSet(bool state);
    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);
    event RelayProcessingWithdrewStakeShare(address indexed recipient, uint256 amountWithdrawn);
    event RelayShareProposed(uint24 amount, uint256 deadline);
    event RelayShareSet(uint24 amount);
    event RelayValidatorDisabled(address validator);
    event RelayValidatorEnabled(address validator, address payee);
    event RelayValidatorPayeeUpdated(address validator, address payee, address indexed initiator);
    event RelayWithdrawDust(address indexed receiver, uint256 amount);
    event RelayWithdrawStuckERC20(address indexed receiver, address indexed token, uint256 amount);
    event RelayWithdrawStuckNativeToken(address indexed receiver, uint256 amount);

    function RESTRICT_EOA() external view returns (bool);
    function disableRelayValidator(address _validator) external;
    function enableRelayValidator(address _validator, address _payee) external;
    function flStakeSharePayable() external view returns (uint256);
    function flStakeShareRatio() external view returns (uint24);
    function fulfilledAuctionsMap(bytes32) external view returns (uint256);
    function getCurrentStakeBalance() external view returns (uint256);
    function getCurrentStakeRatio() external view returns (uint24);
    function getPendingDeadline() external view returns (uint256 _timeDeadline);
    function getPendingStakeRatio() external view returns (uint24 _fastLaneStakeShare);
    function getValidatorBalance(address _validator) external view returns (uint256 _validatorBalance);
    function getValidatorPayee(address _validator) external view returns (address _payee);
    function getValidatorRecipient(address _validator) external view returns (address _recipient);
    function getValidatorStatus(address _validator) external view returns (bool);
    function humanizeError(bytes memory _errorData) external pure returns (string memory decoded);
    function minRelayBidAmount() external view returns (uint256);
    function owner() external view returns (address);
    function paused() external view returns (bool);
    function payValidator(address _validator) external returns (uint256);
    function pendingStakeShareUpdate() external view returns (bool);
    function proposalDeadline() external view returns (uint256);
    function proposalStakeShareRatio() external view returns (uint24);
    function recoverDust(uint256 _amount) external;
    function renounceOwnership() external;
    function setFastLaneStakeShare(uint24 _fastLaneStakeShare) external;
    function setMininumBidAmount(uint256 _minAmount) external;
    function setPausedState(bool _state) external;
    function submitFlashBid(
        uint256 _bidAmount,
        bytes32 _oppTxHash,
        address _searcherToAddress,
        bytes memory _searcherCallData
    ) external payable;
    function transferOwnership(address newOwner) external;
    function triggerPendingStakeShareUpdate() external;
    function updateValidatorPayee(address _validator, address _payee) external;
    function validatorsBalanceMap(address) external view returns (uint256);
    function validatorsStatusMap(address) external view returns (bool);
    function validatorsTotal() external view returns (uint256);
    function withdrawStakeShare(address _recipient, uint256 _amount) external;
    function withdrawStuckERC20(address _tokenAddress) external;
    function withdrawStuckNativeToken(uint256 _amount) external;
}
