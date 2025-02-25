// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../model/Protocol.sol";

library LibAppStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.standard.diamond.storage");

    struct Layout {
        /// @dev maps collateral token to their price feed
        mapping(address token => address priceFeed) s_priceFeeds;
        /// @dev mapping of users to their address
        mapping(address => bool) s_isLoanable;
        /// @dev mapping of requestId to request
        mapping(uint96 requestId => Request) requests;
        /// @dev mapping a requestId to the collaterals used in a request
        mapping(uint96 requestId => mapping(address => uint256)) s_idToCollateralTokenAmount;
        /// @dev mapping of id to loanListing
        mapping(uint96 listingId => LoanListing) loanListings;
        /// @dev user stakes
        mapping(address => UserStake) userStakes;
        /// @dev yield strategies
        mapping(uint256 => YieldStrategy) yieldStrategies;
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
        /// @dev referral rewards
        mapping(address => uint256) referralRewards;
        /// @dev token rates
        mapping(address => TokenRate) tokenRates;
        /// @dev token metrics
        mapping(address => TokenMetrics) tokenMetrics;
        /// @dev token utilization
        mapping(address => TokenUtilization) tokenUtilization;
        /// @dev rebalancing strategies
        mapping(uint256 => RebalancingStrategy) strategies;
        /// @dev strategy performance
        mapping(uint256 => StrategyPerformance) strategyPerformance;
        /// @dev token configs
        mapping(address => TokenConfig) tokenConfigs;
        /// @dev token balances
        mapping(address => TokenBalance) tokenBalances;
        /// @dev supported tokens
        mapping(address => bool) supportedTokens;
        /// @dev reserves
        mapping(address => ReserveData) reserves;
        /// @dev user rewards
        mapping(address => RateData) rateData;
        /// @dev vaults
        mapping(address => address) vaults;
        /// @dev vault deposits
        mapping(address => uint256) vaultDeposits;
        /// @dev vault configs
        mapping(address => VaultConfig) s_vaultConfigs;
        /// @dev user data
        mapping(address => mapping(address => UserData)) s_userData;                                 
        /// @dev rebalancing config
        RebalancingConfig rebalancingConfig;
        /// @dev strategy config
        StrategyConfig strategyConfig;
        /// @dev pool balances
        PoolBalances poolBalances;
        /// @dev p2p balances
        P2PBalances p2pBalances;
        /// @dev yield maximizer params
        YieldMaximizerParams yieldMaximizerParams;
        /// @dev risk minimizer params
        RiskMinimizerParams riskMinimizerParams;
        /// @dev balanced params
        BalancedParams balancedParams;
        /// @dev dynamic params
        DynamicParams dynamicParams;
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
        /// @dev all supported tokens
        address[] s_supportedTokens;
        /// @dev request id;
        uint96 requestId;
        /// @dev the number of listings created
        uint96 listingId;
        /// @dev address of the bot that calls the liquidate function
        address botAddress;
        /// @dev uniswap router address
        address swapRouter;
        /// @dev protocolFeeRecipient   
        address s_protocolFeeRecipient;
        /// @dev protocolFeeBps
        uint256 s_protocolFeeBps;
        /// @dev maxProtocolLTVBps
        uint256 s_maxProtocolLTVBps;
        /// @dev paused
        bool isPaused;
        /// @dev failsafe to stop the contract from being used
        bool isP2pStopped;
        /// @dev protocol token
        address protocolToken;
        /// @dev reward token
        address rewardToken;
        /// @dev reward token decimals
        uint8 rewardTokenDecimals;
        /// @dev yield config
        YieldConfig yieldConfig;
        /// @dev lending pool config
        LendingPoolConfig lendingPoolConfig;
        /// @dev protocol fees
        uint256 protocolFees;
        /// @dev user positions
        mapping(address => UserPosition) userPositions;    
        /// @dev token data
        mapping(address => TokenData) tokenData;
    
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

}
