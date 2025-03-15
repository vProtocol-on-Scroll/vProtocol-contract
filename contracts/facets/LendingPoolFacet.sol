// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibToken, LibFinance} from "../libraries/LibShared.sol";
import {LibPriceOracle} from "../libraries/LibShared.sol";
import {IVTokenVault} from "../interfaces/IVTokenVault.sol";
import {VTokenVault} from "../VTokenVault.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {IWeth} from "../interfaces/IWeth.sol";

/**
 * @title LendingPoolFacet
 * @author Five Protocol
 *
 * @dev This contract manages the lending pool operations using a loan-based approach
 * similar to the P2P system, but with automated rate calculation.
 */
contract LendingPoolFacet {
    using SafeERC20 for IERC20;
    using LibPriceOracle for LibAppStorage.Layout;

    LibAppStorage.Layout internal s;

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
        require(
            reserveFactor <= Constants.MAX_RESERVE_FACTOR,
            "Reserve factor too high"
        );
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

        emit Event.LendingPoolInitialized(
            reserveFactor,
            optimalUtilization,
            baseRate,
            slopeRate
        );
    }

    /**
     * @notice Add a supported token to the lending pool
     * @param token Token address
     * @param ltv Loan-to-value ratio (in basis points)
     * @param liquidationThreshold Liquidation threshold (in basis points)
     * @param liquidationBonus Liquidation bonus (in basis points)
     * @param isLoanable Whether token can be borrowed
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
        require(
            ltv < liquidationThreshold,
            "LTV must be less than liquidation threshold"
        );
        require(
            liquidationThreshold >= Constants.MIN_LIQUIDATION_THRESHOLD,
            "Liquidation threshold too low"
        );
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

        // Initialize token data storage
        TokenData storage tokenData = s.tokenData[token];
        tokenData.isLoanable = isLoanable;
        tokenData.lastUpdateTimestamp = block.timestamp;
        tokenData.normalizedPoolDebt = 1e18; // Initialize at 1.0

        // Initialize rate and reserve data
        ReserveData storage reserve = s.reserves[token];
        reserve.lastUpdateTimestamp = block.timestamp;
        reserve.liquidityIndex = Constants.RAY;
        reserve.borrowIndex = Constants.RAY;

        emit Event.TokenAdded(
            token,
            ltv,
            liquidationThreshold,
            liquidationBonus
        );
    }

    /**
     * @notice Create a lending position with both deposits and borrow in one transaction
     * @param collateralTokens Array of collateral token addresses
     * @param collateralAmounts Array of collateral amounts
     * @param borrowToken Token to borrow
     * @param borrowAmount Amount to borrow (0 for no borrowing)
     * @param useExistingCollateral Whether to use existing collateral
     * @return loanId ID of the created loan (0 if only depositing collateral)
     */
    function createPosition(
        address[] calldata collateralTokens,
        uint256[] calldata collateralAmounts,
        address borrowToken,
        uint256 borrowAmount,
        bool useExistingCollateral
    ) external payable returns (uint256 loanId) {
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");
        require(
            collateralTokens.length == collateralAmounts.length,
            "Array length mismatch"
        );

        // Track total ETH value needed
        uint256 ethNeeded = 0;

        // Handle collateral deposits
        uint256 totalCollateralValue = 0;
        CollateralInfo[] memory collateralInfos = new CollateralInfo[](
            collateralTokens.length
        );

        for (uint i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralAmounts[i];

            require(s.supportedTokens[token], "Collateral token not supported");

            bool isNative = token == Constants.NATIVE_TOKEN;

            if (amount > 0) {
                if (isNative) {
                    ethNeeded += amount;
                } else {
                    // Transfer ERC20 token
                    IERC20(token).safeTransferFrom(
                        msg.sender,
                        address(this),
                        amount
                    );
                }

                // Add collateral to user's position
                s.userPositions[msg.sender].collateral[token] += amount;

                // Calculate collateral value
                uint8 decimal = LibToken.getDecimals(token);
                uint256 value = s.getTokenUsdValue(token, amount, decimal);
                totalCollateralValue += value;

                // Store info for loan creation
                collateralInfos[i] = CollateralInfo({
                    token: token,
                    amount: amount,
                    value: value
                });
            }
        }

        // Check if we need to use existing collateral
        if (useExistingCollateral) {
            for (uint i = 0; i < s.s_supportedTokens.length; i++) {
                address token = s.s_supportedTokens[i];
                if (s.userPositions[msg.sender].collateral[token] > 0) {
                    uint256 existingAmount = s
                        .userPositions[msg.sender]
                        .collateral[token];
                    uint8 decimal = LibToken.getDecimals(token);
                    uint256 value = s.getTokenUsdValue(
                        token,
                        existingAmount,
                        decimal
                    );
                    totalCollateralValue += value;
                }
            }
        }

        // Validate ETH amount if needed
        if (ethNeeded > 0) {
            require(msg.value >= ethNeeded, "Insufficient ETH sent");

            // Refund excess ETH
            if (msg.value > ethNeeded) {
                (bool sent, ) = payable(msg.sender).call{
                    value: msg.value - ethNeeded
                }("");
                require(sent, "ETH refund failed");
            }
        }

        // Handle borrowing if requested
        if (borrowAmount > 0) {
            require(
                s.tokenData[borrowToken].isLoanable,
                "Token not borrowable"
            );

            // Get current interest rate
            _updateState(borrowToken);
            uint256 utilization = LibFinance.getUtilizationRate(s, borrowToken);
            uint256 borrowRate = _calculateBorrowRate(utilization);

            // Check borrowing capacity based on collateral value
            uint256 maxBorrowValue = 0;

            // Calculate max borrow value based on multiple collaterals and their respective LTVs
            for (uint i = 0; i < collateralInfos.length; i++) {
                if (collateralInfos[i].amount > 0) {
                    uint256 ltv = s.tokenConfigs[collateralInfos[i].token].ltv;
                    maxBorrowValue += (collateralInfos[i].value * ltv) / 10000;
                }
            }

            // If using existing collateral, include it in max borrow calculation
            if (useExistingCollateral) {
                for (uint i = 0; i < s.s_supportedTokens.length; i++) {
                    address token = s.s_supportedTokens[i];
                    uint256 existingAmount = s
                        .userPositions[msg.sender]
                        .collateral[token];
                    if (existingAmount > 0) {
                        uint8 decimal = LibToken.getDecimals(token);
                        uint256 value = s.getTokenUsdValue(
                            token,
                            existingAmount,
                            decimal
                        );
                        uint256 ltv = s.tokenConfigs[token].ltv;
                        maxBorrowValue += (value * ltv) / 10000;
                    }
                }
            }

            // Calculate borrow value
            uint8 borrowDecimals = LibToken.getDecimals(borrowToken);
            uint256 borrowValue = s.getTokenUsdValue(
                borrowToken,
                borrowAmount,
                borrowDecimals
            );

            require(
                borrowValue <= maxBorrowValue,
                "Exceeds borrowing capacity"
            );
            require(
                s.tokenData[borrowToken].poolLiquidity >= borrowAmount,
                "Insufficient liquidity"
            );

            // Create a new loan
            s.nextLoanId++;
            loanId = s.nextLoanId;
            // Store the loan details
            PoolLoan storage loan = s.poolLoans[loanId];
            loan.borrower = msg.sender;
            loan.borrowToken = borrowToken;
            loan.borrowAmount = borrowAmount;
            loan.interestRate = borrowRate;
            loan.lastInterestUpdate = block.timestamp;
            loan.status = LoanStatus.ACTIVE;

            // Add multi-collateral support
            for (uint i = 0; i < collateralInfos.length; i++) {
                if (collateralInfos[i].amount > 0) {
                    // Add this collateral to the loan
                    loan.collaterals.push(collateralInfos[i].token);
                    loan.collateralAmounts[
                        collateralInfos[i].token
                    ] = collateralInfos[i].amount;

                    // Lock this collateral for the loan (remove from general collateral)
                    s.userPositions[msg.sender].collateral[
                        collateralInfos[i].token
                    ] -= collateralInfos[i].amount;
                }
            }

            // // If using existing collateral, allocate some to this loan
            if (useExistingCollateral && loan.collaterals.length == 0) {
                uint256 ltv = s.tokenConfigs[loan.borrowToken].ltv;
                uint256 requiredCollateralUSD = (loan.borrowAmount * 10000) /
                    ltv;
                UserPosition storage position = s.userPositions[msg.sender];
                for (uint i = 0; i < s.s_supportedTokens.length; i++) {
                    address token = s.s_supportedTokens[i];
                    uint8 decimal = LibToken.getDecimals(token);

                    // Get user's current balance of this token
                    uint256 collateralAmount = position.collateral[token];
                    uint256 collateralUSD = s.getTokenUsdValue(
                        token,
                        collateralAmount,
                        decimal
                    );

                    // Calculate share of collateral to lock
                    uint256 collateralShare = (collateralUSD * 10000) /
                        totalCollateralValue;
                    uint256 amountToLockUSD = (requiredCollateralUSD *
                        collateralShare) / 10000;

                    // Convert USD to token amount
                    uint256 tokenPricePerUnit = s.getTokenUsdValue(
                        token,
                        10 ** decimal,
                        decimal
                    );
                    uint256 amountToLock = (amountToLockUSD * (10 ** decimal)) /
                        tokenPricePerUnit;

                    // Ensure we don't lock more than available
                    if (amountToLock > collateralAmount) {
                        amountToLock = collateralAmount;
                    }

                    // Lock the collateral
                    position.collateral[token] -= amountToLock;
                    loan.collateralAmounts[token] = amountToLock;
                    loan.collaterals.push(token);
                }
            }

            // Add loan to user's loans
            s.userPoolLoans[msg.sender].push(loanId);

            s.userPositions[msg.sender].poolBorrows[
                borrowToken
            ] += borrowAmount;

            // Update token data
            s.tokenData[borrowToken].poolLiquidity -= borrowAmount;
            s.tokenData[borrowToken].totalBorrows += borrowAmount;
            s.tokenData[borrowToken].lastUpdateTimestamp = block.timestamp;

            // Update user activity for rewards
            s.userActivities[msg.sender].totalBorrowingAmount += borrowValue;
            s.userActivities[msg.sender].lastBorrowerRewardUpdate = block
                .timestamp;

            // Transfer borrowed tokens to user
            if (borrowToken == Constants.NATIVE_TOKEN) {
                (bool sent, ) = payable(msg.sender).call{value: borrowAmount}(
                    ""
                );
                require(sent, "ETH transfer failed");
            } else {
                IERC20(borrowToken).safeTransfer(msg.sender, borrowAmount);
            }

            emit Event.PoolLoanCreated(
                loanId,
                msg.sender,
                collateralTokens,
                borrowToken,
                collateralAmounts,
                borrowAmount,
                borrowRate
            );
        }

        return loanId;
    }

    /**
     * @notice Deposit tokens into the lending pool
     * @param token Token to deposit
     * @param amount Amount to deposit
     * @param asCollateral Whether to mark as collateral
     * @return shares Amount of shares received
     */
    function deposit(
        address token,
        uint256 amount,
        bool asCollateral
    ) external payable returns (uint256 shares) {
        require(amount > 0, "Amount must be greater than 0");
        require(s.supportedTokens[token], "Token not supported");
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Lending pool is paused");

        bool isNativeToken = token == Constants.NATIVE_TOKEN;

        // Handle native token
        if (isNativeToken) {
            require(msg.value >= amount, "Insufficient ETH sent");

            // Refund excess ETH
            if (msg.value > amount) {
                (bool sent, ) = payable(msg.sender).call{
                    value: msg.value - amount
                }("");
                require(sent, "ETH refund failed");
            }
        } else {
            // Transfer tokens from user
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update state with latest interest rates
        _updateState(token);

        // Calculate shares based on current exchange rate
        shares = _calculatePoolShares(token, amount);

        // Update user position based on intended use
        if (asCollateral) {
            s.userPositions[msg.sender].collateral[token] += amount;
        } else {
            s.userPositions[msg.sender].poolDeposits[token] += shares;
        }

        IVTokenVault(s.vaults[token]).mintFor(msg.sender, shares);

        s.userPositions[msg.sender].lastUpdate = block.timestamp;

        // Update token data
        s.tokenData[token].poolLiquidity += amount;
        s.tokenData[token].totalDeposits += amount;
        s.tokenData[token].lastUpdateTimestamp = block.timestamp;

        // Update user activity for rewards
        s.userActivities[msg.sender].totalLendingAmount += s.getTokenUsdValue(
            token,
            amount,
            LibToken.getDecimals(token)
        );
        s.userActivities[msg.sender].lastLenderRewardUpdate = block.timestamp;

        emit Event.Deposited(msg.sender, token, amount, shares);

        return shares;
    }

    /**
     * @notice Toggle whether deposits are used as collateral
     * @param token Token address
     * @param amount Amount to toggle
     * @param asCollateral Whether to mark as collateral or not
     * @return success Whether the operation was successful
     */
    function toggleCollateral(
        address token,
        uint256 amount,
        bool asCollateral
    ) external returns (bool success) {
        require(amount > 0, "Amount must be greater than 0");
        require(s.supportedTokens[token], "Token not supported");
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");

        if (asCollateral) {
            // Check if user has enough deposits
            uint256 shares = _calculatePoolShares(token, amount);
            require(
                s.userPositions[msg.sender].poolDeposits[token] >= shares,
                "Insufficient deposit balance"
            );

            // Update positions
            s.userPositions[msg.sender].poolDeposits[token] -= shares;
            s.userPositions[msg.sender].collateral[token] += amount;
        } else {
            // Check if user has enough collateral
            require(
                s.userPositions[msg.sender].collateral[token] >= amount,
                "Insufficient collateral balance"
            );

            // Calculate if removing collateral would affect health of any loans
            bool safeToRemove = _checkCollateralRemovalSafety(
                msg.sender,
                token,
                amount
            );
            require(safeToRemove, "Collateral needed for existing loans");

            // Update positions
            s.userPositions[msg.sender].collateral[token] -= amount;
            uint256 shares = _calculatePoolShares(token, amount);
            s.userPositions[msg.sender].poolDeposits[token] += shares;
        }

        s.userPositions[msg.sender].lastUpdate = block.timestamp;

        emit Event.CollateralToggled(msg.sender, token, amount, asCollateral);

        return true;
    }

    /**
     * @notice Withdraw tokens from the lending pool
     * @param token Token to withdraw
     * @param amount Amount to withdraw (0 for max)
     * @param fromVault Whether to redeem vault tokens
     * @return withdrawn Amount withdrawn
     */
    function withdraw(
        address token,
        uint256 amount,
        bool fromVault
    ) external returns (uint256 withdrawn) {
        require(amount > 0, "Amount must be greater than 0");
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");

        // Withdraw from deposits
        uint256 shares = _calculatePoolShares(token, amount);

        // Update state with latest interest rates
        _updateState(token);

        if (fromVault) {
            // Withdraw from vault
            address vaultAddress = s.vaults[token];
            require(vaultAddress != address(0), "No vault for this token");

            // Get vault token balance
            IVTokenVault vault = IVTokenVault(vaultAddress);
            uint256 vaultTokens = IERC20(vaultAddress).balanceOf(msg.sender);
            require(vaultTokens > 0, "No vault tokens");

            // Calculate assets to withdraw
            uint256 assetsToWithdraw = amount == 0
                ? vault.maxWithdraw(msg.sender)
                : amount;

            // Withdraw from vault
            withdrawn = vault.redeem(assetsToWithdraw, msg.sender, msg.sender);

            // No need to update protocol state as the vault will call notifyVaultWithdrawal
        } else {
            UserPosition storage position = s.userPositions[msg.sender];

            require(
                position.poolDeposits[token] >= shares,
                "Insufficient deposit balance"
            );

            // Update position
            position.poolDeposits[token] -= shares;
            IVTokenVault(s.vaults[token]).burnFor(msg.sender, shares);
            withdrawn = amount;

            position.lastUpdate = block.timestamp;

            // Update token data
            s.tokenData[token].poolLiquidity -= withdrawn;
            s.tokenData[token].totalDeposits -= withdrawn;

            // Transfer tokens to user
            if (token == Constants.NATIVE_TOKEN) {
                (bool sent, ) = payable(msg.sender).call{value: withdrawn}("");
                require(sent, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(msg.sender, withdrawn);
            }
        }

        emit Event.Withdrawn(msg.sender, token, withdrawn, 0);

        return withdrawn;
    }

    /**
     * @notice Repay a specific loan
     * @param loanId ID of the loan to repay
     * @param amount Amount to repay (0 for full repayment)
     * @return repaid Amount repaid
     */
    function repay(
        uint256 loanId,
        uint256 amount
    ) external payable returns (uint256 repaid) {
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");
        require(loanId <= s.nextLoanId, "Invalid loan ID");

        PoolLoan storage loan = s.poolLoans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");

        // Calculate accrued interest
        uint256 accrued = _calculateAccruedInterest(loan);
        uint256 totalDue = loan.borrowAmount + accrued;

        bool isNativeToken = loan.borrowToken == Constants.NATIVE_TOKEN;

        // Determine repayment amount
        if (amount == 0 || amount > totalDue) {
            repaid = totalDue;
        } else {
            repaid = amount;
        }

        // Handle token transfer
        if (isNativeToken) {
            require(msg.value >= repaid, "Insufficient ETH sent");

            // Refund excess ETH
            if (msg.value > repaid) {
                (bool sent, ) = payable(msg.sender).call{
                    value: msg.value - repaid
                }("");
                require(sent, "ETH refund failed");
            }
        } else {
            IERC20(loan.borrowToken).safeTransferFrom(
                msg.sender,
                address(this),
                repaid
            );
        }

        // Update loan
        if (repaid == totalDue) {
            // Full repayment - return collateral and close loan
            loan.status = LoanStatus.REPAID;

            // Return each collateral token to user
            for (uint i = 0; i < loan.collaterals.length; i++) {
                address collateralToken = loan.collaterals[i];
                uint256 collateralAmount = loan.collateralAmounts[
                    collateralToken
                ];

                if (collateralAmount > 0) {
                    s.userPositions[loan.borrower].collateral[
                        collateralToken
                    ] += collateralAmount;
                    loan.collateralAmounts[collateralToken] = 0;
                }
            }

            s.userPositions[msg.sender].poolBorrows[loan.borrowToken] -= loan
                .borrowAmount;
        } else {
            // Partial repayment - reduce principal
            uint256 interestPortion = repaid > accrued ? accrued : repaid;
            uint256 principalPortion = repaid - interestPortion;

            loan.borrowAmount -= principalPortion;
            loan.lastInterestUpdate = block.timestamp;
        }

        // Update token data
        s.tokenData[loan.borrowToken].poolLiquidity += repaid;
        s.tokenData[loan.borrowToken].totalBorrows -= (repaid - accrued);

        emit Event.PoolLoanRepaid(
            loanId,
            msg.sender,
            repaid,
            loan.status == LoanStatus.REPAID
        );

        return repaid;
    }

    /**
     * @notice Liquidate a specific loan
     * @param loanId ID of the loan to liquidate
     * @return liquidated Amount of collateral liquidated
     */
    function liquidateLoan(
        uint256 loanId
    ) external returns (uint256 liquidated) {
        require(!s.isPaused, "Protocol is paused");
        require(!s.lendingPoolConfig.isPaused, "Pool is paused");
        require(loanId <= s.nextLoanId, "Invalid loan ID");

        PoolLoan storage loan = s.poolLoans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");

        // Calculate current loan health
        bool isLiquidatable = _isLoanLiquidatable(loanId);
        require(isLiquidatable, "Loan not liquidatable");

        // Calculate debt with accrued interest
        uint256 accrued = _calculateAccruedInterest(loan);
        uint256 totalDebt = loan.borrowAmount + accrued;
        uint256 debtValue = 0;

        // Calculate debt value in USD
        uint8 debtDecimals = LibToken.getDecimals(loan.borrowToken);
        debtValue = s.getTokenUsdValue(
            loan.borrowToken,
            totalDebt,
            debtDecimals
        );

        // Transfer debt tokens from liquidator
        IERC20(loan.borrowToken).safeTransferFrom(
            msg.sender,
            address(this),
            totalDebt
        );

        // Calculate collateral distribution for liquidator
        liquidated = 0;
        uint256 collateralValue = 0;
        uint256[] memory collateralValues = new uint256[](
            loan.collaterals.length
        );

        // Calculate total collateral value
        for (uint i = 0; i < loan.collaterals.length; i++) {
            address token = loan.collaterals[i];
            uint256 amount = loan.collateralAmounts[token];
            uint8 decimal = LibToken.getDecimals(token);
            uint256 value = s.getTokenUsdValue(token, amount, decimal);

            collateralValues[i] = value;
            collateralValue += value;
        }

        // Mark loan as liquidated
        loan.status = LoanStatus.LIQUIDATED;

        // Update token data for debt token
        s.tokenData[loan.borrowToken].poolLiquidity += totalDebt;
        s.tokenData[loan.borrowToken].totalBorrows -= loan.borrowAmount;

        // Distribute collateral to liquidator with bonus
        for (uint i = 0; i < loan.collaterals.length; i++) {
            address token = loan.collaterals[i];
            uint256 amount = loan.collateralAmounts[token];

            if (amount > 0) {
                // Calculate share of debt this collateral covers
                uint256 collateralShare = (collateralValues[i] * 10000) /
                    collateralValue;
                uint256 debtCovered = (debtValue * collateralShare) / 10000;

                // Apply liquidation bonus
                uint256 liquidationBonus = s
                    .tokenConfigs[token]
                    .liquidationBonus;
                uint256 tokenValue = s.getTokenUsdValue(
                    token,
                    1e18,
                    LibToken.getDecimals(token)
                );

                // Calculate amount to give liquidator including bonus
                uint256 liquidatorAmount = (debtCovered *
                    liquidationBonus *
                    1e18) / (10000 * tokenValue);

                // Cap at actual collateral amount
                if (liquidatorAmount > amount) {
                    liquidatorAmount = amount;
                }

                // Transfer to liquidator
                if (token == Constants.NATIVE_TOKEN) {
                    (bool sent, ) = payable(msg.sender).call{
                        value: liquidatorAmount
                    }("");
                    require(sent, "ETH transfer failed");
                } else {
                    IERC20(token).safeTransfer(msg.sender, liquidatorAmount);
                }

                liquidated += liquidatorAmount;

                // Return any remaining collateral to borrower
                uint256 remaining = amount - liquidatorAmount;
                if (remaining > 0) {
                    s.userPositions[loan.borrower].collateral[
                        token
                    ] += remaining;
                }

                // Clear loan collateral
                loan.collateralAmounts[token] = 0;
            }
        }

        // Update liquidator's stats for rewards
        s.userActivities[msg.sender].totalLiquidationAmount += debtValue;

        emit Event.PoolLoanLiquidated(
            loanId,
            loan.borrower,
            msg.sender,
            loan.borrowToken,
            loan.collaterals,
            totalDebt,
            liquidated
        );

        return liquidated;
    }

    /**
     * @notice Check if a specific loan is liquidatable
     * @param loanId Loan ID to check
     * @return Whether the loan can be liquidated
     */
    function isLoanLiquidatable(uint256 loanId) external view returns (bool) {
        return _isLoanLiquidatable(loanId);
    }

    /**
     * @notice Get details of a specific loan
     * @param loanId Loan ID to query
     * @return loanDetails The loan details
     * @return currentDebt The current debt including accrued interest
     * @return healthFactor The current health factor
     */
    function getLoanDetails(
        uint256 loanId
    )
        external
        view
        returns (
            PoolLoanDetails memory loanDetails,
            uint256 currentDebt,
            uint256 healthFactor
        )
    {
        require(loanId <= s.nextLoanId, "Invalid loan ID");
        PoolLoan storage loan = s.poolLoans[loanId];
        loanDetails.borrower = loan.borrower;
        loanDetails.borrowToken = loan.borrowToken;
        loanDetails.borrowAmount = loan.borrowAmount;
        loanDetails.interestRate = loan.interestRate;
        loanDetails.lastInterestUpdate = loan.lastInterestUpdate;
        loanDetails.status = loan.status;
        loanDetails.collaterals = loan.collaterals;

        if (loan.status == LoanStatus.ACTIVE) {
            uint256 accrued = _calculateAccruedInterest(loan);
            currentDebt = loan.borrowAmount + accrued;
            healthFactor = _calculateLoanHealthFactor(loan);
        } else {
            currentDebt = 0;
            healthFactor = type(uint256).max;
        }

        return (loanDetails, currentDebt, healthFactor);
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
     * @notice Callback from VToken vault when deposit occurs
     * @param asset Token deposited
     * @param amount Amount deposited
     * @param depositor Address of the depositor
     * @param transferAssets Whether to transfer assets (false if already done)
     */
    function notifyVaultDeposit(
        address asset,
        uint256 amount,
        address depositor,
        bool transferAssets
    ) external {
        // Verify caller is a valid vault
        require(s.vaults[asset] == msg.sender, "Only vault can call");

        // Transfer assets if requested (if not already transferred)
        if (transferAssets) {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }

        if (asset == Constants.NATIVE_TOKEN) {
            IWeth(Constants.WETH).withdraw(amount);
        }

        // Update user positions
        uint256 shares = _calculatePoolShares(asset, amount);
        s.userPositions[depositor].poolDeposits[asset] += shares;

        // Update vault deposits
        s.vaultDeposits[asset] += amount;

        // Update token data
        s.tokenData[asset].poolLiquidity += amount;
        s.tokenData[asset].totalDeposits += amount;

        emit Event.VaultDeposited(asset, depositor, amount);
    }

    /**
     * @notice Callback from VToken vault when withdrawal occurs
     * @param asset Token withdrawn
     * @param amount Amount withdrawn
     * @param receiver Address receiving the tokens
     * @param transferAssets Whether to transfer assets
     */
    function notifyVaultWithdrawal(
        address asset,
        uint256 amount,
        address receiver,
        bool transferAssets
    ) external {
        // Verify caller is a valid vault
        require(s.vaults[asset] == msg.sender, "Only vault can call");

        // Ensure sufficient liquidity
        require(
            s.tokenData[asset].poolLiquidity >= amount,
            "Insufficient liquidity"
        );

        // Ensure user has enough shares to withdraw
        require(
            s.userPositions[receiver].poolDeposits[asset] >= amount,
            "Insufficient shares"
        );

        // Update user positions
        uint256 shares = _calculatePoolShares(asset, amount);
        s.userPositions[receiver].poolDeposits[asset] -= shares;

        // Update vault deposits
        s.vaultDeposits[asset] -= amount;

        // Update token data
        s.tokenData[asset].poolLiquidity -= amount;
        s.tokenData[asset].totalDeposits -= amount;

        // Transfer assets if requested
        if (transferAssets) {
            IERC20(asset).safeTransfer(receiver, amount);
        }

        emit Event.VaultWithdrawn(asset, receiver, amount);
    }

    function notifyVaultTransfer(
        address asset,
        uint256 amount,
        address sender,
        address receiver
    ) external returns (bool) {
        require(s.vaults[asset] == msg.sender, "Only vault can call");
        require(
            s.tokenData[asset].poolLiquidity >= amount,
            "Insufficient liquidity"
        );
        require(sender != receiver, "Sender and receiver are the same");
        require(
            sender != address(0) && receiver != address(0),
            "Invalid sender or receiver"
        );

        // Check if sender has enough shares to transfer and are not collateral
        if (s.userPositions[sender].poolDeposits[asset] < amount) {
            revert("Insufficient shares");
        }

        // Update user positions
        s.userPositions[sender].poolDeposits[asset] -= amount;
        s.userPositions[receiver].poolDeposits[asset] += amount;

        return true;
    }

    /**
     * @notice Deploy a new VToken vault for a supported token
     * @param token Token address
     * @param name Vault token name
     * @param symbol Vault token symbol
     * @return vaultAddress Address of the deployed vault
     */
    function deployVault(
        address token,
        string memory name,
        string memory symbol
    ) external returns (address vaultAddress) {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.supportedTokens[token], "Token not supported");
        require(s.vaults[token] == address(0), "Vault already deployed");

        // Deploy new vault
        VTokenVault vault = new VTokenVault(token, name, symbol, address(this));

        // Store vault address
        s.vaults[token] = address(vault);
        s.vaultDeposits[token] = 0;

        emit Event.VaultDeployed(token, address(vault), name, symbol);

        return address(vault);
    }

    // Internal helper functions

    /**
     * @notice Calculate if a loan is liquidatable
     * @param loanId Loan ID to check
     * @return Whether the loan can be liquidated
     */
    function _isLoanLiquidatable(uint256 loanId) internal view returns (bool) {
        if (loanId > s.nextLoanId) return false;

        PoolLoan storage loan = s.poolLoans[loanId];
        if (loan.status != LoanStatus.ACTIVE) return false;

        uint256 healthFactor = _calculateLoanHealthFactor(loan);
        return healthFactor < Constants.HEALTH_FACTOR_THRESHOLD;
    }

    /**
     * @notice Calculate health factor for a specific loan
     * @param loan Loan to calculate for
     * @return Health factor (scaled by 10000)
     */
    function _calculateLoanHealthFactor(
        PoolLoan storage loan
    ) internal view returns (uint256) {
        // Calculate current debt with interest
        uint256 accrued = _calculateAccruedInterest(loan);
        uint256 totalDebt = loan.borrowAmount + accrued;

        // Calculate debt value
        uint8 debtDecimals = LibToken.getDecimals(loan.borrowToken);
        uint256 debtValue = s.getTokenUsdValue(
            loan.borrowToken,
            totalDebt,
            debtDecimals
        );

        if (debtValue == 0) {
            return type(uint256).max;
        }

        // Calculate total collateral value with liquidation thresholds
        uint256 adjustedCollateralValue = 0;

        for (uint i = 0; i < loan.collaterals.length; i++) {
            address token = loan.collaterals[i];
            uint256 amount = loan.collateralAmounts[token];

            if (amount > 0) {
                uint8 decimal = LibToken.getDecimals(token);
                uint256 value = s.getTokenUsdValue(token, amount, decimal);

                // Apply liquidation threshold
                uint256 liquidationThreshold = s
                    .tokenConfigs[token]
                    .liquidationThreshold;
                adjustedCollateralValue +=
                    (value * liquidationThreshold) /
                    10000;
            }
        }

        // Calculate health factor
        return (adjustedCollateralValue * 10000) / debtValue;
    }

    /**
     * @notice Calculate accrued interest for a loan
     * @param loan Loan to calculate for
     * @return Accrued interest
     */
    function _calculateAccruedInterest(
        PoolLoan storage loan
    ) internal view returns (uint256) {
        if (loan.borrowAmount == 0) return 0;

        uint256 timeElapsed = block.timestamp - loan.lastInterestUpdate;
        if (timeElapsed == 0) return 0;

        // Calculate interest: principal * rate * time
        return
            (loan.borrowAmount * loan.interestRate * timeElapsed) /
            (10000 * Constants.SECONDS_PER_YEAR);
    }

    /**
     * @notice Check if collateral removal is safe for a user's loans
     * @param user User address
     * @param token Collateral token
     * @param {uint256} Amount to remove
     * @return Whether removal is safe
     */
    function _checkCollateralRemovalSafety(
        address user,
        address token,
        uint256 /**amount */
    ) internal view returns (bool) {
        // Get user's loans
        uint256[] storage userLoans = s.userPoolLoans[user];

        // No loans means it's safe to remove
        if (userLoans.length == 0) return true;

        // Check each loan for this collateral token
        for (uint i = 0; i < userLoans.length; i++) {
            PoolLoan storage loan = s.poolLoans[userLoans[i]];

            // Skip non-active loans
            if (loan.status != LoanStatus.ACTIVE) {
                continue;
            }

            // Check if this loan uses the token as collateral
            for (uint j = 0; j < loan.collaterals.length; j++) {
                if (
                    loan.collaterals[j] == token &&
                    loan.collateralAmounts[token] > 0
                ) {
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * @notice Calculate pool shares for an amount
     * @param token Token address
     * @param amount Amount in tokens
     * @return Shares amount
     */
    function _calculatePoolShares(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        if (tokenData.totalDeposits == 0) {
            return amount;
        }
        return (amount * 1e18) / tokenData.normalizedPoolDebt;
    }

    /**
     * @notice Calculate borrow rate based on utilization
     * @param utilization Utilization rate in basis points (0-10000)
     * @return Borrow rate in basis points
     */
    function _calculateBorrowRate(
        uint256 utilization
    ) internal view returns (uint256) {
        if (utilization <= s.lendingPoolConfig.optimalUtilization) {
            return
                s.lendingPoolConfig.baseRate +
                (utilization * s.lendingPoolConfig.slopeRate) /
                s.lendingPoolConfig.optimalUtilization;
        } else {
            uint256 excessUtilization = utilization -
                s.lendingPoolConfig.optimalUtilization;
            return
                s.lendingPoolConfig.baseRate +
                s.lendingPoolConfig.slopeRate +
                (excessUtilization * s.lendingPoolConfig.slopeExcess) /
                (10000 - s.lendingPoolConfig.optimalUtilization);
        }
    }

    /**
     * @notice Update state for a token
     * @param token Token address
     */
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
        uint256 utilization = LibFinance.getUtilizationRate(s, token);

        // Calculate interest rates
        uint256 borrowRate = _calculateBorrowRate(utilization);

        // Update normalized debt
        uint256 interestFactor = (borrowRate * timeDelta) /
            Constants.SECONDS_PER_YEAR;
        tokenData.normalizedPoolDebt =
            (tokenData.normalizedPoolDebt * (10000 + interestFactor)) /
            10000;

        tokenData.lastUpdateTimestamp = block.timestamp;

        // Update token utilization for rebalancing
        s.tokenUtilization[token].poolUtilization = utilization;
    }
}
