// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibToken} from "../libraries/LibShared.sol";
import "../model/Protocol.sol";
import "../model/Event.sol";
import {Constants} from "../utils/constants/Constant.sol";
import {IFlashLoanReceiver} from "../interfaces/IFlashLoanReceiver.sol";

/**
 * @title FlashLoanFacet
 * @author Five Protocol
 *
 * @dev This contract implements flash loan functionality, allowing users to borrow
 * tokens without collateral as long as they are returned within the same transaction.
 */
contract FlashLoanFacet {
    using SafeERC20 for IERC20;

    LibAppStorage.Layout internal s;

    // Define flash loan events
    event FlashLoanInitiated(
        address indexed initiator,
        address indexed receiver,
        address[] tokens,
        uint256[] amounts,
        uint256[] fees
    );
    
    event FlashLoanCompleted(
        address indexed initiator,
        address indexed receiver,
        address[] tokens,
        uint256[] amounts,
        uint256[] fees
    );
    
    event FlashLoanParamUpdated(
        string paramName,
        uint256 value
    );

    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     */
    fallback() external {
        revert("FlashLoanFacet: fallback");
    }

    receive() external payable {}

    /**
     * @notice Initialize flash loan parameters
     * @param feeBps Flash loan fee in basis points
     */
    function initializeFlashLoan(uint256 feeBps) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(feeBps <= 500, "Fee too high"); // Max 5% fee
        
        s.flashLoanConfig.feeBps = feeBps;
        s.flashLoanConfig.isInitialized = true;
        
        emit FlashLoanParamUpdated("feeBps", feeBps);
    }

    /**
     * @notice Update flash loan fee
     * @param feeBps New fee in basis points
     */
    function updateFlashLoanFee(uint256 feeBps) external {
        require(msg.sender == LibDiamond.contractOwner(), "Not authorized");
        require(feeBps <= 500, "Fee too high"); // Max 5% fee
        
        s.flashLoanConfig.feeBps = feeBps;
        
        emit FlashLoanParamUpdated("feeBps", feeBps);
    }

    /**
     * @notice Execute a flash loan
     * @param receiver Address of the contract receiving the flash loan
     * @param tokens Array of token addresses to borrow
     * @param amounts Array of amounts to borrow for each token
     * @param params Additional parameters to pass to the receiver
     * @return success Whether the flash loan was successful
     */
    function flashLoan(
        address receiver,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata params
    ) external returns (bool success) {
        require(!s.isPaused, "Protocol is paused");
        require(s.flashLoanConfig.isInitialized, "Flash loans not initialized");
        require(receiver != address(0), "Invalid receiver");
        require(tokens.length > 0, "No tokens specified");
        require(tokens.length == amounts.length, "Array length mismatch");
        
        // Calculate fees
        uint256[] memory fees = new uint256[](tokens.length);
        uint256[] memory amountsWithFees = new uint256[](tokens.length);
        
        for (uint i = 0; i < tokens.length; i++) {
            require(s.supportedTokens[tokens[i]], "Token not supported");
            
            // Verify sufficient liquidity
            require(
                s.tokenData[tokens[i]].poolLiquidity >= amounts[i], 
                "Insufficient liquidity"
            );
            
            // Calculate fee
            fees[i] = (amounts[i] * s.flashLoanConfig.feeBps) / 10000;
            amountsWithFees[i] = amounts[i] + fees[i];
        }
        
        // Transfer tokens to receiver
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == Constants.NATIVE_TOKEN) {
                (bool sent, ) = payable(receiver).call{value: amounts[i]}("");
                require(sent, "ETH transfer failed");
            } else {
                IERC20(tokens[i]).safeTransfer(receiver, amounts[i]);
            }
            
            // Temporarily reduce pool liquidity
            s.tokenData[tokens[i]].poolLiquidity -= amounts[i];
        }
        
        // Update flash loan stats
        s.flashLoanConfig.totalFlashLoans++;
        
        // Emit flash loan initiated event
        emit FlashLoanInitiated(
            msg.sender,
            receiver,
            tokens,
            amounts,
            fees
        );
        
        // Call receiver with callback
        bool receiverResult = IFlashLoanReceiver(receiver).executeOperation(
            tokens,
            amounts,
            fees,
            msg.sender,
            params
        );
        
        require(receiverResult, "Receiver failed");
        
        // Check and collect repayments
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == Constants.NATIVE_TOKEN) {
                // For ETH, we check balance increased by fee amount
                uint256 expectedBalance = fees[i]; // We expect at least the fee to be transferred
                require(
                    address(this).balance >= expectedBalance,
                    "Flash loan not repaid"
                );
                
                // Update pool liquidity (restored + fee)
                s.tokenData[tokens[i]].poolLiquidity += amounts[i] + fees[i];
            } else {
                // For ERC20, verify token was returned + fee
                uint256 balanceBefore = IERC20(tokens[i]).balanceOf(address(this));
                
                // Transfer token back with fee
                IERC20(tokens[i]).safeTransferFrom(
                    receiver,
                    address(this),
                    amountsWithFees[i]
                );
                
                uint256 balanceAfter = IERC20(tokens[i]).balanceOf(address(this));
                require(
                    balanceAfter >= balanceBefore + amountsWithFees[i],
                    "Flash loan not repaid"
                );
                
                // Update pool liquidity (restored + fee)
                s.tokenData[tokens[i]].poolLiquidity += amounts[i] + fees[i];
            }
            
            // Update protocol fees
            s.flashLoanConfig.totalFeesCollected += fees[i];
            s.protocolFees += fees[i];
        }
        
        // Emit flash loan completed event
        emit FlashLoanCompleted(
            msg.sender,
            receiver,
            tokens,
            amounts,
            fees
        );
        
        return true;
    }

    /**
     * @notice Get flash loan fee
     * @return Fee in basis points
     */
    function getFlashLoanFee() external view returns (uint256) {
        return s.flashLoanConfig.feeBps;
    }

    /**
     * @notice Calculate flash loan fee for a specific amount
     * @param amount Amount to borrow
     * @return Fee amount
     */
    function calculateFlashLoanFee(uint256 amount) external view returns (uint256) {
        return (amount * s.flashLoanConfig.feeBps) / 10000;
    }

    /**
     * @notice Get flash loan statistics
     * @return totalLoans Total number of flash loans executed
     * @return feesCollected Total fees collected from flash loans
     */
    function getFlashLoanStats() external view returns (
        uint256 totalLoans,
        uint256 feesCollected
    ) {
        return (
            s.flashLoanConfig.totalFlashLoans,
            s.flashLoanConfig.totalFeesCollected
        );
    }

    /**
     * @notice Check if a token is available for flash loans
     * @param token Token address to check
     * @return maxAmount Maximum amount available for flash loan
     */
    function getFlashLoanAvailability(address token) external view returns (uint256 maxAmount) {
        if (!s.supportedTokens[token] || !s.flashLoanConfig.isInitialized) {
            return 0;
        }
        
        // Return available liquidity in the pool
        return s.tokenData[token].poolLiquidity;
    }
}