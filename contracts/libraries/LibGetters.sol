// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {LibAppStorage} from "./LibAppStorage.sol";
import {LibToken, LibPriceOracle} from "./LibShared.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../model/Protocol.sol";
import "../utils/validators/Error.sol";

library LibGettersImpl {
    /**
     * @dev Gets the USD value of a token amount using Chainlink price feeds
     */
    function _getUsdValue(
        LibAppStorage.Layout storage s,
        address token,
        uint256 amount,
        uint8 decimal
    ) internal view returns (uint256) {
        (int256 price, bool isStale) = _getPriceFromOracle(s, token);
        if (isStale) revert Protocol__PriceStale();
        return
            ((uint256(price) * Constants.NEW_PRECISION) * amount) /
            (10 ** decimal);
    }

    /**
     * @dev Gets price data from Chainlink oracle and checks for staleness
     */
    function _getPriceFromOracle(
        LibAppStorage.Layout storage s,
        address token
    ) internal view returns (int256 price, bool isStale) {
        TokenData storage tokenData = s.tokenData[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            tokenData.priceFeed
        );
        uint256 updatedAt;
        (
            ,
            /* uint80 roundId */ price,
            ,
            /* uint256 startedAt */ updatedAt,
            /* uint80 answeredInRound */

        ) = priceFeed.latestRoundData();
        isStale =
            (block.timestamp - updatedAt) > Constants.PRICE_STALE_THRESHOLD;
    }

    /**
     * @dev Converts between token amounts based on their USD values
     */
    function _getConvertValue(
        LibAppStorage.Layout storage s,
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint256 value) {
        uint8 fromDecimal = _getTokenDecimal(from);
        uint8 toDecimal = _getTokenDecimal(to);
        uint256 fromUsd = _getUsdValue(s, from, amount, fromDecimal);
        value = (((fromUsd * 10) / _getUsdValue(s, to, 10, 0)) *
            (10 ** toDecimal));
    }

    /**
     * @dev Gets total collateral value in USD for a user
     */
    function _getAccountCollateralValue(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 totalCollateralValueInUsd) {
        UserPosition storage position = s.userPositions[user];

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            uint256 amount = position.collateral[token];
            if (amount > 0) {
                uint8 decimal = _getTokenDecimal(token);
                totalCollateralValueInUsd += _getUsdValue(
                    s,
                    token,
                    amount,
                    decimal
                );
            }
        }
    }

    /**
     * @dev Gets total available balance value in USD for a user
     */
    function _getAccountAvailableValue(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 totalAvailableValueInUsd) {
        UserPosition storage position = s.userPositions[user];

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];

            // Include both pool deposits and P2P lending
            uint256 poolAmount = position.poolDeposits[token];
            uint256 p2pAmount = position.p2pLentAmount[token];
            uint256 totalAmount = poolAmount + p2pAmount;

            if (totalAmount > 0) {
                uint8 decimal = _getTokenDecimal(token);
                totalAvailableValueInUsd += _getUsdValue(
                    s,
                    token,
                    totalAmount,
                    decimal
                );
            }
        }
    }

    /**
     * @dev Gets loan listing details
     */
    function _getLoanListing(
        LibAppStorage.Layout storage s,
        uint96 listingId
    ) internal view returns (LoanListing memory) {
        LoanListing memory listing = s.loanListings[listingId];
        if (listing.author == address(0)) revert Protocol__IdNotExist();
        return listing;
    }

    /**
     * @dev Gets loan request details
     */
    function _getRequest(
        LibAppStorage.Layout storage s,
        uint96 requestId
    ) internal view returns (Request memory) {
        Request memory request = s.requests[requestId];
        if (request.author == address(0)) revert Protocol__NotOwner();
        return request;
    }

    /**
     * @dev Gets total account info including borrows and collateral
     */
    function _getAccountInfo(
        LibAppStorage.Layout storage s,
        address user
    )
        internal
        view
        returns (uint256 totalBorrowInUsd, uint256 collateralValueInUsd)
    {
        totalBorrowInUsd = _getTotalUserDebtInUSD(s, user);
        collateralValueInUsd = _getAccountCollateralValue(s, user);
    }

    /**
     * @dev Calculates user's health factor
     */
    function _healthFactor(
        LibAppStorage.Layout storage s,
        address user,
        uint256 newBorrowValue
    ) internal view returns (uint256) {
        (
            uint256 totalBorrowInUsd,
            uint256 collateralValueInUsd
        ) = _getAccountInfo(s, user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            Constants.LIQUIDATION_THRESHOLD) / Constants.PERCENTAGE_FACTOR;

        if ((totalBorrowInUsd == 0) && (newBorrowValue == 0))
            return type(uint256).max;

        return
            (collateralAdjustedForThreshold * Constants.PRECISION) /
            (totalBorrowInUsd + newBorrowValue);
    }

    function _getP2pHealthFactor(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 p2pHealthFactor) {
        Request[] memory requests = _getUserActiveRequests(s, user);
        for (uint256 i = 0; i < requests.length; i++) {
            p2pHealthFactor += _calculatePositionHealthFactor(
                s,
                requests[i].requestId
            );
        }
        return p2pHealthFactor / requests.length;
    }

    function _getPoolHealthFactor(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 poolHealthFactor) {
        uint256[] memory loanIds = s.userPoolLoans[user];

        for (uint256 i = 0; i < loanIds.length; i++) {
            if (s.poolLoans[loanIds[i]].status == LoanStatus.ACTIVE) {
                poolHealthFactor += _calculateLoanHealthFactor(
                    s,
                    s.poolLoans[loanIds[i]]
                );
            }
        }
        return poolHealthFactor / loanIds.length;
    }

    /**
     * @notice Calculate health factor for a specific position
     * @param requestId Request ID
     * @return Health factor in basis points
     */
    function _calculatePositionHealthFactor(
        LibAppStorage.Layout storage s,
        uint96 requestId
    ) internal view returns (uint256) {
        Request storage request = s.requests[requestId];

        // Get loan value
        uint8 loanDecimal = LibToken.getDecimals(request.loanRequestAddr);
        uint256 loanUsdValue = LibPriceOracle.getTokenUsdValue(
            s,
            request.loanRequestAddr,
            request.totalRepayment,
            loanDecimal
        );

        // Calculate collateral value
        uint256 totalCollateralValue = 0;
        uint256 weightedLiquidationThreshold = 0;

        for (uint i = 0; i < request.collateralTokens.length; i++) {
            address token = request.collateralTokens[i];
            uint256 collateralAmount = s.s_idToCollateralTokenAmount[requestId][
                token
            ];

            if (collateralAmount > 0) {
                uint8 decimal = LibToken.getDecimals(token);
                uint256 tokenValue = LibPriceOracle.getTokenUsdValue(
                    s,
                    token,
                    collateralAmount,
                    decimal
                );

                totalCollateralValue += tokenValue;
                weightedLiquidationThreshold +=
                    tokenValue *
                    s.tokenConfigs[token].liquidationThreshold;
            }
        }

        if (loanUsdValue == 0) {
            return type(uint256).max;
        }

        if (totalCollateralValue == 0) {
            return 0;
        }

        // Calculate weighted liquidation threshold
        uint256 avgLiquidationThreshold = weightedLiquidationThreshold /
            totalCollateralValue;

        // Calculate health factor
        uint256 adjustedCollateralValue = (totalCollateralValue *
            avgLiquidationThreshold) / 10000;
        return (adjustedCollateralValue * 10000) / loanUsdValue;
    }

    /**
     * @notice Calculate health factor for a specific loan
     * @param loan Loan to calculate for
     * @return Health factor (scaled by 10000)
     */
    function _calculateLoanHealthFactor(
        LibAppStorage.Layout storage s,
        PoolLoan storage loan
    ) internal view returns (uint256) {
        // Calculate current debt with interest
        uint256 accrued = _calculateAccruedInterest(loan);
        uint256 totalDebt = loan.borrowAmount + accrued;

        // Calculate debt value
        uint8 debtDecimals = LibToken.getDecimals(loan.borrowToken);
        uint256 debtValue = LibPriceOracle.getTokenUsdValue(
            s,
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
                uint256 value = LibPriceOracle.getTokenUsdValue(
                    s,
                    token,
                    amount,
                    decimal
                );

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
     * @dev Gets token decimals
     */
    function _getTokenDecimal(address token) internal view returns (uint8) {
        if (token == Constants.NATIVE_TOKEN) return 18;
        return ERC20(token).decimals();
    }

    /**
     * @dev Gets user's loan request
     */
    function _getUserRequest(
        LibAppStorage.Layout storage s,
        address user,
        uint96 requestId
    ) internal view returns (Request memory) {
        Request memory request = s.requests[requestId];
        if (request.author != user) revert Protocol__NotOwner();
        return request;
    }

    /**
     * @dev Gets all active requests for a user
     */
    function _getUserActiveRequests(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (Request[] memory) {
        uint96 requestId = s.requestId;
        uint64 count;

        // Count active requests
        for (uint96 i = 1; i <= requestId; i++) {
            Request memory request = s.requests[i];
            if (request.author == user && request.status == Status.SERVICED) {
                count++;
            }
        }

        // Create array and populate
        Request[] memory requests = new Request[](count);
        uint64 index;

        for (uint96 i = 1; i <= requestId; i++) {
            Request memory request = s.requests[i];
            if (request.author == user && request.status == Status.SERVICED) {
                requests[index] = request;
                index++;
            }
        }

        return requests;
    }

    /**
     * @dev Gets total user debt in USD across both P2P and pool lending
     */
    function _getTotalUserDebtInUSD(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 totalDebtUSD) {
        UserPosition storage position = s.userPositions[user];

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];

            // Get pool debt with accrued interest
            uint256 poolDebt = (position.poolBorrows[token] *
                s.tokenData[token].normalizedPoolDebt) / 1e18;

            // Add P2P debt
            uint256 p2pDebt = position.p2pBorrowedAmount[token];

            uint256 totalDebt = poolDebt + p2pDebt;
            if (totalDebt > 0) {
                uint8 decimal = _getTokenDecimal(token);
                totalDebtUSD += _getUsdValue(s, token, totalDebt, decimal);
            }
        }
    }

    /**
     * @dev Gets all collateral tokens for a user with non-zero balance
     * @param s Storage layout
     * @param user User address
     * @return tokens Array of token addresses
     */
    function _getUserCollateralTokens(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (address[] memory tokens) {
        UserPosition storage position = s.userPositions[user];
        uint256 tokenCount = 0;

        // First pass: count tokens with non-zero collateral
        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            if (position.collateral[token] > 0) {
                tokenCount++;
            }
        }

        // Second pass: create and populate array
        tokens = new address[](tokenCount);
        uint256 index = 0;

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            if (position.collateral[token] > 0) {
                tokens[index] = token;
                index++;
            }
        }

        return tokens;
    }

    /**
     * @dev Gets total loan collected in USD for a user across both P2P and pool lending
     * @param s Storage layout
     * @param user User address
     * @return totalLoanUSD Total loan value in USD
     */
    function _getLoanCollectedInUsd(
        LibAppStorage.Layout storage s,
        address user
    ) internal view returns (uint256 totalLoanUSD) {
        UserPosition storage position = s.userPositions[user];

        for (uint256 i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];

            // Get pool debt with accrued interest
            uint256 poolDebt = (position.poolBorrows[token] *
                s.tokenData[token].normalizedPoolDebt) / 1e18;

            // Add P2P debt
            uint256 p2pDebt = position.p2pBorrowedAmount[token];

            uint256 totalDebt = poolDebt + p2pDebt;
            if (totalDebt > 0) {
                uint8 decimal = _getTokenDecimal(token);
                totalLoanUSD += _getUsdValue(s, token, totalDebt, decimal);
            }
        }
    }

    /**
     * @dev Gets all serviced requests for a specific lender
     * @param s Storage layout
     * @param lender Lender address
     * @return requests Array of serviced requests
     */
    function _getServicedRequestByLender(
        LibAppStorage.Layout storage s,
        address lender
    ) internal view returns (Request[] memory) {
        uint96 requestId = s.requestId;
        uint64 count;

        // First pass: count serviced requests for lender
        for (uint96 i = 1; i <= requestId; i++) {
            Request memory request = s.requests[i];
            if (request.lender == lender && request.status == Status.SERVICED) {
                count++;
            }
        }

        // Second pass: create and populate array
        Request[] memory requests = new Request[](count);
        uint64 index;

        for (uint96 i = 1; i <= requestId; i++) {
            Request memory request = s.requests[i];
            if (request.lender == lender && request.status == Status.SERVICED) {
                requests[index] = request;
                index++;
            }
        }

        return requests;
    }

    /**
     * @dev Gets all requests in the system
     * @param s Storage layout
     * @return requests Array of all requests
     */
    function _getAllRequest(
        LibAppStorage.Layout storage s
    ) internal view returns (Request[] memory) {
        uint96 requestId = s.requestId;

        // Create array of all requests
        Request[] memory requests = new Request[](requestId);

        // Populate array with requests
        for (uint96 i = 1; i <= requestId; i++) {
            requests[i - 1] = s.requests[i];
        }

        return requests;
    }
}
