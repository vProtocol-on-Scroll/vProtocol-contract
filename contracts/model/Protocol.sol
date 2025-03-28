// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;


/**
 * @dev Struct to store information about a loan request.
 * @param requestId Unique identifier for the loan request.
 * @param author Address of the user who created the request.
 * @param amount Amount of tokens the user is requesting to borrow.
 * @param interest Interest rate set by the borrower for this loan request.
 * @param totalRepayment Total repayment amount calculated as (amount + interest).
 * @param returnDate The timestamp when the loan is due for repayment.
 * @param lender Address of the lender who accepted the request (if any).
 * @param loanRequestAddr The unique address associated with this specific loan request.
 * @param collateralTokens Array of token addresses offered as collateral for the loan.
 * @param status The current status of the loan request, represented by the `Status` enum.
 */
struct Request {
    uint96 requestId;
    address author;
    uint256 amount;
    uint16 interest;
    uint256 totalRepayment;
    uint256 returnDate;
    uint256 expirationDate;
    address lender;
    address loanRequestAddr;
    address[] collateralTokens;
    Status status;
}

/**
 * @dev Struct to store information about a loan listing created by a lender.
 * @param listingId Unique identifier for the loan listing.
 * @param author Address of the lender creating the listing.
 * @param tokenAddress The address of the token being lent.
 * @param amount Total amount the lender is willing to lend.
 * @param min_amount Minimum amount the lender is willing to lend in a single transaction.
 * @param max_amount Maximum amount the lender is willing to lend in a single transaction.
 * @param returnDate The due date for loan repayment specified by the lender.
 * @param interest Interest rate offered by the lender.
 * @param listingStatus The current status of the loan listing, represented by the `ListingStatus` enum.
 */
struct LoanListing {
    uint96 listingId;
    address author;
    address tokenAddress;
    uint256 amount;
    uint256 min_amount;
    uint256 max_amount;
    uint256 returnDuration;
    uint256 expirationDate;
    uint16 interest;
    ListingStatus listingStatus;
}

enum Round {
    UP,
    DOWN
}

/**
 * @dev Struct to store information about a collateral configuration.
 * @param isEnabled Whether the collateral is enabled for lending.
 * @param ltv Loan-to-value ratio (in basis points).
 * @param liquidationThreshold Liquidation threshold (in basis points).
 * @param liquidationPenalty Liquidation penalty (in basis points).
 */
struct CollateralConfig {
    bool isEnabled;
    uint256 ltv;
    uint256 liquidationThreshold;
    uint256 liquidationPenalty;
}

/**
 * @dev Struct to store information about a yield strategy.
 * @param isActive Whether the yield strategy is active.
 * @param allocationWeights Array of weights for different asset classes.
 * @param totalWeight Total weight of all allocation weights.
 * @param lastUpdated Timestamp of the last update.
 * @param performanceScore Historical performance score.
 */
struct YieldStrategy {
    bool isActive;
    uint256[] allocationWeights; // weights in basis points
    uint256 totalWeight;
    uint256 lastUpdated;
    uint256 performanceScore; // historical performance in basis points
}

/**
 * @dev Struct to store information about a yield configuration.
 * @param isInitialized Whether the yield configuration is initialized.
 * @param rewardToken The address of the reward token.
 * @param totalStaked The total amount of tokens staked.
 * @param epochStartTime The timestamp when the epoch started.
 * @param lastRewardDistribution The timestamp when the last reward distribution occurred.
 * @param rewardEmissionRate The rate at which rewards are emitted.
 * @param accumulatedRewardsPerToken The accumulated rewards per token.
 * @param activeStrategyId The ID of the active yield strategy.
 * @param lastCompoundingTime The timestamp when the last compounding occurred.
 * @param compoundingFrequency The frequency of compounding.
 * @param autoCompoundUsers The addresses of users who have auto-compounded.
 */

struct YieldConfig {
    bool isInitialized;
    address rewardToken;
    uint256 totalStaked;
    uint256 epochStartTime;
    uint256 lastRewardDistribution;
    uint256 rewardEmissionRate;
    uint256 accumulatedRewardsPerToken;
    uint256 activeStrategyId;
    uint256 lastCompoundingTime;
    uint256 compoundingFrequency;
    address[] autoCompoundUsers;
}

