// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {Constants} from "../utils/constants/Constant.sol";
import "../model/Protocol.sol";

/**
 * @title LibFinance
 * @author Five Protocol
 * @notice Library for financial calculations used across the protocol
 */
library LibFinance {
    using LibPriceOracle for LibAppStorage.Layout;

    /**
     * @notice Calculate health factor for a user
     * @param s Storage layout
     * @param user User address
     * @param newBorrowValue Additional borrow value to include in calculation
     * @return Health factor (scaled by 10000)
     */
    function calculateHealthFactor(
        LibAppStorage.Layout storage s,
        address user,
        uint256 newBorrowValue
    ) internal view returns (uint256) {
        (
            uint256 totalDebtUSD,
            uint256 totalCollateralUSD,

        ) = getUserDebtAndCollateral(s, user);

        // Add new potential borrow to existing debt
        totalDebtUSD += newBorrowValue;

        if (totalDebtUSD == 0) {
            return type(uint256).max;
        }

        // Get weighted liquidation threshold based on collateral composition
        uint256 liquidationThreshold = getWeightedLiquidationThreshold(
            s,
            user,
            totalCollateralUSD
        );

        // Adjusted collateral = collateral * liquidation threshold
        uint256 adjustedCollateral = (totalCollateralUSD *
            liquidationThreshold) / Constants.BASIS_POINTS;

        // Health factor = adjusted collateral / total debt
        return (adjustedCollateral * Constants.PRECISION) / totalDebtUSD;
    }

    /**
     * @notice Check if a user is liquidatable
     * @param s Storage layout
     * @param user User address
     * @return True if the position can be liquidated
     */
    function isLiquidatable(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (bool) {
        uint256 healthFactor = calculateHealthFactor(s, user, 0);
        return
            healthFactor < Constants.HEALTH_FACTOR_THRESHOLD &&
            getUserTotalDebt(s, user) > 0;
    }

    /**
     * @notice Calculate interest for a given period
     * @param principal The principal amount
     * @param rate The interest rate (in basis points)
     * @param timeDelta Time period in seconds
     * @return Accrued interest
     */
    function calculateInterest(
        uint256 principal,
        uint256 rate,
        uint256 timeDelta
    ) internal pure returns (uint256) {
        return
            (principal * rate * timeDelta) /
            (Constants.BASIS_POINTS * Constants.SECONDS_PER_YEAR);
    }

    /**
     * @notice Calculate utilization rate for a token
     * @param deposits Total deposits
     * @param borrows Total borrows
     * @return Utilization rate in basis points (0-10000)
     */
    function calculateUtilization(
        uint256 deposits,
        uint256 borrows
    ) internal pure returns (uint256) {
        if (deposits == 0) {
            return 0;
        }
        return (borrows * Constants.BASIS_POINTS) / deposits;
    }

    /**
     * @notice Calculate borrow interest rate based on utilization
     * @param s Storage layout
     * @param utilization Utilization rate in basis points
     * @return Interest rate in basis points per year
     */
    function calculateBorrowRate(
        LibAppStorage.Layout storage s,
        uint256 utilization
    ) internal view returns (uint256) {
        uint256 optimalUtilization = s.lendingPoolConfig.optimalUtilization;
        uint256 baseRate = s.lendingPoolConfig.baseRate;
        uint256 slopeRate = s.lendingPoolConfig.slopeRate;

        if (utilization <= optimalUtilization) {
            // Linear increase until optimal utilization
            return baseRate + (utilization * slopeRate) / optimalUtilization;
        } else {
            // Exponential increase after optimal utilization
            uint256 excessUtilization = utilization - optimalUtilization;
            uint256 slopeExcess = s.lendingPoolConfig.slopeExcess;
            return
                baseRate +
                slopeRate +
                (excessUtilization * slopeExcess) /
                (Constants.BASIS_POINTS - optimalUtilization);
        }
    }

    /**
     * @notice Calculate deposit rate based on borrow rate and utilization
     * @param borrowRate Borrow interest rate
     * @param utilization Utilization rate
     * @param reserveFactor Reserve factor (protocol fee)
     * @return Deposit interest rate in basis points per year
     */
    function calculateDepositRate(
        uint256 borrowRate,
        uint256 utilization,
        uint256 reserveFactor
    ) internal pure returns (uint256) {
        return
            (borrowRate *
                utilization *
                (Constants.BASIS_POINTS - reserveFactor)) /
            (Constants.BASIS_POINTS * Constants.BASIS_POINTS);
    }

    /**
     * @notice Get total debt for a user across all lending types
     * @param s Storage layout
     * @param user User address
     * @return Total debt in USD
     */
    function getUserTotalDebt(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256) {
        (uint256 totalDebtUSD, , ) = getUserDebtAndCollateral(s, user);
        return totalDebtUSD;
    }

    /**
     * @notice Get user's debt and collateral values
     * @param s Storage layout
     * @param user User address
     * @return totalDebtUSD Total debt in USD
     * @return totalCollateralUSD Total collateral in USD
     * @return weightedLiquidationThreshold Weighted liquidation threshold
     */
    function getUserDebtAndCollateral(
        LibAppStorage.Layout storage s,
        address user
    )
        internal
        view
        returns (
            uint256 totalDebtUSD,
            uint256 totalCollateralUSD,
            uint256 weightedLiquidationThreshold
        )
    {
        UserPosition storage position = s.userPositions[user];
        uint256 thresholdSum = 0;

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            uint8 decimal = LibToken.getDecimals(token);

            // Calculate pool debt with accrued interest
            uint256 poolDebt = (position.poolBorrows[token] *
                s.tokenData[token].normalizedPoolDebt) / 1e18;

            // Add P2P debt
            uint256 p2pDebt = position.p2pBorrowedAmount[token];

            // Total debt for this token
            uint256 totalTokenDebt = poolDebt + p2pDebt;
            if (totalTokenDebt > 0) {
                totalDebtUSD += s.getTokenUsdValue(
                    token,
                    totalTokenDebt,
                    decimal
                );
            }

            // Calculate collateral value
            uint256 collateralAmount = position.collateral[token];
            if (collateralAmount > 0) {
                uint256 collateralUSD = s.getTokenUsdValue(
                    token,
                    collateralAmount,
                    decimal
                );
                totalCollateralUSD += collateralUSD;

                // Add weighted liquidation threshold
                uint256 tokenLiqThreshold = s
                    .tokenConfigs[token]
                    .liquidationThreshold;
                thresholdSum += collateralUSD * tokenLiqThreshold;
            }
        }

        // Calculate weighted liquidation threshold
        if (totalCollateralUSD > 0) {
            weightedLiquidationThreshold = thresholdSum / totalCollateralUSD;
        }

        return (totalDebtUSD, totalCollateralUSD, weightedLiquidationThreshold);
    }

    /**
     * @notice Get weighted liquidation threshold for a user
     * @param s Storage layout
     * @param user User address
     * @param totalCollateralUSD Total collateral value (optional, pass 0 to calculate)
     * @return Weighted liquidation threshold
     */
    function getWeightedLiquidationThreshold(
        LibAppStorage.Layout storage s,
        address user,
        uint256 totalCollateralUSD
    ) internal view returns (uint256) {
        if (totalCollateralUSD == 0) {
            (, totalCollateralUSD, ) = getUserDebtAndCollateral(s, user);
            if (totalCollateralUSD == 0) {
                return 0;
            }
        }

        UserPosition storage position = s.userPositions[user];
        uint256 thresholdSum = 0;

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            uint256 collateralAmount = position.collateral[token];

            if (collateralAmount > 0) {
                uint8 decimal = LibToken.getDecimals(token);
                uint256 collateralUSD = s.getTokenUsdValue(
                    token,
                    collateralAmount,
                    decimal
                );
                uint256 tokenLiqThreshold = s
                    .tokenConfigs[token]
                    .liquidationThreshold;

                thresholdSum += collateralUSD * tokenLiqThreshold;
            }
        }

        return thresholdSum / totalCollateralUSD;
    }

    /**
     * @notice Get utilization rate for a token
     * @param token Token address
     * @return Utilization rate in basis points (0-10000)
     */
    function getUtilizationRate(
        LibAppStorage.Layout storage s,
        address token
    ) internal view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        if (tokenData.totalDeposits == 0) {
            return 0;
        }
        return (tokenData.totalBorrows * 10000) / tokenData.totalDeposits;
    }
}

