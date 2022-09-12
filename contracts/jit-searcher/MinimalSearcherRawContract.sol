pragma solidity ^0.8.16;


contract SearcherMinimalRawContract {
    address private owner;
    address payable private PFLRepayAddress;
    address private relayer;

    error WrongPermissions();
    error OriginEOANotOwner();

    constructor(address _relayer, address payable _PFLRepayAddress) {
        relayer = _relayer; // PFL Relayer
        owner = msg.sender;
        PFLRepayAddress = _PFLRepayAddress;
    }

    function doMEV(uint256 _paymentAmount, bytes calldata _forwardedExecData) external payable onlyRelayer {

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
        
        // MySearcherMEVContract.call(_forwardedCalldata);

        // Repay PFL at the end
        safeTransferETH(PFLRepayAddress,_paymentAmount);
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