/**
 * @dev Struct to store information about a user's stake in the protocol.
 * @param amount The amount of tokens staked.
 * @param lockStart The timestamp when the stake was locked.
 * @param lockDuration The duration of the stake.
 * @param loyaltyMultiplier The loyalty multiplier for the stake.
 * @param autoCompound Whether the stake is set to auto-compound.
 * @param isAutoCompoundUser Whether the user is an auto-compounding user.
 */
struct UserStake {
    uint256 amount;
    uint256 lockStart;
    uint256 lockEnd;
    uint256 loyaltyMultiplier;
    bool autoCompound;
    bool isAutoCompoundUser;
}

/**
 * @dev Struct to store information about a user's reward metrics.
 * @param lastRewardsPerToken The last rewards per token.
 * @param lastUpdateTimestamp The timestamp of the last update.
 */
struct UserRewardMetrics {
    uint256 lastRewardsPerToken;
    uint256 lastUpdateTimestamp;
}

/**
 * @dev Struct to store information about a boost tier.
 * @param requiredStake The required stake for the tier.
 * @param boostPercentage The boost percentage for the tier.
 */
struct BoostTier {
    uint256 requiredStake;
    uint256 boostPercentage;
}

/**
 * @dev Struct to store information about a reward accrual.
 * @param lastAccrualTimestamp The timestamp of the last reward accrual.
 * @param accumulatedRewards The total accumulated rewards.
 * @param rewardsPerToken The rewards per token.
 * @param totalStaked The total amount of tokens staked.
 */
struct RewardAccrual {
    uint256 lastAccrualTimestamp;
    uint256 accumulatedRewards;
    uint256 rewardsPerToken;
    uint256 totalStaked;
}

/**
 * @dev Struct to store information about a reward configuration.
 * @param initialized Whether the reward configuration is initialized.
 * @param rewardsPaused Whether the rewards are paused.
 * @param lenderShare The share of rewards for lenders.
 * @param borrowerShare The share of rewards for borrowers.
 * @param liquidatorShare The share of rewards for liquidators.
 * @param stakerShare The share of rewards for stakers.
 * @param lenderRewardRate The reward rate for lenders.
 * @param borrowerRewardRate The reward rate for borrowers.
 * @param liquidatorRewardRate The reward rate for liquidators.
 * @param stakerRewardRate The reward rate for stakers.
 * @param referralRewardRate The reward rate for referrals.
 */
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

/**
 * @dev Struct to store information about reward pools.
 * @param lenderPool The amount of rewards for lenders.
 * @param borrowerPool The amount of rewards for borrowers.
 * @param liquidatorPool The amount of rewards for liquidators.
 * @param stakerPool The amount of rewards for stakers.
 */
struct RewardPools {
    uint256 lenderPool;
    uint256 borrowerPool;
    uint256 liquidatorPool;
    uint256 stakerPool;
}

/**
 * @dev Struct to store information about user activity.
 * @param totalLendingAmount The total amount of lending.
 * @param totalBorrowingAmount The total amount of borrowing.
 * @param totalLiquidationAmount The total amount of liquidation.
 */
struct UserActivity {
    uint256 totalLendingAmount;
    uint256 totalBorrowingAmount;
    uint256 totalLiquidationAmount;
    uint256 lastLenderRewardUpdate;
    uint256 lastBorrowerRewardUpdate;
}

/**
 * @dev Enum representing the type of reward pool.
 */
enum PoolType {
    LENDER,
    BORROWER,
    LIQUIDATOR,
    STAKER
}

// Token-specific balances
struct TokenBalance {
    uint256 poolLiquidity;
    uint256 p2pLiquidity;
}

/**
 * @notice Configuration parameters for each supported token
 * @param ltv Loan-to-value ratio in basis points (e.g., 7500 = 75%)
 * @param liquidationThreshold Liquidation threshold in basis points (e.g., 8250 = 82.5%)
 * @param liquidationBonus Liquidation bonus in basis points (e.g., 10500 = 105%)
 * @param isActive Whether the token is currently active in the protocol
 * @param reserveFactor Reserve factor in basis points (e.g., 2000 = 20%)
 */
struct TokenConfig {
    uint256 ltv;                    // Maximum loan-to-value ratio
    uint256 liquidationThreshold;   // Threshold at which position can be liquidated
    uint256 liquidationBonus;       // Bonus for liquidators
    bool isActive;                  // Whether token is active
    uint256 reserveFactor;          // Percentage of interest that goes to reserves
}

