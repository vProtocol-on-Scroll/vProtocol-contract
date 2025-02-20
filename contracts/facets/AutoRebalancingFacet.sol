// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IAutoRebalancing} from "../interfaces/IAutoRebalancing.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/**
 * @title AutoRebalancingFacet
 * @author Five Protocol
 *
 * @dev This contract provides functionality for optimizing capital allocation
 * between P2P lending and the traditional lending pool, monitoring utilization,
 * and executing rebalancing strategies when necessary.
 */
contract AutoRebalancingFacet is IAutoRebalancing {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal s;

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     */
    fallback() external {
        revert("AutoRebalancingFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Initialize the auto-rebalancing system
     * @param minThreshold Minimum threshold for rebalancing (in basis points)
     * @param maxThreshold Maximum threshold for rebalancing (in basis points)
     * @param cooldownPeriod Minimum time between rebalancing operations
     */
    function initializeRebalancing(
        uint256 minThreshold,
        uint256 maxThreshold,
        uint256 cooldownPeriod
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(minThreshold < maxThreshold, "Invalid thresholds");
        require(maxThreshold <= 10000, "Threshold exceeds maximum");
        require(!s.rebalancingConfig.isInitialized, "Already initialized");
        
        s.rebalancingConfig.isInitialized = true;
        s.rebalancingConfig.minRebalanceThreshold = minThreshold;
        s.rebalancingConfig.maxRebalanceThreshold = maxThreshold;
        s.rebalancingConfig.rebalanceCooldown = cooldownPeriod;
        s.rebalancingConfig.lastRebalanceTime = block.timestamp;
        s.rebalancingConfig.emergencyPaused = false;
        
        emit RebalancingInitialized(minThreshold, maxThreshold, cooldownPeriod);
    }

    /**
     * @notice Check if rebalancing is required based on current utilization rates
     * @return required Boolean indicating if rebalancing is required
     * @return action RebalanceAction type needed (if required)
     */
    function checkRebalancingRequired() external view returns (bool required, RebalanceAction action) {
        if (s.rebalancingConfig.emergencyPaused) {
            return (false, RebalanceAction.NONE);
        }
        
        if (block.timestamp < s.rebalancingConfig.lastRebalanceTime + s.rebalancingConfig.rebalanceCooldown) {
            return (false, RebalanceAction.NONE);
        }
        
        uint256 poolUtilization = getPoolUtilization();
        uint256 p2pUtilization = getP2PUtilization();
        
        if (poolUtilization > s.rebalancingConfig.maxRebalanceThreshold) {
            return (true, RebalanceAction.SHIFT_TO_P2P);
        }
        
        if (p2pUtilization > s.rebalancingConfig.maxRebalanceThreshold) {
            return (true, RebalanceAction.SHIFT_TO_POOL);
        }
        
        if (getCapitalEfficiencyScore() < s.rebalancingConfig.minEfficiencyThreshold) {
            return (true, RebalanceAction.OPTIMIZE_ALLOCATION);
        }
        
        return (false, RebalanceAction.NONE);
    }

    /**
     * @notice Execute rebalancing operation
     * @param action Type of rebalancing action to perform
     * @param token Token to rebalance
     * @param amount Amount to rebalance
     */
    function executeRebalancing(
        RebalanceAction action,
        address token,
        uint256 amount
    ) external {
        require(msg.sender == LibDiamond.contractOwner() || 
                s.rebalancingConfig.authorizedRebalancers[msg.sender], 
                "Not authorized");
        require(!s.rebalancingConfig.emergencyPaused, "Rebalancing paused");
        require(block.timestamp >= s.rebalancingConfig.lastRebalanceTime + s.rebalancingConfig.rebalanceCooldown, 
                "Cooldown period active");
        
        if (action == RebalanceAction.NONE) {
            revert("Invalid rebalancing action");
        }
        
        // Execute the appropriate rebalancing strategy
        if (action == RebalanceAction.SHIFT_TO_P2P) {
            _shiftToP2P(token, amount);
        } else if (action == RebalanceAction.SHIFT_TO_POOL) {
            _shiftToPool(token, amount);
        } else if (action == RebalanceAction.OPTIMIZE_ALLOCATION) {
            _optimizeAllocation(token);
        }
        
        // Update last rebalance time
        s.rebalancingConfig.lastRebalanceTime = block.timestamp;
        
        // Update metrics
        s.rebalancingConfig.rebalanceCount++;
        s.rebalancingConfig.lastRebalanceAction = action;
        s.rebalancingConfig.lastRebalanceAmount = amount;
        
        emit RebalancingExecuted(action, token, amount, block.timestamp);
    }

    /**
     * @notice Emergency pause for rebalancing operations
     * @param paused Whether to pause or unpause rebalancing
     */
    function setEmergencyPause(bool paused) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        s.rebalancingConfig.emergencyPaused = paused;
        emit RebalancingPauseSet(paused);
    }

    /**
     * @notice Add or remove an authorized rebalancer
     * @param rebalancer Address to authorize/deauthorize
     * @param authorized Whether to authorize or deauthorize
     */
    function setRebalancerAuthorization(address rebalancer, bool authorized) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(rebalancer != address(0), "Invalid address");
        
        s.rebalancingConfig.authorizedRebalancers[rebalancer] = authorized;
        emit RebalancerAuthorizationSet(rebalancer, authorized);
    }

    /**
     * @notice Update rebalancing thresholds
     * @param minThreshold Minimum threshold for rebalancing
     * @param maxThreshold Maximum threshold for rebalancing
     */
    function updateRebalancingThresholds(uint256 minThreshold, uint256 maxThreshold) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(minThreshold < maxThreshold, "Invalid thresholds");
        require(maxThreshold <= 10000, "Threshold exceeds maximum");
        
        s.rebalancingConfig.minRebalanceThreshold = minThreshold;
        s.rebalancingConfig.maxRebalanceThreshold = maxThreshold;
        
        emit RebalancingThresholdsUpdated(minThreshold, maxThreshold);
    }

    /**
     * @notice Update cooldown period between rebalancing operations
     * @param cooldownPeriod New cooldown period in seconds
     */
    function updateRebalancingCooldown(uint256 cooldownPeriod) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        s.rebalancingConfig.rebalanceCooldown = cooldownPeriod;
        emit RebalancingCooldownUpdated(cooldownPeriod);
    }

    /**
     * @notice Get current pool utilization rate
     * @return Utilization rate in basis points (0-10000)
     */
    function getPoolUtilization() public view returns (uint256) {
        if (s.poolBalances.totalDeposits == 0) {
            return 0;
        }
        return (s.poolBalances.totalBorrows * 10000) / s.poolBalances.totalDeposits;
    }

    /**
     * @notice Get current P2P utilization rate
     * @return Utilization rate in basis points (0-10000)
     */
    function getP2PUtilization() public view returns (uint256) {
        if (s.p2pBalances.totalLendOrders == 0) {
            return 0;
        }
        return (s.p2pBalances.totalBorrowOrders * 10000) / s.p2pBalances.totalLendOrders;
    }

    /**
     * @notice Calculate capital efficiency score
     * @return Score in basis points (0-10000)
     */
    function getCapitalEfficiencyScore() public view returns (uint256) {
        uint256 poolScore = getPoolCapitalEfficiency();
        uint256 p2pScore = getP2PCapitalEfficiency();
        uint256 totalCapital = s.poolBalances.totalDeposits + s.p2pBalances.totalLendOrders;
        
        if (totalCapital == 0) {
            return 0;
        }
        
        uint256 weightedScore = (
            (poolScore * s.poolBalances.totalDeposits) +
            (p2pScore * s.p2pBalances.totalLendOrders)
        ) / totalCapital;
        
        return weightedScore;
    }

    /**
     * @notice Get rebalancing configuration
     * @return minThreshold Minimum threshold for rebalancing
     * @return maxThreshold Maximum threshold for rebalancing
     * @return cooldownPeriod Cooldown period between rebalancing operations
     * @return lastRebalance Last rebalance time
     * @return isPaused Whether rebalancing is paused
     */
    function getRebalancingConfig() external view returns (
        uint256 minThreshold,
        uint256 maxThreshold,
        uint256 cooldownPeriod,
        uint256 lastRebalance,
        bool isPaused
    ) {
        return (
            s.rebalancingConfig.minRebalanceThreshold,
            s.rebalancingConfig.maxRebalanceThreshold,
            s.rebalancingConfig.rebalanceCooldown,
            s.rebalancingConfig.lastRebalanceTime,
            s.rebalancingConfig.emergencyPaused
        );
    }

    /**
     * @notice Get rebalancing statistics
     * @return rebalanceCount Number of rebalancing operations
     * @return lastAction Last rebalance action
     * @return lastAmount Last rebalance amount
     * @return totalAmountRebalanced Total amount rebalanced
     */
    function getRebalancingStats() external view returns (
        uint256 rebalanceCount,
        RebalanceAction lastAction,
        uint256 lastAmount,
        uint256 totalAmountRebalanced
    ) {
        return (
            s.rebalancingConfig.rebalanceCount,
            s.rebalancingConfig.lastRebalanceAction,
            s.rebalancingConfig.lastRebalanceAmount,
            s.rebalancingConfig.totalAmountRebalanced
        );
    }

    // Internal functions for rebalancing operations
    
    /**
     * @notice Shift capital from lending pool to P2P market
     * @param token Token to rebalance
     * @param amount Amount to shift
     */
    function _shiftToP2P(address token, uint256 amount) internal {
        // Ensure there's enough liquidity in the pool
        require(amount <= getAvailablePoolLiquidity(token), "Insufficient pool liquidity");
        
        // Create P2P lending orders from pool liquidity
        // Implementation depends on P2P matching facet
        s.poolBalances.totalDeposits -= amount;
        s.p2pBalances.totalLendOrders += amount;
        
        // Track rebalanced amount
        s.rebalancingConfig.totalAmountRebalanced += amount;
        
        emit LiquidityShifted(RebalanceAction.SHIFT_TO_P2P, token, amount);
    }
    
    /**
     * @notice Shift capital from P2P market to lending pool
     * @param token Token to rebalance
     * @param amount Amount to shift
     */
    function _shiftToPool(address token, uint256 amount) internal {
        // Ensure there's enough liquidity in P2P
        require(amount <= getAvailableP2PLiquidity(token), "Insufficient P2P liquidity");
        
        // Move funds from P2P lending orders to pool
        // Implementation depends on P2P matching facet
        s.p2pBalances.totalLendOrders -= amount;
        s.poolBalances.totalDeposits += amount;
        
        // Track rebalanced amount
        s.rebalancingConfig.totalAmountRebalanced += amount;
        
        emit LiquidityShifted(RebalanceAction.SHIFT_TO_POOL, token, amount);
    }
    
    /**
     * @notice Optimize capital allocation based on current market conditions
     * @param token Token to optimize allocation for
     */
    function _optimizeAllocation(address token) internal {
        // Get current rates and capital allocation
        uint256 poolAPY = getPoolAPY(token);
        uint256 p2pAPY = getP2PAPY(token);
        
        uint256 availablePoolLiquidity = getAvailablePoolLiquidity(token);
        uint256 availableP2PLiquidity = getAvailableP2PLiquidity(token);
        
        // Determine optimal allocation based on APY difference
        if (p2pAPY > poolAPY && p2pAPY - poolAPY > s.rebalancingConfig.minAPYDifference) {
            // Shift from pool to P2P if P2P APY is higher
            uint256 amountToShift = _calculateOptimalShiftAmount(
                availablePoolLiquidity,
                availableP2PLiquidity,
                poolAPY,
                p2pAPY
            );
            
            if (amountToShift > 0) {
                _shiftToP2P(token, amountToShift);
            }
        } else if (poolAPY > p2pAPY && poolAPY - p2pAPY > s.rebalancingConfig.minAPYDifference) {
            // Shift from P2P to pool if pool APY is higher
            uint256 amountToShift = _calculateOptimalShiftAmount(
                availableP2PLiquidity,
                availablePoolLiquidity,
                p2pAPY,
                poolAPY
            );
            
            if (amountToShift > 0) {
                _shiftToPool(token, amountToShift);
            }
        }
    }
    
    /**
     * @notice Calculate optimal amount to shift between P2P and pool
     * @param sourceAvailable Available liquidity in source
     * @param {uint256} Available capacity in destination
     * @param sourceAPY Current APY in source
     * @param destAPY Current APY in destination
     * @return Amount to shift
     */
    function _calculateOptimalShiftAmount(
        uint256 sourceAvailable,
        uint256 ,
        uint256 sourceAPY,
        uint256 destAPY
    ) internal pure returns (uint256) {
        // Algorithm to determine optimal shift amount based on:
        // 1. APY differential
        // 2. Available liquidity
        // 3. Expected impact on rates after shift
        
        uint256 apyDiff = destAPY > sourceAPY ? destAPY - sourceAPY : 0;
        
        // Simple approach: shift proportional to APY difference
        uint256 baseShiftPercentage = (apyDiff * 100) / destAPY;
        
        // Cap at available liquidity with safety buffer
        uint256 maxShift = (sourceAvailable * 80) / 100; // 80% max of available
        uint256 shiftAmount = (sourceAvailable * baseShiftPercentage) / 100;
        
        return shiftAmount > maxShift ? maxShift : shiftAmount;
    }
    
    // Helper functions for capital efficiency calculations
    
    function getPoolCapitalEfficiency() internal view returns (uint256) {
        uint256 utilization = getPoolUtilization();
        
        // Capital efficiency peaks at optimal utilization (80%)
        if (utilization <= 8000) {
            return (utilization * 10000) / 8000;
        } else {
            // Efficiency decreases as utilization exceeds optimal level
            return 10000 - (((utilization - 8000) * 10000) / 2000);
        }
    }
    
    function getP2PCapitalEfficiency() internal view returns (uint256) {
        uint256 utilization = getP2PUtilization();
        // P2P efficiency increases linearly with utilization
        return (utilization * 10000) / 10000;
    }
    
    // Functions to get available liquidity
    
    function getAvailablePoolLiquidity(address token) internal view returns (uint256) {
        // Implementation depends on lending pool facet
        return s.tokenBalances[token].poolLiquidity;
    }
    
    function getAvailableP2PLiquidity(address token) internal view returns (uint256) {
        // Implementation depends on P2P facet
        return s.tokenBalances[token].p2pLiquidity;
    }
    
    // Functions to get APY information
    
    function getPoolAPY(address token) internal view returns (uint256) {
        // Implementation depends on lending pool facet
        return s.tokenRates[token].lendingPoolRate;
    }
    
    function getP2PAPY(address token) internal view returns (uint256) {
        // Implementation depends on P2P facet
        return s.tokenRates[token].p2pLendingRate;
    }
}