/**
 * @title LibToken
 * @author Five Protocol
 * @notice Library for token operations and data retrieval
 */
library LibToken {
    /**
     * @notice Get token decimals
     * @param token Token address
     * @return Token decimals
     */
    function getDecimals(address token) internal view returns (uint8) {
        if (token == Constants.NATIVE_TOKEN) {
            return 18;
        }
        return ERC20(token).decimals();
    }

    /**
     * @notice Check if a token is native ETH
     * @param token Token address
     * @return True if the token is the native token
     */
    function isNativeToken(address token) internal pure returns (bool) {
        return token == Constants.NATIVE_TOKEN;
    }

    /**
     * @notice Transfer tokens from contract to a recipient
     * @param token Token address
     * @param recipient Recipient address
     * @param amount Amount to transfer
     */
    function transferTo(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        if (token == Constants.NATIVE_TOKEN) {
            (bool sent, ) = payable(recipient).call{value: amount}("");
            require(sent, "Failed to send native token");
        } else {
            IERC20(token).transfer(recipient, amount);
        }
    }

    /**
     * @notice Transfer tokens from a sender to this contract
     * @param token Token address
     * @param sender Sender address
     * @param amount Amount to transfer
     */
    function transferFrom(
        address token,
        address sender,
        uint256 amount
    ) internal {
        if (token == Constants.NATIVE_TOKEN) {
            require(msg.value >= amount, "Insufficient native token sent");
        } else {
            IERC20(token).transferFrom(sender, address(this), amount);
        }
    }
}

