// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/Diamond.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/facets/P2pFacet.sol";

import {Constants} from "../contracts/utils/constants/Constant.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPriceFeed} from "../contracts/mocks/MockPriceFeed.sol";

contract TokenDeployer is Script {
    address DIAMOND_ADDRESS = 0x729D65dE0FD977e49CE4eaF39A62d628777a12dd;
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;

    LendingPoolFacet lendingPoolF;
    P2pFacet p2pF;

    // Mock tokens
    MockERC20 usdc;
    MockERC20 weth;
    MockERC20 wbtc;

    // Mock price feeds
    MockPriceFeed usdcPriceFeed;
    MockPriceFeed wethPriceFeed;
    MockPriceFeed wbtcPriceFeed;

    // Price constants
    int256 constant USDC_PRICE = 1 * 10 ** 8; // $1.00
    int256 constant WETH_PRICE = 2000 * 10 ** 8; // $2000
    int256 constant WBTC_PRICE = 30000 * 10 ** 8; // $30000

    function setUp() public {}

    function run() public {
        // vm.createSelectFork("sepolia");
        vm.startBroadcast();

        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6, 1000);
        weth = new MockERC20("Wrapped ETH", "WETH", 18, 1000);
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8, 1000);

        // Deploy mock price feeds
        // usdcPriceFeed = new MockPriceFeed(USDC_PRICE, 8);
        // wethPriceFeed = new MockPriceFeed(WETH_PRICE, 8);
        // wbtcPriceFeed = new MockPriceFeed(WBTC_PRICE, 8);

        // Setup supported tokens and price feeds
        address[] memory tokens = new address[](4);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);
        tokens[2] = address(wbtc);
        tokens[3] = Constants.NATIVE_TOKEN;

        address[] memory priceFeeds = new address[](4);
        // priceFeeds[0] = address(usdcPriceFeed);
        // priceFeeds[1] = address(wethPriceFeed);
        // priceFeeds[2] = address(wbtcPriceFeed);
        // priceFeeds[3] = address(wethPriceFeed);
        priceFeeds[0] = 0xFadA8b0737D4A3AE7118918B7E69E689034c0127;
        priceFeeds[1] = 0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41;
        priceFeeds[2] = 0x87dce67002e66C17BC0d723Fe20D736b80CAaFda;
        priceFeeds[3] = 0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41;

        p2pF = P2pFacet(payable(DIAMOND_ADDRESS));

        address[] memory tokenToRemove = new address[](4);
        tokenToRemove[0] = 0x191825122Cb4150cf91Eb64cFE38025c27547eB6;
        tokenToRemove[1] = 0xb4a583c3Cdf2b76dFE4A848aFce4AA961756c05A;
        tokenToRemove[2] = 0x7123Dd26c754ea150Af6e8F79a47F35f96D9d8ef;
        tokenToRemove[3] = Constants.NATIVE_TOKEN;

        // p2pF.removeCollateralTokens(tokenToRemove);

        p2pF.addCollateralTokens(tokens, priceFeeds);

        for (uint256 i = 0; i < tokens.length - 1; i++) {
            LendingPoolFacet(payable(DIAMOND_ADDRESS)).addSupportedToken(
                tokens[i],
                8000,
                8500,
                10000,
                true
            );
        }

        console.log("USDC deployed at: ", address(usdc));
        console.log("WETH deployed at: ", address(weth));
        console.log("WBTC deployed at: ", address(wbtc));
        vm.stopBroadcast();
    }
}
