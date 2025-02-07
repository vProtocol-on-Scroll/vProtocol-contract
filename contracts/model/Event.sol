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

    // spoke event
    event Spoke__DepositCollateral(
        uint16 indexed _targetChain,
        uint256 indexed amount,
        address indexed assetAdrress,
        address assetAdd
    );

    event Spoke__CreateRequest(
        uint16 indexed _targetChain,
        uint256 indexed amount,
        address indexed assetAdrress,
        address _loanAddress
    );
    event Spoke__ServiceRequest(
        uint16 indexed _targetChain,
        uint96 indexed _requestId,
        address indexed sender,
        address _tokenAddress
    );

    event Spoke__WithrawnCollateral(
        uint16 indexed _targetChain,
        address indexed _targetAddress,
        address indexed sender,
        address _tokenCollateralAddress
    );

    event Spoke__createLoanListing(
        uint16 indexed _targetChain,
        uint256 indexed _amount,
        address indexed sender,
        address _assetAddress
    );

    event Spoke__RepayLoan(
        uint16 indexed _targetChain,
        uint96 indexed_requestId,
        address indexed sender,
        uint256 _amount
    );

    event Spoke__requestLoanFromListing(
        uint16 indexed _targetChain,
        uint96 indexed_requestId,
        address indexed sender,
        uint256 indexed _amount
    );

    event ProviderRegistered(
        uint16 indexed _chainId,
        address indexed spokeAddr
    );
}