/**
 * @title LibPriceOracle
 * @author Five Protocol
 * @notice Library for price oracle interactions
 */
library LibPriceOracle {
    /**
     * @notice Get USD value of a token amount
     * @param s Storage layout
     * @param token Token address
     * @param amount Token amount
     * @param decimal Token decimal
     * @return Amount in USD
     */
    function getTokenUsdValue(
        LibAppStorage.Layout storage s,
        address token,
        uint256 amount,
        uint8 decimal
    ) internal view returns (uint256) {
        // Get price from oracle
        (int256 price, bool isStale) = getPriceFromOracle(s, token);
        require(!isStale, "Price is stale");

        // Convert to USD
        return (uint256(price) * amount) / (10 ** decimal);
    }

    /**
     * @notice Get price data from Chainlink oracle
     * @param s Storage layout
     * @param token Token address
     * @return price Token price
     * @return isStale Whether the price is stale
     */
    function getPriceFromOracle(
        LibAppStorage.Layout storage s,
        address token
    ) internal view returns (int256 price, bool isStale) {
        address priceFeed = s.tokenData[token].priceFeed;
        require(priceFeed != address(0), "Price feed not set");

        AggregatorV3Interface oracle = AggregatorV3Interface(priceFeed);

        uint256 updatedAt;
        (
            ,
            /* uint80 roundId */ price,
            ,
            /* uint256 startedAt */ updatedAt,
            /* uint80 answeredInRound */

        ) = oracle.latestRoundData();

        isStale =
            (block.timestamp - updatedAt) > Constants.PRICE_STALE_THRESHOLD;

        return (price, isStale);
    }
}
