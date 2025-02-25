// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {LibAppStorage} from "./LibAppStorage.sol";
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
        return ((uint256(price) * Constants.NEW_PRECISION) * amount) / (10 ** decimal);
    }

    /**
     * @dev Gets price data from Chainlink oracle and checks for staleness
     */
    function _getPriceFromOracle(
        LibAppStorage.Layout storage s,
        address token
    ) internal view returns (int256 price, bool isStale) {
        TokenData storage tokenData = s.tokenData[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenData.priceFeed);
        uint256 updatedAt;
        (
            /* uint80 roundId */,
            price,
            /* uint256 startedAt */,
            updatedAt,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();
        isStale = (block.timestamp - updatedAt) > Constants.PRICE_STALE_THRESHOLD;
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
        value = (((fromUsd * 10) / _getUsdValue(s, to, 10, 0)) * (10 ** toDecimal));
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
                totalCollateralValueInUsd += _getUsdValue(s, token, amount, decimal);
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
                totalAvailableValueInUsd += _getUsdValue(s, token, totalAmount, decimal);
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
    ) internal view returns (uint256 totalBorrowInUsd, uint256 collateralValueInUsd) {
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
        (uint256 totalBorrowInUsd, uint256 collateralValueInUsd) = _getAccountInfo(s, user);
        
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            Constants.LIQUIDATION_THRESHOLD) / Constants.PERCENTAGE_FACTOR;

        if ((totalBorrowInUsd == 0) && (newBorrowValue == 0))
            return type(uint256).max;

        return (collateralAdjustedForThreshold * Constants.PRECISION) /
            (totalBorrowInUsd + newBorrowValue);
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
            uint256 poolDebt = (position.poolBorrows[token] * s.tokenData[token].normalizedPoolDebt) / 1e18;
            
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
            uint256 poolDebt = (position.poolBorrows[token] * s.tokenData[token].normalizedPoolDebt) / 1e18;
            
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
