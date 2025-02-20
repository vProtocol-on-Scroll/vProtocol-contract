// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "forge-std/Test.sol";
import "../contracts/Diamond.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/utils/validators/Error.sol";
import {CorePoolConfigFacet} from  "../contracts/facets/CorePoolConfigFacet.sol";
import {CoreFacet} from "../contracts/facets/CoreFacet.sol";


contract CoreVaultTest is Test, IDiamondCut {


    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    CorePoolConfigFacet poolConfigF;
    CoreFacet coreF;

    address[] tokens;
    address[] priceFeeds;


    address _user1 = makeAddr("user 1");
    address _user2 = makeAddr("user 2");
    address _user3 = makeAddr("user 3");


    function setUp() public {

        switchSigner(_user1);

        dCutFacet = new DiamondCutFacet();

        diamond = new Diamond(_user1, address(dCutFacet));

        dLoupe = new DiamondLoupeFacet();

        ownerF = new OwnershipFacet();

        poolConfigF = new CorePoolConfigFacet();

        coreF = new CoreFacet();


        FacetCut[] memory cut = new FacetCut[](4);

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
                facetAddress: address(poolConfigF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("CorePoolConfigFacet")
            })

        );

           cut[3] = (
            FacetCut({
                facetAddress: address(coreF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("CoreFacet")
            })

        );


        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        DiamondLoupeFacet(address(diamond)).facetAddresses();




        tokens.push(address(1));
        priceFeeds.push(0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41);


        diamond.initialize(tokens, priceFeeds);

        poolConfigF = CorePoolConfigFacet(address(diamond));   
        coreF = CoreFacet(address(diamond));

        vm.deal(_user1, 20 ether);
        vm.deal(_user2, 50 ether);

}
    

 function testCreateVault_Success() public {
    switchSigner(_user1);
     vm.deal(_user1, 20 ether);
    // When creating a native token vault, send ETH with the call
    poolConfigF.createVault{value: 1 ether}(
        IERC20(address(1)), // Use address(1) for native token
        "Wrapped ETH Vault",
        "WETH-VAULT",
        8500,
        8500,
        1 ether // Initial deposit
    );

    VaultConfig memory _foundVault = poolConfigF.getVaultConfig(address(1));
    assert(_foundVault.ltvBps == 8500);
}


    function testCreateVault_FailsOnHighLTV() public {
        uint256 invalidLtv = 11000; // 110%
        vm.expectRevert("LTV > 100%");
        poolConfigF.createVault{value: 1 ether}(
        IERC20(address(1)), // Use address(1) for native token
        "Wrapped ETH Vault",
        "WETH-VAULT",
       invalidLtv,
        8500,
        1 ether // Initial deposit
    );   
     }


    function testGetVaultConfig_Success() public {
        switchSigner(_user1);  
    
       poolConfigF.createVault{value: 1 ether}(
        IERC20(address(1)), // Use address(1) for native token
        "Wrapped ETH Vault",
        "WETH-VAULT",
        8500,
        8500,
        1 ether // Initial deposit
    );

    VaultConfig memory _foundVault = poolConfigF.getVaultConfig(address(1));
        assertEq(_foundVault.ltvBps, 8500);
        assertEq(_foundVault.liquidationThresholdBps, 8500);
    }


     function testSetFeeRecipient_Success() public {
        switchSigner(_user1);  


        poolConfigF.setFeeRecipient(_user2);

        address storedRecipient = poolConfigF.getProtocolFeeRecipient();
        assertEq(storedRecipient, _user2);
    }


       function testSetFees_Success() public {
        switchSigner(_user1);  
        uint256 newFee = 500; // 5%
        poolConfigF.setFees(newFee);

        uint256 storedFee = poolConfigF.getProtocolFeeBps();
        assertEq(storedFee, newFee);
    }


      function testUpdateVaultConfig_Success() public {
        switchSigner(_user1);  
        poolConfigF.createVault{value: 1 ether}(
        IERC20(address(1)), // Use address(1) for native token
        "Wrapped ETH Vault",
        "WETH-VAULT",
        8500,
        8500,
        1 ether // Initial deposit
    );
        address vault = poolConfigF.getVault(address(1));

        uint256 newLtv = 7500;  // 75%
        uint256 newLiquidationThreshold = 8000; // 80%
        poolConfigF.updateVaultConfig(vault, newLtv, newLiquidationThreshold);

          VaultConfig memory _foundVault = poolConfigF.getVaultConfig(address(1));
        assertEq(_foundVault.ltvBps, newLtv);
        assertEq(_foundVault.liquidationThresholdBps, newLiquidationThreshold);
    }



    function testSupplyETH() public {
    uint256 supplyAmount = 1 ether;
    switchSigner(_user1);
     vm.deal(_user1, 20 ether);
    vm.deal(_user2, 50 ether);

    // When creating a native token vault, send ETH with the call
    poolConfigF.createVault{value: 1 ether}(
        IERC20(address(1)), // Use address(1) for native token
        "Wrapped ETH Vault",
        "WETH-VAULT",
        8500,
        8500,
        1 ether // Initial deposit
    );

    VaultConfig memory _foundVault = poolConfigF.getVaultConfig(address(1));
    assert(_foundVault.ltvBps == 8500);

        
        switchSigner(_user2);

    
        uint shares = coreF.depositCollateral(IERC20(address(1)),_user3, supplyAmount);
        
        assert(shares == supplyAmount);
    }

    // function testSupplyERC20() public {
    //     uint256 supplyAmount = 10 ether;
        
    //     vm.startPrank(user1);
    //     mockToken.approve(address(diamond), supplyAmount);
        
    //     // Expect event emission
    //     vm.expectEmit(true, true, false, true);
    //     emit AssetSupplied(user1, address(mockToken), supplyAmount, supplyAmount); // Assuming 1:1 share ratio initially
        
    //     // Supply tokens
    //     (bool success, bytes memory data) = address(diamond).call(
    //         abi.encodeWithSignature(
    //             "supplyAsset(address,address,uint256)",
    //             address(mockToken),
    //             user1,
    //             supplyAmount
    //         )
    //     );
    //     require(success, "Supply failed");
        
    //     // Verify state changes
    //     (uint256 depositedAssets,) = diamond.getUserPosition(user1, address(erc20Vault));
    //     assertEq(depositedAssets, supplyAmount, "Incorrect deposited amount");
        
    //     vm.stopPrank();
    // }
    


    function mkaddr(string memory name) public returns (address) {

        address addr = address(

            uint160(uint256(keccak256(abi.encodePacked(name))))

        );

        vm.label(addr, name);

        return addr;

    }



    function switchSigner(address _newSigner) public {

        address foundrySigner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

        if (msg.sender == foundrySigner) {

            vm.startPrank(_newSigner);

        } else {

            vm.stopPrank();

            vm.startPrank(_newSigner);

        }

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