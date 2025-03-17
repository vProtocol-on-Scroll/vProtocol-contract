// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/Diamond.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/facets/P2pFacet.sol";

import {Constants} from "../contracts/utils/constants/Constant.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract TokenDeployer is Script {
    address DIAMOND_ADDRESS = 0x747605f4E4FB4823d8781b74fB6B0c36eB0A83a3;
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;

    LendingPoolFacet lendingPoolF;
    P2pFacet p2pF;

    function setUp() public {}

    function run() public {
        // vm.createSelectFork("sepolia");
        vm.startBroadcast();

        // Setup supported tokens and price feeds
        address[] memory tokens = new address[](3);
        tokens[0] = address(0x7DB192Afb86B887BA39B7f7d058d21534A88BD3C);
        tokens[1] = address(0x9959f02663B7c7BA0ED578613136F15FD56C67E8);
        tokens[2] = address(0xF9091C04901d2501EA170D266Bed70F04c65d32A);

        p2pF = P2pFacet(payable(DIAMOND_ADDRESS));
        lendingPoolF = LendingPoolFacet(payable(DIAMOND_ADDRESS));

        // lendingPoolF.initializeLendingPool(4000, 8000, 1000, 5000);

        address one = lendingPoolF.deployVault(tokens[0], "Five USDC", "vUSDC");
        address two = lendingPoolF.deployVault(tokens[1], "Five WETH", "vWETH");
        address three = lendingPoolF.deployVault(
            tokens[2],
            "Five WBTC",
            "vWBTC"
        );

        console.log("Vaults deployed: ", one, two, three);

        vm.stopBroadcast();
    }
}
