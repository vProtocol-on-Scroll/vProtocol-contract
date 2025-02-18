// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

library Event {
    event RequestCreated(
        address indexed _borrower,
        uint96 indexed requestId,
        uint _amount,
        uint16 _interest,
        uint16 indexed _chainId
    );

    event RequestServiced(
        uint96 indexed _requestId,
        address indexed _lender,
        address indexed _borrower,
        uint256 _amount,
        uint16 _chainId
    );
    event RequestClosed(uint96 indexed _requestId, address indexed _borrower);
    event CollateralWithdrawn(
        address indexed sender,
        address indexed _tokenCollateralAddress,
        uint256 _amount,
        uint16 _chainId
    );
    event UpdatedCollateralTokens(address indexed sender, uint8 newTokensCount);
    event AcceptedListedAds(
        address indexed sender,
        uint96 indexed id,
        uint256 indexed amount,
        uint8 adStatus
    );
    event LoanRepayment(
        address indexed sender,
        uint96 id,
        uint256 amount,
        uint16 indexed chainId
    );
    event UpdateLoanableToken(
        address indexed _token,
        address _priceFeed,
        address indexed sender
    );
    event CollateralDeposited(
        address indexed _sender,
        address indexed _token,
        uint256 _value,
        uint16 indexed _chainId
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
        uint256 amount,
        uint16 chainId
    );

    event RequestLiquidated(
        uint96 indexed requestId,
        address indexed lenderAddress,
        uint256 indexed totalRepayment
    );

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
}
