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

    function userCmd(
        uint16 callpath,
        bytes calldata cmd
    ) external payable returns (bytes memory);
}

interface ICrocImpact {
    // 0xc2c301759B5e0C385a38e678014868A33E2F3ae3
    function calcImpact(
        address base,
        address quote,
        uint256 poolIdx,
        bool isBuy,
        bool inBaseQty,
        uint128 qty,
        uint16 tip,
        uint128 limitPrice
    )
        external
        view
        returns (int128 baseFlow, int128 quoteFlow, uint128 finalPrice);
}

interface ICrocQuery {
    // 0x62223e90605845Cf5CC6DAE6E0de4CDA130d6DDf
    function queryPrice(
        address base,
        address quote,
        uint256 poolIdx
    ) external view returns (uint128);
}
