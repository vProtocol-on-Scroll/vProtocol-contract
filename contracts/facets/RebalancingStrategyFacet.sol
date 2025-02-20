// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IRebalancingStrategy} from "../interfaces/IRebalancingStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/**
 * @title RebalancingStrategyFacet
 * @author Five Protocol
 *
 * @dev This contract manages complex rebalancing strategies and algorithms
 * for optimizing capital allocation between different liquidity markets.
 */
contract RebalancingStrategyFacet is IRebalancingStrategy {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal s;

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     */
    fallback() external {
        revert("RebalancingStrategyFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Initialize the rebalancing strategy system
     * @param defaultStrategy Initial default strategy type
     * @param riskProfile Initial risk profile for the strategy
     */
    function initializeStrategy(
        StrategyType defaultStrategy,
        RiskProfile riskProfile
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(!s.strategyConfig.isInitialized, "Already initialized");
        
        s.strategyConfig.isInitialized = true;
        s.strategyConfig.activeStrategy = defaultStrategy;
        s.strategyConfig.riskProfile = riskProfile;
        s.strategyConfig.lastStrategyUpdate = block.timestamp;
        
        // Initialize strategy parameters based on risk profile
        _initializeStrategyParameters(defaultStrategy, riskProfile);
        
        emit StrategyInitialized(defaultStrategy, riskProfile);
    }

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
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(!s.strategies[strategyId].isActive, "Strategy already exists");
        
        RebalancingStrategy storage strategy = s.strategies[strategyId];
        strategy.strategyType = strategyType;
        strategy.isActive = true;
        strategy.createdAt = block.timestamp;
        
        // Parse and set strategy-specific parameters
        _parseStrategyParameters(strategyId, strategyType, parameters);
        
        emit StrategyCreated(strategyId, strategyType);
    }

    /**
     * @notice Update an existing rebalancing strategy
     * @param strategyId ID of the strategy to update
     * @param parameters New strategy parameters
     */
    function updateStrategy(
        uint256 strategyId,
        bytes calldata parameters
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.strategies[strategyId].isActive, "Strategy not found");
        
        StrategyType strategyType = s.strategies[strategyId].strategyType;
        
        // Parse and update strategy parameters
        _parseStrategyParameters(strategyId, strategyType, parameters);
        s.strategies[strategyId].lastUpdated = block.timestamp;
        
        emit StrategyUpdated(strategyId, strategyType);
    }

    /**
     * @notice Activate a strategy and set it as the active strategy
     * @param strategyId ID of the strategy to activate
     */
    function activateStrategy(uint256 strategyId) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.strategies[strategyId].isActive, "Strategy not found");
        
        s.strategyConfig.activeStrategy = s.strategies[strategyId].strategyType;
        s.strategyConfig.activeStrategyId = strategyId;
        s.strategyConfig.lastStrategyUpdate = block.timestamp;
        
        emit StrategyActivated(strategyId, s.strategies[strategyId].strategyType);
    }

    /**
     * @notice Deactivate a strategy
     * @param strategyId ID of the strategy to deactivate
     */
    function deactivateStrategy(uint256 strategyId) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(s.strategies[strategyId].isActive, "Strategy not found");
        
        s.strategies[strategyId].isActive = false;
        
        // If this was the active strategy, revert to default
        if (s.strategyConfig.activeStrategyId == strategyId) {
            s.strategyConfig.activeStrategy = StrategyType.BALANCED;
            s.strategyConfig.activeStrategyId = 0; // Default strategy ID
            s.strategyConfig.lastStrategyUpdate = block.timestamp;
        }
        
        emit StrategyDeactivated(strategyId);
    }

    /**
     * @notice Update the protocol's risk profile
     * @param riskProfile New risk profile
     */
    function updateRiskProfile(RiskProfile riskProfile) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        
        s.strategyConfig.riskProfile = riskProfile;
        
        // Update parameters for active strategy based on new risk profile
        _updateStrategyRiskParameters(s.strategyConfig.activeStrategyId, riskProfile);
        
        emit RiskProfileUpdated(riskProfile);
    }

    /**
     * @notice Get the recommended rebalancing action based on current market conditions
     * @param token Token to evaluate
     * @return action Recommended rebalancing action
     * @return amount Recommended amount to rebalance
     */
    function getRecommendedAction(address token) external view returns (
        RebalanceAction action,
        uint256 amount
    ) {
        // Get current active strategy
        uint256 activeStrategyId = s.strategyConfig.activeStrategyId;
        StrategyType strategyType = s.strategyConfig.activeStrategy;
        
        // Get current market conditions
        MarketCondition condition = _getCurrentMarketCondition(token);
        
        // Strategy-specific logic
        if (strategyType == StrategyType.YIELD_MAXIMIZER) {
            return _getYieldMaximizerAction(token, activeStrategyId, condition);
        } else if (strategyType == StrategyType.RISK_MINIMIZER) {
            return _getRiskMinimizerAction(token, activeStrategyId, condition);
        } else if (strategyType == StrategyType.BALANCED) {
            return _getBalancedAction(token, activeStrategyId, condition);
        } else if (strategyType == StrategyType.DYNAMIC) {
            return _getDynamicAction(token, activeStrategyId, condition);
        } else if (strategyType == StrategyType.CUSTOM) {
            return _getCustomAction(token, activeStrategyId, condition);
        }
        
        // Default: no action
        return (RebalanceAction.NONE, 0);
    }

    /**
     * @notice Get current strategy information
     * @return strategyType Strategy type
     * @return strategyId Strategy ID
     * @return lastUpdate Last update time
     * @return riskProfile Risk profile
     */
    function getCurrentStrategy() external view returns (
        StrategyType strategyType,
        uint256 strategyId,
        uint256 lastUpdate,
        RiskProfile riskProfile
    ) {
        return (
            s.strategyConfig.activeStrategy,
            s.strategyConfig.activeStrategyId,
            s.strategyConfig.lastStrategyUpdate,
            s.strategyConfig.riskProfile
        );
    }

    /**
     * @notice Get details of a specific strategy
     * @param strategyId ID of the strategy
     * @return strategyType Strategy type
     * @return isActive Whether the strategy is active
     * @return createdAt Creation time
     * @return lastUpdated Last update time
     * @return parameters Strategy parameters
     */
    function getStrategyDetails(uint256 strategyId) external view returns (
        StrategyType strategyType,
        bool isActive,
        uint256 createdAt,
        uint256 lastUpdated,
        bytes memory parameters
    ) {
        RebalancingStrategy storage strategy = s.strategies[strategyId];
        return (
            strategy.strategyType,
            strategy.isActive,
            strategy.createdAt,
            strategy.lastUpdated,
            strategy.parameters
        );
    }

    /**
     * @notice Get strategy performance metrics
     * @param strategyId ID of the strategy
     * @return totalRebalanced Total amount rebalanced
     * @return performanceScore Performance score
     * @return yieldImprovement Yield improvement
     * @return executionCount Execution count
     */
    function getStrategyPerformance(uint256 strategyId) external view returns (
        uint256 totalRebalanced,
        uint256 performanceScore,
        int256 yieldImprovement,
        uint256 executionCount
    ) {
        StrategyPerformance storage performance = s.strategyPerformance[strategyId];
        return (
            performance.totalAmountRebalanced,
            performance.performanceScore,
            performance.yieldImprovement,
            performance.executionCount
        );
    }

    // Internal functions for strategy management
    
    /**
     * @notice Initialize strategy parameters based on risk profile
     * @param strategyType Type of strategy
     * @param riskProfile Risk profile to use
     */
    function _initializeStrategyParameters(
        StrategyType strategyType,
        RiskProfile riskProfile
    ) internal {
        if (strategyType == StrategyType.YIELD_MAXIMIZER) {
            // Yield maximizer parameters
            if (riskProfile == RiskProfile.CONSERVATIVE) {
                s.yieldMaximizerParams.maxShiftPercentage = 2000; // 20%
                s.yieldMaximizerParams.minYieldDifferential = 100; // 1%
            } else if (riskProfile == RiskProfile.MODERATE) {
                s.yieldMaximizerParams.maxShiftPercentage = 3500; // 35%
                s.yieldMaximizerParams.minYieldDifferential = 50; // 0.5%
            } else if (riskProfile == RiskProfile.AGGRESSIVE) {
                s.yieldMaximizerParams.maxShiftPercentage = 5000; // 50%
                s.yieldMaximizerParams.minYieldDifferential = 25; // 0.25%
            }
        } else if (strategyType == StrategyType.RISK_MINIMIZER) {
            // Risk minimizer parameters
            if (riskProfile == RiskProfile.CONSERVATIVE) {
                s.riskMinimizerParams.targetUtilization = 5000; // 50%
                s.riskMinimizerParams.maxVolatilityTolerance = 1000; // 10%
            } else if (riskProfile == RiskProfile.MODERATE) {
                s.riskMinimizerParams.targetUtilization = 6500; // 65%
                s.riskMinimizerParams.maxVolatilityTolerance = 2000; // 20%
            } else if (riskProfile == RiskProfile.AGGRESSIVE) {
                s.riskMinimizerParams.targetUtilization = 8000; // 80%
                s.riskMinimizerParams.maxVolatilityTolerance = 3000; // 30%
            }
        } else if (strategyType == StrategyType.BALANCED) {
            // Balanced strategy parameters
            if (riskProfile == RiskProfile.CONSERVATIVE) {
                s.balancedParams.poolAllocationTarget = 7000; // 70%
                s.balancedParams.p2pAllocationTarget = 3000; // 30%
            } else if (riskProfile == RiskProfile.MODERATE) {
                s.balancedParams.poolAllocationTarget = 5000; // 50%
                s.balancedParams.p2pAllocationTarget = 5000; // 50%
            } else if (riskProfile == RiskProfile.AGGRESSIVE) {
                s.balancedParams.poolAllocationTarget = 3000; // 30%
                s.balancedParams.p2pAllocationTarget = 7000; // 70%
            }
        } else if (strategyType == StrategyType.DYNAMIC) {
            // Dynamic strategy parameters
            if (riskProfile == RiskProfile.CONSERVATIVE) {
                s.dynamicParams.volatilityWeight = 5000; // 50%
                s.dynamicParams.yieldWeight = 2000; // 20%
                s.dynamicParams.liquidityWeight = 3000; // 30%
            } else if (riskProfile == RiskProfile.MODERATE) {
                s.dynamicParams.volatilityWeight = 3000; // 30%
                s.dynamicParams.yieldWeight = 4000; // 40%
                s.dynamicParams.liquidityWeight = 3000; // 30%
            } else if (riskProfile == RiskProfile.AGGRESSIVE) {
                s.dynamicParams.volatilityWeight = 2000; // 20%
                s.dynamicParams.yieldWeight = 6000; // 60%
                s.dynamicParams.liquidityWeight = 2000; // 20%
            }
        }
        // Custom strategy parameters are set via updateStrategy
    }

    // Missing functions in RebalancingStrategyFacet.sol

