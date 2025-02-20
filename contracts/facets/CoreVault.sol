// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, ERC20, ERC4626, SafeERC20, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CoreVault is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address private constant NATIVE_TOKEN = address(1);

    address public immutable factory;
    bool public isNativeToken;

    constructor(IERC20 asset, string memory name, string memory symbol) 
        ERC4626(asset)
        ERC20(name, symbol)
    {
        factory = msg.sender;
        isNativeToken = address(asset) == NATIVE_TOKEN;
    }

    receive() external payable {
        require(isNativeToken, "Not native token vault");
    }

    function initialize(uint256 _initialDeposit) external payable {
        require(msg.sender == factory, "Unauthorized");
        
        if (_initialDeposit > 0) {
            if (isNativeToken) {
                require(msg.value > 0, "Invalid ETH amount");
                _mint(factory, _initialDeposit);
            } else {
                IERC20(asset()).safeTransferFrom(factory, address(this), _initialDeposit);
                _mint(factory, _initialDeposit);
            }
        }
    }

    function deposit(uint256 assets, address receiver) 
        public
        override
        nonReentrant
        returns (uint256)
    {
        require(!isNativeToken, "Use depositETH for native tokens");
        require(assets > 0, "Zero assets");

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        
        uint256 shares = previewDeposit(assets);
        _mint(receiver, shares);

        return shares;
    }

    function depositETH(address receiver) 
        public
        nonReentrant
        payable
        returns (uint256)
    {
        require(isNativeToken, "Not a native token vault");
        require(msg.value > 0, "Zero ETH sent");

        uint256 shares = previewDeposit(msg.value);
        _mint(receiver, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) 
        public
        override
        nonReentrant
        returns (uint256)
    {
        require(!isNativeToken, "Use mintETH for native tokens");
        require(shares > 0, "Zero shares");

        uint256 assets = previewMint(shares);
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        return shares;
    }

    function mintETH(address receiver) 
        public
        nonReentrant
        payable
        returns (uint256)
    {
        require(isNativeToken, "Not a native token vault");
        require(msg.value > 0, "Zero ETH sent");

        uint256 shares = previewMint(msg.value);
        _mint(receiver, shares);

        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256) {
        require(assets > 0, "Zero assets");
        
        uint256 shares = previewWithdraw(assets);
        
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        
        if (isNativeToken) {
            (bool success,) = receiver.call{value: assets}("");
            require(success, "Failed to send ETH");
        } else {
            IERC20(asset()).safeTransfer(receiver, assets);
        }
        
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256) {
        require(shares > 0, "Zero shares");
        
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        uint256 assets = previewRedeem(shares);
        _burn(owner, shares);
        
        if (isNativeToken) {
            (bool success,) = receiver.call{value: assets}("");
            require(success, "Failed to send ETH");
        } else {
            IERC20(asset()).safeTransfer(receiver, assets);
        }
        
        return assets;
    }
}