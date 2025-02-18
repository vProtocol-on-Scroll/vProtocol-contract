// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IYieldOptimization} from "../interfaces/IYieldOptimization.sol";

/**
 * @title YieldOptimizationFacet
 * @author Five Protocol
 *
 * @dev This contract provides functionality for optimizing yield on deposited assets.
 * It allows users to deposit assets and earn yield by providing liquidity to the protocol.
 */

contract YieldOptimizationFacet is IYieldOptimization {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct YieldStrategy {
        uint256 p2pAllocationWeight;    // Weight for P2P lending (basis points)
        uint256 poolAllocationWeight;    // Weight for pool lending (basis points)
        uint256 lastRebalance;          // Timestamp of last rebalance
        uint256 historicalApy;          // Historical APY (basis points)
    }

    struct UserStake {
        uint256 amount;
        uint256 lockStart;
        uint256 lockDuration;
        uint256 loyaltyMultiplier;      // Stored as basis points (100 = 1x)
        bool autoCompound;
    }

    event StrategyUpdated(uint256 p2pWeight, uint256 poolWeight);
    event Staked(address indexed user, uint256 amount, uint256 duration);
    event RewardsCompounded(address indexed user, uint256 amount);

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
        userStake.amount += amount;
        userStake.lockStart = block.timestamp;
        userStake.lockDuration = duration;
        userStake.loyaltyMultiplier = multiplier;
        userStake.autoCompound = autoCompound;

        // Transfer tokens to contract
        IERC20(s.protocolToken).safeTransferFrom(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount, duration);
    }

    function updateStrategy(uint256 p2pWeight, uint256 poolWeight) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(p2pWeight + poolWeight == 10000, "Weights must total 100%");

        s.currentStrategy.p2pAllocationWeight = p2pWeight;
        s.currentStrategy.poolAllocationWeight = poolWeight;
        s.currentStrategy.lastRebalance = block.timestamp;

        emit StrategyUpdated(p2pWeight, poolWeight);
    }

    function compoundRewards(address user) external {
        UserStake storage userStake = s.userStakes[user];
        require(userStake.autoCompound, "Auto-compound not enabled");
        
        uint256 pendingRewards = calculatePendingRewards(user);
        require(pendingRewards > 0, "No rewards to compound");

        userStake.amount += pendingRewards;
        
        emit RewardsCompounded(user, pendingRewards);
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