/**
 * @notice Parse and set strategy-specific parameters
 * @param strategyId ID of the strategy to update
 * @param strategyType Type of strategy being configured
 * @param parameters Encoded parameters specific to the strategy type
 */
function _parseStrategyParameters(
    uint256 strategyId,
    StrategyType strategyType,
    bytes calldata parameters
) internal {
    RebalancingStrategy storage strategy = s.strategies[strategyId];
    
    if (strategyType == StrategyType.YIELD_MAXIMIZER) {
        (uint256 maxShiftPercentage, uint256 minYieldDifferential) = 
            abi.decode(parameters, (uint256, uint256));
            
        require(maxShiftPercentage <= 5000, "Shift percentage too high");
        require(minYieldDifferential <= 500, "Yield differential too high");
        
        strategy.parameters = parameters;
        
    } else if (strategyType == StrategyType.RISK_MINIMIZER) {
        (uint256 targetUtilization, uint256 maxVolatilityTolerance) = 
            abi.decode(parameters, (uint256, uint256));
            
        require(targetUtilization <= 9000, "Target utilization too high");
        require(maxVolatilityTolerance <= 3000, "Volatility tolerance too high");
        
        strategy.parameters = parameters;
        
    } else if (strategyType == StrategyType.BALANCED) {
        (uint256 poolAllocationTarget, uint256 p2pAllocationTarget) = 
            abi.decode(parameters, (uint256, uint256));
            
        require(poolAllocationTarget + p2pAllocationTarget == 10000, "Allocation must total 100%");
        
        strategy.parameters = parameters;
        
    } else if (strategyType == StrategyType.DYNAMIC) {
        (uint256 volatilityWeight, uint256 yieldWeight, uint256 liquidityWeight) = 
            abi.decode(parameters, (uint256, uint256, uint256));
            
        require(volatilityWeight + yieldWeight + liquidityWeight == 10000, "Weights must total 100%");
        
        strategy.parameters = parameters;
        
    } else if (strategyType == StrategyType.CUSTOM) {
        // Custom parameters are stored as-is and interpreted by the strategy
        strategy.parameters = parameters;
    }
}

