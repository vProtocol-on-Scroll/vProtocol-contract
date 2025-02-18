// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.19;

/**
 * @title YieldOptimizationFacet
 * @author Five Protocol
 *
 * @dev This contract provides functionality for optimizing yield on deposited assets.
 * It allows users to deposit assets and earn yield by providing liquidity to the protocol.
 */

contract YieldOptimizationFacet {
    /**
     * @dev Fallback function that reverts any calls made to undefined functions.
     * This ensures the protocol does not accept or process unsupported function calls.
     *
     * Reverts with "YieldOptimizationFacet: fallback" when an undefined function is called.
     */
    fallback() external {
        revert("YieldOptimizationFacet: fallback");
    }

    receive() external payable {}

}
