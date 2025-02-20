// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


// Create a helper contract for direct storage modification
contract StorageHelper {
    // Adjust this struct to match your actual storage layout
    struct RewardConfig {
        bool initialized;
        bool rewardsPaused;
        uint256 lenderShare;
        uint256 borrowerShare;
        uint256 liquidatorShare;
        uint256 stakerShare;
        uint256 lenderRewardRate;
        uint256 borrowerRewardRate;
        uint256 liquidatorRewardRate;
        uint256 stakerRewardRate;
        uint256 referralRewardRate;
    }

    struct RewardPools {
        uint256 lenderPool;
        uint256 borrowerPool;
        uint256 liquidatorPool;
        uint256 stakerPool;
    }

    struct UserActivity {
        uint256 totalLendingAmount;
        uint256 totalBorrowingAmount;
        uint256 totalLiquidationAmount;
        uint256 lastLenderRewardUpdate;
        uint256 lastBorrowerRewardUpdate;
    }

    struct UserStake {
        uint256 amount;
        uint256 lockStart;
        uint256 lockEnd;
        uint256 loyaltyMultiplier;
        bool autoCompound;
    }

    // Storage slots should match exactly with LibAppStorage
    bytes32 constant STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    function getRewardConfig() internal pure returns (RewardConfig storage rc) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            rc.slot := position
        }
    }

    function getRewardPools() internal pure returns (RewardPools storage rp) {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "rewardPools"));
        assembly {
            rp.slot := position
        }
    }

    function getUserActivity(address user) internal pure returns (UserActivity storage ua) {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "userActivities", user));
        assembly {
            ua.slot := position
        }
    }

    function getUserStake(address user) internal pure returns (UserStake storage us) {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "userStakes", user));
        assembly {
            us.slot := position
        }
    }

    function getProtocolFees() internal pure returns (uint256 fees) {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "protocolFees"));
        assembly {
            fees := position
        }
    }

    function getReferralRewards(address user) internal pure returns (uint256 rewards) {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "referralRewards", user));
        assembly {
            rewards := position
        }
    }

    function setProtocolFees(uint256 fees) internal {
        bytes32 position = keccak256(abi.encodePacked(STORAGE_POSITION, "protocolFees"));
        assembly {
            sstore(position, fees)
        }
    }
}