//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import "forge-std/console.sol";


abstract contract FastLaneAuctionHandlerEvents {

    event RelayValidatorPayeeUpdated(address validator, address payee, address indexed initiator);

    event RelayFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);
    event RelaySimulatedFlashBid(address indexed sender, uint256 amount, bytes32 indexed oppTxHash, address indexed validator, address searcherContractAddress);

    event RelayWithdrawStuckERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
    event RelayWithdrawStuckNativeToken(address indexed receiver, uint256 amount);
    
    event RelayProcessingPaidValidator(address indexed validator, uint256 validatorPayment, address indexed initiator);

    event RelayFeeCollected(address indexed payor, address indexed payee, uint256 amount);

    error RelayPermissionSenderNotOrigin();                                 // 0x5c8a268a

    error RelaySearcherWrongParams();                                       // 0x31ae2a9d

    error RelaySearcherCallFailure(bytes retData);                          // 0x291bc14c
    error RelaySimulatedSearcherCallFailure(bytes retData);                 // 0x5be08ca5
    error RelayNotRepaid(uint256 bidAmount, uint256 actualAmount);          // 0x53dc88d9
    error RelaySimulatedNotRepaid(uint256 bidAmount, uint256 actualAmount); // 0xd47ae88a

    error RelayAuctionBidReceivedLate();                                    // 0xb61e767e
    error RelayAuctionSearcherNotWinner(uint256 current, uint256 existing); // 0x5db6f7d9

    error RelayCannotBeZero();                                              // 0x3c9cfe50
    error RelayCannotBeSelf();                                              // 0x6a64f641
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

