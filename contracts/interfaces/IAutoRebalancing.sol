// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../model/Protocol.sol";

/**
 * @title IAutoRebalancing
 * @author Five Protocol
 *
 * @notice Interface for the auto-rebalancing system that optimizes capital allocation
 * between P2P lending and the lending pool
 */
interface IAutoRebalancing {
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
    ) external;

    /**
     * @notice Check if rebalancing is required based on current utilization rates
     * @return required Boolean indicating if rebalancing is required
     * @return action RebalanceAction type needed (if required)
     */
    function checkRebalancingRequired() external view returns (bool required, RebalanceAction action);

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
    ) external;

    /**
     * @notice Emergency pause for rebalancing operations
     * @param paused Whether to pause or unpause rebalancing
     */
    function setEmergencyPause(bool paused) external;

    /**
     * @notice Add or remove an authorized rebalancer
     * @param rebalancer Address to authorize/deauthorize
     * @param authorized Whether to authorize or deauthorize
     */
    function setRebalancerAuthorization(address rebalancer, bool authorized) external;

    /**
     * @notice Update rebalancing thresholds
     * @param minThreshold Minimum threshold for rebalancing
     * @param maxThreshold Maximum threshold for rebalancing
     */
    function updateRebalancingThresholds(uint256 minThreshold, uint256 maxThreshold) external;

    /**
     * @notice Update cooldown period between rebalancing operations
     * @param cooldownPeriod New cooldown period in seconds
     */
    function updateRebalancingCooldown(uint256 cooldownPeriod) external;

    /**
     * @notice Get current pool utilization rate
     * @return Utilization rate in basis points (0-10000)
     */
    function getPoolUtilization() external view returns (uint256);

    /**
     * @notice Get current P2P utilization rate
     * @return Utilization rate in basis points (0-10000)
     */
    function getP2PUtilization() external view returns (uint256);

    /**
     * @notice Calculate capital efficiency score
     * @return Score in basis points (0-10000)
     */
    function getCapitalEfficiencyScore() external view returns (uint256);

    /**
     * @notice Get rebalancing configuration
     * @return minThreshold Minimum threshold for rebalancing
     * @return maxThreshold Maximum threshold for rebalancing
     * @return cooldownPeriod Time required between rebalances
     * @return lastRebalance Timestamp of last rebalance
     * @return isPaused Whether rebalancing is paused
     */
    function getRebalancingConfig() external view returns (
        uint256 minThreshold,
        uint256 maxThreshold,
        uint256 cooldownPeriod,
        uint256 lastRebalance,
        bool isPaused
    );

    /**
     * @notice Get rebalancing statistics
     * @return rebalanceCount Number of rebalances executed
     * @return lastAction Last rebalance action performed
     * @return lastAmount Amount in last rebalance
     * @return totalAmountRebalanced Total amount rebalanced historically
     */
    function getRebalancingStats() external view returns (
        uint256 rebalanceCount,
        RebalanceAction lastAction,
        uint256 lastAmount,
        uint256 totalAmountRebalanced
    );

    // Events
    event RebalancingInitialized(uint256 minThreshold, uint256 maxThreshold, uint256 cooldownPeriod);
    event RebalancingExecuted(RebalanceAction action, address token, uint256 amount, uint256 timestamp);
    event RebalancingPauseSet(bool paused);
    event RebalancerAuthorizationSet(address rebalancer, bool authorized);
    event RebalancingThresholdsUpdated(uint256 minThreshold, uint256 maxThreshold);
    event RebalancingCooldownUpdated(uint256 cooldownPeriod);
    event LiquidityShifted(RebalanceAction action, address token, uint256 amount);
}