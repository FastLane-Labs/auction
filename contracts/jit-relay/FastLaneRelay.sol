//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import { IFastLaneAuction } from "../interfaces/IFastLaneAuction.sol";
import "openzeppelin-contracts/contracts//access/Ownable.sol";



import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";


abstract contract FastLaneRelayEvents {

    event RelayPausedStateSet(bool state);
    event RelayValidatorEnabled(address validator);
    event RelayValidatorDisabled(address validator);
    event RelayInitialized(address vault);
    event RelayFeeSet(uint24 amount);
    event RelayFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);

    error RelayInequalityTooHigh();

    error RelayPermissionPaused();
    error RelayPermissionNotFastlaneValidator();

    error RelayWrongInit();
    error RelayWrongSpecifiedValidator();
    error RelaySearcherWrongParams();

    error RelaySearcherCallFailure(bytes retData);
    error RelayNotRepaid(uint256 missingAmount);
    

}
contract FastLaneRelay is FastLaneRelayEvents, Ownable, ReentrancyGuard {

    using SafeTransferLib for address payable;

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    address public fastlaneAddress;
    address public vaultAddress;

    mapping(address => bool) internal validatorsMap;

    bool public paused = false;

    uint24 public fastlaneRelayFee;

    constructor(address _vaultAddress, uint24 _fee) {
        if (_vaultAddress == address(0) || _fee == 0) revert RelayWrongInit();
        
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();


        vaultAddress = _vaultAddress;
        
        setFastlaneRelayFee(_fee);

        emit RelayInitialized(_vaultAddress);
    }


    function submitFlashBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution
        bytes32 _oppTxHash, // Target TX
        address _validator, // Set to address(0) if any PFL validator works
        address _searcherToAddress,
        bytes calldata _toForwardExecData 
        // _toForwardExecData should contain _bidAmount somewhere in the data to be decoded on the receiving searcher contract
        ) external payable nonReentrant whenNotPaused onlyParticipatingValidators {

            if (_validator != address(0) && _validator != block.coinbase) revert RelayWrongSpecifiedValidator();
            if (_searcherToAddress == address(0) || _bidAmount == 0) revert RelaySearcherWrongParams();
            
            
            uint256 balanceBefore = vaultAddress.balance;
      
            //(uint256 vCut, uint256 flCut) = _calculateRelayCuts(_bidAmount, _fee);

            (bool success, bytes memory retData) = _searcherToAddress.call{value: msg.value}(abi.encodePacked(_toForwardExecData, msg.sender));
            if (!success) revert RelaySearcherCallFailure(retData);

            uint256 expected = balanceBefore + _bidAmount;
            uint256 balanceAfter = vaultAddress.balance;
            if (balanceAfter < expected) revert RelayNotRepaid(expected - balanceAfter);
            emit RelayFlashBid(msg.sender, _bidAmount, _oppTxHash, _validator, _searcherToAddress);
    }


    /// @notice Internal, calculates cuts
    /// @dev vCut 
    /// @param _amount Amount to calculates cuts from
    /// @param _fee Fee bps
    /// @return vCut validator cut
    /// @return flCut protocol cut
    function _calculateRelayCuts(uint256 _amount, uint24 _fee) internal pure returns (uint256 vCut, uint256 flCut) {
        vCut = (_amount * (1000000 - _fee)) / 1000000;
        flCut = _amount - vCut;
    }

    // Unused
    function checkAllowedInAuction(address _coinbase) public view returns (bool) {
        uint128 auction_number = IFastLaneAuction(fastlaneAddress).auction_number();
        IFastLaneAuction.Status memory coinbaseStatus = IFastLaneAuction(fastlaneAddress).getStatus(_coinbase);
        if (coinbaseStatus.kind != IFastLaneAuction.statusType.VALIDATOR) return false;

        // Validator is past his inactivation round number
        if (auction_number >= coinbaseStatus.inactiveAtAuctionRound) return false;
        // Validator is not yet at his activation round number
        if (auction_number < coinbaseStatus.activeAtAuctionRound) return false;
        return true;
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("FastLaneRelay")),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /***********************************|
    |             Owner-only            |
    |__________________________________*/

    /// @notice Defines the paused state of the Auction
    /// @dev Only owner
    /// @param _state New state
    function setPausedState(bool _state) external onlyOwner {
        paused = _state;
        emit RelayPausedStateSet(_state);
    }


    /// @notice Sets the protocol fee (out of 1000000 (ie v2 fee decimals))
    /// @dev Initially set to 50000 (5%) For now we can't change the fee during an ongoing auction since the bids do not store the fee value at bidding time
    /// @param _fastLaneRelayFee Protocol fee on bids
    function setFastlaneRelayFee(uint24 _fastLaneRelayFee)
        public
        onlyOwner
    {
        if (_fastLaneRelayFee > 1000000) revert RelayInequalityTooHigh();
        fastlaneRelayFee = _fastLaneRelayFee;
        emit RelayFeeSet(_fastLaneRelayFee);
    }
    

    function enableRelayValidatorAddress(address _validator) external onlyOwner {
        validatorsMap[_validator] = true;
        emit RelayValidatorEnabled(_validator);
    }

    function disableRelayValidatorAddress(address _validator) external onlyOwner {
        validatorsMap[_validator] = false;
        emit RelayValidatorDisabled(_validator);
    }

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    modifier whenNotPaused() {
        if (paused) revert RelayPermissionPaused();
        _;
    }

    modifier onlyParticipatingValidators() {
        if (!validatorsMap[block.coinbase]) revert RelayPermissionNotFastlaneValidator();
        _;
    }
}