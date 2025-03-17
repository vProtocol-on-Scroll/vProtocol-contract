// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/upgradeInitializers/DiamondInit.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/facets/GettersFacet.sol";
import "../contracts/facets/P2pFacet.sol";
import "../contracts/Diamond.sol";

contract AddFacet is Script, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

    DiamondInit diamondInit;

    // faceted contracts
    GettersFacet gettersF;
    P2pFacet p2pF;

    // address constant DIAMOND_ADDRESS =
    //     0x78A44F68765209efc9A1527b4e0c897f69D8b86e;
    // address constant DIAMOND_INIT_ADDRESS =
    //     0xE5c7e807b531db40735d7a1217b9F835D9644E79;

    address constant DIAMOND_ADDRESS =
        0x3cf9441a4EdbB04E27cb5Ea0b55b5AE0B6B0ACD5;
    address constant DIAMOND_INIT_ADDRESS =
        0x14063E2a3dd5924C922Ca31CE174c3ba41965e30;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        //deploy facets
        diamond = Diamond(payable(DIAMOND_ADDRESS));

        gettersF = new GettersFacet();
        p2pF = new P2pFacet();

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](1);

        // bytes4[] memory gFs = new bytes4[](5);
        // gFs[0] = 0x0251cfa1;
        // gFs[1] = 0xb87147df;
        // gFs[2] = 0x2a7c716c;
        // gFs[3] = 0x84b7249b;
        // gFs[4] = 0x92a576e6;

        // bytes4[] memory p2pFs = new bytes4[](1);
        // p2pFs[0] = 0x7ada5403;

        cut[0] = (
            FacetCut({
                facetAddress: address(gettersF),
                action: FacetCutAction.Add,
                // functionSelectors: gFs
                functionSelectors: generateSelectors("GettersFacet")
            })
        );

        // cut[1] = (
        //     FacetCut({
        //         facetAddress: address(p2pF),
        //         action: FacetCutAction.Add,
        //         functionSelectors: p2pFs
        //     })
        // );

        bytes memory _calldata = abi.encodeWithSelector(
            DiamondInit.init.selector
        );
        //upgrade diamond
        IDiamondCut(DIAMOND_ADDRESS).diamondCut(
            cut,
            DIAMOND_INIT_ADDRESS,
            _calldata
        );

        console.log("Getters Facet", address(gettersF));
        // console.log("P2p Facet", address(p2pF));

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