/**
 * @notice Update strategy parameters based on risk profile
 * @param strategyId ID of the strategy to update
 * @param riskProfile New risk profile to apply
 */
function _updateStrategyRiskParameters(
    uint256 strategyId,
    RiskProfile riskProfile
) internal {
    RebalancingStrategy storage strategy = s.strategies[strategyId];
    StrategyType strategyType = strategy.strategyType;
    
    // Generate new parameters based on strategy type and risk profile
    bytes memory newParameters;
    
    if (strategyType == StrategyType.YIELD_MAXIMIZER) {
        uint256 maxShiftPercentage;
        uint256 minYieldDifferential;
        
        if (riskProfile == RiskProfile.CONSERVATIVE) {
            maxShiftPercentage = 2000; // 20%
            minYieldDifferential = 100; // 1%
        } else if (riskProfile == RiskProfile.MODERATE) {
            maxShiftPercentage = 3500; // 35%
            minYieldDifferential = 50; // 0.5%
        } else {
            maxShiftPercentage = 5000; // 50%
            minYieldDifferential = 25; // 0.25%
        }
        
        newParameters = abi.encode(maxShiftPercentage, minYieldDifferential);
        
    } else if (strategyType == StrategyType.RISK_MINIMIZER) {
        uint256 targetUtilization;
        uint256 maxVolatilityTolerance;
        
        if (riskProfile == RiskProfile.CONSERVATIVE) {
            targetUtilization = 5000; // 50%
            maxVolatilityTolerance = 1000; // 10%
        } else if (riskProfile == RiskProfile.MODERATE) {
            targetUtilization = 6500; // 65%
            maxVolatilityTolerance = 2000; // 20%
        } else {
            targetUtilization = 8000; // 80%
            maxVolatilityTolerance = 3000; // 30%
        }
        
        newParameters = abi.encode(targetUtilization, maxVolatilityTolerance);
        
    } else if (strategyType == StrategyType.BALANCED) {
        uint256 poolAllocationTarget;
        uint256 p2pAllocationTarget;
        
        if (riskProfile == RiskProfile.CONSERVATIVE) {
            poolAllocationTarget = 7000; // 70%
            p2pAllocationTarget = 3000; // 30%
        } else if (riskProfile == RiskProfile.MODERATE) {
            poolAllocationTarget = 5000; // 50%
            p2pAllocationTarget = 5000; // 50%
        } else {
            poolAllocationTarget = 3000; // 30%
            p2pAllocationTarget = 7000; // 70%
        }
        
        newParameters = abi.encode(poolAllocationTarget, p2pAllocationTarget);
        
    } else if (strategyType == StrategyType.DYNAMIC) {
        uint256 volatilityWeight;
        uint256 yieldWeight;
        uint256 liquidityWeight;
        
        if (riskProfile == RiskProfile.CONSERVATIVE) {
            volatilityWeight = 5000; // 50%
            yieldWeight = 2000; // 20%
            liquidityWeight = 3000; // 30%
        } else if (riskProfile == RiskProfile.MODERATE) {
            volatilityWeight = 3000; // 30%
            yieldWeight = 4000; // 40%
            liquidityWeight = 3000; // 30%
        } else {
            volatilityWeight = 2000; // 20%
            yieldWeight = 6000; // 60%
            liquidityWeight = 2000; // 20%
        }
        
        newParameters = abi.encode(volatilityWeight, yieldWeight, liquidityWeight);
    }
    
    // Update strategy parameters
    if (newParameters.length > 0) {
        strategy.parameters = newParameters;
        strategy.lastUpdated = block.timestamp;
    }
}

