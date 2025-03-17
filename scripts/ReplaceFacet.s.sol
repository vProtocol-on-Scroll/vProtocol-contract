// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Script, console} from "forge-std/Script.sol";

import "../contracts/upgradeInitializers/DiamondInit.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
// import "../contracts/facets/P2pFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/Diamond.sol";

contract ReplaceFacet is Script, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

    DiamondInit diamondInit;

    // faceted contracts
    // P2pFacet p2pF;
    LendingPoolFacet lendingPoolF;

    address constant DIAMOND_ADDRESS =
        0x78A44F68765209efc9A1527b4e0c897f69D8b86e;
    address constant DIAMOND_INIT_ADDRESS =
        0xE5c7e807b531db40735d7a1217b9F835D9644E79;

    // address constant GETTERS_ADDRESS =
    //     0xe0948A1AD876B7DE68a9eaa72A9BeB2dCAa70e1E;
    // address constant P2P_ADDRESS = 0x9344dFC688cB168ce1cff4776433D57372296138;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        //deploy facets
        diamond = Diamond(payable(DIAMOND_ADDRESS));

        // p2pF = new P2pFacet();
        lendingPoolF = new LendingPoolFacet();

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](1);

        // cut[0] = (
        //     FacetCut({
        //         facetAddress: address(p2pF),
        //         action: FacetCutAction.Replace,
        //         functionSelectors: generateSelectors("P2pFacet")
        //     })
        // );

        cut[0] = (
            FacetCut({
                facetAddress: address(lendingPoolF),
                action: FacetCutAction.Replace,
                functionSelectors: generateSelectors("LendingPoolFacet")
            })
        );

        bytes memory _calldata = abi.encodeWithSelector(
            DiamondInit.init.selector
        );
        //upgrade diamond
        IDiamondCut(DIAMOND_ADDRESS).diamondCut(
            cut,
            DIAMOND_INIT_ADDRESS,
            _calldata
        );

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
