pragma solidity ^0.8.10;

interface WMATIC {
    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function allowance(address, address) view external returns (uint256);
    function approve(address guy, uint256 wad) external returns (bool);
    function balanceOf(address) view external returns (uint256);
    function decimals() view external returns (uint8);
    function deposit() payable external;
    function name() view external returns (string memory);
    function symbol() view external returns (string memory);
    function totalSupply() view external returns (uint256);
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function withdraw(uint256 wad) external;
}

