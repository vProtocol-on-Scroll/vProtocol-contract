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


    event AssetSupplied(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event VaultCreated(address indexed asset, address vault);
    event FeesUpdated(uint256 feeBps);
    event VaultConfigUpdated(address vault, uint256 ltvBps, uint256 liquidationThresholdBps);

    
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
}
