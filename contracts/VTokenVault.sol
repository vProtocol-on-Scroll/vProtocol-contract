// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {Constants} from "./utils/constants/Constant.sol";
import {IWeth} from "./interfaces/IWeth.sol";
/**
 * @title VTokenVault
 * @author Five Protocol
 * @notice ERC4626-compliant tokenized vault for Five Protocol
 * @dev Unlike traditional ERC4626, value accrues directly to the token through interest
 */
contract VTokenVault is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Protocol diamond address
    address public immutable diamond;
    
    /// @notice Exchange rate when last updated (asset per share, scaled by 1e18)
    uint256 public exchangeRateStored;
    
    /// @notice Last update timestamp
    uint256 public lastUpdateTimestamp;
    
    /// @notice Boolean indicating if vault is paused
    bool public paused;
    
    /// @dev Only diamond modifier
    modifier onlyDiamond() {
        require(msg.sender == diamond, "Only diamond");
        _;
    }
    
    /// @dev Not paused modifier
    modifier notPaused() {
        require(!paused, "Vault is paused");
        _;
    }
    
    /// @dev Update exchange rate
    modifier _updateExchangeRate() {
        exchangeRateStored = exchangeRate();
        lastUpdateTimestamp = block.timestamp;
        _;
    }

    /**
     * @notice Construct a new VToken vault
     * @param _asset Underlying asset
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     * @param _diamond Diamond contract address
     */
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _diamond
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        require(_diamond != address(0), "Invalid diamond");
        
        diamond = _diamond;
        exchangeRateStored = 1e18; // Initialize at 1:1
        lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Set pause state (only diamond)
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyDiamond {
        paused = _paused;
    }

    /**
     * @notice Update exchange rate (only diamond)
     * @param _newExchangeRate New exchange rate
     */
    function updateExchangeRate(uint256 _newExchangeRate) external onlyDiamond {
        require(_newExchangeRate >= exchangeRateStored, "Rate can only increase");
        exchangeRateStored = _newExchangeRate;
        lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Calculate current exchange rate with interest accrual
     * @return Current exchange rate
     */
    function exchangeRate() public view returns (uint256) {
        // For actual implementation, get interest accrual from the lending protocol
        // This is a simplified version
        return IFiveProtocol(diamond).getVaultExchangeRate(asset());
    }

    /**
     * @notice Get total assets managed by the vault
     * @return Total amount of underlying assets
     */
    function totalAssets() public view override returns (uint256) {
        // The value of all assets is: total shares * exchange rate
        return (totalSupply() * exchangeRate()) / 1e18;
    }

    /**
     * @notice Convert assets to shares based on current exchange rate
     * @param assets Amount of assets
     * @return shares Amount of shares
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        uint256 rate = exchangeRate();
        return (assets * 1e18) / rate;
    }
    
    /**
     * @notice Convert shares to assets based on current exchange rate
     * @param shares Amount of shares
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        uint256 rate = exchangeRate();
        return (shares * rate) / 1e18;
    }

    /**
     * @notice Deposit assets into the vault
     * @param assets Amount of assets to deposit
     * @param receiver Address receiving the shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) 
        public 
        override 
        nonReentrant 
        notPaused 
        _updateExchangeRate
        returns (uint256 shares) 
    {
        // Calculate shares
        shares = convertToShares(assets);
        require(shares > 0, "Zero shares");
        
        // Transfer assets to vault
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        
        // Notify diamond about deposit
        IFiveProtocol(diamond).notifyVaultDeposit(asset(), assets, receiver, false);
        
        // Mint shares
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @notice Deposit ETH and receive shares
     * @param receiver Address receiving the shares
     * @return shares Amount of shares minted
     */
    function depositETH(address receiver)
        external
        payable
        nonReentrant
        notPaused
        _updateExchangeRate
        returns (uint256 shares)
    {
        require(asset() == Constants.NATIVE_TOKEN, "Not WETH vault");
        require(msg.value > 0, "Zero value");
        
        // Calculate shares
        shares = convertToShares(msg.value);
        require(shares > 0, "Zero shares");
        
        // Wrap ETH to WETH
        IWeth(Constants.WETH).deposit{value: msg.value}();
        
        // Notify diamond about deposit
        IFiveProtocol(diamond).notifyVaultDeposit(asset(), msg.value, receiver, false);
        
        // Mint shares
        _mint(receiver, shares);
        
        emit Deposit(msg.sender, receiver, msg.value, shares);
        return shares;
    }

    /**
     * @notice Withdraw assets from the vault
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the assets
     * @param owner Owner of the shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        _updateExchangeRate
        returns (uint256 shares)
    {
        // Calculate shares
        shares = convertToShares(assets);
        
        // Check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        // Burn shares
        _burn(owner, shares);
        
        // Notify diamond about withdrawal
        IFiveProtocol(diamond).notifyVaultWithdrawal(asset(), assets, receiver, true);
        
        // Transfer assets to receiver
        IERC20(asset()).safeTransfer(receiver, assets);
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @notice Withdraw ETH from WETH vault
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the ETH
     * @param owner Owner of the shares
     * @return shares Amount of shares burned
     */
    function withdrawETH(uint256 assets, address payable receiver, address owner)
        external
        nonReentrant
        _updateExchangeRate
        returns (uint256 shares)
    {
        require(asset() == Constants.NATIVE_TOKEN, "Not WETH vault");
        
        // Calculate shares
        shares = convertToShares(assets);
        
        // Check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        // Burn shares
        _burn(owner, shares);
        
        // Notify diamond about withdrawal
        IFiveProtocol(diamond).notifyVaultWithdrawal(asset(), assets, receiver, false);
        
        // Unwrap WETH to ETH and send to receiver
        IWeth(Constants.WETH).withdraw(assets);
        (bool success, ) = receiver.call{value: assets}("");
        require(success, "ETH transfer failed");
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }
    
    /**
     * @dev Receive function to handle ETH
     */
    receive() external payable {
        require(asset() == Constants.NATIVE_TOKEN, "Not WETH vault");
    }
}

// External interfaces
interface IFiveProtocol {
    function notifyVaultDeposit(address asset, uint256 amount, address depositor, bool transferAssets) external;
    function notifyVaultWithdrawal(address asset, uint256 amount, address receiver, bool transferAssets) external;
    function getVaultExchangeRate(address asset) external view returns (uint256);
}