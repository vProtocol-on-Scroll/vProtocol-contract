// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../model/Protocol.sol";

library LibAppStorage {
    struct Layout {
        /// @dev maps collateral token to their price feed
        mapping(address token => address priceFeed) s_priceFeeds;
        /// @dev maps address of a token to see if it is loanable
        mapping(address token => bool isLoanable) s_isLoanable;
        /// @dev maps user to the value of balance he has collaterised
        mapping(address => mapping(address token => uint256 balance)) s_addressToCollateralDeposited;
        /// @dev maps user to the value of balance he has available
        mapping(address => mapping(address token => uint256 balance)) s_addressToAvailableBalance;
        /// @dev mapping the address of a user to its Struct
        mapping(address => User) addressToUser;
        /// @dev mapping of users to their address
        mapping(uint96 requestId => Request) request;
        /// @dev mapping a requestId to the collaterals used in a request
        mapping(uint96 requestId => mapping(address => uint256)) s_idToCollateralTokenAmount;
        /// @dev mapping of id to loanListing
        mapping(uint96 listingId => LoanListing) loanListings;
        /// @dev user stakes
        mapping(address => UserStake) userStakes;
        /// @dev yield strategies
        mapping(uint256 strategyId => YieldStrategy strategy) yieldStrategies;
        /// @dev user rewards
        mapping(address => uint256) userRewards;
        /// @dev user reward metrics
        mapping(address => UserRewardMetrics) userRewardMetrics;
        /// @dev reward accrual
        mapping(address => RewardAccrual) rewardAccruals;
        /// @dev user activity
        mapping(address => UserActivity) userActivities;
        /// @dev user reward checkpoints
        mapping(address => uint256) userRewardCheckpoints;
        /// @dev boost tiers
        BoostTier[] boostTiers;
        /// @dev reward config
        RewardConfig rewardConfig;
        /// @dev reward pools
        RewardPools rewardPools;
        /// @dev current strategy id
        uint256 currentStrategyId;
        /// @dev Collection of all colleteral Adresses
        address[] s_collateralToken;
        /// @dev all loanable assets
        address[] s_loanableToken;
        /// @dev request id;
        uint96 requestId;
        /// @dev the number of listings created
        uint96 listingId;
        /// @dev address of the bot that calls the liquidate function
        address botAddress;
        /// @dev uniswap router address
        address swapRouter;
        /// @dev protocol token
        address protocolToken;
        /// @dev reward token
        address rewardToken;
        /// @dev reward token decimals
        uint8 rewardTokenDecimals;
        /// @dev yield config
        YieldConfig yieldConfig;
    }
}
