// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Holds all the constant for our protocol
library Constants {
    uint256 constant NEW_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;
    uint256 constant LIQUIDATION_THRESHOLD = 80;
    uint256 constant MIN_HEALTH_FACTOR = 1;
    uint256 constant COLLATERALIZATION_RATIO = 80;
    address constant NATIVE_TOKEN = address(1);
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    uint8 constant CONSISTENCY_LEVEL_FINALIZED = 15;
    uint256 constant GAS_LIMIT = 400_000;
    uint256 constant PRICE_STALE_THRESHOLD = 3 * 3600; // 3 hours
}