/**
 * @dev Struct to store information about a reserve.
 * @param totalDeposits Total deposits in underlying
 * @param totalBorrows Total borrows in underlying
 * @param totalDepositShares Total shares issued
 * @param normalizedDebt Normalized debt amount
 * @param liquidityIndex Liquidity index for interest accrual
 * @param borrowIndex Borrow index for interest accrual
 * @param lastUpdateTimestamp Last update timestamp
 */
struct ReserveData {
    uint256 totalDeposits;          // Total deposits in underlying
    uint256 totalBorrows;           // Total borrows in underlying
    uint256 totalDepositShares;     // Total shares issued
    uint256 normalizedDebt;         // Normalized debt amount
    uint256 liquidityIndex;         // Liquidity index for interest accrual
    uint256 borrowIndex;            // Borrow index for interest accrual
    uint256 lastUpdateTimestamp;    // Last update timestamp
}


// Token-specific rates
struct TokenRate {
    uint256 lendingPoolRate;
    uint256 p2pLendingRate;
}

// Token-specific metrics
struct TokenMetrics {
    uint256 volatilityIndex;
    uint256 demandIndex;
}

struct TokenUtilization {
    uint256 poolUtilization;
    uint256 p2pUtilization;
}

// Rebalancing Configuration
struct RebalancingConfig {
    bool isInitialized;
    uint256 minRebalanceThreshold;
    uint256 maxRebalanceThreshold;
    uint256 rebalanceCooldown;
    uint256 lastRebalanceTime;
    uint256 minEfficiencyThreshold;
    uint256 minAPYDifference;
    bool emergencyPaused;
    mapping(address => bool) authorizedRebalancers;
    uint256 rebalanceCount;
    RebalanceAction lastRebalanceAction;
    uint256 lastRebalanceAmount;
    uint256 totalAmountRebalanced;
}


struct LendingPoolConfig {
    bool isInitialized;
    uint256 reserveFactor;           // Global reserve factor
    uint256 optimalUtilization;      // Optimal utilization rate
    uint256 baseRate;                // Base interest rate
    uint256 slopeRate;               // Rate increase slope
    uint256 slopeExcess;             // Excess utilization slope
    uint256 lastUpdateTimestamp;     // Last time rates were updated
    bool isPaused;                   // Emergency pause flag
}

// Rate and Reserve Data structs
struct RateData {
    uint256 depositRate;            // Current deposit APY
    uint256 borrowRate;             // Current borrow APY
}


// Strategy Configuration
struct StrategyConfig {
    bool isInitialized;
    StrategyType activeStrategy;
    uint256 activeStrategyId;
    uint256 lastStrategyUpdate;
    RiskProfile riskProfile;
}

// Rebalancing Strategy
struct RebalancingStrategy {
    StrategyType strategyType;
    bool isActive;
    uint256 createdAt;
    uint256 lastUpdated;
    bytes parameters;
}

// Strategy Performance Metrics
struct StrategyPerformance {
    uint256 totalAmountRebalanced;
    uint256 performanceScore;
    int256 yieldImprovement;
    uint256 executionCount;
}

// Pool and P2P Balance Tracking
struct PoolBalances {
    uint256 totalDeposits;
    uint256 totalBorrows;
}

struct P2PBalances {
    uint256 totalLendOrders;
    uint256 totalBorrowOrders;
}

// Strategy-specific parameters
struct YieldMaximizerParams {
    uint256 maxShiftPercentage;
    uint256 minYieldDifferential;
}

struct RiskMinimizerParams {
    uint256 targetUtilization;
    uint256 maxVolatilityTolerance;
}

struct BalancedParams {
    uint256 poolAllocationTarget;
    uint256 p2pAllocationTarget;
}

struct DynamicParams {
    uint256 volatilityWeight;
    uint256 yieldWeight;
    uint256 liquidityWeight;
}

struct UserPosition {
    // Combined user position tracking
    mapping(address => uint256) poolDeposits;      // token => amount
    mapping(address => uint256) poolBorrows;       // token => normalized debt
    mapping(address => uint256) p2pLentAmount;     // token => amount
    mapping(address => uint256) p2pBorrowedAmount; // token => amount
    mapping(address => uint256) collateral;        // token => amount
    uint256 totalLoanCollectedUSD;                 // Combined USD value of all loans
    uint256 lastUpdate;                            // Last position update timestamp
}

