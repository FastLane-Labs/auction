//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { IPaymentProcessor } from "../interfaces/IPaymentProcessor.sol";


abstract contract FastLaneAuctionHandlerEvents {

    event RelayValidatorPayeeUpdated(address validator, address payee, address indexed initiator);

    event RelayFlashBid(address indexed sender, bytes32 indexed oppTxHash, address indexed validator, uint256 bidAmount, uint256 amountPaid, address searcherContractAddress);
    event RelayFlashBidWithRefund(address indexed sender, bytes32 indexed oppTxHash, address indexed validator, uint256 bidAmount, uint256 amountPaid, address searcherContractAddress, uint256 refundedAmount, address refundAddress);
    event RelayFastBid(address indexed sender, address indexed validator, bool success, uint256 bidAmount, address searcherContractAddress);
    event RelaySimulatedFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);

    event RelayWithdrawStuckERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
    event RelayWithdrawStuckNativeToken(address indexed receiver, uint256 amount);
    
    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);

    event RelayFeeCollected(address indexed payor, address indexed payee, uint256 amount);

    event CustomPaymentProcessorPaid(address indexed payor, address indexed payee, address indexed paymentProcessor, uint256 totalAmount, uint256 startBlock, uint256 endBlock);

    // NOTE: Investigated Validators should be presumed innocent.  This event can be triggered inadvertently by honest validators
    // while building a block due to transaction nonces taking precedence over gasPrice.
    event RelayInvestigateOutcome(address indexed validator, address indexed sender, uint256 blockNumber, uint256 existingBidAmount, uint256 newBidAmount, uint256 existingGasPrice, uint256 newGasPrice);

    error RelayPermissionSenderNotOrigin();                                 // 0x5c8a268a

    error RelaySearcherWrongParams();                                       // 0x31ae2a9d

    // error RelaySearcherCallFailure(bytes retData);                       // 0x291bc14c /!\ Deprecated in favor of bubbling up
    error RelayValueIsZero();                                               // 0x7da21207
    // error RelaySimulatedSearcherCallFailure(bytes retData);              // 0x5be08ca5 /!\ Deprecated in favor of bubbling up
    error RelayNotRepaid(uint256 bidAmount, uint256 actualAmount);          // 0x53dc88d9
    error RelaySimulatedNotRepaid(uint256 bidAmount, uint256 actualAmount); // 0xd47ae88a

    error RelayAuctionInvalidBid();                                         // 0xa51c0e05
    error RelayAuctionBidReceivedLate();                                    // 0xb61e767e
    error RelayAuctionSearcherNotWinner(uint256 current, uint256 existing); // 0x5db6f7d9

    error RelayCannotBeZero();                                              // 0x3c9cfe50
    error RelayCannotBeSelf();                                              // 0x6a64f641
    error RelayMustBeSelf();                                                // 0x3ee08eb4

    error RelayValidatorNotAcceptingRefundBids();                           // 0x8b2dbdac
    error RelayProcessorCannotBeZero();                                     // 0x779f4778
    error RelayNotActiveValidator();                                        // 0x68a251a0
    error RelayPayeeIsTimelocked();                                         // 0x9ec568f3
    error RelayInvalidSender();                                             // 0x3e82c9f4
    error RelayImmutableBlockAuthorRate();                                  // 0xe9271574

    error RelayPayeeUpdateInvalid();                                        // 0x561d7b2d
    error RelayCustomCallbackLockInvalid();
    error RelayCustomPayoutCantBePartial();

    error RelayUnapprovedReentrancy();

}

/// @notice Validator Data Struct
/// @dev Subject to BLOCK_TIMELOCK for changes
/// @param payee Who to pay for this validator
/// @param timeUpdated Last time a change was requested for this validator payee
/// @param blockOfLastWithdrawal Last time a withdrawal was initiated
struct ValidatorData {
    address payee;
    uint64 blockOfLastWithdraw;
    uint256 timeUpdated;
}

struct PGAData {
    uint64 lowestGasPrice;
    uint64 lowestFastPrice;
    uint64 lowestTotalPrice;
}

interface ISearcherContract {
    function fastLaneCall(address, uint256, bytes calldata) external payable returns (bool, bytes memory);
}

