// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {IRewardDistribution} from "../interfaces/IRewardDistribution.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";

contract RewardDistributionFacet is IRewardDistribution {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal s;

    
    /**
     * @notice Distributes protocol fees across different reward pools
     * @param totalFees Total fees to distribute
     */
    function distributeProtocolFees(uint256 totalFees) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(totalFees > 0, "No fees to distribute");

        // Calculate pool allocations based on configured shares
        uint256 lenderPool = (totalFees * s.rewardConfig.lenderShare) / 10000;
        uint256 borrowerPool = (totalFees * s.rewardConfig.borrowerShare) / 10000;
        uint256 liquidatorPool = (totalFees * s.rewardConfig.liquidatorShare) / 10000;
        uint256 stakerPool = (totalFees * s.rewardConfig.stakerShare) / 10000;

        // Update pool balances
        s.rewardPools.lenderPool += lenderPool;
        s.rewardPools.borrowerPool += borrowerPool;
        s.rewardPools.liquidatorPool += liquidatorPool;
        s.rewardPools.stakerPool += stakerPool;

        emit PoolsUpdated(lenderPool, borrowerPool, liquidatorPool, stakerPool);
    }

    /**
     * @notice Claims rewards for a user from specified pools
     * @param user Address of the user claiming rewards
     * @param poolTypes Array of pool types to claim from
     */
    function claimRewards(address user, PoolType[] calldata poolTypes) external {
        require(poolTypes.length > 0, "No pools specified");
        
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < poolTypes.length; i++) {
            uint256 poolRewards = calculatePoolRewards(user, poolTypes[i]);
            if (poolRewards > 0) {
                totalRewards += poolRewards;
                updateUserRewards(user, poolTypes[i]);
            }
        }
        
        require(totalRewards > 0, "No rewards to claim");
        
        // Transfer rewards to user
        IERC20(s.protocolToken).safeTransfer(user, totalRewards);
        
        emit Event.RewardDistributed(user, s.protocolToken, totalRewards);
    }

    /**
     * @notice Updates reward configuration
     * @param lenderShare New share for lenders (basis points)
     * @param borrowerShare New share for borrowers (basis points)
     * @param liquidatorShare New share for liquidators (basis points)
     * @param stakerShare New share for stakers (basis points)
     */
    function updateRewardConfig(
        uint256 lenderShare,
        uint256 borrowerShare,
        uint256 liquidatorShare,
        uint256 stakerShare
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(
            lenderShare + borrowerShare + liquidatorShare + stakerShare == 10000,
            "Shares must total 100%"
        );

        s.rewardConfig.lenderShare = lenderShare;
        s.rewardConfig.borrowerShare = borrowerShare;
        s.rewardConfig.liquidatorShare = liquidatorShare;
        s.rewardConfig.stakerShare = stakerShare;

        emit RewardConfigUpdated(lenderShare, borrowerShare, liquidatorShare, stakerShare);
    }

    /**
     * @notice Calculates rewards for a user from a specific pool
     * @param user Address of the user
     * @param poolType Type of reward pool
     */
    function calculatePoolRewards(address user, PoolType poolType) public view returns (uint256) {
        if (poolType == PoolType.LENDER) {
            return calculateLenderRewards(user);
        } else if (poolType == PoolType.BORROWER) {
            return calculateBorrowerRewards(user);
        } else if (poolType == PoolType.LIQUIDATOR) {
            return calculateLiquidatorRewards(user);
        } else if (poolType == PoolType.STAKER) {
            return calculateStakerRewards(user);
        }
        return 0;
    }

    // Internal calculation functions
    function calculateLenderRewards(address user) internal view returns (uint256) {
        UserActivity storage activity = s.userActivities[user];
        if (activity.lastLenderRewardUpdate == 0) return 0;

        uint256 timePassed = block.timestamp - activity.lastLenderRewardUpdate;
        uint256 lendingAmount = activity.totalLendingAmount;
        
        return (lendingAmount * timePassed * s.rewardConfig.lenderRewardRate) / (365 days * 10000);
    }

    function calculateBorrowerRewards(address user) internal view returns (uint256) {
        UserActivity storage activity = s.userActivities[user];
        if (activity.lastBorrowerRewardUpdate == 0) return 0;

        uint256 timePassed = block.timestamp - activity.lastBorrowerRewardUpdate;
        uint256 borrowingAmount = activity.totalBorrowingAmount;
        
        return (borrowingAmount * timePassed * s.rewardConfig.borrowerRewardRate) / (365 days * 10000);
    }

    function calculateLiquidatorRewards(address user) internal view returns (uint256) {
        UserActivity storage activity = s.userActivities[user];
        return (activity.totalLiquidationAmount * s.rewardConfig.liquidatorRewardRate) / 10000;
    }

    function calculateStakerRewards(address user) internal view returns (uint256) {
        UserStake storage stake = s.userStakes[user];
        if (stake.lockStart == 0) return 0;

        uint256 timePassed = block.timestamp - stake.lockStart;
        return (stake.amount * timePassed * stake.loyaltyMultiplier * s.rewardConfig.stakerRewardRate) 
            / (365 days * 10000);
    }

    function updateUserRewards(address user, PoolType poolType) internal {
        UserActivity storage activity = s.userActivities[user];
        
        if (poolType == PoolType.LENDER) {
            activity.lastLenderRewardUpdate = block.timestamp;
        } else if (poolType == PoolType.BORROWER) {
            activity.lastBorrowerRewardUpdate = block.timestamp;
        } else if (poolType == PoolType.LIQUIDATOR) {
            activity.totalLiquidationAmount = 0; // Reset after claiming
        }
        // Staker rewards are handled separately in the YieldOptimizationFacet
    }
}
