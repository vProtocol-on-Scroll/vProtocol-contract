// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VTokenVault
 * @author Five Protocol
 *
 * @dev ERC4626-compliant vault for deposit tokens in vProtocol
 */
contract VTokenVault is ERC20, ERC20Permit, IERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // References
    address public immutable diamond;
    IERC20 immutable assetToken;
    uint8 private immutable _decimals;
    
    /**
     * @notice Initializes a new VTokenVault
     * @param _asset Underlying asset
     * @param _name Vault token name (e.g., "vProtocol USDC")
     * @param _symbol Vault token symbol (e.g., "vUSDC")
     * @param _diamond Diamond contract address
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _diamond

    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        require(_asset != address(0), "Asset cannot be zero address");
        require(_diamond != address(0), "Diamond cannot be zero address");
        
        assetToken = IERC20(_asset);
        diamond = _diamond;
        _decimals = ERC20(_asset).decimals();
        
        // Approve diamond to pull tokens from vault
        IERC20(_asset).approve(_diamond, type(uint256).max);
    }
    
    
    /**
     * @notice Returns the address of the underlying token used for the vault
     * @return Address of the underlying token
     */
    function asset() public view override returns (address) {
        return address(assetToken);
    }
    
    /**
     * @notice Total assets managed by the vault
     * @return Total amount of underlying assets
     */
    function totalAssets() public view override returns (uint256) {
        // Get total managed assets through lens function in diamond
        return IDiamondLendingPool(diamond).getVaultTotalAssets(address(assetToken));
    }
    
    /**
     * @notice Convert assets to shares
     * @param assets Amount of assets
     * @return Amount of shares
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return assets;
        } else {
            uint256 _totalAssets = totalAssets();
            return assets * _totalSupply / _totalAssets;
        }
    }
    
    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return Amount of assets
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return shares;
        } else {
            uint256 _totalAssets = totalAssets();
            return shares * _totalAssets / _totalSupply;
        }
    }
    
    /**
     * @notice Maximum assets that can be deposited
     * @param receiver Address receiving the shares
     * @return Maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) public view override returns (uint256) {
        return IDiamondLendingPool(diamond).isPoolPaused() ? 0 : type(uint256).max;
    }
    
    /**
     * @notice Preview deposit to calculate expected shares
     * @param assets Amount of assets to deposit
     * @return Expected shares to be received
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }
    
    /**
     * @notice Deposit assets and receive shares
     * @param assets Amount of assets to deposit
     * @param receiver Address receiving the shares
     * @return shares Amount of shares received
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        require(assets <= maxDeposit(receiver), "Deposit exceeds maximum");
        
        shares = previewDeposit(assets);
        require(shares > 0, "Zero shares minted");
        
        // Transfer assets from sender to this contract
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        
        // Deposit into the lending pool through the diamond
        IDiamondLendingPool(diamond).depositFromVault(address(assetToken), assets, receiver);
        
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }
    
    /**
     * @notice Maximum mint amount
     * @param receiver Address receiving the shares
     * @return Maximum amount of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256) {
        return IDiamondLendingPool(diamond).isPoolPaused() ? 0 : type(uint256).max;
    }
    
    /**
     * @notice Preview mint to calculate required assets
     * @param shares Amount of shares to mint
     * @return Assets required to mint the specified shares
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return shares;
        } else {
            uint256 _totalAssets = totalAssets();
            return (shares * _totalAssets + _totalSupply - 1) / _totalSupply; // Round up
        }
    }
    
    /**
     * @notice Mint exact shares by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address receiving the shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        require(shares <= maxMint(receiver), "Mint exceeds maximum");
        
        assets = previewMint(shares);
        
        // Transfer assets from sender to this contract
        assetToken.safeTransferFrom(msg.sender, address(this), assets);
        
        // Deposit into the lending pool through the diamond
        IDiamondLendingPool(diamond).depositFromVault(address(assetToken), assets, receiver);
        
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }
    
    /**
     * @notice Maximum withdrawal amount
     * @param owner Address owner of the shares
     * @return Maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (IDiamondLendingPool(diamond).isPoolPaused()) {
            return 0;
        }
        
        uint256 assets = convertToAssets(balanceOf(owner));
        uint256 availableLiquidity = IDiamondLendingPool(diamond).getAvailableLiquidity(address(assetToken));
        
        return assets > availableLiquidity ? availableLiquidity : assets;
    }
    
    /**
     * @notice Preview withdrawal to calculate expected shares burned
     * @param assets Amount of assets to withdraw
     * @return Expected shares to be burned
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) {
            return 0;
        }
        
        uint256 _totalSupply = totalSupply();
        return (assets * _totalSupply + _totalAssets - 1) / _totalAssets; // Round up
    }
    
    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the assets
     * @param owner Address owner of the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        require(assets <= maxWithdraw(owner), "Withdraw exceeds maximum");
        
        shares = previewWithdraw(assets);
        
        if (msg.sender != owner) {
            uint256 currentAllowance = allowance(owner, msg.sender);
            require(currentAllowance >= shares, "ERC20: withdraw amount exceeds allowance");
            _approve(owner, msg.sender, currentAllowance - shares);
        }
        
        _burn(owner, shares);
        
        // Withdraw from the lending pool through the diamond
        IDiamondLendingPool(diamond).withdrawFromVault(address(assetToken), assets, receiver);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }
    
    /**
     * @notice Maximum redeem amount
     * @param owner Address owner of the shares
     * @return Maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (IDiamondLendingPool(diamond).isPoolPaused()) {
            return 0;
        }
        
        uint256 shares = balanceOf(owner);
        uint256 assets = convertToAssets(shares);
        uint256 availableLiquidity = IDiamondLendingPool(diamond).getAvailableLiquidity(address(assetToken));
        
        if (assets > availableLiquidity) {
            return convertToShares(availableLiquidity);
        }
        return shares;
    }
    
    /**
     * @notice Preview redeem to calculate expected assets
     * @param shares Amount of shares to redeem
     * @return Expected assets to be received
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }
    
    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address receiving the assets
     * @param owner Address owner of the shares
     * @return assets Amount of assets redeemed
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        require(shares <= maxRedeem(owner), "Redeem exceeds maximum");
        
        assets = previewRedeem(shares);
        
        if (msg.sender != owner) {
            uint256 currentAllowance = allowance(owner, msg.sender);
            require(currentAllowance >= shares, "ERC20: redeem amount exceeds allowance");
            _approve(owner, msg.sender, currentAllowance - shares);
        }
        
        _burn(owner, shares);
        
        // Withdraw from the lending pool through the diamond
        IDiamondLendingPool(diamond).withdrawFromVault(address(assetToken), assets, receiver);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }
    
    /**
     * @notice Returns the decimals of the vault token, which matches the underlying asset
     */
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint shares for a user (only callable by diamond/owner)
     * @param receiver Address receiving the shares
     * @param shares Amount of shares to mint
     */
    function mintFor(address receiver, uint256 shares) external {
        require(msg.sender == diamond, "Only diamond can call");
        _mint(receiver, shares);
    }
}

/**
 * @dev Interface for diamond lending pool functions used by the vault
 */
interface IDiamondLendingPool {
    function depositFromVault(address token, uint256 assets, address receiver) external;
    function withdrawFromVault(address token, uint256 assets, address receiver) external;
    function getVaultTotalAssets(address token) external view returns (uint256);
    function getAvailableLiquidity(address token) external view returns (uint256);
    function isPoolPaused() external view returns (bool);
}