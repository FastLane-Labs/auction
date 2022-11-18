//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";


abstract contract FastLaneAuctionHandlerEvents {

    event RelayPausedStateSet(bool state);
    event RelayValidatorEnabled(address validator, address payee);
    event RelayValidatorDisabled(address validator);
    event RelayValidatorPayeeUpdated(address validator, address payee, address indexed initiator);

    event RelayInitialized(uint24 initialStakeShare, uint256 minAmount, bool restrictEOA);

    event RelayShareSet(uint24 amount);
    event RelayShareProposed(uint24 amount, uint256 deadline);
    event RelayMinAmountSet(uint256 minAmount);

    event RelayFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);

    event RelayWithdrawDust(address indexed receiver, uint256 amount);
    event RelayWithdrawStuckERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
    event RelayWithdrawStuckNativeToken(address indexed receiver, uint256 amount);
   

    error RelayInequalityTooHigh();

    error RelayPermissionPaused();
    error RelayPermissionNotFastlaneValidator();
    error RelayPermissionSenderNotOrigin();
    error RelayPermissionUnauthorized();

    error RelayWrongInit();
    error RelaySearcherWrongParams();

    error RelaySearcherCallFailure(bytes retData);
    error RelayNotRepaid(uint256 bidAmount, uint256 actualAmount);

    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);
    event RelayProcessingWithdrewStakeShare(address indexed recipient, uint256 amountWithdrawn);
    error RelayProcessingNoBalancePayable();
    error RelayProcessingAmountExceedsBalance(uint256 amountRequested, uint256 balance);
    
    error RelayAuctionBidReceivedLate();
    error RelayAuctionSearcherNotWinner(uint256 current, uint256 existing);

    error RelayTimeUnsuitable();
    error RelayCannotBeZero();
    error RelayCannotBeSelf();
}

/// @notice Validator Data Struct
/// @dev Subject to BLOCK_TIMELOCK for changes
/// @param payee Who to pay for this validator
/// @param timeUpdated Last time a change was requested for this validator payee
struct ValidatorData {
    address payee;
    uint256 timeUpdated;
}

interface ISearcherContract {
    function fastLaneCall(address, uint256, bytes calldata) external payable returns (bool, bytes memory);
}