/**
 * @notice Get current market condition based on metrics
 * @param token Token to evaluate
 * @return Current market condition
 */
function _getCurrentMarketCondition(address token) internal view returns (MarketCondition) {
    // Get key market metrics
    uint256 poolUtilization = _getPoolUtilization(token);
    uint256 p2pUtilization = _getP2PUtilization(token);
    uint256 volatilityIndex = _getMarketVolatility(token);
    uint256 demandIndex = _getMarketDemand(token);
    
    // Determine market condition based on metrics
    if (volatilityIndex > 7000) {
        return MarketCondition.VOLATILE;
    } else if (demandIndex > 8000) {
        return MarketCondition.HIGH_DEMAND;
    } else if (demandIndex < 2000) {
        return MarketCondition.LOW_DEMAND;
    } else if (volatilityIndex > 4000 && (poolUtilization > 9000 || p2pUtilization > 9000)) {
        return MarketCondition.UNSTABLE;
    } else {
        return MarketCondition.NORMAL;
    }
}

/**
 * @notice Get recommended action for Yield Maximizer strategy
 * @param token Token to evaluate
 * @param strategyId Active strategy ID
 * @param condition Current market condition
 * @return action Recommended action
 * @return amount Recommended amount
 */
function _getYieldMaximizerAction(
    address token,
    uint256 strategyId,
    MarketCondition condition
) internal view returns (RebalanceAction action, uint256 amount) {
    // Decode strategy parameters
    (uint256 maxShiftPercentage, uint256 minYieldDifferential) = 
        abi.decode(s.strategies[strategyId].parameters, (uint256, uint256));
    
    // Get current yields
    uint256 poolAPY = _getPoolAPY(token);
    uint256 p2pAPY = _getP2PAPY(token);
    
    uint256 yieldDiff;
    RebalanceAction recommendedAction;
    
    if (p2pAPY > poolAPY) {
        yieldDiff = p2pAPY - poolAPY;
        recommendedAction = RebalanceAction.SHIFT_TO_P2P;
    } else if (poolAPY > p2pAPY) {
        yieldDiff = poolAPY - p2pAPY;
        recommendedAction = RebalanceAction.SHIFT_TO_POOL;
    } else {
        return (RebalanceAction.NONE, 0);
    }
    
    // Only recommend action if yield difference exceeds minimum threshold
    if (yieldDiff < minYieldDifferential) {
        return (RebalanceAction.NONE, 0);
    }
    
    // Calculate amount to shift based on yield difference and market condition
    uint256 basePercentage = (yieldDiff * 100) / (p2pAPY > poolAPY ? p2pAPY : poolAPY);
    uint256 adjustedPercentage = basePercentage;
    
    // Adjust based on market conditions
    if (condition == MarketCondition.VOLATILE) {
        adjustedPercentage = basePercentage / 2; // More conservative in volatile markets
    } else if (condition == MarketCondition.HIGH_DEMAND) {
        adjustedPercentage = (basePercentage * 120) / 100; // More aggressive in high demand
    }
    
    // Cap at max shift percentage
    if (adjustedPercentage > maxShiftPercentage) {
        adjustedPercentage = maxShiftPercentage;
    }
    
    // Calculate actual amount based on available liquidity
    uint256 availableLiquidity;
    if (recommendedAction == RebalanceAction.SHIFT_TO_P2P) {
        availableLiquidity = _getPoolLiquidity(token);
    } else {
        availableLiquidity = _getP2PLiquidity(token);
    }
    
    amount = (availableLiquidity * adjustedPercentage) / 10000;
    
    return (amount > 0 ? recommendedAction : RebalanceAction.NONE, amount);
}

