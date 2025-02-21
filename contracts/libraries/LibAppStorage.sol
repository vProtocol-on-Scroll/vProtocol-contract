// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../model/Protocol.sol";

library LibAppStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.standard.diamond.storage");

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
        /// @dev token balances
        mapping(address => TokenBalance) tokenBalances;
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
        mapping(address => TokenConfig) tokenConfigs;        // token => config
        /// @dev supported tokens
        mapping(address => bool) supportedTokens;            // token => is supported
        /// @dev reserves
        mapping(address => ReserveData) reserves;
        /// @dev user deposits
        mapping(address => mapping(address => uint256)) userDeposits;
        /// @dev user borrows
        mapping(address => mapping(address => uint256)) userBorrows;
        /// @dev user collateral
        mapping(address => mapping(address => uint256)) userCollateral;
        /// @dev user rewards
        mapping(address => RateData) rateData;
        /// @dev vaults
        mapping(address => address) vaults;
        /// @dev vault deposits
        mapping(address => uint256) vaultDeposits;
        /// @dev all tokens
        address[] allTokens;                                 // list of all supported tokens
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
        //  COREPOOLCONFIG STATE VARIABLES
        // Vault Management
        mapping(address => address) assetToVault; // assetAddress => vaultAddress
        mapping(address => VaultConfig) s_vaultConfigs;
        mapping(address => mapping(address => UserData)) s_userData; // user => vault => state
        // Protocol Configuration
        address s_protocolFeeRecipient;
        uint256 s_protocolFeeBps; // Shared fee across all vaults
        uint256 s_maxProtocolLTVBps;
        bool paused;
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
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            l.slot := position
        }
    }
}
