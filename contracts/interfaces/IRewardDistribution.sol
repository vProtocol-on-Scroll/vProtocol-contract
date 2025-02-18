// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/LibAppStorage.sol";

interface IRewardDistribution {
    function distributeProtocolFees(uint256 totalFees) external;
    function claimRewards(address user, PoolType[] calldata poolTypes) external;
    function updateRewardConfig(
        uint256 lenderShare,
        uint256 borrowerShare,
        uint256 liquidatorShare,
        uint256 stakerShare
    ) external;
    function calculatePoolRewards(address user, PoolType poolType) external view returns (uint256);

    event PoolsUpdated(
        uint256 lenderPool,
        uint256 borrowerPool,
        uint256 liquidatorPool,
        uint256 stakerPool
    );
    
    event RewardConfigUpdated(
        uint256 lenderShare,
        uint256 borrowerShare,
        uint256 liquidatorShare,
        uint256 stakerShare
    );
} 