/**
 * @notice Get recommended action for Risk Minimizer strategy
 * @param token Token to evaluate
 * @param strategyId Active strategy ID
 * @param condition Current market condition
 * @return action Recommended action
 * @return amount Recommended amount
 */
function _getRiskMinimizerAction(
    address token,
    uint256 strategyId,
    MarketCondition condition
) internal view returns (RebalanceAction action, uint256 amount) {
    // Decode strategy parameters
    (uint256 targetUtilization, uint256 maxVolatilityTolerance) = 
        abi.decode(s.strategies[strategyId].parameters, (uint256, uint256));
    
    // Get current utilization and volatility
    uint256 poolUtilization = _getPoolUtilization(token);
    uint256 p2pUtilization = _getP2PUtilization(token);
    uint256 volatilityIndex = _getMarketVolatility(token);
    
    // In volatile markets, prioritize safety
    if (volatilityIndex > maxVolatilityTolerance) {
        // Move to the safer market (typically the lending pool)
        if (p2pUtilization > poolUtilization) {
            uint256 excessUtilization = p2pUtilization - targetUtilization;
            uint256 p2pLiquidity = _getP2PLiquidity(token);
            amount = (p2pLiquidity * excessUtilization) / 10000;
            return (RebalanceAction.SHIFT_TO_POOL, amount);
        }
    }
    
    // Normal market conditions - balance utilization
    if (poolUtilization > targetUtilization + 1000) { // 10% over target
        uint256 excessUtilization = poolUtilization - targetUtilization;
        uint256 poolLiquidity = _getPoolLiquidity(token);
        amount = (poolLiquidity * excessUtilization) / 10000;
        return (RebalanceAction.SHIFT_TO_P2P, amount);
    } else if (p2pUtilization > targetUtilization + 1000) { // 10% over target
        uint256 excessUtilization = p2pUtilization - targetUtilization;
        uint256 p2pLiquidity = _getP2PLiquidity(token);
        amount = (p2pLiquidity * excessUtilization) / 10000;
        return (RebalanceAction.SHIFT_TO_POOL, amount);
    }
    
    return (RebalanceAction.NONE, 0);
}

