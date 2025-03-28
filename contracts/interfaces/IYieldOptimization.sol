// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../model/Protocol.sol";

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
     * @param strategyId The ID of the strategy to update
     * @param allocationWeights Array of weights for different asset classes
     */
    function updateStrategy(uint256 strategyId, uint256[] calldata allocationWeights) external;
} 