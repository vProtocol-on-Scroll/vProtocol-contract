// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibGettersImpl} from "../libraries/LibGetters.sol";
import {Request} from "../model/Protocol.sol";
import {TokenData} from "../model/Protocol.sol";

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
     * @notice The health factor is calculated as the ratio of the user's collateral value to the user's borrow value in both P2P and pool lending by averaging the total of the health factor of the two lending types
     * @param user The address of the user to calculate the health factor for
     * @return The user's health factor
     */
    function healthFactor(address user) external view returns (uint256) {
        uint256 p2pHealthFactor = LibGettersImpl._getP2pHealthFactor(s, user);
        uint256 poolHealthFactor = LibGettersImpl._getPoolHealthFactor(s, user);
        return (p2pHealthFactor + poolHealthFactor) / 2;
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

    /**
     * @notice Get utilization rate for a token
     * @param token Token address
     * @return Utilization rate in basis points (0-10000)
     */
    function _getUtilizationRate(address token) public view returns (uint256) {
        TokenData storage tokenData = s.tokenData[token];
        if (tokenData.totalDeposits == 0) {
            return 0;
        }
        return (tokenData.totalBorrows * 10000) / tokenData.totalDeposits;
    }

    /**
     * @notice Get total deposits for a token
     * @param token Token address
     * @return Total deposits in the token
     */
    function getTotalDeposits(address token) public view returns (uint256) {
        return s.tokenData[token].totalDeposits;
    }

    /**
     * @notice Get total borrows for a token
     * @param token Token address
     * @return Total borrows in the token
     */
    function getTotalBorrows(address token) public view returns (uint256) {
        return s.tokenData[token].totalBorrows;
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
     * @notice Get borrow rate for a token
     * @param token Token address
     * @return Borrow rate in basis points
     */
    function getBorrowApr(address token) public view returns (uint256) {
        uint256 utilization = _getUtilizationRate(token);
        return _calculateBorrowRate(utilization);
    }

    /**
     * @notice Get supply APY for a token
     * @param token Token address
     * @return Supply APY in basis points (0-10000)
     */
    function getSupplyApy(address token) public view returns (uint256) {
        uint256 supplyApy = (getBorrowApr(token) *
            _getUtilizationRate(token) *
            (10000 - s.lendingPoolConfig.reserveFactor)) / 10000;
        return supplyApy;
    }

    function getUserPosition(
        address user,
        address token
    )
        external
        view
        returns (
            uint256 _poolDeposits,
            uint256 _poolBorrows,
            uint256 _p2pLentAmount,
            uint256 _p2pBorrowedAmount,
            uint256 _collateral,
            uint256 _totalLoanCollectedUSD,
            uint256 _lastUpdate
        )
    {
        _poolDeposits = s.userPositions[user].poolDeposits[token];
        _poolBorrows = s.userPositions[user].poolBorrows[token];
        _p2pLentAmount = s.userPositions[user].p2pLentAmount[token];
        _p2pBorrowedAmount = s.userPositions[user].p2pBorrowedAmount[token];
        _collateral = s.userPositions[user].collateral[token];
        _totalLoanCollectedUSD = s.userPositions[user].totalLoanCollectedUSD;
        _lastUpdate = s.userPositions[user].lastUpdate;
        return (
            _poolDeposits,
            _poolBorrows,
            _p2pLentAmount,
            _p2pBorrowedAmount,
            _collateral,
            _totalLoanCollectedUSD,
            _lastUpdate
        );
    }

    /**
     * @notice Get all active loans for a user
     * @param user User address
     * @return loanIds Array of loan IDs
     */
    function getUserLoans(
        address user
    ) external view returns (uint256[] memory loanIds) {
        return s.userPoolLoans[user];
    }

    // get user Token collateral
    function getUserTokenCollateral(
        address user,
        address token
    ) external view returns (uint256) {
        return s.userPositions[user].collateral[token];
    }

    /**
     * @notice Get vault's total assets
     * @param asset Token address
     * @return Total assets for the vault
     */
    function getVaultTotalAssets(
        address asset
    ) external view returns (uint256) {
        return s.vaultDeposits[asset];
    }

    /**
     * @notice Get vault's exchange rate
     * @param asset Token address
     * @return Exchange rate for the vault
     */
    function getVaultExchangeRate(
        address asset
    ) external view returns (uint256) {
        // Exchange rate is the ratio of the total assets to the total deposits
        return
            (s.vaultDeposits[asset] * 1e18) / s.tokenData[asset].totalDeposits;
    }
}
