// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICrocSwapDex {
    function swap(
        address base,
        address quote,
        uint256 poolIdx,
        bool isBuy,
        bool inBaseQty,
        uint128 qty,
        uint16 tip,
        uint128 limitPrice,
        uint128 minOut,
        uint8 reserveFlags
    ) external payable returns (int128 baseQuote, int128 quoteFlow);
}
