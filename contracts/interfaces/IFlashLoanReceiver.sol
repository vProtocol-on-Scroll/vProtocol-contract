// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFlashLoanReceiver
 * @author Five Protocol
 *
 * @dev Interface for contracts that want to receive flash loans.
 * Borrowers must implement this interface to receive flash loans.
 */
interface IFlashLoanReceiver {
    /**
     * @notice Called by the lending pool during a flash loan
     * @param assets Addresses of the assets being flash borrowed
     * @param amounts Amounts of the assets being flash borrowed
     * @param premiums Fees for each asset being flash borrowed
     * @param initiator Address initiating the flash loan
     * @param params Arbitrary bytes data passed by the flash loan initiator
     * @return success Whether the operation succeeded
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool success);
}