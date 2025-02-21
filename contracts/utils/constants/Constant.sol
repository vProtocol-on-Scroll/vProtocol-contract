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
    address constant WETH = 0x5300000000000000000000000000000000000004;
    address constant USDC = 0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD;
    uint8 constant CONSISTENCY_LEVEL_FINALIZED = 15;
    uint256 constant GAS_LIMIT = 400_000;
    uint256 constant PRICE_STALE_THRESHOLD = 24 * 3600; // 24 hours
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant LOYALTY_MULTIPLIER_PRECISION = 10000;
    uint256 public constant MIN_LOCK_PERIOD = 7 days;
    uint256 public constant MAX_LOCK_PERIOD = 365 days;
    uint256 public constant EPOCH_DURATION = 1 days;
    address constant SWAP_ROUTER = 0xfB5f26851E03449A0403Ca945eBB4201415fd1fc;
    uint256 constant RAY = 10**27; // 1 in ray format
    uint256 constant SECONDS_PER_YEAR = 365 days;
    uint256 constant MAX_BORROW_RATE = 5000; // 50% maximum borrow rate
    uint256 constant HEALTH_FACTOR_THRESHOLD = 10000; // 100% (1.0)
    uint256 constant LIQUIDATION_CLOSE_FACTOR_DEFAULT = 5000; // 50%
    uint256 constant MAX_RESERVE_FACTOR = 5000; // 50%
    uint256 constant MAX_LTV = 8000; // 80%
    uint256 constant MIN_LIQUIDATION_THRESHOLD = 8250; // 82.5%
}
