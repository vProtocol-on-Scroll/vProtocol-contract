// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {PoolType} from "./Protocol.sol";

library Event {
    event RequestCreated(
        address indexed _borrower,
        uint96 indexed requestId,
        uint _amount,
        uint16 _interest
    );

    event RequestServiced(
        uint96 indexed _requestId,
        address indexed _lender,
        address indexed _borrower,
        uint256 _amount
    );
    event RequestClosed(uint96 indexed _requestId, address indexed _borrower);
    event CollateralWithdrawn(
        address indexed sender,
        address indexed _tokenCollateralAddress,
        uint256 _amount
    );
    event UpdatedCollateralTokens(address indexed sender, uint8 newTokensCount);
    event AcceptedListedAds(
        address indexed sender,
        uint96 indexed id,
        uint256 indexed amount,
        uint8 adStatus
    );
    event LoanRepayment(address indexed sender, uint96 id, uint256 amount);
    event UpdateLoanableToken(
        address indexed _token,
        address _priceFeed,
        address indexed sender
    );
    event CollateralDeposited(
        address indexed _sender,
        address indexed _token,
        uint256 _value
    );

    event withdrawnAdsToken(
        address indexed sender,
        uint96 indexed _orderId,
        uint8 indexed orderStatus,
        uint256 _amount
    );

    event LoanListingCreated(
        uint96 indexed listingId,
        address indexed sender,
        address indexed tokenAddress,
        uint256 amount
    );

    event RequestLiquidated(
        uint96 indexed requestId,
        address indexed lenderAddress,
        uint256 indexed totalRepayment
    );

    event P2pFailSafeStatus(bool status);
    event BoostTierUpdated(uint256 requiredStake, uint256 boostPercentage);

    event RewardConfigUpdated(uint256 lenderShare, uint256 borrowerShare, uint256 liquidatorShare, uint256 stakerShare);

    event RewardPoolsUpdated(uint256 lenderPool, uint256 borrowerPool, uint256 liquidatorPool, uint256 stakerPool);

    event YieldSystemInitialized(address indexed rewardToken);

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);

    event Unstaked(address indexed user, uint256 amount);

    event YieldStrategyUpdated(uint256 strategyId, uint256[] allocationWeights);

    event CompoundingExecuted(address indexed user, address indexed token, uint256 amount);

    event LoyaltyMultiplierUpdated(address indexed user, uint256 multiplier);

    event RewardDistributed(address indexed user, address indexed token, uint256 amount);

    event BoostTiersUpdated(uint256 tiersLength);

    event RewardsPaused();

    event RewardsUnpaused();

    event PoolBalanceAdded(PoolType poolType, uint256 amount);

    event ReferralRewardAdded(address indexed referrer, address indexed referee, uint256 amount);

    event UserBoostUpdated(address indexed user, uint256 boost);

    event UserRewardUpdated(address indexed user, uint256 reward);

    event UserRewardCheckpointed(address indexed user, uint256 checkpoint);    

    event RewardSystemInitialized(address indexed rewardToken);

    event PoolsUpdated(uint256 lenderPool, uint256 borrowerPool, uint256 liquidatorPool, uint256 stakerPool);

    event TokenConfigUpdated(address indexed token, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus);

    event TokenRateUpdated(address indexed token, uint256 lendingPoolRate, uint256 p2pLendingRate);

    event TokenUtilizationUpdated(address indexed token, uint256 utilization);

    event TokenMetricsUpdated(address indexed token, uint256 totalDeposits, uint256 totalBorrowed, uint256 totalInterestAccrued);

    event TokenBalancesUpdated(address indexed token, uint256 poolLiquidity, uint256 p2pLiquidity);

    event TokenSupported(address indexed token);

    event TokenUnsupported(address indexed token);

    event TokenPaused(address indexed token);

    event TokenUnpaused(address indexed token);

    event LendingPoolConfigUpdated(uint256 optimalUtilization, uint256 baseRate, uint256 slopeRate, uint256 slopeExcess);
    event LendingPoolPaused(address indexed token);
    event LendingPoolUnpaused(address indexed token);

     // Initialization and configuration events
    event LendingPoolInitialized(
        uint256 reserveFactor,
        uint256 optimalUtilization,
        uint256 baseRate,
        uint256 slopeRate
    );

    event TokenAdded(
        address indexed token,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    );

    event TokenConfigurationUpdated(
        address indexed token,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    );

    event PoolPauseSet(bool paused);

    // Deposit and withdrawal events
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares
    );

    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares
    );

    // Borrowing and repayment events
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 normalizedDebt
    );

    event Repaid(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 normalizedDebt
    );


    // Liquidation events
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        address indexed debtToken,
        address collateralToken,
        uint256 debtAmount,
        uint256 collateralAmount
    );

    // Vault related events
    event VaultDeployed(
        address indexed token,
        address indexed vault,
        string name,
        string symbol
    );

    event DepositedFromVault(
        address indexed vault,
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event WithdrawnFromVault(
        address indexed vault,
        address indexed user,
        address indexed token,
        uint256 amount
    );

    // Rate update events
    event RatesUpdated(
        address indexed token,
        uint256 depositRate,
        uint256 borrowRate,
        uint256 utilization
    );

    // Index update events
    event IndexesUpdated(
        address indexed token,
        uint256 liquidityIndex,
        uint256 borrowIndex
    );

    event ReserveDataUpdated(
        address indexed token,
        uint256 totalDeposits,
        uint256 totalBorrows,
        uint256 totalDepositShares,
        uint256 normalizedDebt,
        uint256 liquidityIndex,
        uint256 borrowIndex,
        uint256 lastUpdateTimestamp
    );
    
}