contract FastLaneAuctionHandler is FastLaneAuctionHandlerEvents, ReentrancyGuard {

    /// @notice Constant delay before the stake share can be changed
    uint32 internal constant BLOCK_TIMELOCK = 6 days;

    /// @notice Mapping to Validator Data Struct
    mapping(address => ValidatorData) internal validatorsDataMap;

    /// @notice Mapping payee address to validator address
    mapping(address => address) internal payeeMap;

    /// @notice Map[validator] = balance
    mapping(address => uint256) public validatorsBalanceMap;

    /// @notice Map key is keccak hash of opp tx's gasprice and tx hash
    mapping(bytes32 => uint256) public fulfilledAuctionsMap;

    uint256 public validatorsTotal;


    /// @notice Submits a flash bid
    /// @dev Will revert if: already won, minimum bid not respected, or not from EOA
    /// @param _bidAmount Amount committed to be repaid
    /// @param _oppTxHash Target Transaction hash
    /// @param _searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param _searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    function submitFlashBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution
        bytes32 _oppTxHash, // Target TX
        address _searcherToAddress,
        bytes calldata _searcherCallData 
        ) external payable checkBid(_oppTxHash, _bidAmount) onlyEOA nonReentrant {

            if (_searcherToAddress == address(0)) revert RelaySearcherWrongParams();
            
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

    /// @notice Pays the validator for fees / revenue sharing that is collected outside of submitFlashBid function
    function payValidatorFee(address _payor) external payable nonReentrant {
        _payValidatorFee(_payor);
    }

    function _payValidatorFee(address _payor) internal {
        require(msg.value > 0, "msg.value = 0");
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
    /// @param _bidAmount Amount committed to be repaid
    /// @param _oppTxHash Target Transaction hash
    /// @param _searcherToAddress Searcher contract address to be called on its `fastLaneCall` function.
    /// @param _searcherCallData callData to be passed to `_searcherToAddress.fastLaneCall(_bidAmount,msg.sender,callData)`
    function simulateFlashBid(
        uint256 _bidAmount, // Value commited to be repaid at the end of execution, can be set very low in simulated
        bytes32 _oppTxHash, // Target TX
        address _searcherToAddress,
        bytes calldata _searcherCallData 
        ) external payable nonReentrant onlyEOA {

            // Relax check on min bid amount for simulated
            if (_searcherToAddress == address(0)) revert RelaySearcherWrongParams();
            
            // Store the current balance, excluding msg.value
            uint256 balanceBefore = address(this).balance - msg.value;

            // Call the searcher's contract (see searcher_contract.sol for example of call receiver)
            // And forward msg.value
            (bool success, bytes memory retData) = ISearcherContract(_searcherToAddress).fastLaneCall{value: msg.value}(
                        msg.sender,
                        _bidAmount,
                        _searcherCallData
            );

            if (!success) revert RelaySimulatedSearcherCallFailure(retData);

            // Verify that the searcher paid the amount they bid & emit the event
            if (address(this).balance < balanceBefore + _bidAmount) {
                revert RelaySimulatedNotRepaid(_bidAmount, address(this).balance - balanceBefore);
            }
            emit RelaySimulatedFlashBid(msg.sender, _bidAmount, _oppTxHash, block.coinbase, _searcherToAddress);
    }

    /***********************************|
    |    Internal Bid Helper Functions  |
    |__________________________________*/

    function _handleBalances(uint256 _bidAmount, uint256 balanceBefore) internal {
        if (address(this).balance < balanceBefore + _bidAmount) {
            revert RelayNotRepaid(_bidAmount, address(this).balance - balanceBefore);
        }

        if (address(this).balance - balanceBefore > _bidAmount) {
            _bidAmount = address(this).balance - balanceBefore;
        }

        validatorsBalanceMap[block.coinbase] += _bidAmount;
        validatorsTotal += _bidAmount;
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
        // TODO: handle wMATIC differently
        ERC20 oopsToken = ERC20(_tokenAddress);
        uint256 oopsTokenBalance = oopsToken.balanceOf(address(this));

        if (oopsTokenBalance > 0) {
            SafeTransferLib.safeTransferFrom(oopsToken, address(this), msg.sender, oopsTokenBalance);
            emit RelayWithdrawStuckERC20(address(this), msg.sender, oopsTokenBalance);
        }
    }

    /***********************************|
    |          Validator Functions      |
    |__________________________________*/

    /// @notice Pays the validator their outstanding balance
    /// @dev Callable by either validator address, their payee address (if not changed recently), or PFL.
    function collectFees() external nonReentrant validPayee returns (uint256) { 
        // NOTE: Do not let validatorsBalanceMap[validator] balance go to 0, that will remove them from being an "active validator"       
        
        address _validator = getValidator();

        console.log("validator addr in contract", _validator);
        console.log("addr sending to", validatorPayee(_validator));
        console.log("validatorsDataMap[_validator].timeUpdated", validatorsDataMap[_validator].timeUpdated);
        
        uint256 payableBalance = validatorsBalanceMap[_validator] - 1;  
        if (payableBalance <= 0) revert RelayCannotBeZero();

        validatorsTotal -= payableBalance;
        validatorsBalanceMap[_validator] = 1;
        SafeTransferLib.safeTransferETH(
                validatorPayee(_validator), 
                payableBalance
        );
        emit RelayProcessingPaidValidator(_validator, payableBalance, msg.sender);
        return payableBalance;
    }

    /// @notice Updates a validator payee
    /// @dev Callable by either validator address, their payee address (if not changed recently), or PFL.
    function updateValidatorPayee(address _payee) external validPayee nonReentrant {
        // NOTE: Payee cannot be updated until there is a valid balance in the fee vault
        if (_payee == address(0)) revert RelayCannotBeZero();
        if (_payee == address(this)) revert RelayCannotBeSelf();
        
        address _validator = getValidator();

        require(payeeMap[_validator] == address(0) && payeeMap[_payee] == address(0), "invalid payee");

        address _formerPayee = validatorsDataMap[_validator].payee;

        require(_formerPayee != _payee, "not a new payee");

        if (_formerPayee != address(0)) {
            payeeMap[_formerPayee] = address(0);
        }

        validatorsDataMap[_validator].payee = _payee;
        validatorsDataMap[_validator].timeUpdated = block.timestamp;
        payeeMap[_payee] = _validator;

        emit RelayValidatorPayeeUpdated(_validator, _payee, msg.sender);   
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
        _recipient = !isPayeeTimeLocked(_validator) && _payee != address(0) ? _payee : _validator;
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

    modifier onlyActiveValidators() {
        require(validatorsBalanceMap[msg.sender] > 0 || validatorsBalanceMap[payeeMap[msg.sender]] > 0, "only active validators");
        _;
    }

    modifier validPayee() {
        if (payeeMap[msg.sender] != address(0)) {
            require(!isPayeeTimeLocked(payeeMap[msg.sender]), "payee is time locked");
        } else {
            require(validatorsBalanceMap[msg.sender] > 0, "invalid msg.sender");
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
        _;
    }
}