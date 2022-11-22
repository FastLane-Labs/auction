//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

abstract contract FastLaneSearcherDirectContract is ReentrancyGuard {

    address public owner;
    address payable private PFLAuction;

    error WrongPermissions();
    error OriginEOANotOwner();
    error SearcherCallUnsuccessful(bytes retData);
    error SearcherInsufficientFunds(uint256 amountToSend, uint256 currentBalance);

    mapping(address => bool) internal approvedEOAs;

    constructor() {
        owner = msg.sender;
    }

    // The FastLane Auction contract will call this function
    // The `onlyRelayer` modifier makes sure the calls can only come from PFL or will revert
    // PFL will pass along the original msg.sender as _sender for the searcher to do additional checks
    // Do NOT forget `onlyRelayer` and `checkFastLaneEOA(_sender);` or ANYONE will be able to call your contract with arbitrary calldata
    function fastLaneCall(
            address _sender, // Relay will always set this to msg.sender that called it. Ideally you (owner) or an approvedEOA.
            uint256 _bidAmount,
            bytes calldata _searcherCallData // contains func selector and calldata for your MEV transaction ie: abi.encodeWithSignature("doStuff(address,uint256)", 0xF00, 1212);
    ) external payable onlyRelayer nonReentrant returns (bool, bytes memory) {
        
        // Make sure it's your own EOA that's calling your contract 
        checkFastLaneEOA(_sender);

        // Execute the searcher's intended function
        (bool success, bytes memory returnedData) = address(this).call(_searcherCallData);
        
        // If the call didn't turn out the way you wanted, revert either here or inside your MEV function itself
        if (!success) {
            return (false, returnedData);
        }

        // Balance check then pay PFL at the end
        require(
            (address(this).balance >= _bidAmount), 
            string(abi.encodePacked("SearcherInsufficientFunds  ", Strings.toString(_bidAmount), " ", Strings.toString(address(this).balance)))
        );

        safeTransferETH(PFLAuction, _bidAmount);
        
        // /!\ Important to return success true or relay will revert.
        // In case of success == false, `returnedData` will be used as revert message that can be decoded with `.humanizeError()`
        return (success, returnedData);
    }

    // Other functions / modifiers that are necessary for FastLane integration:
    // NOTE: you can use your own versions of these, or find alternative ways
    // to implement similar safety checks. Please be careful when altering!
    function safeTransferETH(address to, uint256 amount) internal {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(success, "ETH_TRANSFER_FAILED");
    }

    function setPFLAuctionAddress(address _pflAuction) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        PFLAuction = payable(_pflAuction);
    }

    function approveFastLaneEOA(address _eoaAddress) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        approvedEOAs[_eoaAddress] = true;
    }

    function revokeFastLaneEOA(address _eoaAddress) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        approvedEOAs[_eoaAddress] = false;
    }

    function checkFastLaneEOA(address _eoaAddress) view internal {
        require(approvedEOAs[_eoaAddress] || _eoaAddress == owner, "SenderEOANotApproved");
    }

    function isTrustedForwarder(address _forwarder) public view returns (bool) {
        return _forwarder == PFLAuction;
    }

    // Be aware with a fallback fn that:
    // `address(this).call(_searcherCallData);` 
    // Will hit this if _searcherCallData function is not implemented. 
    // And success will be true.
    fallback() external payable {
        
    }
    receive() external payable {}

    modifier onlyRelayer {
          if (!isTrustedForwarder(msg.sender)) revert("InvalidPermissions");
          _;
     }
}

contract SearcherContractExample is FastLaneSearcherDirectContract {
    // Your own MEV contract / functions here 
    // NOTE: its security checks must be compatible w/ calls from the FastLane Auction Contract

    address public anAddress; // just a var to change for the placeholder MEV function
    uint256 public anAmount; // another var to change for the placeholder MEV function

    function doStuff(address _anAddress, uint256 _anAmount) public payable returns (bool) {
        // NOTE: this function can't be external as the FastLaneCall func will call it internally
        if (msg.sender != address(this)) { 
            // NOTE: msg.sender becomes address(this) if using call from inside contract per above example in `fasfastLaneCall`
            require(approvedEOAs[msg.sender], "SenderEOANotApproved");
        }
        
        // Do MEV stuff here
        // placeholder
        anAddress = _anAddress;
        anAmount = _anAmount;
        bool isSuccessful = true;
        return isSuccessful;
    }

    function doFail() public payable {
        if (msg.sender != address(this)) { 
            // NOTE: msg.sender becomes address(this) if using call from inside contract per above example in `fasfastLaneCall`
            require(approvedEOAs[msg.sender], "SenderEOANotApproved");
        }
        // Will cause Error(string) of: 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f4641494c5f4f4e5f505552504f53450000000000000000000000000000000000
        // to bubble up to the relay contract.
        // Use the read function `FastLaneRelay.humanizeError(bytes error)` to get a human readable version of an error should your searcher contract fail on a require.
        require(false,"FAIL_ON_PURPOSE");
    }
}