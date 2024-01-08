//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.16;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract FastLaneSearcherProxyContract is ReentrancyGuard {
    address public owner;
    address payable private PFLAuction;
    address payable private searcherContract;

    error WrongPermissions();
    error OriginEOANotOwner();
    error SearcherCallUnsuccessful(bytes retData);
    error SearcherInsufficientFunds(uint256 amountToSend, uint256 currentBalance);

    mapping(address => bool) internal approvedEOAs;

    constructor(address _searcherContract) {
        owner = msg.sender;
        searcherContract = payable(_searcherContract);
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
        // /!\ Don't forget to whitelist `searcherContract` called function
        // to allow this contract.
        (bool success, bytes memory returnedData) = searcherContract.call(_searcherCallData);

        if (!success) {
            // If the call didn't turn out the way you wanted, revert either here or inside your MEV function itself
            return (false, returnedData);
        }

        // Balance check then pay FastLane Auction Handler contract at the end
        require(
            (address(this).balance >= _bidAmount),
            string(
                abi.encodePacked(
                    "SearcherInsufficientFunds  ",
                    Strings.toString(_bidAmount),
                    " ",
                    Strings.toString(address(this).balance)
                )
            )
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

    function setSearcherContractAddress(address _searcherContract) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        searcherContract = payable(_searcherContract);
    }

    function approveFastLaneEOA(address _eoaAddress) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        approvedEOAs[_eoaAddress] = true;
    }

    function revokeFastLaneEOA(address _eoaAddress) public {
        require(msg.sender == owner, "OriginEOANotOwner");
        approvedEOAs[_eoaAddress] = false;
    }

    function checkFastLaneEOA(address _eoaAddress) internal view {
        require(approvedEOAs[_eoaAddress] || _eoaAddress == owner, "SenderEOANotApproved");
    }

    function isTrustedForwarder(address _forwarder) public view returns (bool) {
        return _forwarder == PFLAuction;
    }

    // Be aware with a fallback fn that:
    // `address(this).call(_searcherCallData);`
    // Will hit this if _searcherCallData function is not implemented.
    // And success will be true.
    fallback() external payable {}
    receive() external payable {}

    modifier onlyRelayer() {
        if (!isTrustedForwarder(msg.sender)) revert("InvalidPermissions");
        _;
    }
}