contract FastLaneAuctionHandler is FastLaneAuctionHandlerEvents, Ownable, ReentrancyGuard {

    /// @notice Constant delay before the stake share can be changed
    uint32 internal constant BLOCK_TIMELOCK = 6 days;

    /// @notice Constant base fee
    uint24 internal constant FEE_BASE = 1_000_000;




    /// @notice If a validator is active or not
    mapping(address => bool) public validatorsStatusMap;

    /// @notice Mapping to Validator Data Struct
    mapping(address => ValidatorData) internal validatorsDataMap;

    /// @notice Map[validator] = balance
    mapping(address => uint256) public validatorsBalanceMap;

    /// @notice Map key is keccak hash of opp tx's gasprice and tx hash
    mapping(bytes32 => uint256) public fulfilledAuctionsMap;

    uint256 public validatorsTotal;

    uint256 public flStakeSharePayable;
    uint24 public flStakeShareRatio;

    uint24 public proposalStakeShareRatio;
    uint256 public proposalDeadline;

    uint256 public minRelayBidAmount = 1 ether; // 1 Matic

    bool public pendingStakeShareUpdate;
    bool public paused;
    bool public RESTRICT_EOA = true;

    constructor(uint24 _initialStakeShare, uint256 _minRelayBidAmount, bool _restrictEOA) {
        flStakeShareRatio = _initialStakeShare;
        minRelayBidAmount = _minRelayBidAmount;
        RESTRICT_EOA = _restrictEOA; // Cannot change after deploy
        emit RelayInitialized(_initialStakeShare, _minRelayBidAmount, RESTRICT_EOA);
    }


    /// @notice Submits a flash bid
    /// @dev Will revert if:  minimum bid not respected, not from EOA, or current validator is not participating in PFL.
    /// @param _bidAmount Amount committed to be repaid
    /// @param _oppTxHash Target Transaction hash
    /// @param _searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param _searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    function submitFlashBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution
        bytes32 _oppTxHash, // Target TX
        address _searcherToAddress,
        bytes calldata _searcherCallData 
        ) external payable nonReentrant whenNotPaused onlyParticipatingValidators onlyEOA {

            if (_searcherToAddress == address(0) || _bidAmount < minRelayBidAmount) revert RelaySearcherWrongParams();
            
            // Make sure another searcher hasn't already won the opp
            _checkBid(_oppTxHash, _bidAmount);

            // Store the current balance, excluding msg.value
            uint256 balanceBefore = address(this).balance - msg.value;

            // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
            // And forward msg.value
            (bool success, bytes memory retData) = ISearcherContract(_searcherToAddress).fastLaneCall{value: msg.value}(
                        msg.sender,
                        _bidAmount,
                        _searcherCallData
            );

            if (!success) revert RelaySearcherCallFailure(retData);

            // Verify that the searcher paid the amount they bid & emit the event
            _handleBalances(_bidAmount, balanceBefore);
            emit RelayFlashBid(msg.sender, _bidAmount, _oppTxHash, block.coinbase, _searcherToAddress);
    }

    /***********************************|
    |    Internal Bid Helper Functions  |
    |__________________________________*/

    /// @notice Validates incoming bid
    /// @dev 
    /// @param _oppTxHash Target Transaction hash
    /// @param _bidAmount Amount committed to be repaid
    function _checkBid(bytes32 _oppTxHash, uint256 _bidAmount) internal {
        // Use hash of the opportunity tx hash and the transaction's gasprice as key for bid tracking
        // This is dependent on the PFL Relay verifying that the searcher's gasprice matches
        // the opportunity's gasprice, and that the searcher used the correct opportunity tx hash

        bytes32 auction_key = keccak256(abi.encode(_oppTxHash, tx.gasprice));
        uint256 existing_bid = fulfilledAuctionsMap[auction_key];

        if (existing_bid != 0) {
            if (_bidAmount >= existing_bid) {
                // This error message could also arise if the tx was sent via mempool
                revert RelayAuctionBidReceivedLate();
            } else {
                revert RelayAuctionSearcherNotWinner(_bidAmount, existing_bid);
            }
        }

        // Mark this auction as being complete to provide quicker reverts for subsequent searchers
        fulfilledAuctionsMap[auction_key] = _bidAmount;
    }

    function _handleBalances(uint256 _bidAmount, uint256 balanceBefore) internal {
        if (address(this).balance < balanceBefore + _bidAmount) {
            revert RelayNotRepaid(_bidAmount, address(this).balance - balanceBefore);
        }

        (uint256 amtPayableToValidator, uint256 amtPayableToStakers) = _calculateStakeShare(_bidAmount, flStakeShareRatio);

        validatorsBalanceMap[block.coinbase] += amtPayableToValidator;
        validatorsTotal += amtPayableToValidator;
        flStakeSharePayable += amtPayableToStakers;
    }


    /// @notice Internal, calculates shares
    /// @param _amount Amount to calculates cuts from
    /// @param _share Share bps
    /// @return validatorCut Validator cut
    /// @return stakeCut Stake cut
    function _calculateStakeShare(uint256 _amount, uint24 _share) internal pure returns (uint256 validatorCut, uint256 stakeCut) {
        validatorCut = (_amount * (FEE_BASE - _share)) / FEE_BASE;
        stakeCut = _amount - validatorCut;
    }

    receive() external payable {}
    fallback() external payable {}


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

    /// @notice Defines the minimum bid
    /// @dev Only owner
    /// @param _minAmount New minimum amount
    function setMininumBidAmount(uint256 _minAmount) external onlyOwner {
        minRelayBidAmount = _minAmount;
        emit RelayMinAmountSet(_minAmount);
    }

    /// @notice Sets the stake revenue allocation (out of 1_000_000 (ie v2 fee decimals))
    /// @dev Initially set to 50_000 (5%), and pending for 6 days before a change
    /// @param _fastLaneStakeShare Protocol stake allocation on bids
    function setFastLaneStakeShare(uint24 _fastLaneStakeShare) public onlyOwner {
        if (pendingStakeShareUpdate) revert RelayTimeUnsuitable();
        if (_fastLaneStakeShare > FEE_BASE) revert RelayInequalityTooHigh();
        proposalStakeShareRatio = _fastLaneStakeShare;
        proposalDeadline = block.timestamp + BLOCK_TIMELOCK;
        pendingStakeShareUpdate = true;
        emit RelayShareProposed(_fastLaneStakeShare, proposalDeadline);
    }

    /// @notice Withdraws fl stake share
    /// @dev Owner only
    /// @param _recipient Recipient
    /// @param _amount Amount
    function withdrawStakeShare(address _recipient, uint256 _amount) external onlyOwner nonReentrant {
        if (_recipient == address(0) || _amount == 0) revert RelayCannotBeZero();
        flStakeSharePayable -= _amount;
        SafeTransferLib.safeTransferETH(
            _recipient, 
            _amount
        );
        emit RelayProcessingWithdrewStakeShare(_recipient, _amount);
    }
    

    /// @notice Enables an address as participating validator, and defining a payee for it
    /// @dev Owner only
    /// @param _validator Validator address that will be the coinbase of bids
    /// @param _payee Address that can withdraw for that validator
    function enableRelayValidator(address _validator, address _payee) external onlyOwner {
        if (_validator == address(0) || _payee == address(0)) revert RelayCannotBeZero();
        if (_payee == address(this)) revert RelayCannotBeSelf();
        validatorsStatusMap[_validator] = true;
        validatorsDataMap[_validator] = ValidatorData(_payee, block.timestamp);
        emit RelayValidatorEnabled(_validator, _payee);
    }

    /// @notice Disabled an address as participating validator
    /// @dev Owner only
    /// @param _validator Validator address
    function disableRelayValidator(address _validator) external onlyOwner {
        if (_validator == address(0)) revert RelayCannotBeZero();
        validatorsStatusMap[_validator] = false;
        emit RelayValidatorDisabled(_validator);
    }

    /// @notice Recover bids repaid to the relay over bidAmount
    /// @dev Owner only, can never tap into validator balances nor flStake.
    /// @param _amount amount desired, capped to max
    function recoverDust(uint256 _amount) 
        external
        onlyOwner
        nonReentrant
    {
        uint256 maxDust = address(this).balance - validatorsTotal - flStakeSharePayable;
        if (_amount > maxDust) _amount = maxDust;
        SafeTransferLib.safeTransferETH(owner(), _amount);
        emit RelayWithdrawDust(owner(), _amount);
    }

    /// @notice Withdraws stuck matic
    /// @dev In the event something went really wrong / vuln report
    /// @dev When out of beta role will be moved to gnosis multisig for added safety
    /// @param _amount Amount to send to owner
    function withdrawStuckNativeToken(uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        if (address(this).balance >= _amount) {
            SafeTransferLib.safeTransferETH(owner(), _amount);
            emit RelayWithdrawStuckNativeToken(owner(), _amount);
        }
    }

    /// @notice Withdraws stuck ERC20
    /// @dev In the event people send ERC20 instead of Matic we can send them back 
    /// @param _tokenAddress Address of the stuck token
    function withdrawStuckERC20(address _tokenAddress)
        external
        onlyOwner
        nonReentrant
    {
        ERC20 oopsToken = ERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            SafeTransferLib.safeTransferFrom(oopsToken, address(this), owner(), oopsTokenBalance);
            emit RelayWithdrawStuckERC20(address(this), owner(), oopsTokenBalance);
        }
    }

    /***********************************|
    |          Validator Functions      |
    |__________________________________*/

    /// @notice Pays the validator their outstanding balance
    /// @dev Callable by either validator address, their payee address (if not changed recently), or PFL.
    /// @param _validator Validator address
    function payValidator(address _validator) external whenNotPaused nonReentrant onlyValidatorProxy(_validator) returns (uint256) {        
        uint256 payableBalance = validatorsBalanceMap[_validator];
        if (payableBalance > 0) {
            validatorsTotal -= validatorsBalanceMap[_validator];
            validatorsBalanceMap[_validator] = 0;
            SafeTransferLib.safeTransferETH(
                _validatorPayee(_validator), 
                payableBalance
            );
            emit RelayProcessingPaidValidator(_validator, payableBalance, msg.sender);
        }
        return payableBalance;
    }

    /// @notice Updates a validator payee
    /// @dev Callable by either validator address, their payee address (if not changed recently), or PFL.
    /// @param _validator Validator address
    function updateValidatorPayee(address _validator, address _payee) external onlyValidatorProxy(_validator) nonReentrant {
        if (_payee == address(0)) revert RelayCannotBeZero();
        if (_payee == address(this)) revert RelayCannotBeSelf();
        if (!validatorsStatusMap[_validator]) revert RelayPermissionNotFastlaneValidator();
        validatorsDataMap[_validator].payee = _payee;
        validatorsDataMap[_validator].timeUpdated = block.timestamp;

        emit RelayValidatorPayeeUpdated(_validator, _payee, msg.sender);   
    }

    function _isPayeeNotTimeLocked(address _validator) internal view returns (bool _valid) {
        _valid = block.timestamp > validatorsDataMap[_validator].timeUpdated + BLOCK_TIMELOCK;
    }

    function _isValidPayee(address _validator, address _payee) internal view returns (bool _valid) {
        _valid = _isPayeeNotTimeLocked(_validator) && _payee == validatorsDataMap[_validator].payee;
    }

    function _validatorPayee(address _validator) internal view returns (address _recipient) {
        _recipient = _isPayeeNotTimeLocked(_validator) ? validatorsDataMap[_validator].payee : _validator;
    }

    /***********************************|
    |             Public                |
    |__________________________________*/

    /// @notice Activates a pending stake share update
    /// @dev Anyone can call it after a 6 days delay
    function triggerPendingStakeShareUpdate() external nonReentrant {
        if (!pendingStakeShareUpdate || block.timestamp < proposalDeadline) revert RelayTimeUnsuitable();
        flStakeShareRatio = proposalStakeShareRatio;
        pendingStakeShareUpdate = false;
        emit RelayShareSet(proposalStakeShareRatio);
    }

    /// @notice Returns validator pending balance
    function getValidatorBalance(address _validator) public view returns (uint256 _validatorBalance) {
        _validatorBalance = validatorsBalanceMap[_validator];
    }

    /// @notice Returns the listed payee address regardless of whether or not it has passed the time lock.
    function getValidatorPayee(address _validator) public view returns (address _payee) {
        _payee = validatorsDataMap[_validator].payee;
    }

    /// @notice For validators to determine where their payments will go
    /// @dev Will return the Payee if blockTimeLock has passed, will return Validator if not.
    /// @param _validator Address
    function getValidatorRecipient(address _validator) public view returns (address _recipient) {
        _recipient = _validatorPayee(_validator);
    }

    function getCurrentStakeRatio() public view returns (uint24) {
        return flStakeShareRatio;
    }

    function getCurrentStakeBalance() public view returns (uint256) {
       return flStakeSharePayable;
    }

    function getPendingStakeRatio() public view returns (uint24 _fastLaneStakeShare) {
        _fastLaneStakeShare = pendingStakeShareUpdate ? proposalStakeShareRatio : flStakeShareRatio;
    }

    function getPendingDeadline() public view returns (uint256 _timeDeadline) {
        _timeDeadline = pendingStakeShareUpdate ? proposalDeadline : block.timestamp;
    }

    function getValidatorStatus(address _validator) public view returns (bool) {
        return validatorsStatusMap[_validator];
    }

    function humanizeError(bytes memory _errorData) public pure returns (string memory decoded) {
        uint256 len = _errorData.length;
        bytes memory firstPass = abi.decode(slice(_errorData, 4, len-4), (bytes));
        decoded = abi.decode(slice(firstPass, 4, firstPass.length-4), (string));
    }

    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    )
        internal
        pure
        returns (bytes memory)
    {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    modifier whenNotPaused() {
        if (paused) revert RelayPermissionPaused();
        _;
    }

    modifier onlyEOA() {
        if (RESTRICT_EOA && msg.sender != tx.origin) revert RelayPermissionSenderNotOrigin();
        _;
    }

    modifier onlyParticipatingValidators() {
        if (!validatorsStatusMap[block.coinbase]) revert RelayPermissionNotFastlaneValidator();
        _;
    }

    modifier onlyValidatorProxy(address _validator) {
        if (msg.sender != _validator && msg.sender != owner() && !_isValidPayee(_validator, msg.sender)) revert RelayPermissionUnauthorized();
        _;
    }
}