/**
 * @notice Get recommended action for Balanced strategy
 * @param token Token to evaluate
 * @param strategyId Active strategy ID
 * @param condition Current market condition
 * @return action Recommended action
 * @return amount Recommended amount
 */
function _getBalancedAction(
    address token,
    uint256 strategyId,
    MarketCondition condition
) internal view returns (RebalanceAction action, uint256 amount) {
    // Decode strategy parameters
    (uint256 poolAllocationTarget, uint256 p2pAllocationTarget) = 
        abi.decode(s.strategies[strategyId].parameters, (uint256, uint256));
    
    // Get current allocation
    uint256 poolLiquidity = _getPoolLiquidity(token);
    uint256 p2pLiquidity = _getP2PLiquidity(token);
    uint256 totalLiquidity = poolLiquidity + p2pLiquidity;
    
    if (totalLiquidity == 0) {
        return (RebalanceAction.NONE, 0);
    }
    
    uint256 currentPoolAllocation = (poolLiquidity * 10000) / totalLiquidity;
    uint256 currentP2PAllocation = 10000 - currentPoolAllocation;
    
    // Check if allocation is significantly out of balance (5% threshold)
    if (currentPoolAllocation > poolAllocationTarget + 500) {
        // Too much in pool, shift to P2P
        uint256 excessPercentage = currentPoolAllocation - poolAllocationTarget;
        amount = (poolLiquidity * excessPercentage) / currentPoolAllocation;
        return (RebalanceAction.SHIFT_TO_P2P, amount);
    } else if (currentP2PAllocation > p2pAllocationTarget + 500) {
        // Too much in P2P, shift to pool
        uint256 excessPercentage = currentP2PAllocation - p2pAllocationTarget;
        amount = (p2pLiquidity * excessPercentage) / currentP2PAllocation;
        return (RebalanceAction.SHIFT_TO_POOL, amount);
    }
    
    return (RebalanceAction.NONE, 0);
}

