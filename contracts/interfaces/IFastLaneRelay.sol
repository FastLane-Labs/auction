pragma solidity ^0.8.10;

interface IFastLaneRelay {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RelayFeeSet(uint24 amount);
    event RelayFlashBid(
        address indexed sender,
        uint256 amount,
        bytes32 indexed oppTxHash,
        address indexed validator,
        address searcherContractAddress
    );
    event RelayInitialized(address vault);
    event RelayPausedStateSet(bool state);
    event RelayValidatorDisabled(address validator);
    event RelayValidatorEnabled(address validator);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function checkAllowedInAuction(address _coinbase) external view returns (bool);
    function disableRelayValidatorAddress(address _validator) external;
    function enableRelayValidatorAddress(address _validator) external;
    function fastlaneAddress() external view returns (address);
    function fastlaneRelayFee() external view returns (uint24);
    function owner() external view returns (address);
    function paused() external view returns (bool);
    function renounceOwnership() external;
    function setFastlaneRelayFee(uint24 _fastLaneRelayFee) external;
    function setPausedState(bool _state) external;
    function submitFlashBid(
        uint256 _bidAmount,
        bytes32 _oppTxHash,
        address _validator,
        address _searcherToAddress,
        bytes memory _toForwardExecData
    )
        external
        payable;
    function transferOwnership(address newOwner) external;
    function vaultAddress() external view returns (address);
}
