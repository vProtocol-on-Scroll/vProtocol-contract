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

    using SafeERC20 for IERC20;

    event E(int128, int128);

    /**
     * @dev Allows users to deposit collateral of a specified token into the protocol.
     * @param token The address of the token being deposited as collateral.
     * @param amount The amount of the token to deposit as collateral.
     */
    function depositCollateral(
        address token,
        uint256 amount
    ) external payable {
        // Validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isPaused);
        
        // Validate inputs
        Validator._moreThanZero(amount);
        Validator._isTokenAllowed(_appStorage.tokenData[token].priceFeed);
        
        // Handle native token deposits
        bool isNativeToken = token == Constants.NATIVE_TOKEN;
        if (isNativeToken) {
            amount = msg.value;
        }

        // Update user position
        UserPosition storage position = _appStorage.userPositions[msg.sender];
        position.collateral[token] += amount;
        position.lastUpdate = block.timestamp;

        // Handle token transfer
        if (!isNativeToken) {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit Event.CollateralDeposited(msg.sender, token, amount);
    }

    /**
     * @dev Creates a new P2P lending request
     * @param amount The amount of loan requested
     * @param interest The interest rate for the loan
     * @param returnDuration The expected return date
     * @param expirationDate The expiration date of the request
     * @param loanToken The token address for the loan
     */
    function createLendingRequest(
        uint256 amount,
        uint16 interest,
        uint256 returnDuration,
        uint256 expirationDate,
        address loanToken
    ) external {
        Validator._isP2pStopped(_appStorage.isPaused);
        require(amount > 0, "Amount must be greater than 0");
        require(_appStorage.tokenData[loanToken].isLoanable, "Token not loanable");
        require(expirationDate > block.timestamp, "Invalid expiration");
        require(returnDuration > block.timestamp + 1 days, "Invalid duration");

        // Calculate USD values
        uint8 decimal = LibGettersImpl._getTokenDecimal(loanToken);
        uint256 loanUsdValue = LibGettersImpl._getUsdValue(
            _appStorage,
            loanToken,
            amount,
            decimal
        );
        require(loanUsdValue >= Constants.MIN_LOAN_VALUE_USD, "Loan value too small");

        // Check borrower's health factor
        uint256 healthFactor = LibGettersImpl._healthFactor(
            _appStorage,
            msg.sender,
            loanUsdValue
        );
        require(healthFactor >= Constants.MIN_HEALTH_FACTOR, "Insufficient collateral");

        // Create new request
        uint96 requestId = _appStorage.requestId + 1;
        _appStorage.requestId = requestId;

        Request storage newRequest = _appStorage.requests[requestId];
        newRequest.requestId = requestId;
        newRequest.author = msg.sender;
        newRequest.amount = amount;
        newRequest.interest = interest;
        newRequest.returnDate = returnDuration;
        newRequest.expirationDate = expirationDate;
        newRequest.totalRepayment = Utils.calculateLoanInterest(amount, interest);
        newRequest.loanRequestAddr = loanToken;
        newRequest.status = Status.OPEN;

        // Lock collateral proportionally
        _lockCollateralForRequest(requestId, loanUsdValue);

        emit Event.RequestCreated(msg.sender, requestId, amount, interest);
    }

    /**
     * @dev Services a lending request by transferring funds
     * @param requestId The ID of the lending request
     * @param token The token address for the loan
     */
    function serviceRequest(
        uint96 requestId,
        address token
    ) external payable {
        Validator._isP2pStopped(_appStorage.isPaused);
        
        Request storage request = _appStorage.requests[requestId];
        require(request.status == Status.OPEN, "Request not open");
        require(request.expirationDate > block.timestamp, "Request expired");
        require(request.loanRequestAddr == token, "Invalid token");
        require(request.author != msg.sender, "Cannot fund self");

        uint256 amount = request.amount;
        bool isNativeToken = token == Constants.NATIVE_TOKEN;

        // Validate lender's balance
        if (isNativeToken) {
            require(msg.value >= amount, "Insufficient amount");
        } else {
            require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance");
            require(IERC20(token).allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");
        }

        // Update request status
        request.lender = msg.sender;
        request.status = Status.SERVICED;

        // Update positions
        UserPosition storage borrowerPosition = _appStorage.userPositions[request.author];
        borrowerPosition.p2pBorrowedAmount[token] += amount;
        borrowerPosition.lastUpdate = block.timestamp;

        // Transfer tokens
        if (isNativeToken) {
            if (msg.value > amount) {
                payable(msg.sender).transfer(msg.value - amount);
            }
            payable(request.author).transfer(amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, request.author, amount);
        }

        emit Event.RequestServiced(requestId, msg.sender, request.author, amount);
    }

    /**
     * @dev Internal function to lock collateral for a loan request
     */
    function _lockCollateralForRequest(uint96 requestId, uint256 loanUsdValue) internal {
        UserPosition storage position = _appStorage.userPositions[msg.sender];
        uint256 totalCollateralUSD = LibGettersImpl._getAccountCollateralValue(
            _appStorage,
            msg.sender
        );
        uint256 collateralToLock = (loanUsdValue * Constants.MAX_LTV) / Constants.PERCENTAGE_FACTOR;

        uint256 totalLocked = 0;
        for (uint256 i = 0; i < _appStorage.s_supportedTokens.length; i++) {
            address token = _appStorage.s_supportedTokens[i];
            uint256 collateralAmount = position.collateral[token];
            
            if (collateralAmount > 0) {
                uint8 decimal = LibGettersImpl._getTokenDecimal(token);
                uint256 collateralUSD = LibGettersImpl._getUsdValue(
                    _appStorage,
                    token,
                    collateralAmount,
                    decimal
                );
                uint256 amountToLock = (collateralAmount * collateralToLock) / totalCollateralUSD;
                
                _appStorage.s_idToCollateralTokenAmount[requestId][token] = amountToLock;
                totalLocked += (amountToLock * collateralUSD) / (10 ** decimal);
            }
        }

        require(totalLocked >= collateralToLock, "Insufficient collateral locked");
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
        uint256 _amount
    ) external {
        // validate transaction is not stopped
        Validator._isP2pStopped(_appStorage.isPaused);
        // Validate that the token is allowed and the amount is greater than zero
        Validator._isTokenAllowed(
            _appStorage.tokenData[_tokenCollateralAddress].priceFeed
        );
        Validator._moreThanZero(_amount);

        // Retrieve the user's deposited amount for the specified token
        uint256 depositedAmount = _appStorage.userPositions[msg.sender].collateral[_tokenCollateralAddress];

        // Check if the user has sufficient collateral to withdraw the requested amount
        if (depositedAmount < _amount) {
            revert Protocol__InsufficientCollateralDeposited();
        }

        // Update storage to reflect the withdrawal of collateral
        _appStorage.userPositions[msg.sender].collateral[_tokenCollateralAddress] -= _amount;
        _appStorage.userPositions[msg.sender].lastUpdate = block.timestamp;

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
            _appStorage.tokenData[_tokens[i]].priceFeed = _priceFeeds[i]; // Map token to price feed
            _appStorage.s_supportedTokens.push(_tokens[i]); // Add token to collateral array
        }

        // Emit an event indicating the updated number of collateral tokens
        emit Event.UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_supportedTokens.length)
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
            _appStorage.tokenData[_tokens[i]].priceFeed = address(0); // Remove the price feed for the token

            // Search for the token in the collateral array
            for (uint8 j = 0; j < _appStorage.s_supportedTokens.length; j++) {
                if (_appStorage.s_supportedTokens[j] == _tokens[i]) {
                    // Replace the token to be removed with the last token in the array
                    _appStorage.s_supportedTokens[j] = _appStorage.s_supportedTokens[_appStorage.s_supportedTokens.length - 1];

                    // Remove the last token from the array
                    _appStorage.s_supportedTokens.pop();
                    break; // Stop searching once the token is found and removed
                }
            }
        }

        // Emit an event indicating the updated count of collateral tokens
        emit Event.UpdatedCollateralTokens(
            msg.sender,
            uint8(_appStorage.s_supportedTokens.length)
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
        _appStorage.tokenData[_token].isLoanable = true;

        // Associate the token with its price feed
        _appStorage.tokenData[_token].priceFeed = _priceFeed;

        // Add the loanable token to the list of loanable tokens
        _appStorage.s_supportedTokens.push(_token);

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
        Validator._isP2pStopped(_appStorage.isPaused);

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
        Validator._isP2pStopped(_appStorage.isPaused);

        // Retrieve the lending request associated with the given request ID
        Request storage _foundRequest = _appStorage.requests[_requestId];

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
        Validator._isP2pStopped(_appStorage.isPaused);
        // Validate that the amount is greater than zero and that a value has been sent if using native token
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);
        Validator._moreThanZero(_amount);

        // Ensure the specified loan currency is a loanable token
        if (!_appStorage.tokenData[_loanCurrency].isLoanable) {
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
        uint96 listingId = _appStorage.listingId + 1;
        _appStorage.listingId = listingId;
        LoanListing storage _newListing = _appStorage.loanListings[listingId];

        // Populate the loan listing struct with the provided details
        _newListing.listingId = listingId;
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
            listingId,
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
        Validator._isP2pStopped(_appStorage.isPaused);
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
        uint256 collateralValueInLoanCurrency = LibGettersImpl._getAccountCollateralValue(
            _appStorage,
            msg.sender
        );
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
        address[] memory _collateralTokens = LibGettersImpl._getUserCollateralTokens(
            _appStorage,
            msg.sender
        );

        // Create a new loan request with a unique ID
        uint96 requestId = _appStorage.requestId + 1;
        _appStorage.requestId = requestId;
        Request storage _newRequest = _appStorage.requests[requestId];
        _newRequest.requestId = requestId;
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
            uint256 userBalance = _appStorage.userPositions[msg.sender].collateral[token];

            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                decimal
            ) * collateralToLock) / 100;

            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(
                    _appStorage,
                    token,
                    10,
                    0
                )) *
                (10 ** decimal)) / (Constants.PRECISION);

            _appStorage.s_idToCollateralTokenAmount[requestId][token] = amountToLock;
            _appStorage.userPositions[msg.sender].collateral[token] -= amountToLock;
        }

        // Update borrower's total loan collected in USD
        _appStorage.userPositions[msg.sender].totalLoanCollectedUSD += LibGettersImpl._getLoanCollectedInUsd(
            _appStorage,
            msg.sender
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
            requestId,
            _amount,
            _listing.interest
        );
        emit Event.RequestServiced(
            requestId,
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
        Validator._isP2pStopped(_appStorage.isPaused);
        Validator._moreThanZero(_amount);

        Request storage _request = _appStorage.requests[_requestId];

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
                _appStorage.userPositions[msg.sender].collateral[collateralToken] += _appStorage.s_idToCollateralTokenAmount[_requestId][collateralToken];
            }
        } else {
            // Reduce the outstanding repayment amount for partial payments
            _request.totalRepayment -= _amount;
        }

        // Update borrower's loan collected metrics in USD
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
            msg.sender);
        // Deposit the repayment amount to the lender's available balance
        _appStorage.userPositions[msg.sender].collateral[_request.loanRequestAddr] += _amount;
        _appStorage.userPositions[msg.sender].totalLoanCollectedUSD += _loanUsdValue;

        // Adjust the borrower's total loan collected
        if (loanCollected > _loanUsdValue) {
            _appStorage.userPositions[msg.sender].totalLoanCollectedUSD =
                loanCollected -
                _loanUsdValue;
        } else {
            _appStorage.userPositions[msg.sender].totalLoanCollectedUSD = 0;
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
     * - The loan must be in SERVICED status and past due or below health factor
     * - The request must exist
     *
     * Emits:
     * - `RequestLiquidated` after successfully liquidating the collateral
     */
    function liquidateUserRequest(uint96 requestId) external {
        // Validate transaction is not stopped
        require(!_appStorage.isPaused, "Protocol is paused");

        Request storage request = _appStorage.requests[requestId];
        require(request.status == Status.SERVICED, "Request not serviced");
        
        // Check if loan is past due or below health factor
        bool isPastDue = block.timestamp > request.returnDate;
        bool isBelowHealthFactor = checkLiquidationEligibility(request.author);
        require(isPastDue || isBelowHealthFactor, "Not liquidatable");

        // Calculate total debt including interest
        uint256 totalDebt = request.totalRepayment;
        address loanCurrency = request.loanRequestAddr;
        uint8 loanDecimals = LibGettersImpl._getTokenDecimal(loanCurrency);

        // Track total value recovered for the lender
        uint256 totalRecovered = 0;

        // Process each collateral token
        for (uint256 i = 0; i < request.collateralTokens.length; i++) {
            address collateralToken = request.collateralTokens[i];
            uint256 collateralAmount = _appStorage.s_idToCollateralTokenAmount[requestId][collateralToken];
            
            if (collateralAmount == 0) continue;

            // Get collateral value in loan currency
            uint8 collateralDecimals = LibGettersImpl._getTokenDecimal(collateralToken);
            uint256 collateralValue = LibGettersImpl._getUsdValue(
                _appStorage,
                collateralToken,
                collateralAmount,
                collateralDecimals
            );

            // Apply liquidation discount
            uint256 discountedValue = (collateralValue * (10000 - Constants.LIQUIDATION_DISCOUNT)) / 10000;
            totalRecovered += discountedValue;

            // Transfer collateral to lender
            _appStorage.s_idToCollateralTokenAmount[requestId][collateralToken] = 0;
            _appStorage.userPositions[request.author].collateral[collateralToken] -= collateralAmount;
            _appStorage.userPositions[request.lender].collateral[collateralToken] += collateralAmount;
        }

        // Update borrower's loan metrics
        UserPosition storage borrowerPosition = _appStorage.userPositions[request.author];
        borrowerPosition.p2pBorrowedAmount[loanCurrency] -= request.amount;
        
        // If loan currency is native token, handle wrapped version
        if (loanCurrency == Constants.NATIVE_TOKEN) {
            loanCurrency = Constants.WETH;
        }

        // Mark request as closed
        request.status = Status.LIQUIDATED;

        emit Event.RequestLiquidated(
            requestId,
            request.lender,
            totalRecovered
        );
    }

   

    /// @notice this function is used to activate or deactivate the p2p fail safe
    /// @param _activate a boolean to activate or deactivate the fail safe
    /// @dev this function can only be called by the deployer of the contract
    /// @dev emits the P2pFailSafeStatus event
    function activtateFailSafe(bool _activate) external {
        LibDiamond.enforceIsContractOwner();

        _appStorage.isPaused = _activate;
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

        // Validate return duration
        if (_returnDuration <= block.timestamp) {
            return 0;
        }

        // Iterate through all existing lending offers to find the best match
        for (uint96 i = 1; i < _appStorage.listingId + 1; i++) {
            LoanListing memory listing = _appStorage.loanListings[i];

            // Skip listings that don't meet basic criteria
            if (listing.listingStatus != ListingStatus.OPEN) continue;
            if (listing.tokenAddress != _loanCurrency) continue;
            if (listing.interest > _maxInterest) continue;
            if (listing.amount < _amount) continue;
            if (_amount < listing.min_amount || _amount > listing.max_amount) continue;
            if (_returnDuration > block.timestamp + listing.returnDuration) continue;

            // Calculate match score - prioritize:
            // 1. Lower interest rates (weighted most heavily)
            // 2. Longer available durations
            // 3. Larger available amounts

            // Safe interest score calculation
            uint256 interestScore;
            unchecked {
                // We already checked listing.interest <= _maxInterest
                interestScore = (_maxInterest - listing.interest) * 1000;
            }

            // Safe duration score calculation
            uint256 durationScore = (listing.returnDuration * 100) / 
                (_returnDuration - block.timestamp);  // Safe due to initial check

            // Safe amount score calculation (listing.amount >= _amount was checked)
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
        Validator._isP2pStopped(_appStorage.isPaused);

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
        if (!_appStorage.tokenData[_loanCurrency].isLoanable) {
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
        uint256 collateralValueInLoanCurrency = LibGettersImpl._getAccountCollateralValue(
            _appStorage,
            msg.sender
        );

        // Calculate the maximum loanable amount based on available collateral
        uint256 maxLoanableAmount = Utils.maxLoanableAmount(
            collateralValueInLoanCurrency
        );

        // Check if the loan exceeds the user's collateral allowance
        if (
            _appStorage.userPositions[msg.sender].totalLoanCollectedUSD +
                _loanUsdValue >=
            maxLoanableAmount
        ) {
            revert Protocol__InsufficientCollateral();
        }

        // Retrieve collateral tokens associated with the borrower
        address[] memory _collateralTokens = LibGettersImpl._getUserCollateralTokens(
            _appStorage,
            msg.sender
        );

        // Increment the request ID and initialize the new loan request
        uint96 newRequestId = _appStorage.requestId + 1;
        _appStorage.requestId = newRequestId;
        Request storage _newRequest = _appStorage.requests[newRequestId];
        _newRequest.requestId = newRequestId;
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
            uint256 userBalance = _appStorage.userPositions[msg.sender].collateral[token];

            // Calculate the amount to lock in USD for each token based on the proportional collateral
            uint256 amountToLockUSD = (LibGettersImpl._getUsdValue(
                _appStorage,
                token,
                userBalance,
                _decimalToken
            ) * collateralToLock) / 100;

            // Convert USD amount to token amount and apply the correct decimal scaling
            uint256 amountToLock = ((((amountToLockUSD) * 10) /
                LibGettersImpl._getUsdValue(
                    _appStorage,
                    token,
                    10,
                    0
                )) *
                (10 ** _decimalToken)) / (Constants.PRECISION);

            // Store the locked amount for each collateral token
            _appStorage.s_idToCollateralTokenAmount[newRequestId][token] = amountToLock;
        }

        // Emit an event for the created loan request
        emit Event.RequestCreated(
            msg.sender,
            newRequestId,
            _amount,
            _interest
        );

        return (newRequestId, false);
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
        Validator._isP2pStopped(_appStorage.isPaused);

        // Create the loan listing first
        // Validate that the amount is greater than zero and that a value has been sent if using native token
        Validator._valueMoreThanZero(_amount, _loanCurrency, msg.value);
        Validator._moreThanZero(_amount);

        // Ensure the specified loan currency is a loanable token
        if (!_appStorage.tokenData[_loanCurrency].isLoanable) {
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
        uint96 newListingId = _appStorage.listingId + 1;
        _appStorage.listingId = newListingId;
        LoanListing storage _newListing = _appStorage.loanListings[newListingId];

        // Populate the loan listing struct with the provided details
        _newListing.listingId = newListingId;
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
            newListingId,
            msg.sender,
            _loanCurrency,
            _amount
        );

        listingId = newListingId;

        // If auto-matching is enabled, find compatible borrowing requests
        if (_autoMatch) {
            // Get all open borrowing requests for this currency
            uint96[] memory potentialMatches = new uint96[](
                _appStorage.requestId
            );
            uint256 matchCount = 0;

            // Find all eligible requests
            for (uint96 i = 1; i <= _appStorage.requestId; i++) {
                Request memory req = _appStorage.requests[i];

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
                            _appStorage.requests[potentialMatches[j]].interest <
                            _appStorage.requests[potentialMatches[j + 1]]
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
                Request memory req = _appStorage.requests[requestId];

                // Skip if we can't fulfill this request
                if (req.amount > remainingAmount || req.amount < _min_amount) {
                    continue;
                }

                // Service this request
                    if (req.loanRequestAddr != Constants.NATIVE_TOKEN){
                        IERC20(req.loanRequestAddr).approve(address(this), req.amount);
                    }
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

        return (listingId, matchedRequests);
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
