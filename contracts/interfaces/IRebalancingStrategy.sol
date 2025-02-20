// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../model/Protocol.sol";

/**
* @title IRebalancingStrategy
* @author Five Protocol
*
* @notice Interface for the rebalancing strategy system that manages
* different capital allocation strategies between lending markets
*/
interface IRebalancingStrategy {
   /**
    * @notice Initialize the rebalancing strategy system
    * @param defaultStrategy Initial default strategy type
    * @param riskProfile Initial risk profile for the strategy
    */
   function initializeStrategy(
       StrategyType defaultStrategy, 
       RiskProfile riskProfile
   ) external;

   /**
    * @notice Create a new rebalancing strategy
    * @param strategyId Unique identifier for the strategy
    * @param strategyType Type of strategy to create
    * @param parameters Strategy-specific parameters
    */
   function createStrategy(
       uint256 strategyId,
       StrategyType strategyType,
       bytes calldata parameters
   ) external;

   /**
    * @notice Update an existing rebalancing strategy
    * @param strategyId ID of the strategy to update
    * @param parameters New strategy parameters
    */
   function updateStrategy(
       uint256 strategyId,
       bytes calldata parameters
   ) external;

   /**
    * @notice Activate a strategy and set it as the active strategy
    * @param strategyId ID of the strategy to activate
    */
   function activateStrategy(uint256 strategyId) external;

   /**
    * @notice Deactivate a strategy
    * @param strategyId ID of the strategy to deactivate
    */
   function deactivateStrategy(uint256 strategyId) external;

   /**
    * @notice Update the protocol's risk profile
    * @param riskProfile New risk profile
    */
   function updateRiskProfile(RiskProfile riskProfile) external;

   /**
    * @notice Get the recommended rebalancing action based on current market conditions
    * @param token Token to evaluate
    * @return action Recommended rebalancing action
    * @return amount Recommended amount to rebalance
    */
   function getRecommendedAction(address token) external view returns (
       RebalanceAction action,
       uint256 amount
   );

   /**
    * @notice Get current strategy information
    * @return strategyType Type of active strategy
    * @return strategyId ID of active strategy
    * @return lastUpdate Timestamp of last strategy update
    * @return riskProfile Current risk profile
    */
   function getCurrentStrategy() external view returns (
       StrategyType strategyType,
       uint256 strategyId,
       uint256 lastUpdate,
       RiskProfile riskProfile
   );

   /**
    * @notice Get details of a specific strategy
    * @param strategyId ID of the strategy
    * @return strategyType Type of strategy
    * @return isActive Whether strategy is active
    * @return createdAt Creation timestamp
    * @return lastUpdated Last update timestamp
    * @return parameters Strategy parameters
    */
   function getStrategyDetails(uint256 strategyId) external view returns (
       StrategyType strategyType,
       bool isActive,
       uint256 createdAt,
       uint256 lastUpdated,
       bytes memory parameters
   );

   /**
    * @notice Get strategy performance metrics
    * @param strategyId ID of the strategy
    * @return totalRebalanced Total amount rebalanced using this strategy
    * @return performanceScore Performance score (basis points)
    * @return yieldImprovement Yield improvement achieved (can be negative)
    * @return executionCount Number of times strategy was executed
    */
   function getStrategyPerformance(uint256 strategyId) external view returns (
       uint256 totalRebalanced,
       uint256 performanceScore,
       int256 yieldImprovement,
       uint256 executionCount
   );

   // Events
   event StrategyInitialized(StrategyType strategyType, RiskProfile riskProfile);
   event StrategyCreated(uint256 strategyId, StrategyType strategyType);
   event StrategyUpdated(uint256 strategyId, StrategyType strategyType);
   event StrategyActivated(uint256 strategyId, StrategyType strategyType);
   event StrategyDeactivated(uint256 strategyId);
   event RiskProfileUpdated(RiskProfile riskProfile);
}