//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

struct Round {
    uint24 roundNumber;
    uint24 stakeAllocation;
    uint64 startBlock;
    uint64 endBlock;
    uint24 nextValidatorIndex;
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

    event ProcessingPaidValidator(address validator, uint256 validatorPayment);
    event ProcessingWithdrewStakeShare(address recipient, uint256 amountWithdrawn);

    error RelayInequalityTooHigh();

    error RelayPermissionPaused();
    error RelayPermissionNotFastlaneValidator();

    error RelayWrongInit();
    error RelayWrongSpecifiedValidator();
    error RelaySearcherWrongParams();

    error RelaySearcherCallFailure(bytes retData);
    error RelayNotRepaid(uint256 missingAmount);

    error AuctionEOANotEnabled();
    error AuctionCallerMustBeSender();
    error AuctionValidatorNotParticipating(address validator);
    error AuctionSearcherNotWinner(uint256 searcherBid, uint256 winningBid);
    error AuctionBidReceivedLate();

    error ProcessingRoundNotOver();
    error ProcessingRoundFullyPaidOut();
    error ProcessingInProgress();
    error ProcessingNoBalancePayable();
    error ProcessingAmountExceedsBalance(uint256 amountRequested, uint256 balance);
}

contract FastLaneRelay is FastLaneRelayEvents, Ownable, ReentrancyGuard {

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    uint24 internal currentRoundNumber;
    uint24 internal lastRoundProcessed;
    uint24 public fastlaneStakeShare;

    uint256 internal stakeSharePayable;

    bool public paused = false;
    bool internal isProcessingPayments = false;

    mapping(address => bool) internal validatorsMap;
    mapping(uint24 => mapping(address => uint256)) internal validatorBalanceMap; // map[round][validator] = balance
    mapping(address => uint256) internal validatorBalancePayableMap;
    mapping(uint24 => Round) internal roundDataMap;
    mapping(address => mapping(address => bool)) internal searcherContractEOAMap;
    mapping(bytes32 => uint256) internal fulfilledAuctionMap;

    address[] internal participatingValidators;
    address[] internal removedValidators; 

    constructor() {
        if (address(this) == address(0)) revert RelayWrongInit();
        
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        uint24 _share = 5_000;
        
        setFastlaneStakeShare(_share);

        currentRoundNumber = uint24(1);
        roundDataMap[currentRoundNumber] = Round(currentRoundNumber, fastlaneStakeShare, uint64(block.number), 0, 0, false);

        emit RelayInitialized(address(this));
    }
    
    function submitFastLaneBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution
        bytes32 _oppTxHash, // Target TX
        address _searcherToAddress,
        bytes calldata _toForwardExecData 
        // _toForwardExecData should contain _bidAmount somewhere in the data to be decoded on the receiving searcher contract
        ) external payable nonReentrant whenNotPaused onlyParticipatingValidators senderIsOrigin {

            bytes32 auction_key = keccak256(abi.encode(_oppTxHash, tx.gasprice));
            // NOTE: using abi.encodePacked may make this spoofable by clever antagonists 
            // who shift decimals in certain (rare) scenarios

            uint256 existing_bid = fulfilledAuctionMap[auction_key];

            if (existing_bid != 0) {
                if (_bidAmount >= existing_bid) {
                    revert AuctionBidReceivedLate();
                } else {
                    revert AuctionSearcherNotWinner(_bidAmount, existing_bid);
                }
            }

            if (!searcherContractEOAMap[_searcherToAddress][msg.sender]) {
                revert AuctionEOANotEnabled();
            }

            if (_searcherToAddress == address(0) || _bidAmount == 0) revert RelaySearcherWrongParams();
            
            uint256 balanceBefore = address(this).balance;

            (bool success, bytes memory retData) = _searcherToAddress.call{value: msg.value}(abi.encodePacked(_toForwardExecData, msg.sender));
            if (!success) revert RelaySearcherCallFailure(retData);

            uint256 expected = balanceBefore + _bidAmount;
            uint256 balanceAfter = address(this).balance;
            if (balanceAfter < expected) revert RelayNotRepaid(expected - balanceAfter);

            validatorBalanceMap[currentRoundNumber][block.coinbase] += _bidAmount;
            fulfilledAuctionMap[auction_key] = _bidAmount;

            emit RelayFlashBid(msg.sender, _bidAmount, _oppTxHash, block.coinbase, _searcherToAddress);
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

    function newRound() external onlyOwner whenNotPaused {
        uint64 currentBlockNumber = uint64(block.number);
        
        roundDataMap[currentRoundNumber].endBlock = currentBlockNumber;
        currentRoundNumber++;

        roundDataMap[currentRoundNumber] = Round(currentRoundNumber, fastlaneStakeShare, currentBlockNumber, 0, 0, false);
    }

    function processValidatorsBalances() external whenNotPaused senderIsOrigin returns (bool) {
        // can be called by anyone
        // process rounds sequentially
        uint24 roundNumber = lastRoundProcessed + 1;

        if (roundNumber >= currentRoundNumber) revert ProcessingRoundNotOver();

        if (roundDataMap[roundNumber].completedPayments) revert ProcessingRoundFullyPaidOut();

        isProcessingPayments = true;

        uint24 stakeAllocation = roundDataMap[roundNumber].stakeAllocation;
        uint256 removedValidatorsLength = removedValidators.length;
        uint256 participatingValidatorsLength = participatingValidators.length;
        address validator;
        uint256 grossRevenue;
        uint256 netValidatorRevenue;
        uint256 netStakeRevenue;
        uint256 netStakeRevenueCollected;
        bool completedLoop = true;

        uint256 n = uint256(roundDataMap[roundNumber].nextValidatorIndex);
        
        if (n < removedValidatorsLength) {
            // check removed validators too - they may have been removed partway through a round
            for (n; n < removedValidatorsLength; n++) {
                if (gasleft() < 80_000) {
                    completedLoop = false;
                    break;
                }
                validator = removedValidators[n];
                grossRevenue = validatorBalanceMap[currentRoundNumber][validator];
                if (grossRevenue > 0) {
                    (netValidatorRevenue, netStakeRevenue) = _calculateStakeShare(grossRevenue, stakeAllocation);
                    validatorBalancePayableMap[validator] += netValidatorRevenue;
                    netStakeRevenueCollected += netStakeRevenue;
                }
            }
        }

        if (n < removedValidatorsLength + participatingValidatorsLength && n >= removedValidatorsLength) {
            for (n; n < removedValidatorsLength + participatingValidatorsLength; n++) {
                if (gasleft() < 80_000) {
                    completedLoop = false;
                    break;
                }
                validator = participatingValidators[n - removedValidatorsLength];
                grossRevenue = validatorBalanceMap[currentRoundNumber][validator];
                if (grossRevenue > 0) {
                    (netValidatorRevenue, netStakeRevenue) = _calculateStakeShare(grossRevenue, stakeAllocation);
                    validatorBalancePayableMap[validator] += netValidatorRevenue;
                    netStakeRevenueCollected += netStakeRevenue;
                }
            }
        }

        if (completedLoop) n += 1; // makes sure we didn't run out of gas on final validator in list
        
        roundDataMap[roundNumber].nextValidatorIndex = uint24(n);
        stakeSharePayable += netStakeRevenueCollected;

        if (n > removedValidatorsLength + participatingValidatorsLength) {
            // TODO: check if n keeps the final ++ increment that pushes it out of range of for loop
            roundDataMap[roundNumber].completedPayments = true;
            lastRoundProcessed = roundNumber;
            isProcessingPayments = false;
            return true;
        } else {
            return false;
        }
    }

    function getValidatorBalance(address validator) public view returns (uint256, uint256) {
        // returns balancePayable, balancePending
        if (isProcessingPayments) revert ProcessingInProgress();
        uint256 balancePending; 
        uint256 netValidatorRevenue;
        for (uint24 _roundNumber = lastRoundProcessed + 1; _roundNumber <= currentRoundNumber; _roundNumber++) {
            (netValidatorRevenue,) = _calculateStakeShare(validatorBalanceMap[_roundNumber][validator], roundDataMap[_roundNumber].stakeAllocation);
            balancePending += netValidatorRevenue;
        }
        return (validatorBalancePayableMap[validator], balancePending);
    }

    function payValidator(address validator) public whenNotPaused senderIsOrigin returns (uint256) {
        if (validatorBalancePayableMap[validator] == 0) revert ProcessingNoBalancePayable();
        if (isProcessingPayments) revert ProcessingInProgress();
        uint256 payableBalance = validatorBalancePayableMap[validator];
        validatorBalancePayableMap[validator] = 0;
        payable(validator).transfer(payableBalance);
        emit ProcessingPaidValidator(validator, payableBalance);
        return payableBalance;
    }

    function withdrawStakeShare(address recipient, uint256 amount) external onlyOwner {
        // TODO: Add limitations around recipient & amount (integrate DAO controls / voting results)
        if (amount > stakeSharePayable) revert ProcessingAmountExceedsBalance(amount, stakeSharePayable);
        stakeSharePayable -= amount;
        payable(recipient).transfer(amount);
        emit ProcessingWithdrewStakeShare(recipient, amount);
    }

    /// @notice Sets the stake revenue allocation (out of 1_000_000 (ie v2 fee decimals))
    /// @dev Initially set to 50_000 (5%) 
    /// Can't change the stake revenue allocation mid round - all changes go into effect in next round
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
                removedValidators[validatorIndex] = lastElement;
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
                participatingValidators[validatorIndex] = lastElement;
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

    modifier senderIsOrigin() {
        if (msg.sender != tx.origin) revert AuctionCallerMustBeSender();
        _;
    }

    modifier onlyParticipatingValidators() {
        if (!validatorsMap[block.coinbase]) revert RelayPermissionNotFastlaneValidator();
        _;
    }
}

