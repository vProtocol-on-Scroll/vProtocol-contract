// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../model/Protocol.sol";

library LibAppStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.standard.diamond.storage");

    struct Layout {
        // Token configuration
        mapping(address token => address priceFeed) s_priceFeeds;
        mapping(address => bool) s_isLoanable;
        mapping(address => bool) supportedTokens;
        mapping(address => TokenConfig) tokenConfigs;
        address[] s_supportedTokens;
        
        // P2P loan requests
        mapping(uint96 requestId => Request) requests;
        mapping(uint96 requestId => mapping(address => uint256)) s_idToCollateralTokenAmount;
        uint96 requestId;
        
        // P2P loan listings
        mapping(uint96 listingId => LoanListing) loanListings;
        uint96 listingId;
        
        // Pool loans (updated structure)
        mapping(uint256 => PoolLoan) poolLoans;
        mapping(address => uint256[]) userPoolLoans;
        uint256 nextLoanId;
        
        // User positions and collateral
        mapping(address => UserPosition) userPositions;
        mapping(address => mapping(address => UserData)) s_userData;
        address[] s_collateralToken;
        
        // Token data and balances
        mapping(address => TokenData) tokenData;
        mapping(address => TokenBalance) tokenBalances;
        mapping(address => ReserveData) reserves;
        mapping(address => RateData) rateData;
        mapping(address => TokenUtilization) tokenUtilization;
        mapping(address => TokenMetrics) tokenMetrics;
        mapping(address => TokenRate) tokenRates;
        
        // Vault integration
        mapping(address => address) vaults;
        mapping(address => uint256) vaultDeposits;
        mapping(address => VaultConfig) s_vaultConfigs;
        
        // Rebalancing
        RebalancingConfig rebalancingConfig;
        StrategyConfig strategyConfig;
        PoolBalances poolBalances;
        P2PBalances p2pBalances;
        
        // Yield optimization
        YieldConfig yieldConfig;
        mapping(uint256 => YieldStrategy) yieldStrategies;
        YieldMaximizerParams yieldMaximizerParams;
        RiskMinimizerParams riskMinimizerParams;
        BalancedParams balancedParams;
        DynamicParams dynamicParams;
        
        // Rewards
        RewardConfig rewardConfig;
        RewardPools rewardPools;
        mapping(address => UserStake) userStakes;
        mapping(address => uint256) userRewards;
        mapping(address => UserRewardMetrics) userRewardMetrics;
        mapping(address => RewardAccrual) rewardAccruals;
        mapping(address => UserActivity) userActivities;
        mapping(address => uint256) userRewardCheckpoints;
        mapping(address => uint256) referralRewards;
        BoostTier[] boostTiers;
        
        // Protocol config
        address botAddress;
        address swapRouter;
        address s_protocolFeeRecipient;
        uint256 s_protocolFeeBps;
        uint256 s_maxProtocolLTVBps;
        
        // Protocol state
        bool isPaused;
        bool isP2pStopped;
        
        // Protocol tokens
        address protocolToken;
        address rewardToken;
        uint8 rewardTokenDecimals;
        
        // Lending pool config
        LendingPoolConfig lendingPoolConfig;
        
        // Rebalancing strategy
        mapping(uint256 => RebalancingStrategy) strategies;
        mapping(uint256 => StrategyPerformance) strategyPerformance;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }

}
