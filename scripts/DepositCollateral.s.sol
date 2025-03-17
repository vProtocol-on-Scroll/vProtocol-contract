// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/Diamond.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/facets/P2pFacet.sol";

import {Constants} from "../contracts/utils/constants/Constant.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract DepositCollateral is Script {
    address DIAMOND_ADDRESS = 0x78A44F68765209efc9A1527b4e0c897f69D8b86e;
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

        for (uint8 i = 0; i < tokens.length; i++) {
            MockERC20 token = MockERC20(tokens[i]);
            uint256 amount = token.balanceOf(msg.sender);
            token.approve(DIAMOND_ADDRESS, amount / 2);
            lendingPoolF.deposit(tokens[i], amount / 2, true);
        }

        vm.stopBroadcast();
    }
}
