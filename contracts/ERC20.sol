// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
interface ERC20{
  function deposit() external payable;
  function withdraw(uint256 amount) external payable;
  function transfer(address sender, uint value ) external payable ;
  function balanceOf(address owner) external view returns (uint256 balance);
  function approve(address guy, uint wad) external returns (bool);
  function allowance(address owner, address spender) external returns(uint256);
}