//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import { IFastLaneAuction } from "../interfaces/IFastLaneAuction.sol";
import "openzeppelin-contracts/contracts//access/Ownable.sol";



import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";


struct Round {
    uint24 roundNumber;
    uint24 stakeAllocation;
    uint64 startBlock;
    uint64 endBlock;
    uint256 revenueCollected;
    uint256 revenuePaid;
    uint256 paidValidatorIndex;
    bool completedPayments;
}

abstract contract FastLaneRelayEvents {

    event RelayPausedStateSet(bool state);
    event RelayValidatorEnabled(address validator);
    event RelayValidatorDisabled(address validator);
    event RelayInitialized(address vault);
    event RelayShareSet(uint24 amount);
    event RelayFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);
    event RelayNewRound(uint24 newRoundNumber);

    error RelayInequalityTooHigh();

    error RelayPermissionPaused();
    error RelayPermissionNotFastlaneValidator();

    error RelayWrongInit();
    error RelayWrongSpecifiedValidator();
    error RelaySearcherWrongParams();

    error RelaySearcherCallFailure(bytes retData);
    error RelayNotRepaid(uint256 missingAmount);

    error AuctionEOANotEnabled();
    error AuctionValidatorNotParticipating(address validator);
    error AuctionSearcherNotWinner(uint256 searcherBid, uint256 winningBid);
    error AuctionBidReceivedLate();

    error ProcessingRoundNotOver();
    error ProcessingRoundFullyPaidOut();
}