/**
 * @notice Get recommended action for Dynamic strategy
 * @param token Token to evaluate
 * @param strategyId Active strategy ID
 * @param condition Current market condition
 * @return action Recommended action
 * @return amount Recommended amount
 */
function _getDynamicAction(
    address token,
    uint256 strategyId,
    MarketCondition condition
) internal view returns (RebalanceAction action, uint256 amount) {
    // Decode strategy parameters
    (uint256 volatilityWeight, uint256 yieldWeight, uint256 liquidityWeight) = 
        abi.decode(s.strategies[strategyId].parameters, (uint256, uint256, uint256));
    
    // Combine multiple factors to score each market
    uint256 poolScore = _calculateMarketScore(
        token,
        true, // is pool
        volatilityWeight,
        yieldWeight,
        liquidityWeight
    );
    
    uint256 p2pScore = _calculateMarketScore(
        token,
        false, // is p2p
        volatilityWeight,
        yieldWeight,
        liquidityWeight
    );
    
    // Calculate optimal allocation based on relative scores
    uint256 totalScore = poolScore + p2pScore;
    if (totalScore == 0) return (RebalanceAction.NONE, 0);
    
    uint256 optimalPoolAllocation = (poolScore * 10000) / totalScore;
    
    // Get current allocation
    uint256 poolLiquidity = _getPoolLiquidity(token);
    uint256 p2pLiquidity = _getP2PLiquidity(token);
    uint256 totalLiquidity = poolLiquidity + p2pLiquidity;
    
    if (totalLiquidity == 0) {
        return (RebalanceAction.NONE, 0);
    }
    
    uint256 currentPoolAllocation = (poolLiquidity * 10000) / totalLiquidity;
    
    // Determine action based on allocation difference (3% threshold)
    if (currentPoolAllocation > optimalPoolAllocation + 300) {
        // Too much in pool, shift to P2P
        uint256 targetShiftPercentage = (currentPoolAllocation - optimalPoolAllocation) / 2; // Move halfway to target
        amount = (poolLiquidity * targetShiftPercentage) / 10000;
        return (RebalanceAction.SHIFT_TO_P2P, amount);
    } else if (optimalPoolAllocation > currentPoolAllocation + 300) {
        // Too much in P2P, shift to pool
        uint256 targetShiftPercentage = (optimalPoolAllocation - currentPoolAllocation) / 2; // Move halfway to target
        amount = (p2pLiquidity * targetShiftPercentage) / 10000;
        return (RebalanceAction.SHIFT_TO_POOL, amount);
    }
    
    return (RebalanceAction.NONE, 0);
}

/**
 * @notice Get recommended action for Custom strategy
 * @param token Token to evaluate
 * @param strategyId Active strategy ID
 * @param condition Current market condition
 * @return action Recommended action
 * @return amount Recommended amount
 */
