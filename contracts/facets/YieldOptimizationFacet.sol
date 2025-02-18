// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IYieldOptimization} from "../interfaces/IYieldOptimization.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {Constants} from "../utils/constants/Constant.sol";

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
     */
    fallback() external {
        revert("YieldOptimizationFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Initialize the yield optimization system
     * @param rewardToken Address of the token used for rewards
     */
    function initializeYieldSystem(address rewardToken) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(rewardToken != address(0), "Invalid reward token");
        require(!s.yieldConfig.isInitialized, "Already initialized");
        
        s.yieldConfig.rewardToken = rewardToken;
        s.yieldConfig.isInitialized = true;
        s.yieldConfig.epochStartTime = block.timestamp;
        s.yieldConfig.lastRewardDistribution = block.timestamp;
        s.yieldConfig.rewardEmissionRate = 100; // tokens per day, configurable
        s.yieldConfig.compoundingFrequency = 1 days;
        
        // Initialize default strategy
        YieldStrategy storage defaultStrategy = s.yieldStrategies[0];
        defaultStrategy.isActive = true;
        defaultStrategy.allocationWeights = new uint256[](1);
        defaultStrategy.allocationWeights[0] = Constants.BASIS_POINTS; // 100% to default pool
        defaultStrategy.totalWeight = Constants.BASIS_POINTS;
        defaultStrategy.lastUpdated = block.timestamp;
        s.yieldConfig.activeStrategyId = 0;
        
        emit Event.YieldSystemInitialized(rewardToken);
    }

    /**
     * @notice Stake tokens to earn rewards
     * @param amount Amount to stake
     * @param duration Period to lock tokens (in seconds)
     * @param autoCompound Whether to automatically compound rewards
     */
    function stake(uint256 amount, uint256 duration, bool autoCompound) external {
        require(s.yieldConfig.isInitialized, "Yield system not initialized");
        require(amount > 0, "Cannot stake 0");
        require(
            duration >= Constants.MIN_LOCK_PERIOD && duration <= Constants.MAX_LOCK_PERIOD,
            "Invalid duration"
        );
        
        // Calculate loyalty multiplier (100-200 basis points)
        uint256 multiplier = Constants.BASIS_POINTS + 
            (duration * Constants.BASIS_POINTS) / Constants.MAX_LOCK_PERIOD;
        
        // Update accrued rewards before modifying stake
        _updateAccruedRewards(msg.sender);
        
        UserStake storage userStake = s.userStakes[msg.sender];
        
        // Transfer tokens
        IERC20(s.protocolToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update total staked
        s.yieldConfig.totalStaked += amount;
        
        // Update user stake info
        userStake.amount += amount;
        userStake.lockStart = block.timestamp;
        userStake.lockEnd = block.timestamp + duration;
        userStake.loyaltyMultiplier = multiplier;
        userStake.autoCompound = autoCompound;
        
        // Add user to auto-compound list if enabled
        if (autoCompound && !userStake.isAutoCompoundUser) {
            s.yieldConfig.autoCompoundUsers.push(msg.sender);
            userStake.isAutoCompoundUser = true;
        }
        
        emit Event.Staked(msg.sender, amount, duration);
        emit Event.LoyaltyMultiplierUpdated(msg.sender, multiplier);
    }

    /**
     * @notice Unstake tokens and claim rewards
     * @param amount Amount to unstake (0 for all)
     */
    function unstake(uint256 amount) external {
        UserStake storage userStake = s.userStakes[msg.sender];
        require(userStake.amount > 0, "No stake found");
        require(block.timestamp >= userStake.lockEnd, "Still locked");
        
        // Update accrued rewards before unstaking
        _updateAccruedRewards(msg.sender);
        
        // Determine amount to unstake
        uint256 unstakeAmount = amount == 0 ? userStake.amount : amount;
        require(unstakeAmount <= userStake.amount, "Exceeds staked amount");
        
        // Update user stake
        userStake.amount -= unstakeAmount;
        
        // Update total staked
        s.yieldConfig.totalStaked -= unstakeAmount;
        
        // Transfer tokens back to user
        IERC20(s.protocolToken).safeTransfer(msg.sender, unstakeAmount);
        
        // If fully unstaked, reset auto-compound flag
        if (userStake.amount == 0 && userStake.isAutoCompoundUser) {
            _removeFromAutoCompound(msg.sender);
        }
        
        emit Event.Unstaked(msg.sender, unstakeAmount);
        
        // Claim rewards automatically
        claimRewards();
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() public {
        // Calculate rewards
        _updateAccruedRewards(msg.sender);
        
        uint256 pendingRewards = s.userRewards[msg.sender];
        if (pendingRewards == 0) {
            return;
        }
        
        // Reset user rewards
        s.userRewards[msg.sender] = 0;
        
        // Transfer rewards to user
        IERC20(s.yieldConfig.rewardToken).safeTransfer(msg.sender, pendingRewards);
        
        emit Event.RewardDistributed(msg.sender, s.yieldConfig.rewardToken, pendingRewards);
    }

    /**
     * @notice Update yield strategy
     * @param strategyId Strategy ID to update
     * @param allocationWeights New allocation weights (in basis points)
     */
    function updateStrategy(uint256 strategyId, uint256[] calldata allocationWeights) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        
        // Validate allocation weights
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < allocationWeights.length; i++) {
            totalWeight += allocationWeights[i];
        }
        
        require(totalWeight == Constants.BASIS_POINTS, "Weights must total 100%");
        
        // Update strategy
        YieldStrategy storage strategy = s.yieldStrategies[strategyId];
        strategy.allocationWeights = allocationWeights;
        strategy.totalWeight = totalWeight;
        strategy.lastUpdated = block.timestamp;
        strategy.isActive = true;
        
        // Set as active strategy
        s.yieldConfig.activeStrategyId = strategyId;
        
        emit Event.YieldStrategyUpdated(strategyId, allocationWeights);
    }

    /**
     * @notice Execute auto-compounding for eligible users
     */
    function executeAutoCompounding() external {
        require(
            block.timestamp >= s.yieldConfig.lastCompoundingTime + s.yieldConfig.compoundingFrequency,
            "Too soon to compound"
        );
        
        address[] memory autoCompoundUsers = s.yieldConfig.autoCompoundUsers;
        
        for (uint256 i = 0; i < autoCompoundUsers.length; i++) {
            address user = autoCompoundUsers[i];
            UserStake storage userStake = s.userStakes[user];
            
            if (!userStake.autoCompound || userStake.amount == 0) {
                continue;
            }
            
            // Update accrued rewards
            _updateAccruedRewards(user);
            
            uint256 pendingRewards = s.userRewards[user];
            if (pendingRewards == 0) {
                continue;
            }
            
            // Compound rewards by adding to stake
            userStake.amount += pendingRewards;
            s.yieldConfig.totalStaked += pendingRewards;
            
            // Reset pending rewards
            s.userRewards[user] = 0;
            
            emit Event.CompoundingExecuted(user, s.yieldConfig.rewardToken, pendingRewards);
        }
        
        s.yieldConfig.lastCompoundingTime = block.timestamp;
    }

    /**
     * @notice Update boost tiers
     * @param tiers Array of boost tiers
     */
    function updateBoostTiers(BoostTier[] calldata tiers) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        
        // Clear existing tiers
        delete s.boostTiers;
        
        // Add new tiers
        for (uint256 i = 0; i < tiers.length; i++) {
            s.boostTiers.push(tiers[i]);
        }
        
        emit Event.BoostTiersUpdated(tiers.length);
    }

    /**
     * @notice Get user's staking information
     * @param user User address
     */
    function getUserStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 lockEnd,
        uint256 loyaltyMultiplier,
        uint256 pendingRewards
    ) {
        UserStake storage userStake = s.userStakes[user];
        
        amount = userStake.amount;
        lockEnd = userStake.lockEnd;
        loyaltyMultiplier = userStake.loyaltyMultiplier;
        
        // Calculate pending rewards
        pendingRewards = _calculatePendingRewards(user);
    }

    /**
     * @notice Update accrued rewards for a user
     * @param user User address
     */
    function _updateAccruedRewards(address user) internal {
        UserStake storage userStake = s.userStakes[user];
        
        if (userStake.amount == 0) {
            return;
        }
        
        // Update global reward state if needed
        _updateGlobalRewardState();
        
        // Calculate new rewards since last update
        uint256 newRewards = _calculateUserRewards(user);
        
        // Add to accumulated rewards
        s.userRewards[user] += newRewards;
        
        // Update user's last reward checkpoint
        s.userRewardCheckpoints[user] = s.yieldConfig.lastRewardDistribution;
    }

    /**
     * @notice Update global reward state
     */
    function _updateGlobalRewardState() internal {
        if (block.timestamp <= s.yieldConfig.lastRewardDistribution) {
            return;
        }
        
        if (s.yieldConfig.totalStaked == 0) {
            s.yieldConfig.lastRewardDistribution = block.timestamp;
            return;
        }
        
        // Calculate rewards for this period
        uint256 timeDelta = block.timestamp - s.yieldConfig.lastRewardDistribution;
        uint256 rewardsForPeriod = _calculateRewardsForPeriod(timeDelta);
        
        // Update rewards per token
        s.yieldConfig.accumulatedRewardsPerToken += 
            (rewardsForPeriod * 1e18) / s.yieldConfig.totalStaked;
        
        s.yieldConfig.lastRewardDistribution = block.timestamp;
    }

    /**
     * @notice Calculate rewards for a time period
     * @param period Time period in seconds
     * @return Amount of rewards
     */
    function _calculateRewardsForPeriod(uint256 period) internal view returns (uint256) {
        // Base calculation using emission rate
        uint256 baseRewards = s.yieldConfig.rewardEmissionRate * period / 1 days;
        
        // Apply boosters based on current strategy performance
        YieldStrategy storage currentStrategy = s.yieldStrategies[s.yieldConfig.activeStrategyId];
        uint256 strategyBoost = Constants.BASIS_POINTS + (currentStrategy.performanceScore / 100);
        
        return (baseRewards * strategyBoost) / Constants.BASIS_POINTS;
    }

    /**
     * @notice Calculate user rewards
     * @param user User address
     * @return Amount of rewards
     */
    function _calculateUserRewards(address user) internal returns (uint256) {
        UserStake storage userStake = s.userStakes[user];
        
        uint256 rewardsPerTokenDelta = s.yieldConfig.accumulatedRewardsPerToken - 
            s.userRewardMetrics[user].lastRewardsPerToken;
        
        uint256 baseRewards = (userStake.amount * rewardsPerTokenDelta) / 1e18;
        
        // Apply loyalty multiplier
        uint256 boostedRewards = (baseRewards * userStake.loyaltyMultiplier) / Constants.BASIS_POINTS;
        
        // Update user's reward metrics
        s.userRewardMetrics[user].lastRewardsPerToken = s.yieldConfig.accumulatedRewardsPerToken;
        
        return boostedRewards;
    }

    /**
     * @notice Calculate pending rewards for a user
     * @param user User address
     * @return Pending rewards amount
     */
    function _calculatePendingRewards(address user) internal view returns (uint256) {
        UserStake storage userStake = s.userStakes[user];
        
        if (userStake.amount == 0) {
            return s.userRewards[user];
        }
        
        // Get current global rewards per token
        uint256 currentRewardsPerToken = _getUpdatedRewardsPerToken();
        
        // Calculate new rewards
        uint256 rewardsPerTokenDelta = currentRewardsPerToken - 
            s.userRewardMetrics[user].lastRewardsPerToken;
        
        uint256 newRewards = (userStake.amount * rewardsPerTokenDelta) / 1e18;
        uint256 boostedRewards = (newRewards * userStake.loyaltyMultiplier) / Constants.BASIS_POINTS;
        
        // Add existing rewards
        return s.userRewards[user] + boostedRewards;
    }

    /**
     * @notice Get updated rewards per token value
     * @return Updated rewards per token
     */
    function _getUpdatedRewardsPerToken() internal view returns (uint256) {
        if (s.yieldConfig.totalStaked == 0) {
            return s.yieldConfig.accumulatedRewardsPerToken;
        }
        
        uint256 timeDelta = block.timestamp - s.yieldConfig.lastRewardDistribution;
        uint256 rewardsForPeriod = _calculateRewardsForPeriod(timeDelta);
        
        return s.yieldConfig.accumulatedRewardsPerToken + 
            (rewardsForPeriod * 1e18) / s.yieldConfig.totalStaked;
    }

    /**
     * @notice Remove user from auto-compound list
     * @param user User address to remove
     */
    function _removeFromAutoCompound(address user) internal {
        address[] storage users = s.yieldConfig.autoCompoundUsers;
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                // Replace with last element and pop
                users[i] = users[users.length - 1];
                users.pop();
                s.userStakes[user].isAutoCompoundUser = false;
                break;
            }
        }
    }
}