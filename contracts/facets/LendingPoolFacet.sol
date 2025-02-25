// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {VTokenVault} from "../VTokenVault.sol";
import  "../utils/constants/Constant.sol";
import {LibGettersImpl} from "../libraries/LibGetters.sol";
/**
 * @title LendingPoolFacet
 * @author Five Protocol
 *
 * @dev This contract manages the lending pool operations including deposits, withdrawals,
 * borrowing, repayment, interest rate calculations, and liquidity management.
 */
contract LendingPoolFacet {
    using SafeERC20 for IERC20;


    LibAppStorage.Layout internal s;

    // Internal helper functions first
    function _calculatePoolShares(address token, uint256 amount) internal view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        if (tokenData.totalDeposits == 0) {
            return amount;
        }
        return (amount * tokenData.normalizedPoolDebt) / 1e18;
    }

    function _calculateNormalizedDebt(address token, uint256 amount) internal view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        return (amount * 1e18) / tokenData.normalizedPoolDebt;
    }

    function _calculateActualDebt(address token, uint256 normalizedDebt) internal view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        return (normalizedDebt * tokenData.normalizedPoolDebt) / 1e18;
    }

    function _calculateBorrowRate(uint256 utilization) internal view returns (uint256) {
        if (utilization <= s.lendingPoolConfig.optimalUtilization) {
            return s.lendingPoolConfig.baseRate + 
                   (utilization * s.lendingPoolConfig.slopeRate) / s.lendingPoolConfig.optimalUtilization;
        } else {
            uint256 excessUtilization = utilization - s.lendingPoolConfig.optimalUtilization;
            return s.lendingPoolConfig.baseRate + s.lendingPoolConfig.slopeRate +
                   (excessUtilization * s.lendingPoolConfig.slopeExcess) / (10000 - s.lendingPoolConfig.optimalUtilization);
        }
    }

    function _calculateDepositRate(uint256 borrowRate, uint256 utilization) internal view returns (uint256) {
        return (borrowRate * utilization * (10000 - s.lendingPoolConfig.reserveFactor)) / (10000 * 10000);
    }

    function _updateState(address token) internal {
        TokenData storage tokenData = s.tokenData[token];
        
        // Skip if updated in same block
        if (tokenData.lastUpdateTimestamp == block.timestamp) {
            return;
        }

        uint256 timeDelta = block.timestamp - tokenData.lastUpdateTimestamp;
        if (timeDelta == 0) {
            return;
        }

        // Calculate utilization rate
        uint256 utilization = tokenData.totalDeposits == 0 ? 0 : 
            (tokenData.totalBorrows * 10000) / tokenData.totalDeposits;

        // Calculate interest rates
        uint256 borrowRate = _calculateBorrowRate(utilization);
        uint256 depositRate = _calculateDepositRate(borrowRate, utilization);

        // Update normalized debt
        uint256 interestFactor = (borrowRate * timeDelta) / Constants.SECONDS_PER_YEAR;
        tokenData.normalizedPoolDebt = (tokenData.normalizedPoolDebt * (10000 + interestFactor)) / 10000;
        
        tokenData.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     */
    fallback() external {
        revert("LendingPoolFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Initialize the lending pool
     * @param reserveFactor Reserve factor percentage (in basis points)
     * @param optimalUtilization Optimal utilization rate (in basis points)
     * @param baseRate Base interest rate (in basis points)
     * @param slopeRate Slope factor for interest rate model
     */
    function initializeLendingPool(
        uint256 reserveFactor,
        uint256 optimalUtilization,
        uint256 baseRate,
        uint256 slopeRate
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(!s.lendingPoolConfig.isInitialized, "Already initialized");
        require(reserveFactor <= Constants.MAX_RESERVE_FACTOR, "Reserve factor too high");
        require(optimalUtilization <= 9000, "Optimal utilization too high");
        require(baseRate <= 1000, "Base rate too high"); // Max 10%
        
        s.lendingPoolConfig.isInitialized = true;
        s.lendingPoolConfig.reserveFactor = reserveFactor;
        s.lendingPoolConfig.optimalUtilization = optimalUtilization;
        s.lendingPoolConfig.baseRate = baseRate;
        s.lendingPoolConfig.slopeRate = slopeRate;
        s.lendingPoolConfig.slopeExcess = Constants.MAX_BORROW_RATE - baseRate; // Calculate max slope
        s.lendingPoolConfig.lastUpdateTimestamp = block.timestamp;
        s.lendingPoolConfig.isPaused = false;
        
        emit Event.LendingPoolInitialized(reserveFactor, optimalUtilization, baseRate, slopeRate);
    }

    /**
 * @notice Add a supported token to the lending pool
 * @param token Token address
 * @param ltv Loan-to-value ratio (in basis points)
 * @param liquidationThreshold Liquidation threshold (in basis points)
 * @param liquidationBonus Liquidation bonus (in basis points)
 */
function addSupportedToken(
    address token,
    uint256 ltv,
    uint256 liquidationThreshold,
    uint256 liquidationBonus,
    bool isLoanable
) external {
    require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
    require(token != address(0), "Invalid token address");
    require(!s.supportedTokens[token], "Token already supported");
    require(ltv <= Constants.MAX_LTV, "LTV too high");
    require(ltv < liquidationThreshold, "LTV must be less than liquidation threshold");
    require(liquidationThreshold >= Constants.MIN_LIQUIDATION_THRESHOLD, "Liquidation threshold too low");
    require(liquidationThreshold <= 9500, "Liquidation threshold too high"); // Max 95%
    require(liquidationBonus >= 10000, "Liquidation bonus too low"); // Min 100%
    
    s.supportedTokens[token] = true;
    s.s_supportedTokens.push(token);
    s.s_isLoanable[token] = isLoanable;
    
    TokenConfig storage tokenConfig = s.tokenConfigs[token];
    tokenConfig.ltv = ltv;
    tokenConfig.liquidationThreshold = liquidationThreshold;
    tokenConfig.liquidationBonus = liquidationBonus;
    tokenConfig.isActive = true;
    tokenConfig.reserveFactor = s.lendingPoolConfig.reserveFactor;
    
    // Initialize rate and reserve data
    ReserveData storage reserve = s.reserves[token];
    reserve.lastUpdateTimestamp = block.timestamp;
    reserve.liquidityIndex = Constants.RAY;
    reserve.borrowIndex = Constants.RAY;
    
    // Create a vault for this token if it doesn't exist
    if (s.vaults[token] == address(0)) {
        string memory tokenSymbol = ERC20(token).symbol();
        string memory vaultName = string(abi.encodePacked("vProtocol ", tokenSymbol));
        string memory vaultSymbol = string(abi.encodePacked("v", tokenSymbol));
        
        VTokenVault vault = new VTokenVault(token, vaultName, vaultSymbol, address(this));
        s.vaults[token] = address(vault);
        s.vaultDeposits[token] = 0;
        
        emit Event.VaultDeployed(token, address(vault), vaultName, vaultSymbol);
    }
    
        emit Event.TokenAdded(token, ltv, liquidationThreshold, liquidationBonus);
    }

    /**
     * @notice Update token configuration
     * @param token Token address
     * @param ltv New LTV
     * @param liquidationThreshold New liquidation threshold
     * @param liquidationBonus New liquidation bonus
     */
    function updateTokenConfiguration(
        address token,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.supportedTokens[token], "Token not supported");
        require(ltv <= Constants.MAX_LTV, "LTV too high"); // Max 80%
        require(ltv < liquidationThreshold, "LTV must be less than liquidation threshold");
        require(liquidationThreshold >= Constants.MIN_LIQUIDATION_THRESHOLD, "Liquidation threshold too low");
        require(liquidationThreshold <= 9500, "Liquidation threshold too high"); // Max 95%
        require(liquidationBonus >= 10000, "Liquidation bonus too low"); // Min 100%
        
        TokenConfig storage tokenConfig = s.tokenConfigs[token];
        tokenConfig.ltv = ltv;
        tokenConfig.liquidationThreshold = liquidationThreshold;
        tokenConfig.liquidationBonus = liquidationBonus;
        
        emit Event.TokenConfigUpdated(token, ltv, liquidationThreshold, liquidationBonus);
    }

    /**
     * @notice Deposit tokens into the lending pool
     * @param token Token to deposit
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(s.tokenData[token].isLoanable, "Token not supported");
        require(!s.isPaused, "Protocol is paused");

        // Update state with latest interest rates
        _updateState(token);

        UserPosition storage position = s.userPositions[msg.sender];
        TokenData storage tokenData = s.tokenData[token];

        // Calculate shares based on current exchange rate
        uint256 shares = _calculatePoolShares(token, amount);
        
        // Update user position
        position.poolDeposits[token] += shares;
        position.lastUpdate = block.timestamp;

        // Update token data
        tokenData.poolLiquidity += amount;
        tokenData.totalDeposits += amount;
        tokenData.lastUpdateTimestamp = block.timestamp;

        // Update user activity for rewards
        UserActivity storage activity = s.userActivities[msg.sender];
        activity.totalLendingAmount += LibGettersImpl._getUsdValue(s, token, amount, LibGettersImpl._getTokenDecimal(token));
        activity.lastLenderRewardUpdate = block.timestamp;

        // Transfer tokens to protocol
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Event.Deposited(msg.sender, token, amount, shares);
    }

    /**
     * @notice Withdraw tokens from the lending pool
     * @param token Token to withdraw
     * @param amount Amount to withdraw (0 for max)
     * @return Amount withdrawn
     */
    function withdraw(address token, uint256 amount) external returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        require(!s.isPaused, "Protocol is paused");

        // Update state with latest interest rates
        _updateState(token);

        UserPosition storage position = s.userPositions[msg.sender];
        TokenData storage tokenData = s.tokenData[token];

        // Calculate shares to burn
        uint256 shares = _calculatePoolShares(token, amount);
        require(position.poolDeposits[token] >= shares, "Insufficient balance");

        // Check if withdrawal would affect health factor
        uint256 healthFactor = LibGettersImpl._healthFactor(s, msg.sender, 0);
        require(healthFactor >= Constants.MIN_HEALTH_FACTOR, "Withdrawal would affect health factor");

        // Update user position
        position.poolDeposits[token] -= shares;
        position.lastUpdate = block.timestamp;

        // Update token data
        tokenData.poolLiquidity -= amount;
        tokenData.totalDeposits -= amount;

        // Transfer tokens to user
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Event.Withdrawn(msg.sender, token, amount, shares);
        
        return amount;
    }

    /**
     * @notice Borrow tokens from the lending pool
     * @param token Token to borrow
     * @param amount Amount to borrow
     */
    function borrow(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(!s.isPaused, "Protocol is paused");
        require(s.tokenData[token].isLoanable, "Token not supported");

        // Update state with latest interest rates
        _updateState(token);

        UserPosition storage position = s.userPositions[msg.sender];
        TokenData storage tokenData = s.tokenData[token];

        // Calculate USD values
        uint8 decimal = LibGettersImpl._getTokenDecimal(token);
        uint256 borrowUsdValue = LibGettersImpl._getUsdValue(s, token, amount, decimal);

        // Check borrower's health factor
        uint256 healthFactor = LibGettersImpl._healthFactor(s, msg.sender, borrowUsdValue);
        require(healthFactor >= Constants.MIN_HEALTH_FACTOR, "Insufficient collateral");

        // Check pool liquidity
        require(tokenData.poolLiquidity >= amount, "Insufficient liquidity");

        // Update user position
        uint256 normalizedDebt = _calculateNormalizedDebt(token, amount);
        position.poolBorrows[token] += normalizedDebt;
        position.lastUpdate = block.timestamp;

        // Update token data
        tokenData.poolLiquidity -= amount;
        tokenData.totalBorrows += amount;

        // Update user activity for rewards
        UserActivity storage activity = s.userActivities[msg.sender];
        activity.totalBorrowingAmount += borrowUsdValue;
        activity.lastBorrowerRewardUpdate = block.timestamp;

        // Transfer tokens to borrower
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Event.Borrowed(msg.sender, token, amount, normalizedDebt);
    }

    /**
     * @notice Repay a loan
     * @param token Token to repay
     * @param amount Amount to repay (0 for max)
     * @return Amount repaid
     */
    function repay(address token, uint256 amount) external returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        require(!s.isPaused, "Protocol is paused");

        // Update state with latest interest rates
        _updateState(token);

        UserPosition storage position = s.userPositions[msg.sender];
        TokenData storage tokenData = s.tokenData[token];

        // Calculate actual debt with accrued interest
        uint256 normalizedDebt = position.poolBorrows[token];
        uint256 actualDebt = _calculateActualDebt(token, normalizedDebt);
        require(actualDebt > 0, "No debt to repay");

        // Cap repayment at actual debt
        uint256 repayAmount = amount > actualDebt ? actualDebt : amount;
        uint256 normalizedRepayment = _calculateNormalizedDebt(token, repayAmount);

        // Update user position
        position.poolBorrows[token] -= normalizedRepayment;
        position.lastUpdate = block.timestamp;

        // Update token data
        tokenData.poolLiquidity += repayAmount;
        tokenData.totalBorrows -= repayAmount;

        // Transfer tokens from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Event.Repaid(msg.sender, token, repayAmount, normalizedRepayment);
        
        return repayAmount;
    }

    /**
     * @notice Deposits collateral to improve borrowing power
     * @param token Collateral token
     * @param amount Amount to deposit
     */
    function depositCollateral(address token, uint256 amount) external {
        require(s.lendingPoolConfig.isInitialized, "Pool not initialized");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");
        require(s.supportedTokens[token], "Token not supported");
        require(s.tokenConfigs[token].isActive, "Token not active");
        require(amount > 0, "Amount must be greater than 0");
        
        // Transfer tokens from user
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update user's collateral balance
        UserPosition storage position = s.userPositions[msg.sender];
        position.collateral[token] += amount;
        position.lastUpdate = block.timestamp;
        
        emit Event.CollateralDeposited(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw collateral if health factor allows
     * @param token Collateral token
     * @param amount Amount to withdraw
     */
    function withdrawCollateral(address token, uint256 amount) external {
        require(s.lendingPoolConfig.isInitialized, "Pool not initialized");
        require(s.supportedTokens[token], "Token not supported");
        
        UserPosition storage position = s.userPositions[msg.sender];
        uint256 currentCollateral = position.collateral[token];
        require(currentCollateral >= amount, "Insufficient collateral");
        
        // Calculate new health factor after withdrawal
        uint256 collateralValueInEth = _valueInEth(token, currentCollateral);
        uint256 withdrawValueInEth = _valueInEth(token, amount);
        uint256 newCollateralValueInEth = collateralValueInEth - withdrawValueInEth;
        
        uint256 currentDebt = _calculateTotalDebt(msg.sender);
        
        // Only check health factor if user has debt
        if (currentDebt > 0) {
            uint256 newHealthFactor = _calculateHealthFactor(newCollateralValueInEth, currentDebt);
            require(newHealthFactor >= Constants.HEALTH_FACTOR_THRESHOLD, "Health factor too low");
        }
        
        // Update user's collateral balance
        position.collateral[token] -= amount;
        
        // Transfer tokens to user
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit Event.CollateralWithdrawn(msg.sender, token, amount);
    }

    /**
     * @notice Execute liquidation of an unhealthy position
     * @param user User to liquidate
     * @param debtToken Debt token
     * @param collateralToken Collateral token to receive
     * @param debtAmount Amount of debt to cover
     * @return Amount of collateral liquidated
     */
    function liquidate(
        address user,
        address debtToken,
        address collateralToken,
        uint256 debtAmount
    ) external returns (uint256) {
        require(s.lendingPoolConfig.isInitialized, "Pool not initialized");
        require(s.supportedTokens[debtToken], "Debt token not supported");
        require(s.supportedTokens[collateralToken], "Collateral token not supported");
        require(user != msg.sender, "Cannot liquidate self");
        require(debtAmount > 0, "Debt amount must be greater than 0");
        
        // Update state with latest interest rates
        _updateState(debtToken);
        
        // Check if position is unhealthy
        uint256 healthFactor = _getUserHealthFactor(user);
        require(healthFactor < Constants.HEALTH_FACTOR_THRESHOLD, "Position not liquidatable");
        
        // Get user's debt
        UserPosition storage position = s.userPositions[user];
        uint256 normalizedDebt = position.poolBorrows[debtToken];
        require(normalizedDebt > 0, "No debt to liquidate");
        
        // Calculate actual debt with accrued interest
        uint256 userDebt = _calculateActualDebt(debtToken, normalizedDebt);
        
        // Check collateral availability
        uint256 userCollateral = position.collateral[collateralToken];
        require(userCollateral > 0, "No collateral to liquidate");
        
        // Limit debt amount to max allowed (50% of debt or total debt if health factor < 50%)
        uint256 maxLiquidatableDebt;
        if (healthFactor < 5000) {
            maxLiquidatableDebt = userDebt;
        } else {
            maxLiquidatableDebt = (userDebt * Constants.LIQUIDATION_CLOSE_FACTOR_DEFAULT) / 10000;
        }
        
        uint256 debtToLiquidate = debtAmount > maxLiquidatableDebt ? maxLiquidatableDebt : debtAmount;
        
        // Calculate collateral to receive (including bonus)
        uint256 collateralPrice = _getPrice(collateralToken);
        uint256 debtTokenPrice = _getPrice(debtToken);
        uint256 liquidationBonus = s.tokenConfigs[collateralToken].liquidationBonus;
        
        uint256 collateralToLiquidate = (debtToLiquidate * debtTokenPrice * liquidationBonus) 
                                        / (collateralPrice * 10000);
        
        // Ensure we're not liquidating more than available
        if (collateralToLiquidate > userCollateral) {
            collateralToLiquidate = userCollateral;
            // Recalculate debt based on available collateral
            debtToLiquidate = (collateralToLiquidate * collateralPrice * 10000) 
                              / (debtTokenPrice * liquidationBonus);
        }
        
        // Calculate normalized debt to reduce
        uint256 normalizedToReduce = (debtToLiquidate * normalizedDebt) / userDebt;
        
        // Transfer debt tokens from liquidator
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), debtToLiquidate);
        
        // Update user's debt
        position.poolBorrows[debtToken] -= normalizedToReduce;
        
        // Update user's collateral
        position.collateral[collateralToken] -= collateralToLiquidate;
        
        // Update reserve data
        ReserveData storage reserve = s.reserves[debtToken];
        reserve.totalBorrows -= debtToLiquidate;
        reserve.normalizedDebt -= normalizedToReduce;
        
        // Update global pool balances
        s.poolBalances.totalBorrows -= _valueInEth(debtToken, debtToLiquidate);
        
        // Update token-specific balances
        s.tokenBalances[debtToken].poolLiquidity += debtToLiquidate;
        
        // Update liquidator activity for rewards
        UserActivity storage activity = s.userActivities[msg.sender];
        activity.totalLiquidationAmount += _valueInEth(debtToken, debtToLiquidate);
        
        // Transfer collateral to liquidator
        IERC20(collateralToken).safeTransfer(msg.sender, collateralToLiquidate);
        
        // Update rates based on new utilization
        _updateRates(debtToken);
        
        emit Event.Liquidated(
            user,
            msg.sender,
            debtToken,
            collateralToken,
            debtToLiquidate,
            collateralToLiquidate
        );
        
        return collateralToLiquidate;
    }

    /**
     * @notice Set emergency pause state
     * @param paused Whether to pause or unpause the pool
     */
    function setPause(bool paused) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        
        s.lendingPoolConfig.isPaused = paused;
        
        emit Event.PoolPauseSet(paused);
    }

    /**
     * @notice Deploy a new ERC4626 vault for a supported token
     * @param token Token address
     * @param name Vault token name
     * @param symbol Vault token symbol
     * @return Address of the deployed vault
     */
    function deployVault(
        address token,
        string memory name,
        string memory symbol
    ) external returns (address) {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.supportedTokens[token], "Token not supported");
        require(s.vaults[token] == address(0), "Vault already deployed");
        
        VTokenVault vault = new VTokenVault(token, name, symbol, address(this));
        s.vaults[token] = address(vault);
        s.vaultDeposits[token] = 0;
        
        emit Event.VaultDeployed(token, address(vault), name, symbol);
        
        return address(vault);
    }

    /**
     * @notice Handle deposits from vault
     * @param token Token address
     * @param assets Amount of assets
     * @param receiver Address receiving benefits
     */
    function depositFromVault(
        address token,
        uint256 assets,
        address receiver
    ) external {
        require(s.vaults[token] == msg.sender, "Only vault can call");
        require(s.lendingPoolConfig.isInitialized, "Pool not initialized");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");
        require(s.supportedTokens[token], "Token not supported");
        
        // Calculate shares (for internal tracking)
        uint256 shares = _calculateDepositShares(token, assets);
        
        // Handle the deposit internally
        _handleDeposit(token, assets, shares, receiver);
        
        emit Event.DepositedFromVault(msg.sender, receiver, token, assets);
    }

    /**
     * @notice Handle withdrawals from vault
     * @param token Token address
     * @param assets Amount of assets
     * @param receiver Address receiving the assets
     */
    function withdrawFromVault(
        address token,
        uint256 assets,
        address receiver
    ) external {
        require(s.vaults[token] == msg.sender, "Only vault can call");
        require(s.lendingPoolConfig.isInitialized, "Pool not initialized");
        require(s.supportedTokens[token], "Token not supported");
        
        // Update state with latest interest rates
        _updateState(token);
        
        // Check available liquidity
        require(assets <= s.tokenBalances[token].poolLiquidity, "Insufficient liquidity");
        require(assets <= s.vaultDeposits[token], "Exceeds vault deposits");
        
        // Calculate shares (for internal tracking)
        uint256 shares = _amountToShares(token, assets);
        
        // Update vault accounting
        s.vaultDeposits[token] -= assets;
        
        // Update reserve data
        ReserveData storage reserve = s.reserves[token];
        reserve.totalDeposits -= assets;
        reserve.totalDepositShares -= shares;
        
        // Update global pool balances for rebalancing
        s.poolBalances.totalDeposits -= _valueInEth(token, assets);
        
        // Update token-specific balances
        s.tokenBalances[token].poolLiquidity -= assets;
        
        // Transfer tokens to receiver
        IERC20(token).safeTransfer(receiver, assets);
        
        emit Event.WithdrawnFromVault(msg.sender, receiver, token, assets);
    }

    /**
     * @notice Get user account data
     * @param user User address
     * @return totalCollateralETH Total collateral in ETH
     * @return totalDebtETH Total debt in ETH
     * @return availableBorrowsETH Available borrowing power in ETH
     * @return currentLiquidationThreshold Current liquidation threshold
     * @return ltv Current loan to value
     * @return healthFactor Current health factor
     */
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        totalCollateralETH = _calculateTotalCollateral(user);
        totalDebtETH = _calculateTotalDebt(user);
        
        (ltv, currentLiquidationThreshold) = _calculateUserLtvAndThreshold(user);
        
        availableBorrowsETH = totalDebtETH >= (totalCollateralETH * ltv) / 10000 ?
            0 : ((totalCollateralETH * ltv) / 10000) - totalDebtETH;
            
        healthFactor = _calculateHealthFactor(totalCollateralETH, totalDebtETH);
    }

    /**
     * @notice Get reserve data for a token
     * @param token Token address
     * @return liquidityRate Current supply APY
     * @return stableBorrowRate Current stable borrow APY
     * @return variableBorrowRate Current variable borrow APY
     * @return liquidityIndex Current liquidity index
     * @return variableBorrowIndex Current variable borrow index
     * @return lastUpdateTimestamp Last update timestamp
     */
    function getReserveData(address token) external view returns (
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    ) {
        ReserveData storage reserve = s.reserves[token];
        RateData storage rates = s.rateData[token];
        
        return (
            rates.depositRate,
            0, // No stable borrowing in this implementation
            rates.borrowRate,
            reserve.liquidityIndex,
            reserve.borrowIndex,
            uint40(reserve.lastUpdateTimestamp)
        );
    }

    /**
     * @notice Get user deposit balance
     * @param user User address
     * @param token Token address
     * @return Deposit balance in underlying tokens
     */
    function getUserDepositBalance(address user, address token) external view returns (uint256) {
        uint256 shares = s.userPositions[user].poolDeposits[token];
        return _sharesToAmount(token, shares);
    }

    /**
     * @notice Get user borrow balance
     * @param user User address
     * @param token Token address
     * @return Borrow balance in underlying tokens
     */
    function getUserBorrowBalance(address user, address token) external view returns (uint256) {
        uint256 normalizedDebt = s.userPositions[user].poolBorrows[token];
        return _calculateActualDebt(token, normalizedDebt);
   }

   /**
    * @notice Check if pool is paused
    * @return True if paused
    */
   function isPoolPaused() external view returns (bool) {
       return s.lendingPoolConfig.isPaused;
   }

   /**
    * @notice Get available liquidity for a token
    * @param token Token address
    * @return Available liquidity
    */
   function getAvailableLiquidity(address token) external view returns (uint256) {
       return s.tokenBalances[token].poolLiquidity;
   }

   /**
    * @notice Get total assets managed by a vault
    * @param token Token address
    * @return Total assets
    */
   function getVaultTotalAssets(address token) external view returns (uint256) {
       return s.vaultDeposits[token];
   }

   /**
    * @notice Get vault address for a token
    * @param token Token address
    * @return Vault address
    */
   function getVault(address token) external view returns (address) {
       return s.vaults[token];
   }
   
   /**
    * @notice Check if user position is liquidatable
    * @param user User address
    * @return True if liquidatable
    */
   function isUserLiquidatable(address user) external view returns (bool) {
       uint256 healthFactor = _getUserHealthFactor(user);
       return healthFactor < Constants.HEALTH_FACTOR_THRESHOLD && _calculateTotalDebt(user) > 0;
   }
   
   /**
    * @notice Get user health factor
    * @param user User address
    * @return Health factor (scaled by 10000, 1.0 = 10000)
    */
   function getUserHealthFactor(address user) external view returns (uint256) {
       return _getUserHealthFactor(user);
   }

   // ==================== Internal functions ====================

   /**
    * @notice Handle deposit logic (used by both direct deposit and vault)
    * @param token Token address
    * @param amount Amount in tokens
    * @param shares Calculated shares
    * @param receiver User receiving credit for this deposit
    */
   function _handleDeposit(
       address token,
       uint256 amount,
       uint256 shares,
       address receiver
   ) internal {
       // Update state with latest interest rates
       _updateState(token);
       
       // Update vault accounting if deposit comes from vault
       if (msg.sender == s.vaults[token]) {
           s.vaultDeposits[token] += amount;
       }
       
       // Update reserve data
       ReserveData storage reserve = s.reserves[token];
       reserve.totalDeposits += amount;
       reserve.totalDepositShares += shares;
       
       // Update global pool balances for rebalancing
       s.poolBalances.totalDeposits += _valueInEth(token, amount);
       
       // Update token-specific balances
       s.tokenBalances[token].poolLiquidity += amount;
       
       // Update user activity for rewards
       UserActivity storage activity = s.userActivities[receiver];
       activity.totalLendingAmount += _valueInEth(token, amount);
       activity.lastLenderRewardUpdate = block.timestamp;
   }

   /**
    * @notice Update interest rates based on utilization
    * @param token Token address
    */
   function _updateRates(address token) internal {
       ReserveData storage reserve = s.reserves[token];
       RateData storage rates = s.rateData[token];
       
       // Calculate utilization rate
       uint256 utilization;
       if (reserve.totalDeposits == 0) {
           utilization = 0;
       } else {
           utilization = (reserve.totalBorrows * 10000) / reserve.totalDeposits;
       }
       
       // Update token utilization for rebalancing
       s.tokenUtilization[token].poolUtilization = utilization;
       
       uint256 optimalUtilization = s.lendingPoolConfig.optimalUtilization;
       
       // Calculate borrow rate based on utilization
       uint256 borrowRate;
       if (utilization <= optimalUtilization) {
           // Linear increase until optimal utilization
           borrowRate = (s.lendingPoolConfig.baseRate * utilization) / optimalUtilization;
       } else {
           // Exponential increase after optimal utilization
           uint256 excessUtilization = utilization - optimalUtilization;
           uint256 slopeExcess = (excessUtilization * s.lendingPoolConfig.slopeExcess) / (10000 - optimalUtilization);
           borrowRate = s.lendingPoolConfig.baseRate + slopeExcess;
       }
       
       // Calculate deposit rate based on borrow rate and reserve factor
       uint256 reserveFactor = s.tokenConfigs[token].reserveFactor;
       uint256 depositRate = (borrowRate * utilization * (10000 - reserveFactor)) / (10000 * 10000);
       
       // Update rates
       rates.borrowRate = borrowRate;
       rates.depositRate = depositRate;
   }

   /**
    * @notice Calculate compounded interest
    * @param rate Interest rate per second (in ray)
    * @param timeDelta Time delta in seconds
    * @return Compounded interest factor (in ray)
    */
   function _calculateCompoundedInterest(
       uint256 rate,
       uint256 timeDelta
   ) internal pure returns (uint256) {
       return _calculateCompoundedInterestCore(rate, timeDelta);
   }
   
   /**
    * @notice Core calculation for compounded interest
    * @param rate Interest rate per second (in ray)
    * @param timeDelta Time delta in seconds
    * @return Compounded interest factor (in ray)
    */
   function _calculateCompoundedInterestCore(
       uint256 rate,
       uint256 timeDelta
   ) internal pure returns (uint256) {
       if (timeDelta == 0) {
           return Constants.RAY;
       }
       
       // For small rates and short time periods, we can use approximation
       // (1 + x)^n ≈ 1 + n*x for small x
       uint256 ratePerSecondPlusOne = rate + Constants.RAY;
       uint256 result = Constants.RAY; // 1.0 in ray
       
       if (timeDelta > 31536000) {
           // More than a year, cap at max
           timeDelta = 31536000;
       }
       
       // Limited binary exponentiation
       uint256 baseRateRay = ratePerSecondPlusOne;
       uint256 expiry = timeDelta;
       
       while (expiry > 0) {
           if (expiry & 1 == 1) {
               result = (result * baseRateRay) / Constants.RAY;
           }
           baseRateRay = (baseRateRay * baseRateRay) / Constants.RAY;
           expiry >>= 1;
       }
       
       return result;
   }

   /**
    * @notice Calculate deposit shares for an amount
    * @param token Token address
    * @param amount Amount in underlying tokens
    * @return Number of shares
    */
   function _calculateDepositShares(address token, uint256 amount) internal view returns (uint256) {
       ReserveData storage reserve = s.reserves[token];
       
       if (reserve.totalDepositShares == 0 || reserve.totalDeposits == 0) {
           return amount;
       }
       
       return (amount * reserve.totalDepositShares) / reserve.totalDeposits;
   }

   /**
    * @notice Convert shares to underlying amount
    * @param token Token address
    * @param shares Number of shares
    * @return Amount in underlying tokens
    */
   function _sharesToAmount(address token, uint256 shares) internal view returns (uint256) {
       ReserveData storage reserve = s.reserves[token];
       
       if (reserve.totalDepositShares == 0 || reserve.totalDeposits == 0) {
           return shares;
       }
       
       return (shares * reserve.totalDeposits) / reserve.totalDepositShares;
   }

   /**
    * @notice Convert amount to shares
    * @param token Token address
    * @param amount Amount in underlying tokens
    * @return Number of shares
    */
   function _amountToShares(address token, uint256 amount) internal view returns (uint256) {
       ReserveData storage reserve = s.reserves[token];
       
       if (reserve.totalDepositShares == 0 || reserve.totalDeposits == 0) {
           return amount;
       }
       
       return (amount * reserve.totalDepositShares) / reserve.totalDeposits;
   }

   /**
    * @notice Calculate user's total collateral value in ETH
    * @param user User address
    * @return Total collateral value in ETH
    */
   function _calculateTotalCollateral(address user) internal view returns (uint256) {
       uint256 totalCollateralETH = 0;
       
       // Iterate through all supported tokens
       address[] memory supportedCollaterals = _getSupportedTokens();
       for (uint256 i = 0; i < supportedCollaterals.length; i++) {
           address token = supportedCollaterals[i];
           uint256 collateralAmount = s.userPositions[user].collateral[token];
           
           if (collateralAmount > 0) {
               totalCollateralETH += _valueInEth(token, collateralAmount);
           }
       }
       
       return totalCollateralETH;
   }

   /**
    * @notice Calculate user's total debt value in ETH
    * @param user User address
    * @return Total debt value in ETH
    */
   function _calculateTotalDebt(address user) internal view returns (uint256) {
       uint256 totalDebtETH = 0;
       
       // Iterate through all supported tokens
       address[] memory supportedTokens = _getSupportedTokens();
       for (uint256 i = 0; i < supportedTokens.length; i++) {
           address token = supportedTokens[i];
           uint256 normalizedDebt = s.userPositions[user].poolBorrows[token];
           
           if (normalizedDebt > 0) {
               uint256 actualDebt = _calculateActualDebt(token, normalizedDebt);
               totalDebtETH += _valueInEth(token, actualDebt);
           }
       }
       
       return totalDebtETH;
   }

   /**
    * @notice Calculate user's borrowing power in ETH
    * @param user User address
    * @return Borrowing power in ETH
    */
   function _calculateBorrowingPower(address user) internal view returns (uint256) {
       (uint256 ltv, ) = _calculateUserLtvAndThreshold(user);
       uint256 totalCollateralETH = _calculateTotalCollateral(user);
       
       return (totalCollateralETH * ltv) / 10000;
   }

   /**
    * @notice Calculate user's LTV and liquidation threshold
    * @param user User address
    * @return ltv Loan-to-value ratio
    * @return liquidationThreshold Liquidation threshold
    */
   function _calculateUserLtvAndThreshold(address user) internal view returns (uint256 ltv, uint256 liquidationThreshold) {
       uint256 totalCollateralETH = 0;
       uint256 weightedLtv = 0;
       uint256 weightedThreshold = 0;
       
       // Iterate through all supported tokens
       address[] memory supportedCollaterals = _getSupportedTokens();
       for (uint256 i = 0; i < supportedCollaterals.length; i++) {
           address token = supportedCollaterals[i];
           uint256 collateralAmount = s.userPositions[user].collateral[token];
           
           if (collateralAmount > 0) {
               uint256 collateralValueETH = _valueInEth(token, collateralAmount);
               totalCollateralETH += collateralValueETH;
               
               TokenConfig storage config = s.tokenConfigs[token];
               weightedLtv += config.ltv * collateralValueETH;
               weightedThreshold += config.liquidationThreshold * collateralValueETH;
           }
       }
       
       if (totalCollateralETH == 0) {
           return (0, 0);
       }
       
       ltv = weightedLtv / totalCollateralETH;
       liquidationThreshold = weightedThreshold / totalCollateralETH;
   }

   /**
    * @notice Calculate health factor
    * @param collateralETH Collateral value in ETH
    * @param debtETH Debt value in ETH
    * @return Health factor (scaled by 10000, 1.0 = 10000)
    */
   function _calculateHealthFactor(uint256 collateralETH, uint256 debtETH) internal view returns (uint256) {
       if (debtETH == 0) {
           return type(uint256).max;
       }
       
       if (collateralETH == 0) {
           return 0;
       }
       
       (, uint256 liquidationThreshold) = _calculateWeightedLtvAndThreshold();
       
       return (collateralETH * liquidationThreshold) / (debtETH * 100);
   }

   /**
    * @notice Calculate weighted LTV and liquidation threshold
    * @return ltv Weighted LTV
    * @return liquidationThreshold Weighted liquidation threshold
    */
   function _calculateWeightedLtvAndThreshold() internal view returns (uint256 ltv, uint256 liquidationThreshold) {
       uint256 totalCollateral = 0;
       uint256 weightedLtv = 0;
       uint256 weightedThreshold = 0;
       
       address[] memory supportedTokens = _getSupportedTokens();
       for (uint256 i = 0; i < supportedTokens.length; i++) {
           address token = supportedTokens[i];
           TokenConfig storage config = s.tokenConfigs[token];
           
           // Consider all tokens equally for this calculation
           weightedLtv += config.ltv;
           weightedThreshold += config.liquidationThreshold;
           totalCollateral++;
       }
       
       if (totalCollateral == 0) {
           return (0, 0);
       }
       
       ltv = weightedLtv / totalCollateral;
       liquidationThreshold = weightedThreshold / totalCollateral;
   }

   /**
    * @notice Get user health factor
    * @param user User address
    * @return Health factor
    */
   function _getUserHealthFactor(address user) internal view returns (uint256) {
       uint256 totalCollateralETH = _calculateTotalCollateral(user);
       uint256 totalDebtETH = _calculateTotalDebt(user);
       
       return _calculateHealthFactor(totalCollateralETH, totalDebtETH);
   }

   /**
    * @notice Get list of supported tokens
    * @return Array of supported token addresses
    */
   function _getSupportedTokens() internal view returns (address[] memory) {
       return s.s_supportedTokens;
   }

   /**
    * @notice Get token value in ETH
    * @param token Token address
    * @param amount Amount in token units
    * @return Value in ETH
    */
   function _valueInEth(address token, uint256 amount) internal view returns (uint256) {
       if (amount == 0) {
           return 0;
       }
       
       uint256 price = _getPrice(token);
       return (amount * price) / 10**_getDecimals(token);
   }

   /**
    * @notice Get token price from oracle
    * @param token Token address
    * @return Price in ETH (with 18 decimals)
    */
   function _getPrice(address token) internal view returns (uint256) {
       // Use price oracle
       address oracle = s.s_priceFeeds[token];
       if (oracle == address(0)) {
           return 10**18; // 1:1 for testing
       }
       
       return IPriceOracle(oracle).getAssetPrice(token);
   }

   /**
    * @notice Get token decimals
    * @param token Token address
    * @return Number of decimals
    */
   function _getDecimals(address token) internal view returns (uint8) {
       return IERC20Metadata(token).decimals();
   }
}

interface IERC20Metadata {
   function decimals() external view returns (uint8);
}

interface IPriceOracle {
   function getAssetPrice(address asset) external view returns (uint256);
}