contract FastLaneRelay is FastLaneRelayEvents, Ownable, ReentrancyGuard {

    using SafeTransferLib for address payable;

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    address public fastlaneAddress;
    address public vaultAddress;

    uint24 internal currentRoundNumber;
    Round internal currentRoundData;
    
    mapping(address => bool) internal validatorsMap;
    mapping(uint24 => mapping(address => uint256)) internal validatorBalanceMap; // map[round][validator] = balance
    mapping(uint24 => Round) internal roundDataMap;
    mapping(address => mapping(address => bool)) internal searcherContractEOAMap;
    mapping(bytes32 => uint256) internal fulfilledAuctionMap;

    bool public paused = false;

    uint24 public fastlaneStakeShare;

    address[] internal participatingValidators;
    address[] internal removedValidators; 

    constructor(address _vaultAddress, uint24 _share) {
        if (_vaultAddress == address(0)) revert RelayWrongInit();
        
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        vaultAddress = _vaultAddress;
        
        setFastlaneStakeShare(_share);

        currentRoundNumber = uint24(1);
        currentRoundData = Round(currentRoundNumber, fastlaneStakeShare, block.number, 0, 0, 0, 0, false);

        emit RelayInitialized(_vaultAddress);
    }
    
    function submitFlashBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution
        bytes32 _oppTxHash, // Target TX
        address _searcherToAddress,
        bytes calldata _toForwardExecData 
        // _toForwardExecData should contain _bidAmount somewhere in the data to be decoded on the receiving searcher contract
        ) external payable nonReentrant whenNotPaused onlyParticipatingValidators {

            if (searcherContractEOAMap[_searcherToAddress][msg.sender]) {
                revert AuctionEOANotEnabled();
            }

            bytes32 auction_key = keccak256(_oppTxHash, abi.encode(tx.gasprice));
            uint256 existing_bid = fulfilledAuctionMap[auction_key];

            if (existing_bid != uint256(0)) {
                if (_bidAmount >= existing_bid) {
                    revert AuctionBidReceivedLate();
                } else {
                    revert AuctionSearcherNotWinner(_bidAmount, existing_bid);
                }
            }

            if (_searcherToAddress == address(0) || _bidAmount == 0) revert RelaySearcherWrongParams();
            
            
            uint256 balanceBefore = vaultAddress.balance;

            (bool success, bytes memory retData) = _searcherToAddress.call{value: msg.value}(abi.encodePacked(_toForwardExecData, msg.sender));
            if (!success) revert RelaySearcherCallFailure(retData);

            uint256 expected = balanceBefore + _bidAmount;
            uint256 balanceAfter = vaultAddress.balance;
            if (balanceAfter < expected) revert RelayNotRepaid(expected - balanceAfter);

            address _validator = block.coinbase;
            validatorBalanceMap[currentRoundNumber][_validator] += _bidAmount;
            fulfilledAuctionMap[auction_key] = _bidAmount;

            emit RelayFlashBid(msg.sender, _bidAmount, _oppTxHash, _validator, _searcherToAddress);
    }

    function authorizeSearcherEOA(
        address _searcherEOA
    ) external {
        // This is designed to be called by searchers' smart contracts
        // therefore msg.sender should be the smart contract. 
        searcherContractEOAMap[msg.sender][_searcherEOA] = true;
    }

    function deauthorizeSearcherEOA(
        address _searcherEOA
    ) external {
        // This is designed to be called by searchers' smart contracts
        // therefore msg.sender will be the smart contract. 
        searcherContractEOAMap[msg.sender][_searcherEOA] = false;
    }


    /// @notice Internal, calculates cuts
    /// @dev validatorCut 
    /// @param _amount Amount to calculates cuts from
    /// @param _share bps
    /// @return validatorCut validator cut
    /// @return stakeCut protocol cut
    function _calculateStakeShare(uint256 _amount, uint24 _share) internal pure returns (uint256 validatorCut, uint256 stakeCut) {
        validatorCut = (_amount * (1000000 - _share)) / 1000000;
        stakeCut = _amount - validatorCut;
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

    function newRound() external onlyOwner {
        uint64 currentBlockNumber = uint64(block.number);
        
        // copy existing struct to then store in map
        Round memory _currentRoundData = currentRoundData;
        _currentRoundData.endBlock = currentBlockNumber;

        roundDataMap[currentRoundNumber] = _currentRoundData;
        currentRoundNumber++;

        currentRoundData = Round(currentRoundNumber, fastlaneStakeShare, currentBlockNumber, 0, 0, 0, 0, false);
        // any changes in 
    }

    function payValidators(uint24 roundNumber) external onlyOwner returns (bool) {
        if (roundNumber >= currentRoundNumber) revert ProcessingRoundNotOver();

        if (roundDataMap[roundNumber].completedPayments) revert ProcessingRoundFullyPaidOut();

        uint24 stakeAllocation = roundDataMap[roundNumber].stakeAllocation;
        uint256 removedValidatorsLength = removedValidators.length;
        uint256 participatingValidatorsLength = participatingValidators.length;
        address validator;
        uint256 grossRevenue;
        uint256 netValidatorRevenue;
        uint256 netStakeRevenue;
        uint256 netStakeRevenueCollected;
        // uint256 newIndex; // is this necessary? Or does n retain the loop's ++'s?

        uint256 n = roundDataMap[roundNumber].paidValidatorIndex;
        
        if (n < removedValidatorsLength) {
            // check removed validators too - they may have been removed partway through a round
            for (n; n < removedValidatorsLength; n++) {
                if (gasleft() < 80_000) {
                    // newIndex = n;
                    break;
                }
                validator = removedValidators[n];
                grossRevenue = validatorBalanceMap[currentRoundNumber][validator];
                if (grossRevenue > 0) {
                    (netValidatorRevenue, netStakeRevenue) = _calculateStakeShare(grossRevenue, stakeAllocation);
                    payable(validator).transfer(netValidatorRevenue);
                    netStakeRevenueCollected += netStakeRevenue;
                }
            }
        }

        if (n < removedValidatorsLength + participatingValidatorsLength && n >= removedValidatorsLength) {
            for (n; n < removedValidatorsLength + participatingValidatorsLength; n++) {
                if (gasleft() < 80_000) {
                    // newIndex = n;
                    break;
                }
                validator = removedValidators[n - removedValidatorsLength];
                grossRevenue = validatorBalanceMap[currentRoundNumber][validator];
                if (grossRevenue > 0) {
                    (netValidatorRevenue, netStakeRevenue) = _calculateStakeShare(grossRevenue, stakeAllocation);
                    payable(validator).transfer(netValidatorRevenue);
                    netStakeRevenueCollected += netStakeRevenue;
                }
            }
        }

        roundDataMap[roundNumber].paidValidatorIndex = n;
        roundDataMap[roundNumber].revenueCollected += netStakeRevenueCollected;
        if (n >= removedValidatorsLength + participatingValidatorsLength - 1) {
            roundDataMap[roundNumber].completedPayments = true;
            return true;
        } else {
            return false;
        }
    }


    /// @notice Sets the stake revenue allocation (out of 1000000 (ie v2 fee decimals))
    /// @dev Initially set to 50000 (5%) For now we can't change the stake revenue allocation
    // during an ongoing auction since the bids do not store the stake allocation value at bidding time
    /// @param _fastlaneStakeShare Protocol stake allocation on bids
    function setFastlaneStakeShare(uint24 _fastlaneStakeShare)
        public
        onlyOwner
    {
        if (_fastlaneStakeShare > 1000000) revert RelayInequalityTooHigh();
        fastlaneStakeShare = _fastlaneStakeShare;
        emit RelayShareSet(_fastlaneStakeShare);
    }
    

    function enableRelayValidatorAddress(address _validator) external onlyOwner {
        if (!validatorsMap[_validator]) {
            // check to see if this validator is being re-added
            bool existing = false;
            uint256 validatorIndex;
            address lastElement = removedValidators[removedValidators.length - 1];
            for (uint256 z=0; z < removedValidators.length; z++) {
                if (removedValidators[z] == _validator) {
                    validatorIndex = z;
                    existing = true;
                    break;
                }
            }
            if (existing) {
                removedValidators[z] = lastElement;
                delete removedValidators[removedValidators.length - 1];
            }
            participatingValidators.push(_validator);
        }
        validatorsMap[_validator] = true;
        emit RelayValidatorEnabled(_validator);
    }

    function disableRelayValidatorAddress(address _validator) external onlyOwner {
        if (validatorsMap[_validator]) {
            bool existing = false;
            uint256 validatorIndex;
            address lastElement = participatingValidators[participatingValidators.length - 1];
            for (uint256 z=0; z < participatingValidators.length; z++) {
                if (participatingValidators[z] == _validator) {
                    validatorIndex = z;
                    existing = true;
                    break;
                }
            }
            if (existing) {
                participatingValidators[z] = lastElement;
                delete participatingValidators[participatingValidators.length - 1];
            }
            removedValidators.push(_validator);
        }
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