struct TokenData {
    // Combined token-specific data
    uint256 poolLiquidity;          // Amount available in lending pool
    uint256 p2pLiquidity;           // Amount locked in P2P loans
    uint256 totalDeposits;          // Total deposits across both systems
    uint256 totalBorrows;           // Total borrows across both systems
    uint256 normalizedPoolDebt;     // For pool interest calculations
    uint256 lastUpdateTimestamp;    // Last update of rates
    bool isLoanable;                // If token can be borrowed
    address priceFeed;              // Price oracle address
    address vault;                   // Associated ERC4626 vault
}

// Rebalancing Action Types
enum RebalanceAction {
    NONE,
    SHIFT_TO_POOL,
    SHIFT_TO_P2P,
    OPTIMIZE_ALLOCATION
}

// Strategy Types
enum StrategyType {
    BALANCED,
    YIELD_MAXIMIZER,
    RISK_MINIMIZER,
    DYNAMIC,
    CUSTOM
}

// Risk Profile Types
enum RiskProfile {
    CONSERVATIVE,
    MODERATE,
    AGGRESSIVE
}

// Market Condition Types
enum MarketCondition {
    NORMAL,
    VOLATILE,
    HIGH_DEMAND,
    LOW_DEMAND,
    UNSTABLE
}

/**
 * @dev Enum for loan status
 */
enum LoanStatus {
    NONE,
    ACTIVE,
    REPAID,
    LIQUIDATED,
    DEFAULTED
}



/**
 * @dev Enum representing the status of a loan request.
 * OPEN - The loan request is open and waiting for a lender.
 * SERVICED - The loan request has been accepted and is currently serviced by a lender.
 * CLOSED - The loan request has been closed (either fully repaid or canceled).
 */
enum Status {
    OPEN,
    SERVICED,
    CLOSED,
    LIQUIDATED
}

/**
 * @dev Enum representing the status of a loan listing.
 * OPEN - The loan listing is available and open to borrowers.
 * CLOSED - The loan listing is closed and no longer available.
 */
enum ListingStatus {
    OPEN,
    CLOSED
}

//COREPOOL CONFIG
// Expanded User State
struct UserData {
    uint256 depositedAssets;
    uint256 borrowedAssets;
    uint256 interestAccrued;
    uint256 shares;
    uint256 lastUpdated;
    uint256 collateralUsed;
}

struct VaultConfig {
    uint256 ltvBps; // Loan-to-Value (8500 = 85%)
    uint256 liquidationThresholdBps;
    uint256 totalDeposits;
    uint256 totalBorrowed;
}

/**
 * @dev Struct to store lending offer data for matching
 */
struct LendingOffer {
    uint96 listingId;
    address author;
    uint256 amount;
    uint256 minAmount;
    uint256 maxAmount;
    uint16 interest;
    uint256 returnDuration;
    address tokenAddress;
    uint256 score;
}


// Helper struct for tracking collateral info during loan creation
struct CollateralInfo {
    address token;
    uint256 amount;
    uint256 value;
}

// Updated Pool Loan structure to support multiple collaterals
struct PoolLoan {
    address borrower;
    address borrowToken;
    uint256 borrowAmount;
    uint256 interestRate;
    uint256 lastInterestUpdate;
    LoanStatus status;
    address[] collaterals;
    mapping(address => uint256) collateralAmounts;
}

/**
 * @dev Struct to store details about a pool loan.
 * @param borrower The address of the borrower
 * @param borrowToken The address of the token being borrowed
 * @param borrowAmount The amount of tokens being borrowed
 * @param interestRate The interest rate for the loan
 * @param lastInterestUpdate The timestamp of the last interest update
 * @param status The status of the loan
 * @param collaterals The addresses of the collateral tokens
 */                                                 
struct PoolLoanDetails {
    address borrower;
    address borrowToken;
    uint256 borrowAmount;
    uint256 interestRate;
    uint256 lastInterestUpdate;
    LoanStatus status;
    address[] collaterals;
}

/**
 * @dev Struct to store flash loan configuration.
 * @param isInitialized Whether the flash loan system is initialized
 * @param feeBps Flash loan fee in basis points (e.g., 9 = 0.09%)
 * @param totalFlashLoans Total number of flash loans executed
 * @param totalFeesCollected Total fees collected from flash loans
 */
struct FlashLoanConfig {
    bool isInitialized;
    uint256 feeBps;
    uint256 totalFlashLoans;
    uint256 totalFeesCollected;
}