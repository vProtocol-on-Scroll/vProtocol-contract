// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IYieldOptimization} from "../interfaces/IYieldOptimization.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/**
 * @title YieldOptimizationFacet
 * @author Five Protocol
 *
 * @dev This contract provides functionality for optimizing yield on deposited assets.
 * It allows users to deposit assets and earn yield by providing liquidity to the protocol.
 */

contract YieldOptimizationFacet is IYieldOptimization {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal s;

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     * This ensures the protocol does not accept or process unsupported function calls.
     *
     * Reverts with "YieldOptimizationFacet: fallback" when an undefined function is called.
     */
    fallback() external {
        revert("YieldOptimizationFacet: fallback");
    }

    receive() external payable {}

    function initializeYieldSystem(address rewardToken) external {
        require(rewardToken != address(0), "Invalid reward token");
    }

    function stake(uint256 amount, uint256 duration, bool autoCompound) external {
        require(amount > 0, "Cannot stake 0");
        require(duration >= 7 days && duration <= 365 days, "Invalid duration");

        // Calculate loyalty multiplier (100-200 basis points)
        uint256 multiplier = 100 + (duration * 100) / (365 days);
        
        UserStake storage userStake = s.userStakes[msg.sender];
        userStake.amount = amount;
        userStake.lockStart = block.timestamp;
        userStake.lockDuration = duration;
        userStake.loyaltyMultiplier = multiplier;
        userStake.autoCompound = autoCompound;

        // Transfer tokens to contract
        IERC20(s.protocolToken).safeTransferFrom(msg.sender, address(this), amount);
        
        emit Event.Staked(msg.sender, amount, duration);
    }

    function updateStrategy(uint256 strategyId, uint256[] calldata allocationWeights) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        
        YieldStrategy storage strategy = s.yieldStrategies[strategyId];
        strategy.isActive = true;
        strategy.allocationWeights = allocationWeights;
        strategy.lastUpdated = block.timestamp;
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < allocationWeights.length; i++) {
            totalWeight += allocationWeights[i];
        }
        require(totalWeight == 10000, "Weights must total 100%");
        strategy.totalWeight = totalWeight;

        emit Event.YieldStrategyUpdated(strategyId, allocationWeights);
    }

    function compoundRewards(address user) external {
        UserStake storage userStake = s.userStakes[user];
        require(userStake.autoCompound, "Auto-compound not enabled");
        
        uint256 pendingRewards = calculatePendingRewards(user);
        require(pendingRewards > 0, "No rewards to compound");

        userStake.amount += pendingRewards;
        
        emit Event.CompoundingExecuted(user, s.protocolToken, pendingRewards);
    }

    // Internal function to calculate pending rewards
    function calculatePendingRewards(address user) internal view returns (uint256) {
        UserStake storage userStake = s.userStakes[user];
        
        // Basic reward calculation based on stake amount, duration, and multiplier
        uint256 baseReward = (userStake.amount * 
            (block.timestamp - userStake.lockStart) * 
            userStake.loyaltyMultiplier) / (365 days * 100);
            
        return baseReward;
    }
}
