//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockVault is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function deposit(uint256 amount) external {
        _mint(msg.sender, amount);
    }
    
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }

    function mintForUser(address user, uint256 amount) external {
        _mint(user, amount);
    }

    function burnFromUser(address user, uint256 amount) external {
        _burn(user, amount);
    }
}