function _getCustomAction(
    address token,
    uint256 strategyId,
    MarketCondition condition
) internal view returns (RebalanceAction action, uint256 amount) {
    // Custom strategies implement their own logic based on parameters
    bytes memory params = s.strategies[strategyId].parameters;
    
    // Example implementation for a simple custom strategy
    uint256 poolLiquidity = _getPoolLiquidity(token);
    uint256 p2pLiquidity = _getP2PLiquidity(token);
    uint256 poolAPY = _getPoolAPY(token);
    uint256 p2pAPY = _getP2PAPY(token);
    
    // Complex custom logic would go here
    // This is a placeholder implementation
    if (condition == MarketCondition.VOLATILE) {
        // In volatile markets, favor the pool
        if (p2pLiquidity > poolLiquidity) {
            amount = p2pLiquidity / 10; // Move 10% to pool
            return (RebalanceAction.SHIFT_TO_POOL, amount);
        }
    } else if (condition == MarketCondition.HIGH_DEMAND) {
        // In high demand, favor higher APY
        if (p2pAPY > poolAPY) {
            amount = poolLiquidity / 5; // Move 20% to P2P
            return (RebalanceAction.SHIFT_TO_P2P, amount);
        } else if (poolAPY > p2pAPY) {
            amount = p2pLiquidity / 5; // Move 20% to pool
            return (RebalanceAction.SHIFT_TO_POOL, amount);
        }
    }
    
    return (RebalanceAction.NONE, 0);
}

/**
 * @notice Calculate market score based on weighted factors
 * @param token Token to evaluate
 * @param isPool Whether to score pool (true) or P2P (false)
 * @param volatilityWeight Weight for volatility factor
 * @param yieldWeight Weight for yield factor
 * @param liquidityWeight Weight for liquidity factor
 */
function _calculateMarketScore(
    address token,
    bool isPool,
    uint256 volatilityWeight,
    uint256 yieldWeight,
    uint256 liquidityWeight
) internal view returns (uint256) {
    // Get relevant metrics
    uint256 utilization = isPool ? _getPoolUtilization(token) : _getP2PUtilization(token);
    uint256 yield = isPool ? _getPoolAPY(token) : _getP2PAPY(token);
    uint256 liquidity = isPool ? _getPoolLiquidity(token) : _getP2PLiquidity(token);
    uint256 volatility = _getMarketVolatility(token);
    
    // Score factors (higher is better)
    uint256 volatilityScore = isPool ? 
        10000 - volatility : // Pool is safer in volatility
        (10000 - volatility) / 2; // P2P is riskier
    
    uint256 yieldScore = yield;
    
    uint256 totalLiquidity = _getPoolLiquidity(token) + _getP2PLiquidity(token);
    uint256 liquidityScore = totalLiquidity > 0 ? 
        (liquidity * 10000) / totalLiquidity : 
        5000; // Default to 50% if no liquidity
    
    // Calculate weighted score
    return (
        (volatilityScore * volatilityWeight) +
        (yieldScore * yieldWeight) +
        (liquidityScore * liquidityWeight)
    ) / 10000;
}

// Helper functions for accessing protocol metrics
function _getPoolUtilization(address token) internal view returns (uint256) {
    return s.tokenUtilization[token].poolUtilization;
}

function _getP2PUtilization(address token) internal view returns (uint256) {
    return s.tokenUtilization[token].p2pUtilization;
}

function _getMarketVolatility(address token) internal view returns (uint256) {
    return s.tokenMetrics[token].volatilityIndex;
}

function _getMarketDemand(address token) internal view returns (uint256) {
    return s.tokenMetrics[token].demandIndex;
}

function _getPoolLiquidity(address token) internal view returns (uint256) {
    return s.tokenBalances[token].poolLiquidity;
}

function _getP2PLiquidity(address token) internal view returns (uint256) {
    return s.tokenBalances[token].p2pLiquidity;
}

function _getPoolAPY(address token) internal view returns (uint256) {
    return s.tokenRates[token].lendingPoolRate;
}

function _getP2PAPY(address token) internal view returns (uint256) {
    return s.tokenRates[token].p2pLendingRate;
}
}