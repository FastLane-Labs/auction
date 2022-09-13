pragma solidity ^0.8.16;


contract SearcherMinimalRawContract {

    address private owner;
    address payable private PFLRepayAddress;
    address private relayer;

    error WrongPermissions();
    error OriginEOANotOwner();

    constructor(address _relayer, address _PFLRepayAddress) {
        relayer = _relayer; // PFL Relayer
        owner = msg.sender;
        PFLRepayAddress = payable(_PFLRepayAddress);
    }

    // You choose your params as you want,
    // You will declare them in the `submitBid` transaction to PFL
    function doMEV(uint256 _paymentAmount, address _target, bytes calldata _encodedCall) external payable onlyRelayer {

        // In a relayed context _msgSender() will point back to the EOA that signed the searcherTX
        // as the normal `msg.sender` points to the relayer.
        // see https://ethereum.stackexchange.com/questions/99250/understanding-openzeppelins-context-contract
        if (_msgSender() != owner) revert OriginEOANotOwner();

        /* 
            ...
            Do whatever you want here, call your usual searcher contract, use msg.data
            or do the swaps / multicall from inside this one.
            `msg.sender` will be your SearcherMinimalContract
            ...
        */
        
        // MySearcherMEVContract.call(whatever); or
        // Someopportunity.call(whatever)
        _target.call(_encodedCall);
        // Repay PFL at the end
        safeTransferETH(PFLRepayAddress, _paymentAmount);
    }

    function _msgSender() internal view returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }

    // Can receive ETH
    fallback() external payable {}

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == relayer;
    }

    function safeTransferETH(address to, uint256 amount) internal {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
    }

    modifier onlyRelayer {
          if (!isTrustedForwarder(msg.sender)) revert WrongPermissions();
          _;
     }

}