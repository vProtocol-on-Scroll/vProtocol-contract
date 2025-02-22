// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AppStorage} from "./AppStorage.sol";
import {LibGettersImpl} from "../../libraries/LibGetters.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {Validator} from "../validators/Validator.sol";
import {Constants} from "../constants/Constant.sol";
import {Utils} from "./Utils.sol";
import "../../interfaces/IUniswapV2Router02.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../model/Protocol.sol";
import "../../model/Event.sol";
import "../validators/Error.sol";
import {ICrocSwapDex, ICrocImpact, ICrocQuery} from "../../interfaces/ICrocSwapDex.sol";

/**
 * @title Operations
 * @author vProtocol
 *
 * Public write-only functions that allows writing into the state of vProtocol
 */
contract Operations is AppStorage {
    event E(int128, int128);
    using SafeERC20 for IERC20;

    /**
     * @dev Allows users to deposit collateral of a specified token into the protocol. Supports both
     *      native and ERC-20 token collateral deposits.
     *
     * @param _tokenCollateralAddress The address of the token being deposited as collateral.
     * @param _amountOfCollateral The amount of the token to deposit as collateral.
     *
     * Requirements:
     * - `_amountOfCollateral` must be greater than zero.
     * - `_tokenCollateralAddress` must be an allowed token (i.e., have a non-zero price feed).
     *
     * If the deposit is in the native token, `_amountOfCollateral` is set to `msg.value`.
     * The function updates the collateral and available balance mappings for the sender, and if
     * the collateral is an ERC-20 token, it transfers `_amountOfCollateral` from the sender to the contract.
     * Emits a `CollateralDeposited` event on successful deposit.
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountOfCollateral
    ) external payable {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validate the input parameters: `_amountOfCollateral` must be greater than zero,
        // and `_tokenCollateralAddress` must have a valid price feed (non-zero address).
        Validator._valueMoreThanZero(
            _amountOfCollateral,
            _tokenCollateralAddress,
            msg.value
        );
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );

        // Determine if the collateral is the native token
        bool _isNativeToken = _tokenCollateralAddress == Constants.NATIVE_TOKEN;

        // Set `_amountOfCollateral` to `msg.value` if it's a native token deposit
        if (_isNativeToken) {
            _amountOfCollateral = msg.value;
        }

        // Update the user's collateral and available balance in storage
        _appStorage.s_addressToCollateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;
        _appStorage.s_addressToAvailableBalance[msg.sender][
            _tokenCollateralAddress
        ] += _amountOfCollateral;

        // Transfer ERC-20 tokens from the sender to the contract if not the native token
        if (!_isNativeToken) {
            IERC20(_tokenCollateralAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amountOfCollateral
            );
        }

        // Emit an event for the collateral deposit
        emit Event.CollateralDeposited(
            msg.sender,
            _tokenCollateralAddress,
            _amountOfCollateral
        );
    }

    /**
     * @dev Creates a new lending request by validating input parameters, calculating loanable amounts,
     *      and locking collateral proportional to the loan request.
     *
     * @param _amount The amount of loan requested by the borrower.
     * @param _interest The interest rate for the loan.
     * @param _returnDuration The expected return date for the loan.
     * @param _expirationDate The expiration date of lending request if not serviced
     * @param _loanCurrency The token address for the currency in which the loan is requested.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - `_loanCurrency` must be an approved loanable token.
     * - `_returnDate` must be at least 1 day in the future.
     * - The calculated USD value of `_amount` should meet the minimum loan amount requirement.
     * - Borrower must have sufficient collateral based on their collateral value and `_loanUsdValue`.
     *
     * The function locks collateral based on the proportional USD value of each token in the borrower’s
     * collateral, calculates the total repayment including interest, and stores loan request data.
     * Emits a `RequestCreated` event on successful request creation.
     */
    function createLendingRequest(
        uint256 _amount,
        uint16 _interest,
        uint256 _returnDuration,
        uint256 _expirationDate,
        address _loanCurrency
    ) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validate that the loan amount is greater than zero
        Validator._moreThanZero(_amount);

        // Check if the loan currency is allowed by validating it against allowed loanable tokens
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        if (_expirationDate < block.timestamp) {
            revert Protocol__DateMustBeInFuture();
        }

        uint256 _duration = _returnDuration - block.timestamp;

        // Ensure the return date is at least 1 day in the future
        if (_duration < 1 days) {
            revert Protocol__DateMustBeInFuture();
        }

        // Retrieve the loan currency's decimal precision
        uint8 decimal = LibGettersImpl._getTokenDecimal(_loanCurrency);

        // Calculate the USD equivalent of the loan amount
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _loanCurrency,
            _amount,
            decimal
        );

        // Ensure that the USD value of the loan is valid and meets minimum requirements
        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        // Get the total USD collateral value for the borrower
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, msg.sender);

        // Calculate the maximum loanable amount based on available collateral
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Check if the loan exceeds the user's collateral allowance
        if (
            _appStorage.addressToUser[msg.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Retrieve collateral tokens associated with the borrower
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, msg.sender);

        // Increment the request ID and initialize the new loan request
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = msg.sender;
        _newRequest.amount = _amount;
        _newRequest.interest = _interest;
        _newRequest.returnDate = _returnDuration;
        _newRequest.expirationDate = _expirationDate;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            _amount,
            _interest
        );
        _newRequest.loanRequestAddr = _loanCurrency;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.OPEN;

        // Calculate the amount of collateral to lock based on the loan value
        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );

        // For each collateral token, lock an appropriate amount based on its USD value
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 _decimalToken = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                msg.sender
            ][token];

            // Calculate the amount to lock in USD for each token based on the proportional collateral
            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                _decimalToken
            ) * collateralToLock) / 100;

            // Convert USD amount to token amount and apply the correct decimal scaling
            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            // Store the locked amount for each collateral token
            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
        }

        // Emit an event for the created loan request
        emit Event.RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _interest
        );
    }

    /**
     * @dev Services a lending request by transferring funds from the lender to the borrower and updating request status.
     * @param _requestId The ID of the lending request to service.
     * @param _tokenAddress The address of the token to be used for funding.
     *
     * Requirements:
     * - `_tokenAddress` must be the native token or the lender must have approved sufficient balance of the specified token.
     * - Request must be open, not expired, and authored by someone other than the lender.
     * - Lender must have sufficient balance and allowance for ERC20 tokens, or sufficient msg.value for native tokens.
     * - The borrower's collateral must have a healthy factor after the loan is funded.
     *
     * Emits a `RequestServiced` event upon successful funding.
     */
    function serviceRequest(
        uint96 _requestId,
        address _tokenAddress
    ) external payable {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validate if native token is being used and msg.value is non-zero
        Validator._nativeMoreThanZero(_tokenAddress, msg.value);

        // Load the request from storage
        Request storage _foundRequest = _appStorage.request[_requestId];

        // Ensure the request status is open and has not expired
        if (_foundRequest.status != Status.OPEN)
            revert Protocol__RequestNotOpen();
        if (_foundRequest.expirationDate <= block.timestamp)
            revert Protocol__RequestNotOpen();
        if (_foundRequest.loanRequestAddr != _tokenAddress)
            revert Protocol__InvalidToken();
        if (_foundRequest.author == msg.sender) revert Protocol__CantFundSelf();

        // Update lender and request status to indicate servicing
        _foundRequest.lender = msg.sender;
        _foundRequest.status = Status.SERVICED;
        uint256 amountToLend = _foundRequest.amount;

        // Validate lender's balance and allowance if using ERC20 token, or msg.value if using native token
        if (_tokenAddress == Constants.NATIVE_TOKEN) {
            if (msg.value < amountToLend) {
                revert Protocol__InsufficientAmount();
            }
        } else {
            if (IERC20(_tokenAddress).balanceOf(msg.sender) < amountToLend)
                revert Protocol__InsufficientBalance();
            if (
                IERC20(_tokenAddress).allowance(msg.sender, address(this)) <
                amountToLend
            ) revert Protocol__InsufficientAllowance();
        }

        // Get token's decimal value and calculate the loan's USD equivalent
        uint8 _decimalToken = LibGettersImpl._getTokenDecimal(_tokenAddress);
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            amountToLend,
            _decimalToken
        );

        // Calculate the total repayment amount including interest
        uint256 _totalRepayment = amountToLend +
            Utils.calculateLoanInterest(
                _foundRequest.amount,
                _foundRequest.interest
            );
        _foundRequest.totalRepayment = _totalRepayment;

        // Update total loan collected in USD for the borrower
        _appStorage
            .addressToUser[_foundRequest.author]
            .totalLoanCollected += LibGettersImpl._getUsdValue(
            _appStorage,
            _tokenAddress,
            _totalRepayment,
            _decimalToken
        );

        // Validate borrower's collateral health factor after loan
        if (
            LibGettersImpl._healthFactor(
                _appStorage,
                _foundRequest.author,
                _loanUsdValue
            ) < 1
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Lock collateral amounts in the specified tokens for the request
        for (uint i = 0; i < _foundRequest.collateralTokens.length; i++) {
            _appStorage.s_addressToAvailableBalance[_foundRequest.author][
                _foundRequest.collateralTokens[i]
            ] -= _appStorage.s_idToCollateralTokenAmount[_requestId][
                _foundRequest.collateralTokens[i]
            ];
        }

        // Transfer loan amount to borrower based on token type
        if (_tokenAddress != Constants.NATIVE_TOKEN) {
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                _foundRequest.author,
                amountToLend
            );
        } else {
            (bool sent, ) = payable(_foundRequest.author).call{
                value: amountToLend
            }("");

            if (!sent) revert Protocol__TransferFailed();
        }

        if (_tokenAddress == Constants.NATIVE_TOKEN) {
            if (msg.value > amountToLend) {
                uint256 _refund = msg.value - amountToLend;
                (bool sent, ) = payable(msg.sender).call{value: _refund}("");
                if (!sent) revert Protocol__TransferFailed();
            }
        }

        // Emit an event indicating successful servicing of the request
        emit Event.RequestServiced(
            _requestId,
            msg.sender,
            _foundRequest.author,
            amountToLend
        );
    }

    /**
     * @dev Allows a user to withdraw a specified amount of collateral.
     * @param _tokenCollateralAddress The address of the collateral token to withdraw.
     * @param _amount The amount of collateral to withdraw.
     *
     * Requirements:
     * - The token address must be valid and allowed by the protocol.
     * - The withdrawal amount must be greater than zero.
     * - User must have at least the specified amount of collateral deposited.
     *
     * Emits a `CollateralWithdrawn` event on successful withdrawal.
     */
    function withdrawCollateral(
        address _tokenCollateralAddress,
        uint128 _amount
    ) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validate that the token is allowed and the amount is greater than zero
        Validator._isTokenAllowed(
            _appStorage.s_priceFeeds[_tokenCollateralAddress]
        );
        Validator._moreThanZero(_amount);

        // Retrieve the user's deposited amount for the specified token
        uint256 depositedAmount = _appStorage.s_addressToAvailableBalance[
            msg.sender
        ][_tokenCollateralAddress];

        // Check if the user has sufficient collateral to withdraw the requested amount
        if (depositedAmount < _amount) {
            revert Protocol__InsufficientCollateralDeposited();
        }

        // Update storage to reflect the withdrawal of collateral
        _appStorage.s_addressToCollateralDeposited[msg.sender][
            _tokenCollateralAddress
        ] -= _amount;
        _appStorage.s_addressToAvailableBalance[msg.sender][
            _tokenCollateralAddress
        ] -= _amount;

        // Handle withdrawal for native token vs ERC20 tokens
        if (_tokenCollateralAddress == Constants.NATIVE_TOKEN) {
            // Transfer native token to the user
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert Protocol__TransferFailed();
        } else {
            // Transfer ERC20 token to the user
            IERC20(_tokenCollateralAddress).safeTransfer(msg.sender, _amount);
        }

        // Emit an event indicating successful collateral withdrawal
        emit Event.CollateralWithdrawn(
            msg.sender,
            _tokenCollateralAddress,
            _amount
        );
    }

    /**
     * @dev Adds new collateral tokens along with their respective price feeds to the protocol.
     * @param _tokens An array of token addresses to add as collateral.
     * @param _priceFeeds An array of corresponding price feed addresses for the tokens.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     * - The `_tokens` and `_priceFeeds` arrays must have the same length.
     *
     * Emits an `UpdatedCollateralTokens` event with the total number of collateral tokens added.
     */
    function addCollateralTokens(
        address[] memory _tokens,
        address[] memory _priceFeeds
    ) external {
        // Ensure only the contract owner can add collateral tokens
        LibDiamond.enforceIsContractOwner();

        // Validate that the tokens and price feeds arrays have the same length
        if (_tokens.length != _priceFeeds.length) {
            revert Protocol__tokensAndPriceFeedsArrayMustBeSameLength();
        }

        // Loop through each token to set its price feed and add it to the collateral list
        for (uint8 i = 0; i < _tokens.length; i++) {
            _appStorage.s_priceFeeds[_tokens[i]] = _priceFeeds[i]; // Map token to price feed
            _appStorage.s_collateralToken.push(_tokens[i]); // Add token to collateral array
        }

        // Emit an event indicating the updated number of collateral tokens
        emit Event.UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_collateralToken.length)
        );
    }

    /**
     * @dev Removes specified collateral tokens and their associated price feeds from the protocol.
     * @param _tokens An array of token addresses to be removed as collateral.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     *
     * Emits an `UpdatedCollateralTokens` event with the updated total number of collateral tokens.
     */
    function removeCollateralTokens(address[] memory _tokens) external {
        // Ensure only the contract owner can remove collateral tokens
        LibDiamond.enforceIsContractOwner();

        // Loop through each token to remove it from collateral and reset its price feed
        for (uint8 i = 0; i < _tokens.length; i++) {
            _appStorage.s_priceFeeds[_tokens[i]] = address(0); // Remove the price feed for the token

            // Search for the token in the collateral array
            for (uint8 j = 0; j < _appStorage.s_collateralToken.length; j++) {
                if (_appStorage.s_collateralToken[j] == _tokens[i]) {
                    // Replace the token to be removed with the last token in the array
                    _appStorage.s_collateralToken[j] = _appStorage
                        .s_collateralToken[
                            _appStorage.s_collateralToken.length - 1
                        ];

                    // Remove the last token from the array
                    _appStorage.s_collateralToken.pop();
                    break; // Stop searching once the token is found and removed
                }
            }
        }

        // Emit an event indicating the updated count of collateral tokens
        emit Event.UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_collateralToken.length)
        );
    }

    /**
     * @dev Adds a new token as a loanable token and associates it with a price feed.
     * @param _token The address of the token to be added as loanable.
     * @param _priceFeed The address of the price feed for the loanable token.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     *
     * Emits an `UpdateLoanableToken` event indicating the new loanable token and its price feed.
     */
    function addLoanableToken(address _token, address _priceFeed) external {
        // Ensure only the contract owner can add loanable tokens
        LibDiamond.enforceIsContractOwner();

        // Mark the token as loanable
        _appStorage.s_isLoanable[_token] = true;

        // Associate the token with its price feed
        _appStorage.s_priceFeeds[_token] = _priceFeed;

        // Add the loanable token to the list of loanable tokens
        _appStorage.s_loanableToken.push(_token);

        // Emit an event to notify that a loanable token has been added
        emit Event.UpdateLoanableToken(_token, _priceFeed, msg.sender);
    }

    /**
     * @dev Closes a listing advertisement and transfers the remaining amount to the author.
     * @param _listingId The ID of the listing advertisement to be closed.
     *
     * Requirements:
     * - The listing must be in an OPEN status.
     * - Only the author of the listing can close it.
     * - The amount of the listing must be greater than zero.
     *
     * Emits a `withdrawnAdsToken` event indicating the author, listing ID, status, and amount withdrawn.
     */
    function closeListingAd(uint96 _listingId) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);

        // Retrieve the loan listing associated with the given listing ID
        LoanListing storage _newListing = _appStorage.loanListings[_listingId];

        // Check if the listing is OPEN; revert if it's not
        if (_newListing.listingStatus != ListingStatus.OPEN)
            revert Protocol__OrderNotOpen();

        // Ensure that the caller is the author of the listing; revert if not
        if (_newListing.author != msg.sender)
            revert Protocol__OwnerCreatedOrder();

        // Ensure the amount is greater than zero; revert if it is zero
        if (_newListing.amount == 0) revert Protocol__MustBeMoreThanZero();

        // Store the amount to be transferred and reset the listing amount to zero
        uint256 _amount = _newListing.amount;
        _newListing.amount = 0; // Prevent re-entrancy by setting amount to zero
        _newListing.listingStatus = ListingStatus.CLOSED; // Update listing status to CLOSED

        // Handle the transfer of funds based on whether the token is native or ERC20
        if (_newListing.tokenAddress == Constants.NATIVE_TOKEN) {
            // Transfer native tokens (ETH) to the author
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert Protocol__TransferFailed(); // Revert if the transfer fails
        } else {
            // Transfer ERC20 tokens to the author
            IERC20(_newListing.tokenAddress).safeTransfer(msg.sender, _amount);
        }

        // Emit an event to notify that the listing has been closed and tokens have been withdrawn
        emit Event.withdrawnAdsToken(
            msg.sender,
            _listingId,
            uint8(_newListing.listingStatus),
            _amount
        );
    }

    /**
     * @dev Closes a lending request, updating its status to CLOSED.
     * @param _requestId The ID of the request to be closed.
     *
     * Requirements:
     * - The request must be in an OPEN status.
     * - Only the author of the request can close it.
     *
     * Emits a `RequestClosed` event indicating the request ID and the author of the request.
     */
    function closeRequest(uint96 _requestId) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);

        // Retrieve the lending request associated with the given request ID
        Request storage _foundRequest = _appStorage.request[_requestId];

        // Check if the request is OPEN; revert if it's not
        if (_foundRequest.status != Status.OPEN)
            revert Protocol__RequestNotOpen();

        // Ensure that the caller is the author of the request; revert if not
        if (_foundRequest.author != msg.sender) revert Protocol__NotOwner();

        // Update the request status to CLOSED
        _foundRequest.status = Status.CLOSED;

        // Emit an event to notify that the request has been closed
        emit Event.RequestClosed(_requestId, msg.sender);
    }

    /**
     * @dev Creates a loan listing for lenders to fund.
     * @param _amount The total amount being loaned.
     * @param _min_amount The minimum amount a lender can fund.
     * @param _max_amount The maximum amount a lender can fund.
     * @param _returnDuration The date by which the loan should be repaid.
     * @param _interest The interest rate to be applied on the loan.
     * @param _loanCurrency The currency in which the loan is issued (token address).
     *
     * Requirements:
     * - The loan amount must be greater than zero.
     * - The currency must be a loanable token.
     * - If using a token, the sender must have sufficient balance and allowance.
     * - If using the native token, the amount must be sent as part of the transaction.
     *
     * Emits a `LoanListingCreated` event indicating the listing ID, author, and loan currency.
     */
    function createLoanListing(
        uint256 _amount,
        uint256 _min_amount,
        uint256 _max_amount,
        uint256 _returnDuration,
        uint16 _interest,
        address _loanCurrency
    ) external payable {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validate that the amount is greater than zero and that a value has been sent if using native token
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);
        Validator._moreThanZero(_amount);

        // Ensure the specified loan currency is a loanable token
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        // Check for sufficient balance and allowance if using a token other than native
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();

            if (
                IERC20(_loanCurrency).allowance(msg.sender, address(this)) <
                _amount
            ) revert Protocol__InsufficientAllowance();
        }

        // If using the native token, set the amount to the value sent with the transaction
        if (_loanCurrency == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
        }

        // Transfer the specified amount from the user to the contract if using a token
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            IERC20(_loanCurrency).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        // Increment the listing ID to create a new loan listing
        _appStorage.listingId = _appStorage.listingId + 1;
        LoanListing storage _newListing = _appStorage.loanListings[
            _appStorage.listingId
        ];

        // Populate the loan listing struct with the provided details
        _newListing.listingId = _appStorage.listingId;
        _newListing.author = msg.sender;
        _newListing.amount = _amount;
        _newListing.min_amount = _min_amount;
        _newListing.max_amount = _max_amount;
        _newListing.interest = _interest;
        _newListing.returnDuration = _returnDuration - block.timestamp;
        _newListing.tokenAddress = _loanCurrency;
        _newListing.listingStatus = ListingStatus.OPEN;

        // Emit an event to notify that a new loan listing has been created
        emit Event.LoanListingCreated(
            _appStorage.listingId,
            msg.sender,
            _loanCurrency,
            _amount
        );
    }

    /**
     * @dev Allows a borrower to request a loan from an open listing.
     * @param _listingId The unique identifier of the loan listing.
     * @param _amount The requested loan amount.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - The listing must be open, not created by the borrower, and within min/max constraints.
     * - The borrower must have sufficient collateral to meet the health factor.
     *
     * Emits:
     * - `RequestCreated` when a loan request is successfully created.
     * - `RequestServiced` when the loan request is successfully serviced.
     */
    function requestLoanFromListing(uint96 _listingId, uint256 _amount) public {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        Validator._moreThanZero(_amount);

        LoanListing storage _listing = _appStorage.loanListings[_listingId];

        // Check if the listing is open and the borrower is not the listing creator
        if (_listing.listingStatus != ListingStatus.OPEN)
            revert Protocol__ListingNotOpen();
        if (_listing.author == msg.sender)
            revert Protocol__OwnerCreatedListing();

        // Validate that the requested amount is within the listing's constraints
        if ((_amount < _listing.min_amount) || (_amount > _listing.max_amount))
            revert Protocol__InvalidAmount();
        if (_amount > _listing.amount) revert Protocol__InvalidAmount();

        // Fetch token decimal and calculate USD value of the loan amount
        uint8 _decimalToken = LibGettersImpl._getTokenDecimal(
            _listing.tokenAddress
        );
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _listing.tokenAddress,
            _amount,
            _decimalToken
        );

        // Ensure borrower meets the health factor threshold for collateralization
        if (
            LibGettersImpl._healthFactor(
                _appStorage,
                msg.sender,
                _loanUsdValue
            ) < 1
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Calculate max loanable amount based on collateral value
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, msg.sender);
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Update the listing's available amount, adjusting min/max amounts as necessary
        _listing.amount = _listing.amount - _amount;
        if (_listing.amount <= _listing.max_amount)
            _listing.max_amount = _listing.amount;
        if (_listing.amount <= _listing.min_amount) _listing.min_amount = 0;
        if (_listing.amount == 0) _listing.listingStatus = ListingStatus.CLOSED;

        // Retrieve the borrower's collateral tokens for collateralization
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, msg.sender);

        // Create a new loan request with a unique ID
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = msg.sender;
        _newRequest.lender = _listing.author;
        _newRequest.amount = _amount;
        _newRequest.interest = _listing.interest;
        _newRequest.returnDate = block.timestamp + _listing.returnDuration;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            _amount,
            _listing.interest
        );
        _newRequest.loanRequestAddr = _listing.tokenAddress;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.SERVICED;

        // Calculate collateral to lock for each token, proportional to its USD value
        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 decimal = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                msg.sender
            ][token];

            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                decimal
            ) * collateralToLock) / 100;

            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
            _appStorage.s_addressToAvailableBalance[msg.sender][
                token
            ] -= amountToLock;
        }

        // Update borrower's total loan collected in USD
        _appStorage
            .addressToUser[msg.sender]
            .totalLoanCollected += LibGettersImpl._getUsdValue(
            _appStorage,
            _listing.tokenAddress,
            _newRequest.totalRepayment,
            _decimalToken
        );

        // Transfer the loan amount to the borrower
        if (_listing.tokenAddress == Constants.NATIVE_TOKEN) {
            (bool sent, ) = payable(msg.sender).call{value: _amount}("");
            if (!sent) revert Protocol__TransferFailed();
        } else {
            IERC20(_listing.tokenAddress).safeTransfer(msg.sender, _amount);
        }

        // Emit events to notify the loan request creation and servicing
        emit Event.RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _listing.interest
        );
        emit Event.RequestServiced(
            _newRequest.requestId,
            _newRequest.lender,
            _newRequest.author,
            _amount
        );
    }

    /**
     * @dev Allows a borrower to repay a loan in part or in full.
     * @param _requestId The unique identifier of the loan request.
     * @param _amount The repayment amount.
     *
     * Requirements:
     * - `_amount` must be greater than zero.
     * - The loan request must be in the SERVICED status.
     * - The caller must be the borrower who created the loan request.
     * - If repaying in a token, the borrower must have sufficient balance and allowance.
     *
     * Emits:
     * - `LoanRepayment` upon successful repayment.
     */
    function repayLoan(uint96 _requestId, uint256 _amount) external payable {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        Validator._moreThanZero(_amount);

        Request storage _request = _appStorage.request[_requestId];

        // Ensure that the loan request is currently serviced and the caller is the original borrower
        if (_request.status != Status.SERVICED)
            revert Protocol__RequestNotServiced();
        if (msg.sender != _request.author) revert Protocol__NotOwner();

        // Process repayment amount based on the token type
        if (_request.loanRequestAddr == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
        } else {
            IERC20 _token = IERC20(_request.loanRequestAddr);
            if (_token.balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();
            if (_token.allowance(msg.sender, address(this)) < _amount)
                revert Protocol__InsufficientAllowance();

            _token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        // If full repayment is made, close the request and release the collateral
        if (_amount >= _request.totalRepayment) {
            _amount = _request.totalRepayment;
            _request.totalRepayment = 0;
            _request.status = Status.CLOSED;

            for (uint i = 0; i < _request.collateralTokens.length; i++) {
                address collateralToken = _request.collateralTokens[i];
                _appStorage.s_addressToAvailableBalance[_request.author][
                    collateralToken
                ] += _appStorage.s_idToCollateralTokenAmount[_requestId][
                    collateralToken
                ];
            }
        } else {
            // Reduce the outstanding repayment amount for partial payments
            _request.totalRepayment -= _amount;
        }

        // Update borrower’s loan collected metrics in USD
        uint8 decimal = LibGettersImpl._getTokenDecimal(
            _request.loanRequestAddr
        );
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _request.loanRequestAddr,
            _amount,
            decimal
        );
        uint256 loanCollected = LibGettersImpl._getLoanCollectedInUsd(
            _appStorage,
            msg.sender
        );

        // Deposit the repayment amount to the lender's available balance
        _appStorage.s_addressToCollateralDeposited[_request.lender][
            _request.loanRequestAddr
        ] += _amount;
        _appStorage.s_addressToAvailableBalance[_request.lender][
            _request.loanRequestAddr
        ] += _amount;

        // Adjust the borrower's total loan collected
        if (loanCollected > _loanUsdValue) {
            _appStorage.addressToUser[msg.sender].totalLoanCollected =
                loanCollected -
                _loanUsdValue;
        } else {
            _appStorage.addressToUser[msg.sender].totalLoanCollected = 0;
        }

        // Emit event to notify of loan repayment
        emit Event.LoanRepayment(msg.sender, _requestId, _amount);
    }

    function checkLiquidationEligibility(
        address _user
    ) public view returns (bool) {
        uint256 _loanUsd = LibGettersImpl._getLoanCollectedInUsd(
            _appStorage,
            _user
        );
        uint256 _collateralUsd = LibGettersImpl._getAccountCollateralValue(
            _appStorage,
            _user
        );
        return
            _loanUsd >
            ((_collateralUsd * Constants.LIQUIDATION_THRESHOLD) / 100);
    }

    /**
     * @dev Liquidates the collateral associated with a loan request and compensates the lender.
     * @param requestId The unique identifier of the loan request to be liquidated.
     *
     * Requirements:
     * - Only a designated bot can execute this function.
     * - The loan must be in a state eligible for liquidation.
     *
     * Emits:
     * - `RequestLiquidated` after successfully liquidating the collateral and transferring the repayment.
     */
    function liquidateUserRequest(uint96 requestId) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);
        // Validator._onlyBot(_appStorage.botAddress, msg.sender);

        Request memory _activeRequest = _appStorage.request[requestId];
        address loanCurrency = _activeRequest.loanRequestAddr;
        address lenderAddress = _activeRequest.lender;
        uint256 swappedAmount = 0;

        if (!checkLiquidationEligibility(_activeRequest.author)) {
            revert Protocol__NotLiquidateable();
        }

        // Loop through each collateral token and swap to loan currency if applicable
        for (
            uint96 index = 0;
            index < _activeRequest.collateralTokens.length;
            index++
        ) {
            address collateralToken = _activeRequest.collateralTokens[index];
            uint256 amountOfCollateralToken = _appStorage
                .s_idToCollateralTokenAmount[requestId][collateralToken];

            if (amountOfCollateralToken > 0) {
                // Attempt to swap collateral token to loan currency
                // (int128 baseQuote, int128 quoteFlow) = swapToLoanCurrency(
                //     collateralToken,
                //     amountOfCollateralToken,
                //     loanCurrency
                // );

                // Update the collateral deposited for the user
                _appStorage.s_addressToCollateralDeposited[
                    _activeRequest.author
                ][collateralToken] -= amountOfCollateralToken;

                // Add swapped amount to the total; if swap failed, fallback to using collateral amount
                // swappedAmount += uint256(quoteFlow); //loanCurrencyAmount[1];

                // Mark collateral as fully used
                _appStorage.s_idToCollateralTokenAmount[requestId][
                    collateralToken
                ] = 0;
            }
        }

        // Transfer loan currency to the lender, ensuring not to exceed total repayment
        if (swappedAmount >= _activeRequest.totalRepayment) {
            if (loanCurrency == Constants.NATIVE_TOKEN) {
                IERC20(Constants.WETH).safeTransfer(
                    lenderAddress,
                    _activeRequest.totalRepayment
                );
            } else {
                IERC20(loanCurrency).safeTransfer(
                    lenderAddress,
                    _activeRequest.totalRepayment
                );
            }
        } else {
            if (loanCurrency == Constants.NATIVE_TOKEN) {
                (bool _sent, ) = payable(lenderAddress).call{
                    value: swappedAmount
                }("");
                require(_sent, "Protocol__TransferFailed");
            } else {
                IERC20(loanCurrency).safeTransfer(lenderAddress, swappedAmount);
            }
        }

        // Mark request as closed post liquidation
        _activeRequest.status = Status.CLOSED;

        emit Event.RequestLiquidated(
            requestId,
            lenderAddress,
            _activeRequest.totalRepayment
        );
    }

    /**
     * @dev Swaps a specified collateral token into the loan currency using Uniswap.
     * @param collateralToken The token used as collateral.
     * @param collateralAmount The amount of collateral to swap.
     * @param loanCurrency The target currency for the loan.
     * @return baseQuote The base amount swapped
     * @return quoteFLow The loan currency received
     */
    // function swapToLoanCurrency(
    //     address collateralToken,
    //     uint256 collateralAmount,
    //     address loanCurrency
    // ) public returns (int128, int128) {
    //     // validate transaction is not stopped
    //     ICrocSwapDex swapRouter = ICrocSwapDex(_appStorage.swapRouter);
    //     Validator._isP2pStopped(_appStorage.isP2pStopped);

    //     ICrocQuery queryRouter = ICrocQuery(
    //         0x62223e90605845Cf5CC6DAE6E0de4CDA130d6DDf
    //     );

    //     uint128 _price = queryRouter.queryPrice(
    //         address(0),
    //         0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD,
    //         420
    //     );

    //     ICrocImpact impactRouter = ICrocImpact(
    //         0xc2c301759B5e0C385a38e678014868A33E2F3ae3
    //     );

    //     int128 baseQuote;
    //     int128 quoteFlow;

    //     // Early exit if collateral and loan currencies are the same
    //     if (loanCurrency == collateralToken) {
    //         baseQuote = -int128(int256(collateralAmount));
    //         quoteFlow = int128(int256(collateralAmount));
    //         return (baseQuote, quoteFlow);
    //     }

    //     require(
    //         collateralAmount <= type(uint128).max,
    //         "Value exceeds uint128 limit"
    //     );

    //     uint128 _amount = uint128(collateralAmount);

    //     impactRouter.calcImpact(
    //         address(0),
    //         loanCurrency,
    //         420,
    //         true,
    //         true,
    //         _amount,
    //         0,
    //         _price
    //     );
    //     // Handle ETH to ERC20 swap
    //     if (collateralToken == Constants.NATIVE_TOKEN) {
    //         swapRouter.userCmd{value: collateralAmount}(
    //             1,
    //             abi.encode(
    //                 address(0),
    //                 loanCurrency,
    //                 420, //poolIdx,
    //                 true,
    //                 true,
    //                 uint128(_amount),
    //                 0,
    //                 _price,
    //                 1,
    //                 0x0
    //             )
    //         );
    //     } else {
    //         // Handle ERC20 to ERC20 swap
    //         // Approve Uniswap router to transfer collateral tokens
    //         IERC20(collateralToken).approve(
    //             _appStorage.swapRouter,
    //             collateralAmount
    //         );

    //         swapRouter.userCmd(
    //             1,
    //             abi.encode(
    //                 collateralToken,
    //                 loanCurrency,
    //                 420, //poolIdx,
    //                 true,
    //                 true,
    //                 uint128(_amount),
    //                 0,
    //                 _price,
    //                 1,
    //                 0x0
    //             )
    //         );
    //     }

    //     // Return the output amount in the target loan currency
    //     return (baseQuote, quoteFlow);
    // }

    /**
     * @notice Sets the bot address for the protocol.
     * @dev This function allows the contract owner to set an address for automated bot actions within the protocol,
     *      such as monitoring and liquidating undercollateralized loans. Only callable by the contract owner.
     * @param _botAddress The address designated as the bot for handling automated protocol tasks.
     *        It should be a valid external or contract address with necessary permissions.
     * @custom:access Only callable by the contract owner.
     */
    function setBotAddress(address _botAddress) external {
        // Ensures only the contract owner can call this function
        LibDiamond.enforceIsContractOwner();

        // Sets the bot address in storage, enabling bot actions within the protocol
        _appStorage.botAddress = _botAddress;
    }

    /**
     * @notice Sets the swap router address for handling token exchanges within the protocol.
     * @dev This function allows the contract owner to set the router address used for token swaps
     *      (e.g., using Uniswap or a compatible DEX) as part of the protocol's operations.
     *      Only callable by the contract owner.
     * @param _swapRouter The address of the swap router, typically a Uniswap or similar DEX router
     *        that supports token exchange functionality required by the protocol.
     * @custom:access Only callable by the contract owner.
     */
    function setSwapRouter(address _swapRouter) external {
        // Ensures only the contract owner can call this function
        LibDiamond.enforceIsContractOwner();

        // Sets the swap router address in storage, enabling token swaps within the protocol
        _appStorage.swapRouter = _swapRouter;
    }

    /// @notice this function is used to activate or deactivate the p2p fail safe
    /// @param _activate a boolean to activate or deactivate the fail safe
    /// @dev this function can only be called by the deployer of the contract
    /// @dev emits the P2pFailSafeStatus event
    function activtateFailSafe(bool _activate) external {
        LibDiamond.enforceIsContractOwner();

        _appStorage.isP2pStopped = _activate;
        emit Event.P2pFailSafeStatus(_activate);
    }

    /**
     * @dev Find the best matching lending offer for a new borrowing request
     * @param _loanCurrency The currency being borrowed
     * @param _amount The amount needed to borrow
     * @param _maxInterest Maximum interest rate the borrower is willing to pay
     * @param _returnDuration The loan return duration
     * @return listingId ID of the best matching lending offer, 0 if no match found
     */
    function findMatchingLendingOffer(
        address _loanCurrency,
        uint256 _amount,
        uint16 _maxInterest,
        uint256 _returnDuration
    ) public view returns (uint96 listingId) {
        uint256 bestScore = 0;
        uint96 bestMatch = 0;

        // Iterate through all existing lending offers to find the best match
        for (uint96 i = 1; i <= _appStorage.listingId; i++) {
            LoanListing memory listing = _appStorage.loanListings[i];

            // Skip listings that don't meet basic criteria
            if (listing.listingStatus != ListingStatus.OPEN) continue;
            if (listing.tokenAddress != _loanCurrency) continue;
            if (listing.interest > _maxInterest) continue;
            if (listing.amount < _amount) continue;
            if (_amount < listing.min_amount || _amount > listing.max_amount)
                continue;
            if (_returnDuration > block.timestamp + listing.returnDuration)
                continue;

            // Calculate match score - prioritize:
            // 1. Lower interest rates (weighted most heavily)
            // 2. Longer available durations
            // 3. Larger available amounts

            uint256 interestScore = (_maxInterest - listing.interest) * 1000;
            uint256 durationScore = (listing.returnDuration * 100) /
                (_returnDuration - block.timestamp);
            uint256 amountScore = (listing.amount * 10) / _amount;

            uint256 score = interestScore + durationScore + amountScore;

            if (score > bestScore) {
                bestScore = score;
                bestMatch = i;
            }
        }

        return bestMatch;
    }

    /**
     * @dev Find multiple matching lending offers for a borrowing request
     * @param _loanCurrency The currency being borrowed
     * @param _amount The amount needed to borrow
     * @param _maxInterest Maximum interest rate the borrower is willing to pay
     * @param _returnDuration The loan return duration
     * @param _maxMatches Maximum number of matches to return
     * @return matches Array of matched lending offer IDs
     */
    function findMultipleLendingOffers(
        address _loanCurrency,
        uint256 _amount,
        uint16 _maxInterest,
        uint256 _returnDuration,
        uint8 _maxMatches
    ) public view returns (uint96[] memory matches) {
        LendingOffer[] memory offers = new LendingOffer[](
            _appStorage.listingId
        );
        uint256 matchCount = 0;

        // First pass: identify all eligible matches and calculate scores
        for (uint96 i = 1; i <= _appStorage.listingId; i++) {
            LoanListing memory listing = _appStorage.loanListings[i];

            // Skip listings that don't meet basic criteria
            if (listing.listingStatus != ListingStatus.OPEN) continue;
            if (listing.tokenAddress != _loanCurrency) continue;
            if (listing.interest > _maxInterest) continue;
            if (listing.amount < _amount) continue;
            if (_amount < listing.min_amount || _amount > listing.max_amount)
                continue;
            if (_returnDuration > block.timestamp + listing.returnDuration)
                continue;

            // Calculate match score
            uint256 interestScore = (_maxInterest - listing.interest) * 1000;
            uint256 durationScore = (listing.returnDuration * 100) /
                (_returnDuration - block.timestamp);
            uint256 amountScore = (listing.amount * 10) / _amount;

            uint256 score = interestScore + durationScore + amountScore;

            // Add to offers array
            offers[matchCount] = LendingOffer({
                listingId: i,
                author: listing.author,
                amount: listing.amount,
                minAmount: listing.min_amount,
                maxAmount: listing.max_amount,
                interest: listing.interest,
                returnDuration: listing.returnDuration,
                tokenAddress: listing.tokenAddress,
                score: score
            });
            matchCount++;
        }

        // Sort matches by score (simple bubble sort for on-chain efficiency)
        if (matchCount > 1) {
            for (uint256 i = 0; i < matchCount - 1; i++) {
                for (uint256 j = 0; j < matchCount - i - 1; j++) {
                    if (offers[j].score < offers[j + 1].score) {
                        LendingOffer memory temp = offers[j];
                        offers[j] = offers[j + 1];
                        offers[j + 1] = temp;
                    }
                }
            }
        }

        // Return the top matches up to _maxMatches
        uint256 resultCount = matchCount < _maxMatches
            ? matchCount
            : _maxMatches;
        matches = new uint96[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            matches[i] = offers[i].listingId;
        }

        return matches;
    }

    /**
     * @dev Creates a new lending request and automatically attempts to match and service it from existing lending offers
     * @param _amount The amount of loan requested by the borrower.
     * @param _interest The interest rate for the loan.
     * @param _returnDuration The expected return date for the loan.
     * @param _expirationDate The expiration date of lending request if not serviced
     * @param _loanCurrency The token address for the currency in which the loan is requested.
     * @return requestId The ID of the created request
     * @return matched Whether the request was automatically matched and serviced
     */
    function createAndMatchLendingRequest(
        uint256 _amount,
        uint16 _interest,
        uint256 _returnDuration,
        uint256 _expirationDate,
        address _loanCurrency
    ) external returns (uint96 requestId, bool matched) {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);

        // First, try to find the best matching lending offer
        uint96 matchedListingId = findMatchingLendingOffer(
            _loanCurrency,
            _amount,
            _interest,
            _returnDuration
        );

        // If a matching offer is found, directly borrow from it without creating a request
        if (matchedListingId > 0) {
            // Use requestLoanFromListing to avoid code duplication
            requestLoanFromListing(matchedListingId, _amount);

            // The most recent request ID will be the one created in requestLoanFromListing
            return (_appStorage.requestId, true);
        }

        // If no match found, create a regular lending request
        // Create the lending request normally
        Validator._moreThanZero(_amount);

        // Check if the loan currency is allowed by validating it against allowed loanable tokens
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        if (_expirationDate < block.timestamp) {
            revert Protocol__DateMustBeInFuture();
        }

        uint256 _duration = _returnDuration - block.timestamp;

        // Ensure the return date is at least 1 day in the future
        if (_duration < 1 days) {
            revert Protocol__DateMustBeInFuture();
        }

        // Retrieve the loan currency's decimal precision
        uint8 decimal = LibGettersImpl._getTokenDecimal(_loanCurrency);

        // Calculate the USD equivalent of the loan amount
        uint256 _loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            _loanCurrency,
            _amount,
            decimal
        );

        // Ensure that the USD value of the loan is valid and meets minimum requirements
        if (_loanUsdValue < 1) revert Protocol__InvalidAmount();

        // Get the total USD collateral value for the borrower
        uint256 collateralValueInLoanCurrency = LibGettersImpl
            ._getAccountCollateralValue(_appStorage, msg.sender);

        // Calculate the maximum loanable amount based on available collateral
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Check if the loan exceeds the user's collateral allowance
        if (
            _appStorage.addressToUser[msg.sender].totalLoanCollected +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Retrieve collateral tokens associated with the borrower
        address[] memory _collateralTokens = LibGettersImpl
            ._getUserCollateralTokens(_appStorage, msg.sender);

        // Increment the request ID and initialize the new loan request
        _appStorage.requestId = _appStorage.requestId + 1;
        Request storage _newRequest = _appStorage.request[
            _appStorage.requestId
        ];
        _newRequest.requestId = _appStorage.requestId;
        _newRequest.author = msg.sender;
        _newRequest.amount = _amount;
        _newRequest.interest = _interest;
        _newRequest.returnDate = _returnDuration;
        _newRequest.expirationDate = _expirationDate;
        _newRequest.totalRepayment = Utils.calculateLoanInterest(
            _amount,
            _interest
        );
        _newRequest.loanRequestAddr = _loanCurrency;
        _newRequest.collateralTokens = _collateralTokens;
        _newRequest.status = Status.OPEN;

        // Calculate the amount of collateral to lock based on the loan value
        uint256 collateralToLock = Utils.calculateColateralToLock(
            _loanUsdValue,
            maxLoanableAmount
        );

        // For each collateral token, lock an appropriate amount based on its USD value
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint8 _decimalToken = LibGettersImpl._getTokenDecimal(token);
            uint256 userBalance = _appStorage.s_addressToCollateralDeposited[
                msg.sender
            ][token];

            // Calculate the amount to lock in USD for each token based on the proportional collateral
            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                _decimalToken
            ) * collateralToLock) / 100;

            // Convert USD amount to token amount and apply the correct decimal scaling
            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(_appStorage, token, 10, 0)) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            // Store the locked amount for each collateral token
            _appStorage.s_idToCollateralTokenAmount[_appStorage.requestId][
                token
            ] = amountToLock;
        }

        // Emit an event for the created loan request
        emit Event.RequestCreated(
            msg.sender,
            _appStorage.requestId,
            _amount,
            _interest
        );

        return (_appStorage.requestId, false);
    }

    /**
     * @dev Create a loan listing that auto-matches with existing borrowing requests
     * @param _amount The total amount being loaned
     * @param _min_amount The minimum amount a borrower can request
     * @param _max_amount The maximum amount a borrower can request
     * @param _returnDuration The date by which the loan should be repaid
     * @param _interest The interest rate to be applied on the loan
     * @param _loanCurrency The currency in which the loan is issued
     * @param _autoMatch Whether to attempt to auto-match with existing borrowing requests
     * @return listingId The ID of the created listing
     * @return matchedRequests Array of request IDs that were automatically matched
     */
    function createLoanListingWithMatching(
        uint256 _amount,
        uint256 _min_amount,
        uint256 _max_amount,
        uint256 _returnDuration,
        uint16 _interest,
        address _loanCurrency,
        bool _autoMatch
    )
        external
        payable
        returns (uint96 listingId, uint96[] memory matchedRequests)
    {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isP2pStopped);

        // Create the loan listing first
        // Validate that the amount is greater than zero and that a value has been sent if using native token
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);
        Validator._moreThanZero(_amount);

        // Ensure the specified loan currency is a loanable token
        if (!_appStorage.s_isLoanable[_loanCurrency]) {
            revert Protocol__TokenNotLoanable();
        }

        // Check for sufficient balance and allowance if using a token other than native
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            if (IERC20(_loanCurrency).balanceOf(msg.sender) < _amount)
                revert Protocol__InsufficientBalance();

            if (
                IERC20(_loanCurrency).allowance(msg.sender, address(this)) <
                _amount
            ) revert Protocol__InsufficientAllowance();
        }

        // If using the native token, set the amount to the value sent with the transaction
        if (_loanCurrency == Constants.NATIVE_TOKEN) {
            _amount = msg.value;
        }

        // Transfer the specified amount from the user to the contract if using a token
        if (_loanCurrency != Constants.NATIVE_TOKEN) {
            IERC20(_loanCurrency).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        // Increment the listing ID to create a new loan listing
        _appStorage.listingId = _appStorage.listingId + 1;
        LoanListing storage _newListing = _appStorage.loanListings[
            _appStorage.listingId
        ];

        // Populate the loan listing struct with the provided details
        _newListing.listingId = _appStorage.listingId;
        _newListing.author = msg.sender;
        _newListing.amount = _amount;
        _newListing.min_amount = _min_amount;
        _newListing.max_amount = _max_amount;
        _newListing.interest = _interest;
        _newListing.returnDuration = _returnDuration - block.timestamp;
        _newListing.tokenAddress = _loanCurrency;
        _newListing.listingStatus = ListingStatus.OPEN;

        // Emit an event to notify that a new loan listing has been created
        emit Event.LoanListingCreated(
            _appStorage.listingId,
            msg.sender,
            _loanCurrency,
            _amount
        );

        // If auto-matching is enabled, find compatible borrowing requests
        if (_autoMatch) {
            // Get all open borrowing requests for this currency
            uint96[] memory potentialMatches = new uint96[](
                _appStorage.requestId
            );
            uint256 matchCount = 0;

            // Find all eligible requests
            for (uint96 i = 1; i <= _appStorage.requestId; i++) {
                Request memory req = _appStorage.request[i];

                if (
                    req.status == Status.OPEN &&
                    req.loanRequestAddr == _loanCurrency &&
                    req.interest >= _interest &&
                    req.amount >= _min_amount &&
                    req.amount <= _max_amount &&
                    req.returnDate <=
                    block.timestamp + _newListing.returnDuration &&
                    req.expirationDate > block.timestamp &&
                    req.author != msg.sender
                ) {
                    potentialMatches[matchCount] = i;
                    matchCount++;
                }
            }

            // Sort matches by highest interest rate first
            if (matchCount > 1) {
                for (uint256 i = 0; i < matchCount - 1; i++) {
                    for (uint256 j = 0; j < matchCount - i - 1; j++) {
                        if (
                            _appStorage.request[potentialMatches[j]].interest <
                            _appStorage
                                .request[potentialMatches[j + 1]]
                                .interest
                        ) {
                            uint96 temp = potentialMatches[j];
                            potentialMatches[j] = potentialMatches[j + 1];
                            potentialMatches[j + 1] = temp;
                        }
                    }
                }
            }

            // Attempt to service requests until no more funds available
            uint256 remainingAmount = _amount;
            uint96[] memory matchedRequestsTemp = new uint96[](matchCount);
            uint256 matchedCount = 0;

            for (uint256 i = 0; i < matchCount && remainingAmount > 0; i++) {
                uint96 requestId = potentialMatches[i];
                Request memory req = _appStorage.request[requestId];

                // Skip if we can't fulfill this request
                if (req.amount > remainingAmount || req.amount < _min_amount) {
                    continue;
                }

                // Service this request
                try
                    this.serviceRequest{
                        value: (req.loanRequestAddr == Constants.NATIVE_TOKEN)
                            ? req.amount
                            : 0
                    }(requestId, req.loanRequestAddr)
                {
                    // If successful, update remaining amount and track the match
                    remainingAmount -= req.amount;
                    _newListing.amount = remainingAmount;

                    if (remainingAmount <= _newListing.max_amount) {
                        _newListing.max_amount = remainingAmount;
                    }

                    if (remainingAmount <= _newListing.min_amount) {
                        _newListing.min_amount = 0;
                    }

                    if (remainingAmount == 0) {
                        _newListing.listingStatus = ListingStatus.CLOSED;
                    }

                    matchedRequestsTemp[matchedCount] = requestId;
                    matchedCount++;
                } catch {
                    // If service failed, just skip this request
                    continue;
                }
            }

            // Create return array with exact size
            matchedRequests = new uint96[](matchedCount);
            for (uint256 i = 0; i < matchedCount; i++) {
                matchedRequests[i] = matchedRequestsTemp[i];
            }
        } else {
            // If auto-matching is disabled, return an empty array
            matchedRequests = new uint96[](0);
        }

        return (_appStorage.listingId, matchedRequests);
    }

    function matchListing(
        address _loanToken,
        uint16 _interestRate,
        uint256 _amount,
        uint256 _duration
    ) internal view returns (uint96) {
        uint96 _totalListings = _appStorage.listingId;

        for (uint96 _idx = 0; _idx < _totalListings; _idx++) {
            LoanListing memory _listing = _appStorage.loanListings[_idx];

            if (
                (_loanToken == _listing.tokenAddress) &&
                (_interestRate == _listing.interest) &&
                (_amount <= _listing.amount) &&
                (_duration <=
                    block.timestamp + (_listing.returnDuration - 1 days))
            ) {
                return _listing.listingId;
            }
        }
        return 0;
    }
}
