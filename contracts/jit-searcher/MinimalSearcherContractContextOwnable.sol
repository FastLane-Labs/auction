pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts//access/Ownable.sol";
import { ERC2771Context } from "openzeppelin-contracts/contracts/metatx/ERC2771Context.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

contract MinimalSearcherContractContextOwnable is ERC2771Context, Ownable {

     error WrongPermissions();
     error OriginEOANotOwner();

     address private PFLRepayAddress;

     using SafeTransferLib for address payable;

     constructor(address _relayer, address _PFLRepayAddress) ERC2771Context(_relayer) {
          require(_relayer != address(0) && _PFLRepayAddress != address(0),"MSCCO-C0");
          PFLRepayAddress = _PFLRepayAddress;
     }

     // Can receive ETH
     fallback() external payable {}

     function doMEV(address payable callTo, uint256 flags, uint256 _paybackAmount, bytes calldata params) external payable onlyRelayer {

          // In a relayed context _msgSender() will point back to the EOA that signed the searcherTX
          // as the normal `msg.sender` points to the relayer.
          // see https://ethereum.stackexchange.com/questions/99250/understanding-openzeppelins-context-contract
          if (_msgSender() != owner()) revert OriginEOANotOwner();

          /* 
               ...
               Do whatever you want here, call your usual searcher contract, use msg.data
               or do the swaps / multicall from inside this one.
               `msg.sender` will be your SearcherMinimalContract
               ...
          */
          
          // MySearcherMEVContract.call(callTo, flags, params);

          // Repay PFL at the end
          payable(PFLRepayAddress).safeTransferETH(_paybackAmount);
     }

     function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
          return ERC2771Context._msgSender();
     }

     function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
          return ERC2771Context._msgData();
     }

     modifier onlyRelayer {
          if (!isTrustedForwarder(msg.sender)) revert WrongPermissions();
          _;
     }
}