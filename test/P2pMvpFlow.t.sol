// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "forge-std/Test.sol";
import "../contracts/Diamond.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LendingPoolFacet} from "../contracts/facets/LendingPoolFacet.sol";
import {P2pFacet} from "../contracts/facets/P2pFacet.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockPriceFeed} from "../contracts/mocks/MockPriceFeed.sol";
import {VTokenVault} from "../contracts/VTokenVault.sol";

import {Event} from "../contracts/model/Event.sol";
import {Request, Status} from "../contracts/model/Protocol.sol";

contract MVPFlow is Test, IDiamondCut {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;

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

    MockERC20 protocolToken;

    address owner;
    address user1;
    address user2;

    // Price constants
    int256 constant USDC_PRICE = 1 * 10 ** 8; // $1.00
    int256 constant WETH_PRICE = 2000 * 10 ** 8; // $2000
    int256 constant WBTC_PRICE = 30000 * 10 ** 8; // $30000\

    address[] tokens;
    address[] priceFeeds;

    address vUsdc;
    address vWeth;
    address vWbtc;

    function setUp() public {
        user1 = mkaddr("user1");
        user2 = mkaddr("user2");
        owner = mkaddr("owner");
        vm.warp(1 days);
        //deploy facets
        switchSigner(owner);

        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(owner, address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();

        lendingPoolF = new LendingPoolFacet();
        p2pF = new P2pFacet();
        protocolToken = new MockERC20("Protocol Token", "PT", 18, 1000e18);

        //upgrade diamond with facets

        //build cut struct
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
                facetAddress: address(lendingPoolF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("LendingPoolFacet")
            })
        );

        cut[3] = (
            FacetCut({
                facetAddress: address(p2pF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("P2pFacet")
            })
        );

        // deploy mock tokens and price feeds
        usdc = new MockERC20("USDC", "USDC", 6, 1000);
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 1000);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8, 1000);

        usdcPriceFeed = new MockPriceFeed(USDC_PRICE, 6);
        wethPriceFeed = new MockPriceFeed(WETH_PRICE, 18);
        wbtcPriceFeed = new MockPriceFeed(WBTC_PRICE, 8);

        // Setup supported tokens and price feeds
        tokens.push(address(usdc));
        tokens.push(address(weth));
        tokens.push(address(wbtc));

        priceFeeds.push(address(usdcPriceFeed));
        priceFeeds.push(address(wethPriceFeed));
        priceFeeds.push(address(wbtcPriceFeed));

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        diamond.initialize(tokens, priceFeeds, address(protocolToken));

        LendingPoolFacet _lF = LendingPoolFacet(payable(diamond));

        for (uint256 i = 0; i < tokens.length; i++) {
            _lF.addSupportedToken(tokens[i], 8000, 8500, 10000, true);
        }

        _lF.initializeLendingPool(4000, 8000, 1000, 5000);

        vUsdc = _lF.deployVault(tokens[0], "Five USDC", "vUSDC");
        vWeth = _lF.deployVault(tokens[1], "Five WETH", "vWETH");
        vWbtc = _lF.deployVault(tokens[2], "Five WBTC", "vWBTC");

        _fundAccounts();

        //call a function
        // DiamondLoupeFacet(address(diamond)).facetAddresses();
    }

    function testDepositCollateral() public {
        switchSigner(user1);
        LendingPoolFacet pool = LendingPoolFacet(payable(diamond));

        usdc.approve(address(diamond), 500e6);
        pool.deposit(address(usdc), 500e6, true);

        assertEq(usdc.balanceOf(address(diamond)), 500e6);
    }

    function testWithdrawCollateral() public {
        // _depositCollateral(user1);
        switchSigner(user1);
        LendingPoolFacet pool = LendingPoolFacet(payable(diamond));
        usdc.approve(address(pool), 200e6);
        pool.deposit(address(usdc), 200e6, false);

        VTokenVault(payable(vUsdc)).approve(address(diamond), 200e6);

        vm.expectEmit(true, true, true, false);
        emit IERC20.Transfer(address(diamond), user1, 100e6);
        pool.withdraw(address(usdc), 100e6, false);
        assertEq(usdc.balanceOf(address(diamond)), 100e6);
    }

    function testCreatePeerPostion() public {
        _depositCollateral(user1);
        P2pFacet p2p = P2pFacet(payable(diamond));

        address[] memory _tokens = new address[](0);
        uint256[] memory _amounts = new uint256[](0);
        (uint96 _id, bool _matched) = p2p.createAndMatchLendingRequest(
            100e18,
            1000,
            block.timestamp + 30 days,
            block.timestamp + 10 days,
            address(weth),
            _tokens,
            _amounts,
            true
        );

        assertFalse(_matched);

        switchSigner(user2);
        vm.expectRevert("Insufficient collateral");
        p2p.createAndMatchLendingRequest(
            100e18,
            1000,
            block.timestamp + 30 days,
            block.timestamp + 10 days,
            address(weth),
            _tokens,
            _amounts,
            true
        );
    }

    function testServiceRequest() public {
        _depositCollateral(user1);
        _createPositionPeer(user1);
        switchSigner(user2);
        weth.approve(address(diamond), 100e18);
        P2pFacet p2p = P2pFacet(payable(diamond));

        uint256 _balanceBefore = weth.balanceOf(user1);
        p2p.serviceRequest(1, address(weth));
        uint256 _balanceAfter = weth.balanceOf(user1);
        assertEq(_balanceAfter, _balanceBefore + 100e18);
    }

    function testCreateListingWithMatching() public {
        _depositCollateral(user1);
        _createPositionPeer(user1);
        switchSigner(user2);

        weth.approve(address(diamond), 100e18);
        P2pFacet p2p = P2pFacet(payable(diamond));
        (uint96 _id, uint96[] memory _matches) = p2p
            .createLoanListingWithMatching(
                100e18,
                1e18,
                100e18,
                block.timestamp + 30 days,
                1000,
                address(weth),
                true
            );

        Request memory req = p2p.getRequest(1);
        assertEq(uint8(req.status), uint8(Status.SERVICED));
    }

    function testCreateRequestWithMatching() public {
        switchSigner(user2);
        weth.approve(address(diamond), 100e18);
        P2pFacet p2p = P2pFacet(payable(diamond));
        (uint96 _id, uint96[] memory _matches) = p2p
            .createLoanListingWithMatching(
                100e18,
                1e18,
                100e18,
                block.timestamp + 30 days,
                1000,
                address(weth),
                true
            );

        _depositCollateral(user1);
        _createPositionPeer(user1);

        Request memory req = p2p.getRequest(1);
        assertEq(uint8(req.status), uint8(Status.SERVICED));
    }

    function testRepayLoan() public {
        _depositCollateral(user1);
        _createPositionPeer(user1);
        _serviceRequest(user2, 1);

        switchSigner(user1);
        P2pFacet p2p = P2pFacet(payable(diamond));

        Request memory reqBefore = p2p.getRequest(1);

        MockERC20 token = MockERC20(reqBefore.loanRequestAddr);
        token.approve(address(diamond), reqBefore.totalRepayment);

        p2p.repayLoan(1, reqBefore.totalRepayment);

        Request memory reqAfter = p2p.getRequest(1);

        assertEq(uint8(reqAfter.status), uint8(Status.CLOSED));
    }

    function testRequestLoanFromListingFailsWithoutEnoughCollateral() public {
        P2pFacet p2p = P2pFacet(payable(diamond));
        LendingPoolFacet lP = LendingPoolFacet(payable(diamond));
        _depositCollateral(user1);

        weth.approve(address(diamond), 100e18);
        p2p.createLoanListingWithMatching(
            100e18,
            1,
            100e18,
            block.timestamp + 100 days,
            1000,
            address(weth),
            true
        );

        switchSigner(user2);

        vm.expectRevert("No Active collateral");
        p2p.requestLoanFromListing(1, 50e18);

        weth.approve(address(diamond), 10e18);
        lP.deposit(address(weth), 10e18, true);
        vm.expectRevert("Insufficient collateral");
        p2p.requestLoanFromListing(1, 9e18);
    }

    function testRequestLoanFromListingPassWithEnoughCollateral() public {
        P2pFacet p2p = P2pFacet(payable(diamond));
        LendingPoolFacet lP = LendingPoolFacet(payable(diamond));
        _depositCollateral(user1);

        weth.approve(address(diamond), 100e18);
        p2p.createLoanListingWithMatching(
            100e18,
            1,
            100e18,
            block.timestamp + 100 days,
            1000,
            address(weth),
            true
        );

        switchSigner(user2);

        weth.approve(address(diamond), 1000e18);
        lP.deposit(address(weth), 1000e18, true);

        vm.expectEmit(true, true, true, true);
        emit Event.RequestServiced(1, user1, user2, 100e18);
        p2p.requestLoanFromListing(1, 100e18);
    }

    function _serviceRequest(address user, uint96 _id) internal {
        switchSigner(user);
        P2pFacet p2p = P2pFacet(payable(diamond));
        Request memory req = p2p.getRequest(_id);
        MockERC20(req.loanRequestAddr).approve(address(diamond), req.amount);
        p2p.serviceRequest(_id, address(weth));
    }

    function _depositCollateral(address user) internal {
        switchSigner(user);
        LendingPoolFacet pool = LendingPoolFacet(payable(diamond));

        for (uint8 i = 0; i < tokens.length; i++) {
            MockERC20 token = MockERC20(tokens[i]);
            uint256 amount = token.balanceOf(user);
            token.approve(address(diamond), amount / 2);
            pool.deposit(tokens[i], amount / 2, true);
        }
    }

    function _fundAccounts() internal {
        for (uint8 i = 0; i < tokens.length; i++) {
            MockERC20(tokens[i]).mint(user1, 1000e18);
            MockERC20(tokens[i]).mint(user2, 1000e18);
        }
    }

    function _createPositionPeer(address user) internal {
        switchSigner(user);
        P2pFacet p2p = P2pFacet(payable(diamond));

        address[] memory _tokens = new address[](0);
        uint256[] memory _amounts = new uint256[](0);
        (uint96 _id, bool _matched) = p2p.createAndMatchLendingRequest(
            100e18,
            1000,
            block.timestamp + 30 days,
            block.timestamp + 10 days,
            address(weth),
            _tokens,
            _amounts,
            true
        );
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

    function switchSigner(address _newSigner) public {
        address foundrySigner = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
        if (msg.sender == foundrySigner) {
            vm.startPrank(_newSigner);
        } else {
            vm.stopPrank();
            vm.startPrank(_newSigner);
        }
    }

    function mkaddr(string memory name) public returns (address) {
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(name))))
        );
        vm.label(addr, name);
        return addr;
    }
}
