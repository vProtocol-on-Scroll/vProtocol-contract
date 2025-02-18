// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IYieldOptimization {
    /**
     * @notice Allows users to stake tokens with a specified lock duration
     * @param amount The amount of tokens to stake
     * @param duration The lock duration in seconds (7-365 days)
     * @param autoCompound Whether to enable auto-compounding of rewards
     */
    function stake(uint256 amount, uint256 duration, bool autoCompound) external;

    /**
     * @notice Updates the yield strategy allocation weights
     * @param p2pWeight Weight for P2P lending (in basis points)
     * @param poolWeight Weight for pool lending (in basis points)
     */
    function updateStrategy(uint256 p2pWeight, uint256 poolWeight) external;

    /**
     * @notice Compounds rewards for a user if auto-compound is enabled
     * @param user Address of the user to compound rewards for
     */
    function compoundRewards(address user) external;

    // Events
    event StrategyUpdated(uint256 p2pWeight, uint256 poolWeight);
    event Staked(address indexed user, uint256 amount, uint256 duration);
    event RewardsCompounded(address indexed user, uint256 amount);
} 