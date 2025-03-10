// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/upgradeInitializers/DiamondInit.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/facets/AutoRebalancingFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/facets/P2pFacet.sol";
import "../contracts/facets/PauseableFacet.sol";
import "../contracts/facets/RebalancingStrategyFacet.sol";
import "../contracts/facets/RewardDistributionFacet.sol";
import "../contracts/facets/YieldOptimizationFacet.sol";
import "../contracts/Diamond.sol";

import {Constants} from "../contracts/utils/constants/Constant.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPriceFeed} from "../contracts/mocks/MockPriceFeed.sol";

contract DiamondDeployer is Script, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

    DiamondInit diamondInit;

    // faceted contracts
    AutoRebalancingFacet autoRebalancingF;
    LendingPoolFacet lendingPoolF;
    P2pFacet p2pF;
    PauseableFacet pauseableF;
    RebalancingStrategyFacet rebalancingStrategyF;
    RewardDistributionFacet rewardDistributionF;
    YieldOptimizationFacet yieldOptimizationF;

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
        vm.startBroadcast();
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(msg.sender, address(dCutFacet));

        //deploy diamond init
        diamondInit = new DiamondInit();

        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();

        // deploy faceted contracts
        autoRebalancingF = new AutoRebalancingFacet();
        lendingPoolF = new LendingPoolFacet();
        p2pF = new P2pFacet();
        pauseableF = new PauseableFacet();
        rebalancingStrategyF = new RebalancingStrategyFacet();
        // rewardDistributionF = new RewardDistributionFacet();
        yieldOptimizationF = new YieldOptimizationFacet();

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](8);

        cut[0] = (
            FacetCut({
                facetAddress: address(dLoupe),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
                facetAddress: address(ownerF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        cut[2] = (
            FacetCut({
                facetAddress: address(autoRebalancingF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("AutoRebalancingFacet")
            })
        );

        cut[3] = (
            FacetCut({
                facetAddress: address(lendingPoolF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("LendingPoolFacet")
            })
        );

        cut[4] = (
            FacetCut({
                facetAddress: address(p2pF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("P2pFacet")
            })
        );

        cut[5] = (
            FacetCut({
                facetAddress: address(pauseableF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("PauseableFacet")
            })
        );

        cut[6] = (
            FacetCut({
                facetAddress: address(rebalancingStrategyF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("RebalancingStrategyFacet")
            })
        );

        // cut[7] = (
        //     FacetCut({
        //         facetAddress: address(rewardDistributionF),
        //         action: FacetCutAction.Add,
        //         functionSelectors: generateSelectors("RewardDistributionFacet")
        //     })
        // );

        cut[7] = (
            FacetCut({
                facetAddress: address(yieldOptimizationF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("YieldOptimizationFacet")
            })
        );

        bytes memory _calldata = abi.encodeWithSelector(
            DiamondInit.init.selector
        );
        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(
            cut,
            address(diamondInit),
            _calldata
        );

        //call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();

        // Deploy mock tokens
        // usdc = new MockERC20("USD Coin", "USDC", 6, 1000);
        // weth = new MockERC20("Wrapped ETH", "WETH", 18, 1000);
        // wbtc = new MockERC20("Wrapped BTC", "WBTC", 8, 1000);

        // Deploy mock price feeds
        // usdcPriceFeed = new MockPriceFeed(USDC_PRICE, 8);
        // wethPriceFeed = new MockPriceFeed(WETH_PRICE, 8);
        // wbtcPriceFeed = new MockPriceFeed(WBTC_PRICE, 8);

        // Setup supported tokens and price feeds
        address[] memory tokens = new address[](4);
        // tokens[0] = address(usdc);
        // tokens[1] = address(weth);
        // tokens[2] = address(wbtc);
        tokens[0] = address(0x7DB192Afb86B887BA39B7f7d058d21534A88BD3C);
        tokens[1] = address(0x9959f02663B7c7BA0ED578613136F15FD56C67E8);
        tokens[2] = address(0xF9091C04901d2501EA170D266Bed70F04c65d32A);
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

        // Initialize diamond with tokens and price feeds
        diamond.initialize(tokens, priceFeeds, address(diamond));

        for (uint256 i = 0; i < tokens.length - 1; i++) {
            LendingPoolFacet(payable(diamond)).addSupportedToken(
                tokens[i],
                8000,
                8500,
                10000,
                true
            );
        }

        LendingPoolFacet lpF = LendingPoolFacet(payable(diamond));
        address one = lpF.deployVault(tokens[0], "Five USDC", "vUSDC");
        address two = lpF.deployVault(tokens[1], "Five WETH", "vWETH");
        address three = lpF.deployVault(tokens[2], "Five WBTC", "vWBTC");
        // Initialize reward distribution
        // MockERC20 rewardToken = new MockERC20("Reward Token", "vREWARD", 18, 0);

        // RewardDistributionFacet(address(diamond)).initializeRewardDistribution(
        //     address(rewardToken) // TODO: change to reward token
        // );
        lpF.initializeLendingPool(2000, 8000, 1000, 3000);

        console.log("Diamond deployed at: ", address(diamond));
        console.log("DiamondInit deployed at: ", address(diamondInit));
        console.log("DiamondCutFacet deployed at: ", address(dCutFacet));
        console.log("DiamondLoupeFacet deployed at: ", address(dLoupe));
        console.log("OwnershipFacet deployed at: ", address(ownerF));
        console.log(
            "AutoRebalancingFacet deployed at: ",
            address(autoRebalancingF)
        );
        console.log("LendingPoolFacet deployed at: ", address(lendingPoolF));
        console.log("P2pFacet deployed at: ", address(p2pF));
        console.log("PauseableFacet deployed at: ", address(pauseableF));
        console.log(
            "RebalancingStrategyFacet deployed at: ",
            address(rebalancingStrategyF)
        );
        // console.log("RewardDistributionFacet deployed at: ", address(rewardDistributionF));
        console.log(
            "YieldOptimizationFacet deployed at: ",
            address(yieldOptimizationF)
        );

        console.log("USDC deployed at: ", address(usdc));
        console.log("WETH deployed at: ", address(weth));
        console.log("WBTC deployed at: ", address(wbtc));
        vm.stopBroadcast();
    }

    function generateSelectors(
        string memory _facetName
    ) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "scripts/genSelectors.js";
        cmd[2] = _facetName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {}
}
