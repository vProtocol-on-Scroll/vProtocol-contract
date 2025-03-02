// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibToken} from "../libraries/LibShared.sol";
import {LibPriceOracle} from "../libraries/LibShared.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {Constants} from "../utils/constants/Constant.sol";

/**
 * @title P2pFacet
 * @author Five Protocol
 *
 * @dev This contract manages the peer-to-peer lending operations.
 */
contract P2pFacet {
    using SafeERC20 for IERC20;
    using LibPriceOracle for LibAppStorage.Layout;

    LibAppStorage.Layout internal s;

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     */
    fallback() external {
        revert("P2pFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Create a position with multi-collateral and match with existing listings
     * @param loanToken The token to borrow
     * @param borrowAmount The amount to borrow
     * @param maxInterest Maximum acceptable interest rate
     * @param returnDuration Loan duration
     * @param expirationDate When the request expires if not filled
     * @param collateralTokens Array of collateral token addresses
     * @param collateralAmounts Array of collateral amounts
     * @return requestId The ID of the created request (or matched loan)
     * @return matched Whether the request was automatically matched
     */
    function createPosition(
        address loanToken,
        uint256 borrowAmount,
        uint16 maxInterest,
        uint256 returnDuration,
        uint256 expirationDate,
        address[] calldata collateralTokens,
        uint256[] calldata collateralAmounts
    ) internal returns (uint96 requestId, bool matched) {
        require(!s.isPaused, "Protocol is paused");
        require(borrowAmount > 0, "Borrow amount must be greater than 0");
        require(s.tokenData[loanToken].isLoanable, "Token not loanable");
        require(expirationDate > block.timestamp, "Invalid expiration");
        require(returnDuration > block.timestamp + 1 days, "Invalid duration");
        require(collateralTokens.length == collateralAmounts.length, "Array length mismatch");
        require(collateralTokens.length > 0, "Must provide collateral");
        
        // Handle native token collateral
        uint256 nativeValue = 0;
        for (uint i = 0; i < collateralTokens.length; i++) {
            if (collateralTokens[i] == Constants.NATIVE_TOKEN) {
                nativeValue += collateralAmounts[i];
            }
        }
        
        if (nativeValue > 0) {
            require(msg.value >= nativeValue, "Insufficient ETH sent");
        }
        
        // First, try to find a matching listing
        uint96 matchedListingId = _findMatchingLendingOffer(
            loanToken,
            borrowAmount,
            maxInterest,
            returnDuration
        );
        
        // If a match is found, process the match
        if (matchedListingId > 0) {
            // First deposit the collateral
            _depositMultiCollateral(collateralTokens, collateralAmounts);
            
            // Then use it to borrow from the matched listing
            _requestLoanFromListing(matchedListingId, borrowAmount);
            
            // The most recent request ID will be the one created
            return (s.requestId, true);
        }
        
        // If no match found, create a new request
        // First deposit the collateral
        _depositMultiCollateral(collateralTokens, collateralAmounts);
        
        // Calculate USD values for collateral
        uint256 totalCollateralUSD = 0;
        for (uint i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralAmounts[i];
            
            uint8 decimal = LibToken.getDecimals(token);
            totalCollateralUSD += s.getTokenUsdValue(token, amount, decimal);
        }
        
        // Calculate loan USD value
        uint8 loanDecimal = LibToken.getDecimals(loanToken);
        uint256 loanUsdValue = s.getTokenUsdValue(loanToken, borrowAmount, loanDecimal);
        
        // Check if user has sufficient collateral for the loan
        require(loanUsdValue * 10000 <= totalCollateralUSD * Constants.MAX_LTV, "Insufficient collateral");
        
        // Create the request
        requestId = ++s.requestId;
        
        Request storage newRequest = s.requests[requestId];
        newRequest.requestId = requestId;
        newRequest.author = msg.sender;
        newRequest.amount = borrowAmount;
        newRequest.interest = maxInterest;
        newRequest.returnDate = returnDuration;
        newRequest.expirationDate = expirationDate;
        newRequest.totalRepayment = _calculateLoanInterest(borrowAmount, maxInterest);
        newRequest.loanRequestAddr = loanToken;
        newRequest.status = Status.OPEN;
        newRequest.collateralTokens = collateralTokens;
        
        // Lock collateral proportionally
        _lockCollateralForRequest(requestId, loanUsdValue, collateralTokens, totalCollateralUSD);
        
        emit Event.RequestCreated(msg.sender, requestId, borrowAmount, maxInterest);
        
        return (requestId, false);
    }

    /**
     * @notice Service a lending request (fund it)
     * @param requestId ID of the request to service
     * @param token Token to lend
     */
    function serviceRequest(uint96 requestId, address token) external payable {
        require(!s.isPaused, "Protocol is paused");
        
        Request storage request = s.requests[requestId];
        require(request.status == Status.OPEN, "Request not open");
        require(request.expirationDate > block.timestamp, "Request expired");
        require(request.loanRequestAddr == token, "Invalid token");
        require(request.author != msg.sender, "Cannot fund self");

        uint256 amount = request.amount;
        bool isNativeToken = LibToken.isNativeToken(token);

        // Validate lender's balance
        if (isNativeToken) {
            require(msg.value >= amount, "Insufficient amount");
            
            // Refund excess
            if (msg.value > amount) {
                (bool sent, ) = payable(msg.sender).call{value: msg.value - amount}("");
                require(sent, "ETH refund failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update request status
        request.lender = msg.sender;
        request.status = Status.SERVICED;

        // Update positions
        UserPosition storage borrowerPosition = s.userPositions[request.author];
        borrowerPosition.p2pBorrowedAmount[token] += amount;
        borrowerPosition.lastUpdate = block.timestamp;

        // Update P2P balances for rebalancing
        s.p2pBalances.totalBorrowOrders += amount;

        // Transfer tokens to borrower
        if (isNativeToken) {
            (bool sent, ) = payable(request.author).call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(request.author, amount);
        }

        emit Event.RequestServiced(requestId, msg.sender, request.author, amount);
    }

    /**
     * @notice Create a loan listing with matching
     * @param amount Total amount to lend
     * @param minAmount Minimum loan size
     * @param maxAmount Maximum loan size
     * @param returnDuration Loan duration
     * @param interest Interest rate
     * @param loanCurrency Token to lend
     * @param autoMatch Whether to auto-match with borrowers
     * @return listingId ID of the created listing
     * @return matchedRequests Array of matched request IDs
     */
    function createLoanListingWithMatching(
        uint256 amount,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 returnDuration,
        uint16 interest,
        address loanCurrency,
        bool autoMatch
    ) external payable returns (uint96 listingId, uint96[] memory matchedRequests) {
        // Create the loan listing
        listingId = _createLoanListing(
            amount,
            minAmount,
            maxAmount,
            returnDuration,
            interest,
            loanCurrency
        );
        
        // If auto-matching is disabled, return empty array
        if (!autoMatch) {
            return (listingId, new uint96[](0));
        }
        
        // If auto-matching is enabled, find compatible borrowing requests
        uint96[] memory potentialMatches = new uint96[](s.requestId);
        uint256 matchCount = 0;

        // Find all eligible requests
        for (uint96 i = 1; i <= s.requestId; i++) {
            Request memory req = s.requests[i];

            if (
                req.status == Status.OPEN &&
                req.loanRequestAddr == loanCurrency &&
                req.interest >= interest &&
                req.amount >= minAmount &&
                req.amount <= maxAmount &&
                req.returnDate <= block.timestamp + returnDuration &&
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
                        s.requests[potentialMatches[j]].interest <
                        s.requests[potentialMatches[j + 1]].interest
                    ) {
                        uint96 temp = potentialMatches[j];
                        potentialMatches[j] = potentialMatches[j + 1];
                        potentialMatches[j + 1] = temp;
                    }
                }
            }
        }

        // Attempt to service requests until no more funds available
        uint256 remainingAmount = amount;
        matchedRequests = new uint96[](matchCount);
        uint256 matchedCount = 0;

        for (uint256 i = 0; i < matchCount && remainingAmount > 0; i++) {
            uint96 reqId = potentialMatches[i];
            Request memory req = s.requests[reqId];

            // Skip if we can't fulfill this request
            if (req.amount > remainingAmount || req.amount < minAmount) {
                continue;
            }

            // Service this request
            try this.serviceRequest{
                value: (req.loanRequestAddr == Constants.NATIVE_TOKEN) ? req.amount : 0
            }(reqId, req.loanRequestAddr) {
                // If successful, update remaining amount and track the match
                remainingAmount -= req.amount;
                
                // Update listing
                LoanListing storage listing = s.loanListings[listingId];
                listing.amount = remainingAmount;
                
                if (remainingAmount <= listing.max_amount) {
                    listing.max_amount = remainingAmount;
                }
                
                if (remainingAmount <= listing.min_amount) {
                    listing.min_amount = 0;
                }
                
                if (remainingAmount == 0) {
                    listing.listingStatus = ListingStatus.CLOSED;
                }
                
                matchedRequests[matchedCount] = reqId;
                matchedCount++;
            } catch {
                // If service failed, just skip this request
                continue;
            }
        }

        // Trim matchedRequests array to actual matches
        if (matchedCount < matchCount) {
            uint96[] memory trimmedMatches = new uint96[](matchedCount);
            for (uint256 i = 0; i < matchedCount; i++) {
                trimmedMatches[i] = matchedRequests[i];
            }
            matchedRequests = trimmedMatches;
        }

        return (listingId, matchedRequests);
    }

    /**
     * @notice Create a lending request and try auto-matching
     * @param amount Amount of the loan
     * @param interest Interest rate
     * @param returnDuration Loan duration
     * @param expirationDate Expiration date
     * @param loanToken Loan token
     * @param collateralTokens Array of collateral tokens
     * @param collateralAmounts Array of collateral amounts
     * @return requestId The ID of the created request
     * @return matched Whether the request was matched
     */
    function createAndMatchLendingRequest(
        uint256 amount,
        uint16 interest,
        uint256 returnDuration,
        uint256 expirationDate,
        address loanToken,
        address[] calldata collateralTokens,
        uint256[] calldata collateralAmounts
    ) external payable returns (uint96 requestId, bool matched) {
        return createPosition(
            loanToken,
            amount,
            interest,
            returnDuration,
            expirationDate,
            collateralTokens,
            collateralAmounts
        );
    }

    /**
     * @notice Repay a P2P loan
     * @param requestId ID of the loan request
     * @param amount Amount to repay (0 for full repayment)
     */
    function repayLoan(uint96 requestId, uint256 amount) external payable {
        require(!s.isPaused, "Protocol is paused");
        
        Request storage request = s.requests[requestId];
        require(request.status == Status.SERVICED, "Request not serviced");
        require(msg.sender == request.author, "Not the borrower");
        
        address token = request.loanRequestAddr;
        bool isNativeToken = LibToken.isNativeToken(token);
        
        // Determine repayment amount
        uint256 repayAmount;
        if (amount == 0) {
            repayAmount = request.totalRepayment;
        } else {
            repayAmount = amount < request.totalRepayment ? amount : request.totalRepayment;
        }
        
        // Handle native token
        if (isNativeToken) {
            require(msg.value >= repayAmount, "Insufficient ETH sent");
            
            // Refund excess
            if (msg.value > repayAmount) {
                (bool sent, ) = payable(msg.sender).call{value: msg.value - repayAmount}("");
                require(sent, "ETH refund failed");
            }
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);
        }
        
        // Update request
        request.totalRepayment -= repayAmount;
        
        // Update P2P balances for rebalancing
        s.p2pBalances.totalBorrowOrders -= repayAmount;
        
        // Update user position
        UserPosition storage position = s.userPositions[msg.sender];
        position.p2pBorrowedAmount[token] -= repayAmount;
        
        // If fully repaid, close the request and release collateral
        if (request.totalRepayment == 0) {
            request.status = Status.CLOSED;
            
            // Release locked collateral
            for (uint i = 0; i < request.collateralTokens.length; i++) {
                address collateralToken = request.collateralTokens[i];
                uint256 lockedAmount = s.s_idToCollateralTokenAmount[requestId][collateralToken];
                if (lockedAmount > 0) {
                    position.collateral[collateralToken] += lockedAmount;
                    s.s_idToCollateralTokenAmount[requestId][collateralToken] = 0;
                }
            }
        }
        
        // Transfer to lender
        if (isNativeToken) {
            (bool sent, ) = payable(request.lender).call{value: repayAmount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(request.lender, repayAmount);
        }
        
        emit Event.LoanRepayment(msg.sender, requestId, repayAmount);
    }

    /**
     * @notice Close a loan listing and retrieve funds
     * @param listingId ID of the listing to close
     */
    function closeListingAd(uint96 listingId) external {
        require(!s.isPaused, "Protocol is paused");
        
        LoanListing storage listing = s.loanListings[listingId];
        require(listing.listingStatus == ListingStatus.OPEN, "Listing not open");
        require(listing.author == msg.sender, "Not the listing owner");
        require(listing.amount > 0, "No funds to withdraw");
        
        uint256 amount = listing.amount;
        address token = listing.tokenAddress;
        
        // Update listing
        listing.amount = 0;
        listing.listingStatus = ListingStatus.CLOSED;
        
        // Update P2P balances for rebalancing
        s.p2pBalances.totalLendOrders -= amount;
        s.tokenBalances[token].p2pLiquidity -= amount;
        
        // Transfer funds back to lender
        if (token == Constants.NATIVE_TOKEN) {
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        
        emit Event.withdrawnAdsToken(
            msg.sender,
            listingId,
            uint8(listing.listingStatus),
            amount
        );
    }

    /**
     * @notice Find matching loan listings
     * @param loanCurrency Token to borrow
     * @param amount Amount needed
     * @param maxInterest Maximum interest rate
     * @param returnDuration Loan duration
     * @return Best matching listing ID
     */
    function findMatchingLendingOffer(
        address loanCurrency,
        uint256 amount,
        uint16 maxInterest,
        uint256 returnDuration
    ) external view returns (uint96) {
        return _findMatchingLendingOffer(
            loanCurrency,
            amount,
            maxInterest,
            returnDuration
        );
    }

    /**
     * @notice Liquidate a P2P loan
     * @param requestId ID of the request to liquidate
     */
    function liquidateUserRequest(uint96 requestId) external payable {
        require(!s.isPaused, "Protocol is paused");
        
        Request storage request = s.requests[requestId];
        require(request.status == Status.SERVICED, "Request not serviced");
        
        // Check if loan is past due or below health factor
        bool isPastDue = block.timestamp > request.returnDate;
        bool isBelowHealthFactor = _isPositionLiquidatable(request.author, requestId);
        require(isPastDue || isBelowHealthFactor, "Not liquidatable");
        
        address borrower = request.author;
        address lender = request.lender;
        address loanToken = request.loanRequestAddr;
        uint256 totalDebt = request.totalRepayment;
        
        // Calculate total value of collateral
        uint256 totalCollateralValue = 0;
        for (uint i = 0; i < request.collateralTokens.length; i++) {
            address collateralToken = request.collateralTokens[i];
            uint256 collateralAmount = s.s_idToCollateralTokenAmount[requestId][collateralToken];
            if (collateralAmount > 0) {
                uint8 decimal = LibToken.getDecimals(collateralToken);
                totalCollateralValue += s.getTokenUsdValue(collateralToken, collateralAmount, decimal);
            }
        }
        
        // Update request status
        request.status = Status.LIQUIDATED;
        
        // Update P2P balances for rebalancing
        s.p2pBalances.totalBorrowOrders -= request.amount;
        
        // Update borrower position
        UserPosition storage borrowerPosition = s.userPositions[borrower];
        borrowerPosition.p2pBorrowedAmount[loanToken] -= request.amount;
        
        // Transfer debt from liquidator to lender
        if (loanToken == Constants.NATIVE_TOKEN) {
            require(msg.value >= totalDebt, "Insufficient ETH sent");
            
            // Refund excess
            if (msg.value > totalDebt) {
                (bool refundSent, ) = payable(msg.sender).call{value: msg.value - totalDebt}("");
                require(refundSent, "ETH refund failed");
            }
            
            // Transfer to lender
            (bool lenderSent, ) = payable(lender).call{value: totalDebt}("");
            require(lenderSent, "ETH transfer to lender failed");
        } else {
            IERC20(loanToken).safeTransferFrom(msg.sender, lender, totalDebt);
        }
        
        // Transfer collateral to liquidator
        for (uint i = 0; i < request.collateralTokens.length; i++) {
            address collateralToken = request.collateralTokens[i];
            uint256 collateralAmount = s.s_idToCollateralTokenAmount[requestId][collateralToken];
            if (collateralAmount > 0) {
                // Apply liquidation discount
                uint256 discountedAmount = (collateralAmount * (10000 - Constants.LIQUIDATION_DISCOUNT)) / 10000;
                
                // Transfer to liquidator
                if (collateralToken == Constants.NATIVE_TOKEN) {
                    (bool sent, ) = payable(msg.sender).call{value: discountedAmount}("");
                    require(sent, "ETH transfer failed");
                } else {
                    IERC20(collateralToken).safeTransfer(msg.sender, discountedAmount);
                }
                
                // Any remaining after discount goes to protocol fees
                uint256 protocolAmount = collateralAmount - discountedAmount;
                if (protocolAmount > 0 && s.s_protocolFeeRecipient != address(0)) {
                    if (collateralToken == Constants.NATIVE_TOKEN) {
                        (bool sent, ) = payable(s.s_protocolFeeRecipient).call{value: protocolAmount}("");
                        require(sent, "ETH fee transfer failed");
                    } else {
                        IERC20(collateralToken).safeTransfer(s.s_protocolFeeRecipient, protocolAmount);
                    }
                }
                
                // Clear locked amount
                s.s_idToCollateralTokenAmount[requestId][collateralToken] = 0;
            }
        }
        
        // Update liquidator's stats for rewards
        UserActivity storage activity = s.userActivities[msg.sender];
        activity.totalLiquidationAmount += totalCollateralValue;
        
        emit Event.RequestLiquidated(requestId, lender, totalCollateralValue);
    }

    /**
     * @notice Check if a position can be liquidated
     * @param user User address
     * @param requestId Request ID
     * @return Whether position can be liquidated
     */
    function isPositionLiquidatable(address user, uint96 requestId) external view returns (bool) {
        return _isPositionLiquidatable(user, requestId);
    }

    // Internal functions

    /**
     * @notice Deposit multiple collateral tokens
     * @param collateralTokens Array of collateral token addresses
     * @param collateralAmounts Array of collateral amounts
     */
    function _depositMultiCollateral(
        address[] calldata collateralTokens,
        uint256[] calldata collateralAmounts
    ) internal {
        for (uint i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralAmounts[i];
            
            if (token == Constants.NATIVE_TOKEN) {
                // Native token is handled via msg.value, no transfer needed
                continue;
            } else {
                // Transfer token from user
                IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            }
            
            // Update collateral position
            s.userPositions[msg.sender].collateral[token] += amount;
        }
        
        s.userPositions[msg.sender].lastUpdate = block.timestamp;
    }

    /**
     * @notice Calculate loan interest
     * @param amount Loan amount
     * @param interestRate Interest rate in basis points
     * @return Total repayment amount with interest
     */
    function _calculateLoanInterest(uint256 amount, uint16 interestRate) internal pure returns (uint256) {
        uint256 interest = (amount * interestRate) / 10000;
        return amount + interest;
    }

    /**
     * @notice Lock collateral for a loan request
     * @param requestId Request ID
     * @param loanUsdValue USD value of the loan
     * @param collateralTokens Array of collateral tokens
     * @param totalCollateralUSD Total USD value of collateral
     */
    function _lockCollateralForRequest(
        uint96 requestId, 
        uint256 loanUsdValue,
        address[] memory collateralTokens,
        uint256 totalCollateralUSD
    ) internal {
        UserPosition storage position = s.userPositions[msg.sender];
        
        // Calculate required collateral to lock based on loan value and LTV
        uint256 requiredCollateralUSD = (loanUsdValue * 10000) / Constants.MAX_LTV;
        
        // Lock a proportional amount of each collateral token
        for (uint i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint8 decimal = LibToken.getDecimals(token);
            
            // Get user's current balance of this token
            uint256 collateralAmount = position.collateral[token];
            uint256 collateralUSD = s.getTokenUsdValue(token, collateralAmount, decimal);
            
            // Calculate share of collateral to lock
            uint256 collateralShare = (collateralUSD * 10000) / totalCollateralUSD;
            uint256 amountToLockUSD = (requiredCollateralUSD * collateralShare) / 10000;
            
            // Convert USD to token amount
            uint256 tokenPricePerUnit = s.getTokenUsdValue(token, 10**decimal, decimal);
            uint256 amountToLock = (amountToLockUSD * (10**decimal)) / tokenPricePerUnit;
            
            // Ensure we don't lock more than available
            if (amountToLock > collateralAmount) {
                amountToLock = collateralAmount;
            }
            
            // Lock the collateral
            position.collateral[token] -= amountToLock;
            s.s_idToCollateralTokenAmount[requestId][token] = amountToLock;
        }
    }

    /**
     * @notice Check if a position can be liquidated
     * @param user User address
     * @param requestId Request ID
     * @return Whether the position can be liquidated
     */
    function _isPositionLiquidatable(address user, uint96 requestId) internal view returns (bool) {
        Request storage request = s.requests[requestId];
        
        // Only active loans can be liquidated
        if (request.status != Status.SERVICED || request.author != user) {
            return false;
        }
        
        // Check if loan is past due
        if (block.timestamp > request.returnDate) {
            return true;
        }
        
        // Calculate health factor
        uint256 healthFactor = _calculatePositionHealthFactor(requestId);
        return healthFactor < Constants.HEALTH_FACTOR_THRESHOLD;
    }

    /**
     * @notice Calculate health factor for a specific position
     * @param requestId Request ID
     * @return Health factor in basis points
     */
    function _calculatePositionHealthFactor(uint96 requestId) internal view returns (uint256) {
        Request storage request = s.requests[requestId];
        
        // Get loan value
        uint8 loanDecimal = LibToken.getDecimals(request.loanRequestAddr);
        uint256 loanUsdValue = s.getTokenUsdValue(request.loanRequestAddr, request.totalRepayment, loanDecimal);
        
        // Calculate collateral value
        uint256 totalCollateralValue = 0;
        uint256 weightedLiquidationThreshold = 0;
        
        for (uint i = 0; i < request.collateralTokens.length; i++) {
            address token = request.collateralTokens[i];
            uint256 collateralAmount = s.s_idToCollateralTokenAmount[requestId][token];
            
            if (collateralAmount > 0) {
                uint8 decimal = LibToken.getDecimals(token);
                uint256 tokenValue = s.getTokenUsdValue(token, collateralAmount, decimal);
                
                totalCollateralValue += tokenValue;
                weightedLiquidationThreshold += tokenValue * s.tokenConfigs[token].liquidationThreshold;
            }
        }
        
        if (loanUsdValue == 0) {
            return type(uint256).max;
        }
        
        if (totalCollateralValue == 0) {
            return 0;
        }
        
        // Calculate weighted liquidation threshold
        uint256 avgLiquidationThreshold = weightedLiquidationThreshold / totalCollateralValue;
        
        // Calculate health factor
        uint256 adjustedCollateralValue = (totalCollateralValue * avgLiquidationThreshold) / 10000;
        return (adjustedCollateralValue * 10000) / loanUsdValue;
    }

    /**
     * @notice Find a matching loan listing
     * @param loanCurrency Token to borrow
     * @param amount Amount needed
     * @param maxInterest Maximum interest rate
     * @param returnDuration Loan duration
     * @return Best matching listing ID
     */
    function _findMatchingLendingOffer(
        address loanCurrency,
        uint256 amount,
        uint16 maxInterest,
        uint256 returnDuration
    ) internal view returns (uint96) {
        uint256 bestScore = 0;
        uint96 bestMatch = 0;

        // Validate return duration
        if (returnDuration <= block.timestamp) {
            return 0;
        }

        // Iterate through all existing lending offers to find the best match
        for (uint96 i = 1; i <= s.listingId; i++) {
            LoanListing memory listing = s.loanListings[i];

            // Skip listings that don't meet basic criteria
            if (listing.listingStatus != ListingStatus.OPEN) continue;
            if (listing.tokenAddress != loanCurrency) continue;
            if (listing.interest > maxInterest) continue;
            if (listing.amount < amount) continue;
            if (amount < listing.min_amount || amount > listing.max_amount) continue;
            if (returnDuration > block.timestamp + listing.returnDuration) continue;

            // Calculate match score - prioritize:
            // 1. Lower interest rates (weighted most heavily)
            // 2. Longer available durations
            // 3. Larger available amounts

            // Safe interest score calculation
            uint256 interestScore;
            unchecked {
                interestScore = (maxInterest - listing.interest) * 1000;
            }

            // Safe duration score calculation
            uint256 durationScore = (listing.returnDuration * 100) / 
                (returnDuration - block.timestamp);

            // Safe amount score calculation (listing.amount >= amount was checked)
            uint256 amountScore = (listing.amount * 10) / amount;

            uint256 score = interestScore + durationScore + amountScore;

            if (score > bestScore) {
                bestScore = score;
                bestMatch = i;
            }
        }

        return bestMatch;
    }

    /**
     * @notice Request a loan from a listing
     * @param listingId Listing ID to borrow from
     * @param amount Amount to borrow
     * @return Whether the request was successful
     */
    function _requestLoanFromListing(uint96 listingId, uint256 amount) internal returns (bool) {
        // Get loan listing
        LoanListing storage listing = s.loanListings[listingId];
        require(listing.listingStatus == ListingStatus.OPEN, "Listing not open");
        require(listing.amount >= amount, "Insufficient funds in listing");
        require(amount >= listing.min_amount && amount <= listing.max_amount, "Invalid amount");
        
        // Create a new loan request
        uint96 requestId = ++s.requestId;
        Request storage newRequest = s.requests[requestId];
        
        newRequest.requestId = requestId;
        newRequest.author = msg.sender;
        newRequest.lender = listing.author;
        newRequest.amount = amount;
        newRequest.interest = listing.interest;
        newRequest.returnDate = block.timestamp + listing.returnDuration;
        newRequest.totalRepayment = _calculateLoanInterest(amount, listing.interest);
        newRequest.loanRequestAddr = listing.tokenAddress;
        newRequest.status = Status.SERVICED;
        
        // Get user's collateral tokens
        address[] memory collateralTokens = new address[](s.s_supportedTokens.length);
        uint256 collateralCount = 0;
        
        for (uint i = 0; i < s.s_supportedTokens.length; i++) {
            address token = s.s_supportedTokens[i];
            if (s.userPositions[msg.sender].collateral[token] > 0) {
                collateralTokens[collateralCount] = token;
                collateralCount++;
            }
        }
        
        // Resize collateral tokens array
        address[] memory finalCollateralTokens = new address[](collateralCount);
        for (uint i = 0; i < collateralCount; i++) {
            finalCollateralTokens[i] = collateralTokens[i];
        }
        
        newRequest.collateralTokens = finalCollateralTokens;
        
        // Lock collateral proportionally
        uint8 loanDecimal = LibToken.getDecimals(listing.tokenAddress);
        uint256 loanUsdValue = s.getTokenUsdValue(listing.tokenAddress, amount, loanDecimal);
        
        // Calculate total collateral value
        uint256 totalCollateralUSD = 0;
        for (uint i = 0; i < collateralCount; i++) {
            address token = finalCollateralTokens[i];
            uint8 decimal = LibToken.getDecimals(token);
            uint256 collateralAmount = s.userPositions[msg.sender].collateral[token];
            totalCollateralUSD += s.getTokenUsdValue(token, collateralAmount, decimal);
        }
        
        _lockCollateralForRequest(requestId, loanUsdValue, finalCollateralTokens, totalCollateralUSD);
        
        // Update listing
        listing.amount -= amount;
        if (listing.amount < listing.max_amount) {
            listing.max_amount = listing.amount;
        }
        if (listing.amount < listing.min_amount) {
            listing.min_amount = 0;
        }
        if (listing.amount == 0) {
            listing.listingStatus = ListingStatus.CLOSED;
        }
        
        // Update borrower position
        s.userPositions[msg.sender].p2pBorrowedAmount[listing.tokenAddress] += amount;
        s.userPositions[msg.sender].lastUpdate = block.timestamp;
        
        // Update P2P balances for rebalancing
        s.p2pBalances.totalLendOrders -= amount;
        s.p2pBalances.totalBorrowOrders += amount;
        s.tokenBalances[listing.tokenAddress].p2pLiquidity -= amount;
        
        // Transfer tokens to borrower
        if (listing.tokenAddress == Constants.NATIVE_TOKEN) {
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            require(sent, "ETH transfer failed");
        } else {
            IERC20(listing.tokenAddress).safeTransfer(msg.sender, amount);
        }
        
        emit Event.RequestCreated(msg.sender, requestId, amount, listing.interest);
        emit Event.RequestServiced(requestId, listing.author, msg.sender, amount);
        
        return true;
    }

    /**
     * @notice Create a loan listing
     * @param amount Total amount to lend
     * @param minAmount Minimum loan size
     * @param maxAmount Maximum loan size
     * @param returnDuration Loan duration
     * @param interest Interest rate
     * @param loanCurrency Token to lend
     * @return listingId ID of the created listing
     */
    function _createLoanListing(
        uint256 amount,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 returnDuration,
        uint16 interest,
        address loanCurrency
    ) internal returns (uint96 listingId) {
        require(!s.isPaused, "Protocol is paused");
        require(amount > 0, "Amount must be greater than 0");
        require(s.tokenData[loanCurrency].isLoanable, "Token not loanable");
        require(minAmount > 0 && minAmount <= maxAmount && maxAmount <= amount, "Invalid amount parameters");
        require(returnDuration > block.timestamp, "Invalid duration");
        
        bool isNativeToken = loanCurrency == Constants.NATIVE_TOKEN;
        
        // Handle token transfer
        if (isNativeToken) {
            require(msg.value >= amount, "Insufficient ETH sent");
            
            // Refund excess
            if (msg.value > amount) {
                (bool sent, ) = payable(msg.sender).call{value: msg.value - amount}("");
                require(sent, "ETH refund failed");
            }
        } else {
            IERC20(loanCurrency).safeTransferFrom(msg.sender, address(this), amount);
        }
        
        // Create listing
        listingId = ++s.listingId;
        
        LoanListing storage newListing = s.loanListings[listingId];
        newListing.listingId = listingId;
        newListing.author = msg.sender;
        newListing.tokenAddress = loanCurrency;
        newListing.amount = amount;
        newListing.min_amount = minAmount;
        newListing.max_amount = maxAmount;
        newListing.returnDuration = returnDuration - block.timestamp;
        newListing.interest = interest;
        newListing.listingStatus = ListingStatus.OPEN;
        
        // Update P2P balances for rebalancing
        s.p2pBalances.totalLendOrders += amount;
        s.tokenBalances[loanCurrency].p2pLiquidity += amount;
        
        emit Event.LoanListingCreated(listingId, msg.sender, loanCurrency, amount);
        
        return listingId;
    }
}