contract FastLaneAuctionHandler is FastLaneAuctionHandlerEvents {

    /// @notice Constant delay before the stake share can be changed
    uint32 internal constant BLOCK_TIMELOCK = 6 days;

    uint256 internal constant MIN_GAS_SPENT_PGA = 100_000;

    /// @notice The scale for validator refund share
    uint256 internal constant VALIDATOR_REFUND_SCALE = 10_000; // 1 = 0.01%

    /// @notice Mapping to Validator Data Struct
    mapping(address => ValidatorData) internal validatorsDataMap;

    /// @notice Mapping payee address to validator address
    mapping(address => address) public payeeMap;

    /// @notice Map[validator] = balance
    mapping(address => uint256) public validatorsBalanceMap;

    /// @notice Map key is keccak hash of opp tx's gasprice and tx hash
    mapping(bytes32 => uint256) public fulfilledAuctionsMap;

    /// @notice Map key is block.number
    mapping(uint256 => PGAData) public fulfilledPGAMap;

    /// @notice Map[validator] = % payment to validator in a bid with refund
    mapping(address => uint256) public validatorsRefundShareMap;

    uint256 public validatorsTotal;

    bytes32 private constant UNLOCKED = bytes32(uint256(1));
    bytes32 private constant LOCKED = bytes32(uint256(2));

    bytes32 private lock = UNLOCKED;

    /// @notice Submits a flash bid
    /// @dev Will revert if: already won, minimum bid not respected, or not from EOA
    /// @param bidAmount Amount committed to be repaid
    /// @param oppTxHash Target Transaction hash
    /// @param searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    function submitFlashBid(
        uint256 bidAmount, // Value commited to be repaid at the end of execution
        bytes32 oppTxHash, // Target TX
        address searcherToAddress,
        bytes calldata searcherCallData 
    ) external payable checkBid(oppTxHash, bidAmount) onlyEOA nonReentrant {

            if (searcherToAddress == address(0)) revert RelaySearcherWrongParams();
            
            // Store the current balance, excluding msg.value
            uint256 balanceBefore = address(this).balance - msg.value;

            {
            // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
            // And forward msg.value
            (bool success, bytes memory retData) = ISearcherContract(searcherToAddress).fastLaneCall{value: msg.value}(
                        msg.sender,
                        bidAmount,
                        searcherCallData
            );

            if (!success) {
                    assembly {
                        revert(
                            // Start of revert data bytes. The 0x20 offset is always the same.
                            add(retData, 0x20),
                            // Length of revert data.
                            mload(retData)
                        )
                    }
                }
            }

            // Verify that the searcher paid the amount they bid & emit the event
            uint256 amountPaid = _handleBalances(bidAmount, balanceBefore);

            emit RelayFlashBid(msg.sender, oppTxHash, block.coinbase, bidAmount, amountPaid, searcherToAddress);
    }

    /// @notice Submits a flash bid which refunds a portion of payment to `refundAddress`
    /// @dev Will revert if: already won, minimum bid not respected, or not from EOA
    /// @param bidAmount Amount committed to be repaid
    /// @param oppTxHash Target Transaction hash
    /// @param searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param searcherCallData callData to be passed to `searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    /// @param refundAddress The address that will receive the refund
    function submitFlashBidWithRefund(
        uint256 bidAmount, // Value commited to be repaid at the end of execution
        bytes32 oppTxHash, // Target TX
        address refundAddress,
        address searcherToAddress,
        bytes memory searcherCallData
    ) external payable checkBid(oppTxHash, bidAmount) onlyEOA nonReentrant {
            
            if (searcherToAddress == address(0)) revert RelaySearcherWrongParams();
            if (validatorsRefundShareMap[block.coinbase] > VALIDATOR_REFUND_SCALE) revert RelayValidatorNotAcceptingRefundBids();

            // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
            // And forward msg.value
            // Store the current balance, excluding msg.value
            uint256 balanceBefore = address(this).balance - msg.value;

            {
            (bool success, bytes memory retData) = ISearcherContract(searcherToAddress).fastLaneCall{value: msg.value}(
                        msg.sender,
                        bidAmount,
                        searcherCallData
            );
            if (!success) {
                    assembly {
                        revert(
                            // Start of revert data bytes. The 0x20 offset is always the same.
                            add(retData, 0x20),
                            // Length of revert data.
                            mload(retData)
                        )
                    }
                }
            }

            // Verify that the searcher paid the amount they bid & emit the event
            _handleBalancesWithRefundAndEmit(bidAmount, balanceBefore, refundAddress, oppTxHash, searcherToAddress);
    }

    /// @notice Submits a fast bid
    /// @dev Will not revert
    /// @param fastGasPrice Bonus gasPrice rate that Searcher commits to pay to validator for gas used by searcher's call
    /// @param searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(fastPrice,msg.sender,callData)`
    function submitFastBid(
        uint256 fastGasPrice, // Value commited to be paid at the end of execution
        address searcherToAddress,
        bytes calldata searcherCallData 
    ) external payable checkPGA(fastGasPrice) onlyEOA nonReentrant {

        if (searcherToAddress == address(this) || searcherToAddress == msg.sender) revert RelaySearcherWrongParams();

        // Use a try/catch pattern so that tx.gasprice and bidAmount can be saved to verify that
        // proper transaction ordering is being followed. 
        try this.fastBidWrapper{value: msg.value}(
            msg.sender, fastGasPrice, searcherToAddress, searcherCallData
        ) returns (uint256 bidAmount) {
            emit RelayFastBid(msg.sender, block.coinbase, true, bidAmount, searcherToAddress);
        } catch {
            emit RelayFastBid(msg.sender, block.coinbase, false, 0, searcherToAddress);
        }
    }

    function fastBidWrapper(
        address msgSender,
        uint256 fastPrice, // Value commited to be paid at the end of execution
        address searcherToAddress,
        bytes calldata searcherCallData 
    ) external payable returns (uint256) {

        // This is meant to be called inside of a try/catch by address(this)
        if (msg.sender != address(this)) revert RelayMustBeSelf();

        // Store the current balance, excluding msg.value, and store the gas left
        uint256 balanceBefore = address(this).balance - msg.value;
        uint256 gasSpent = gasleft();

        {
        // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
        // And forward msg.value
        (bool success, bytes memory retData) = ISearcherContract(searcherToAddress).fastLaneCall{value: msg.value}(
                    msgSender,
                    fastPrice,
                    searcherCallData
        );

        if (!success) {
                    assembly {
                        revert(
                            // Start of revert data bytes. The 0x20 offset is always the same.
                            add(retData, 0x20),
                            // Length of revert data.
                            mload(retData)
                        )
                    }
                }
        }

        // Calculate how much gas was spent by searcher
        gasSpent -= gasleft();

        // Multiply the fastBidAmount (a rate) by the gas spent to get the total amount
        uint256 bidAmount = fastPrice * (gasSpent < MIN_GAS_SPENT_PGA ? MIN_GAS_SPENT_PGA : gasSpent);
        
        return _handleBalancesFast(bidAmount, balanceBefore, searcherToAddress);
    }

    function payValidatorFee(address _payor) external payable nonReentrant {
        if (msg.value == 0) revert RelayValueIsZero();
        validatorsBalanceMap[block.coinbase] += msg.value;
        validatorsTotal += msg.value;
        emit RelayFeeCollected(_payor, block.coinbase, msg.value);
    }

    /// @notice Submits a SIMULATED flash bid. THE HTTP RELAY won't accept calls for this function.
    /// @notice This is just a convenience function for you to test by simulating a call to simulateFlashBid 
    /// @notice To ensure your calldata correctly works when relayed to `_searcherToAddress`.fastLaneCall(_searcherCallData)
    /// @dev This does NOT check that current coinbase is participating in PFL.
    /// @dev Only use for testing _searcherCallData
    /// @dev You can submit any _bidAmount you like for testing
    /// @param bidAmount Amount committed to be repaid
    /// @param oppTxHash Target Transaction hash
    /// @param searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    function simulateFlashBid(
        uint256 bidAmount, // Value commited to be repaid at the end of execution, can be set very low in simulated
        bytes32 oppTxHash, // Target TX
        address searcherToAddress,
        bytes calldata searcherCallData 
        ) external payable nonReentrant onlyEOA {

            // Relax check on min bid amount for simulated
            if (searcherToAddress == address(0)) revert RelaySearcherWrongParams();
            
            // Store the current balance, excluding msg.value
            uint256 balanceBefore = address(this).balance - msg.value;

            // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
            // And forward msg.value
            (bool success, bytes memory retData) = ISearcherContract(searcherToAddress).fastLaneCall{value: msg.value}(
                        msg.sender,
                        bidAmount,
                        searcherCallData
            );

            if (!success) {
                    assembly {
                        revert(
                            // Start of revert data bytes. The 0x20 offset is always the same.
                            add(retData, 0x20),
                            // Length of revert data.
                            mload(retData)
                        )
                    }
                }

            // Verify that the searcher paid the amount they bid & emit the event
            if (address(this).balance < balanceBefore + bidAmount) {
                revert RelaySimulatedNotRepaid(bidAmount, address(this).balance - balanceBefore);
            }
            emit RelaySimulatedFlashBid(msg.sender, bidAmount, oppTxHash, block.coinbase, searcherToAddress);
    }

    /***********************************|
    |    Internal Bid Helper Functions  |
    |__________________________________*/

    function _handleBalances(uint256 _bidAmount, uint256 balanceBefore) internal returns (uint256) {
        if (address(this).balance < balanceBefore + _bidAmount) {
            revert RelayNotRepaid(_bidAmount, address(this).balance - balanceBefore);
        }

        if (address(this).balance - balanceBefore > _bidAmount) {
            _bidAmount = address(this).balance - balanceBefore;
        }

        validatorsBalanceMap[block.coinbase] += _bidAmount;
        validatorsTotal += _bidAmount;

        return _bidAmount;
    }

    function _handleBalancesFast(uint256 _bidAmount, uint256 balanceBefore, address _searcherToAddress) internal returns (uint256) {
        // Verify that the searcher paid the amount they bid & emit the event
        if (address(this).balance - balanceBefore < _bidAmount) {
            revert RelayNotRepaid(_bidAmount, address(this).balance - balanceBefore);
        }

        // Check if searcher overpaid and, if so, initiate a refund
        uint256 surplus = (address(this).balance - balanceBefore) - _bidAmount;
        if (surplus > 0) {

            // If value came from the EOA, refund to EOA
            if (msg.value > _bidAmount) {
                SafeTransferLib.safeTransferETH(
                    tx.origin, 
                    surplus
                );

            // Otherwise refund the searcher contract
            } else {
                SafeTransferLib.safeTransferETH(
                    _searcherToAddress, 
                    surplus
                );
            }
        }

        validatorsBalanceMap[block.coinbase] += _bidAmount;
        validatorsTotal += _bidAmount;
        
        return _bidAmount;
    }

    /// Verifies the searcher paid for the bid and handles a refund to specified address
    function _handleBalancesWithRefundAndEmit(
        uint256 bidAmount,
        uint256 balanceBefore,
        address refundAddress,
        bytes32 oppTxHash,
        address searcherContract
    ) internal {
        uint256 originalBidAmount = bidAmount;

        if (address(this).balance < balanceBefore + bidAmount) {
            revert RelayNotRepaid(bidAmount, address(this).balance - balanceBefore);
        }

        if (address(this).balance - balanceBefore > bidAmount) {
            bidAmount = address(this).balance - balanceBefore;
        }

        // Calculate the split of payment
        uint256 validatorShare = (validatorsRefundShareMap[block.coinbase] * bidAmount) / VALIDATOR_REFUND_SCALE;
        uint256 refundAmount = bidAmount - validatorShare; // subtract to ensure no overflow

        // Update balance and make payment
        validatorsBalanceMap[block.coinbase] += validatorShare;
        validatorsTotal += validatorShare;
        payable(refundAddress).transfer(refundAmount);

        emit RelayFlashBidWithRefund(msg.sender, oppTxHash, block.coinbase, originalBidAmount, bidAmount, searcherContract, refundAmount, refundAddress);
    }

    receive() external payable {}

    fallback() external payable {}


    /***********************************|
    |             Maintenance           |
    |__________________________________*/

    /// @notice Syncs stuck matic to calling validator
    /// @dev In the event something went really wrong / vuln report
    function syncStuckNativeToken()
        external
        onlyActiveValidators
        nonReentrant
    {
        uint256 _expectedBalance = validatorsTotal;
        uint256 _currentBalance = address(this).balance;
        if (_currentBalance >= _expectedBalance) {

            address _validator = getValidator();

            uint256 _surplus = _currentBalance - _expectedBalance;

            validatorsBalanceMap[_validator] += _surplus;
            validatorsTotal += _surplus;

            emit RelayWithdrawStuckNativeToken(_validator, _surplus);
        }
    }

    /// @notice Withdraws stuck ERC20
    /// @dev In the event people send ERC20 instead of Matic we can send them back 
    /// @param _tokenAddress Address of the stuck token
    function withdrawStuckERC20(address _tokenAddress)
        external
        onlyActiveValidators
        nonReentrant
    {
        ERC20 oopsToken = ERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            SafeTransferLib.safeTransfer(oopsToken, msg.sender, oopsTokenBalance);
            emit RelayWithdrawStuckERC20(address(this), msg.sender, oopsTokenBalance);
        }
    }

    /***********************************|
    |          Validator Functions      |
    |__________________________________*/

    /// @notice Pays the validator their outstanding balance
    /// @dev Callable by either validator address or their payee address (if not changed recently).
    function collectFees() external nonReentrant validPayee returns (uint256) { 
        // NOTE: Do not let validatorsBalanceMap[validator] balance go to 0, that will remove them from being an "active validator"       
        address _validator = getValidator();

        uint256 payableBalance = validatorsBalanceMap[_validator] - 1;  
        if (payableBalance <= 0) revert RelayCannotBeZero();

        validatorsTotal -= payableBalance;
        validatorsBalanceMap[_validator] = 1;
        validatorsDataMap[_validator].blockOfLastWithdraw = uint64(block.number);
        SafeTransferLib.safeTransferETH(
                validatorPayee(_validator), 
                payableBalance
        );
        emit RelayProcessingPaidValidator(_validator, payableBalance, msg.sender);
        return payableBalance;
    }

    /// @notice Pays a validator their fee via a custom payment processor
    function collectFeesCustom(address paymentProcessor, bytes calldata data) 
        external 
        limitedReentrant(paymentProcessor) 
        validPayee 
    {
        if (paymentProcessor == address(0)) revert RelayProcessorCannotBeZero();

        address validator = getValidator();
        uint256 validatorBalance = validatorsBalanceMap[validator] - 1;
        
        IPaymentProcessor(paymentProcessor).payValidator({
            validator: validator,
            startBlock: validatorsDataMap[validator].blockOfLastWithdraw,
            endBlock: block.number,
            totalAmount: validatorBalance,
            data: data
        });

        if (validatorsBalanceMap[validator] != 1) revert RelayCustomPayoutCantBePartial();
        validatorsDataMap[validator].blockOfLastWithdraw = uint64(block.number);
    }

    function paymentCallback(address validator, address payee, uint256 amount) 
        external
        permittedReentrant(validator)  
    {
       
        validatorsBalanceMap[validator] -= amount; // Expect EVM revert on underflow
        validatorsTotal -= amount;

        SafeTransferLib.safeTransferETH(
            payee, 
            amount
        );

        emit CustomPaymentProcessorPaid({
            payor: validator,
            payee: payee,
            paymentProcessor: msg.sender,
            totalAmount: amount,
            startBlock: validatorsDataMap[validator].blockOfLastWithdraw,
            endBlock: block.number
        });
    }

    /// @notice Updates a validator payee
    /// @dev Callable by either validator address or their payee address (if not changed recently).
    function updateValidatorPayee(address _payee) external validPayee nonReentrant {
        // NOTE: Payee cannot be updated until there is a valid balance in the fee vault
        if (_payee == address(0)) revert RelayCannotBeZero();
        if (_payee == address(this)) revert RelayCannotBeSelf();
        
        address _validator = getValidator();

        address _formerPayee = validatorsDataMap[_validator].payee;

        // Can't override with a validator
        // Can't override an already assigned payee
        if (payeeMap[_payee] != address(0) || validatorsBalanceMap[_payee] != 0) revert RelayPayeeUpdateInvalid();

        if (_formerPayee != address(0)) {
            payeeMap[_formerPayee] = address(0);
        }

        validatorsDataMap[_validator].payee = _payee;
        validatorsDataMap[_validator].timeUpdated = block.timestamp;
        payeeMap[_payee] = _validator;

        emit RelayValidatorPayeeUpdated(_validator, _payee, msg.sender);   
    }

    /// @notice Clears a validator payee
    /// @dev Callable by validator
    function clearValidatorPayee() external nonReentrant {
        if (validatorsBalanceMap[msg.sender] == 0) revert RelayNotActiveValidator(); 
        address _validator = msg.sender;

        address _formerPayee = validatorsDataMap[_validator].payee;
        validatorsDataMap[_validator].payee = address(0);
        validatorsDataMap[_validator].timeUpdated = block.timestamp;
        payeeMap[_formerPayee] = address(0);

        emit RelayValidatorPayeeUpdated(_validator, address(0), msg.sender);
    }

    /// @notice Updates a validator's share
    /// @param refundShare the share in % that should be paid to the validator
    function updateValidatorRefundShare(uint256 refundShare) public validPayee nonReentrant {
        address validator = getValidator();

        // ensure that validators can't insert txs to boost their refund rates during their own blocks
        if (validator == block.coinbase) revert RelayImmutableBlockAuthorRate();

        validatorsRefundShareMap[validator] = refundShare;
    }

    /***********************************|
    |              Views                |
    |__________________________________*/

    function isPayeeTimeLocked(address _validator) public view returns (bool _isTimeLocked) {
        _isTimeLocked = block.timestamp < validatorsDataMap[_validator].timeUpdated + BLOCK_TIMELOCK;
    }

    function isValidPayee(address _validator, address _payee) public view returns (bool _valid) {
        _valid = !isPayeeTimeLocked(_validator) && _payee == validatorsDataMap[_validator].payee;
    }

    function validatorPayee(address _validator) internal view returns (address _recipient) {
        address _payee = validatorsDataMap[_validator].payee;
        _recipient = !isPayeeTimeLocked(_validator) && _payee != address(0) && validatorsBalanceMap[_payee] == 0 ? _payee : _validator;
    }

    /// @notice Returns validator pending balance
    function getValidatorBalance(address _validator) public view returns (uint256 _validatorBalance) {
        _validatorBalance = validatorsBalanceMap[_validator];
    }

    /// @notice Returns the listed payee address regardless of whether or not it has passed the time lock.
    function getValidatorPayee(address _validator) public view returns (address _payee) {
        _payee = validatorsDataMap[_validator].payee;
    }

    /// @notice Returns the last block in which a validator withdrew their fees
    function getValidatorBlockOfLastWithdraw(address _validator) public view returns (uint256 _blockNumber) {
        _blockNumber = validatorsDataMap[_validator].blockOfLastWithdraw;
    }

    /// @notice For validators to determine where their payments will go
    /// @dev Will return the Payee if blockTimeLock has passed, will return Validator if not.
    /// @param _validator Address
    function getValidatorRecipient(address _validator) public view returns (address _recipient) {
        _recipient = validatorPayee(_validator);
    }
    

    function getValidator() internal view returns (address) {
        if (validatorsBalanceMap[msg.sender] > 0) {
            return msg.sender;
        }
        if (payeeMap[msg.sender] != address(0)) {
            return payeeMap[msg.sender];
        }
        // throw if invalid
        revert("Invalid validator");
    }

    /***********************************|
    |             Modifiers             |
    |__________________________________*/

    modifier nonReentrant() {
        require(lock == UNLOCKED, "REENTRANCY");

        lock = LOCKED;
        _;
        lock = UNLOCKED;
    }

    modifier limitedReentrant(address paymentProcessor) {
        require(lock == UNLOCKED, "REENTRANCY");

        lock = keccak256(abi.encodePacked(getValidator(), paymentProcessor));
        _;
        lock = UNLOCKED;
    }

    modifier permittedReentrant(address approver) {
        if(lock != keccak256(abi.encodePacked(approver, msg.sender))) revert RelayUnapprovedReentrancy();
        _;
    }

    modifier onlyActiveValidators() {
        if (validatorsBalanceMap[msg.sender] == 0 && validatorsBalanceMap[payeeMap[msg.sender]] == 0) revert RelayNotActiveValidator();
        _;
    }

    modifier validPayee() {
        if (payeeMap[msg.sender] != address(0)) {
            if (isPayeeTimeLocked(payeeMap[msg.sender])) revert RelayPayeeIsTimelocked();
        } else {
            if (validatorsBalanceMap[msg.sender] == 0) revert RelayInvalidSender();
        }
        _;
    }

    modifier onlyEOA() {
        if (msg.sender != tx.origin) revert RelayPermissionSenderNotOrigin();
        _;
    }

    /// @notice Validates incoming bid
    /// @dev 
    /// @param _oppTxHash Target Transaction hash
    /// @param _bidAmount Amount committed to be repaid
    modifier checkBid(bytes32 _oppTxHash, uint256 _bidAmount) {
        if (_bidAmount == 0) {
            revert RelayAuctionInvalidBid();
        }

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

        _;

        // Mark this auction as being complete to provide quicker reverts for subsequent searchers
        fulfilledAuctionsMap[auction_key] = _bidAmount;
    }

    modifier validatedValidator(address[] calldata approvedVals) {
        if (approvedVals.length == 0 || _validateValidator(approvedVals)) {
            _;
        }
    }

    function _validateValidator(address[] calldata approvedVals) 
        internal 
        view 
        returns (bool validValidator) 
    {
        uint256 valsLength = approvedVals.length;
        uint256 i;
        for(;i<valsLength;) {
            if (block.coinbase == approvedVals[i]) {
                return true;
            }
            unchecked { ++i; }
        } 
        return false;
    }

    /// @notice Validates incoming PGA bid
    /// @dev 
    /// @param fastGasPrice Amount committed to be repaid
    modifier checkPGA(uint256 fastGasPrice) {
        if (fastGasPrice == 0 || fastGasPrice > tx.gasprice) {
            revert RelayAuctionInvalidBid();
        }

        PGAData memory existing_bid = fulfilledPGAMap[block.number];
        uint256 lowestFastPrice = uint256(existing_bid.lowestFastPrice);
        uint256 lowestGasPrice = uint256(existing_bid.lowestGasPrice);
        uint256 lowestTotalPrice = uint256(existing_bid.lowestTotalPrice);

        // NOTE: These checks help mitigate the damage to searchers caused by relay error and adversarial validators by reverting
        // early if the transactions are not sequenced pursuant to auction rules. 

        // Do not execute if a fastBid tx with a lower gasPrice was executed prior to this tx in the same block. 
        // NOTE: This edge case should only be achieveable via validator manipulation or erratic searcher nonce management 
        if (lowestGasPrice != 0 && lowestGasPrice < tx.gasprice) {
            emit RelayInvestigateOutcome(block.coinbase, msg.sender, block.number, lowestFastPrice, fastGasPrice, lowestGasPrice, tx.gasprice);
        
        // Do not execute if a fastBid tx with a lower bid amount was executed prior to this tx in the same block.  
        } else if (lowestTotalPrice != 0 && lowestTotalPrice <= fastGasPrice + tx.gasprice) {
            emit RelayInvestigateOutcome(block.coinbase, msg.sender, block.number, lowestFastPrice, fastGasPrice, lowestGasPrice, tx.gasprice);
        
        // Execute the tx if there are no issues w/ ordering. 
        } else {
            _;
            // Mark this auction as being complete to provide quicker reverts for subsequent searchers
            fulfilledPGAMap[block.number] = PGAData({
                lowestGasPrice: uint64(tx.gasprice), 
                lowestFastPrice: uint64(fastGasPrice),
                lowestTotalPrice: uint64(fastGasPrice + tx.gasprice)
            });
        }
    }
}