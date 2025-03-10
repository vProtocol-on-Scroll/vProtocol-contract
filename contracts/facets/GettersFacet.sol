// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibGettersImpl} from "../libraries/LibGetters.sol";
import {Request} from "../model/Protocol.sol";

/**
 * @title LendingPoolFacet
 * @author Five Protocol
 *
 * @dev This contract manages the lending pool operations using a loan-based approach
 * similar to the P2P system, but with automated rate calculation.
 */
contract GettersFacet {
    LibAppStorage.Layout internal s;

    /**
     * @dev Gets the USD value of a token amount using Chainlink price feeds
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        return
            LibGettersImpl._getUsdValue(
                s,
                token,
                amount,
                LibGettersImpl._getTokenDecimal(token)
            );
    }
    /**
     * @dev Gets price data from Chainlink oracle and checks for staleness
     */
    function getPriceFromOracle(
        address token
    ) external view returns (int256 price, bool isStale) {
        return LibGettersImpl._getPriceFromOracle(s, token);
    }

    /**
     * @dev Converts between token amounts based on their USD values
     */
    function getConvertValue(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint256) {
        return LibGettersImpl._getConvertValue(s, from, to, amount);
    }

    /**
     * @dev Gets total collateral value in USD for a user
     */
    function getAccountCollateralValue(
        address user
    ) external view returns (uint256) {
        return LibGettersImpl._getAccountCollateralValue(s, user);
    }

    /**
     * @dev Gets total available balance value in USD for a user
     */
    function getAccountAvailableValue(
        address user
    ) external view returns (uint256) {
        return LibGettersImpl._getAccountAvailableValue(s, user);
    }

    /**
     * @dev Gets total account info including borrows and collateral
     */
    function getAccountInfo(
        address user
    )
        external
        view
        returns (uint256 totalBorrowInUsd, uint256 collateralValueInUsd)
    {
        return LibGettersImpl._getAccountInfo(s, user);
    }

    /**
     * @dev Calculates user's health factor
     */
    function healthFactor(
        address user,
        uint256 newBorrowValue
    ) external view returns (uint256) {
        return LibGettersImpl._healthFactor(s, user, newBorrowValue);
    }

    /**
     * @dev Gets user's loan request
     */
    function getUserRequest(
        address user,
        uint96 requestId
    ) external view returns (Request memory) {
        return LibGettersImpl._getUserRequest(s, user, requestId);
    }

    /**
     * @dev Gets all active requests for a user
     */
    function getUserActiveRequests(
        address user
    ) external view returns (Request[] memory) {
        return LibGettersImpl._getUserActiveRequests(s, user);
    }

    /**
     * @dev Gets total user debt in USD across both P2P and pool lending
     */
    function getTotalUserDebtInUSD(
        address user
    ) external view returns (uint256) {
        return LibGettersImpl._getTotalUserDebtInUSD(s, user);
    }

    /**
     * @dev Gets all collateral tokens for a user with non-zero balance
     * @param user User address
     * @return tokens Array of token addresses
     */
    function getUserCollateralTokens(
        address user
    ) external view returns (address[] memory) {
        return LibGettersImpl._getUserCollateralTokens(s, user);
    }

    /**
     * @dev Gets total loan collected in USD for a user across both P2P and pool lending
     * @param user User address
     * @return totalLoanUSD Total loan value in USD
     */
    function getLoanCollectedInUsd(
        address user
    ) external view returns (uint256) {
        return LibGettersImpl._getLoanCollectedInUsd(s, user);
    }

    /**
     * @dev Gets all serviced requests for a specific lender
     * @param lender Lender address
     * @return requests Array of serviced requests
     */
    function getServicedRequestByLender(
        address lender
    ) external view returns (Request[] memory) {
        return LibGettersImpl._getServicedRequestByLender(s, lender);
    }

    /**
     * @dev Gets all requests in the system
     * @return requests Array of all requests
     */
    function getAllRequest() external view returns (Request[] memory) {
        return LibGettersImpl._getAllRequest(s);
    }
}
