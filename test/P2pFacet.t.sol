// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/Diamond.sol";
import "../contracts/upgradeInitializers/DiamondInit.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/facets/P2pFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/libraries/LibAppStorage.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockPriceFeed.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Use the mock contracts from the previous test
contract P2pFacetTest is Test {
    // Diamond contracts
    Diamond diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    OwnershipFacet ownershipFacet;
    P2pFacet p2pFacet;
    DiamondInit diamondInit;

    // Mock contracts (same as in LendingPoolFacetTest)
    MockERC20 mockUSDC;
    MockERC20 mockWETH;
    MockPriceFeed mockUSDCPriceFeed;
    MockPriceFeed mockWETHPriceFeed;

    // Test addresses
    address owner = address(0x1);
    address borrower = address(0x2);
    address lender = address(0x3);
    address liquidator = address(0x4);

    // Constants
    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 18; // 10000 tokens with 18 decimals

    function setUp() public {
        // Setup accounts
        vm.startPrank(owner);

        // Deploy mock tokens
        mockUSDC = new MockERC20("USDC", "USDC", 18, INITIAL_BALANCE);
        mockWETH = new MockERC20("WETH", "WETH", 18, INITIAL_BALANCE);

        // Deploy mock price feeds
        mockUSDCPriceFeed = new MockPriceFeed(1 * 10 ** 8, 8); // $1.00 USD with 8 decimals
        mockWETHPriceFeed = new MockPriceFeed(2000 * 10 ** 8, 8); // $2000.00 USD with 8 decimals

        // Setup diamond
        diamondCutFacet = new DiamondCutFacet();
        diamond = new Diamond(owner, address(diamondCutFacet));

        // Build diamond cut for facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](3);

        // Add DiamondLoupeFacet
        diamondLoupeFacet = new DiamondLoupeFacet();
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupeFacet")
        });

        // Add OwnershipFacet
        ownershipFacet = new OwnershipFacet();
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateSelectors("OwnershipFacet")
        });

        // Add P2pFacet
        p2pFacet = new P2pFacet();
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(p2pFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateSelectors("P2pFacet")
        });

        // Initialize diamond
        diamondInit = new DiamondInit();
        bytes memory initData = abi.encodeWithSelector(
            DiamondInit.init.selector
        );

        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(diamondInit),
            initData
        );

        // Setup protocol tokens and price feeds
        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](2);

        tokens[0] = address(mockUSDC);
        tokens[1] = address(mockWETH);

        priceFeeds[0] = address(mockUSDCPriceFeed);
        priceFeeds[1] = address(mockWETHPriceFeed);

        // Initialize the Diamond with tokens
        Diamond(payable(address(diamond))).initialize(
            tokens,
            priceFeeds,
            address(2)
        );

        // Give tokens to test users
        mockUSDC.mint(borrower, INITIAL_BALANCE);
        mockUSDC.mint(lender, INITIAL_BALANCE);
        mockWETH.mint(borrower, INITIAL_BALANCE);
        mockWETH.mint(lender, INITIAL_BALANCE);
        mockUSDC.mint(liquidator, INITIAL_BALANCE);
        mockWETH.mint(liquidator, INITIAL_BALANCE);

        vm.warp(block.timestamp + 1000000000000000000);

        vm.stopPrank();
    }

    function testCreateLoanListing() public {
        // Lender creates a loan listing
        vm.startPrank(lender);
        mockUSDC.approve(address(diamond), 1000 * 10 ** 18);

        (uint96 listingId, uint96[] memory matchedRequests) = P2pFacet(
            payable(address(diamond))
        ).createLoanListingWithMatching(
                1000 * 10 ** 18, // Amount
                100 * 10 ** 18, // Min amount
                500 * 10 ** 18, // Max amount
                block.timestamp + 30 days, // Return duration
                300, // 3% interest
                address(mockUSDC),
                false // No auto-matching
            );
        vm.stopPrank();

        // Verify listing creation
        assertEq(listingId, 1, "First listing should have ID 1");
        assertEq(matchedRequests.length, 0, "No matches should be found yet");

        // Check listing is stored correctly
        LoanListing memory listing = P2pFacet(payable(address(diamond)))
            .getLoanListing(listingId);

        assertEq(listing.author, lender, "Author should be the lender");
        assertEq(
            listing.tokenAddress,
            address(mockUSDC),
            "Token should be USDC"
        );
        assertEq(listing.amount, 1000 * 10 ** 18, "Amount should match");
        assertTrue(
            listing.listingStatus == ListingStatus.OPEN,
            "Listing should be open"
        );
    }

    function testCreateLendingRequest() public {
        // Borrower creates a lending request with collateral
        vm.startPrank(borrower);
        mockWETH.approve(address(diamond), 1 * 10 ** 18);

        address[] memory collateralTokens = new address[](1);
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralTokens[0] = address(mockWETH);
        collateralAmounts[0] = 1 * 10 ** 18; // 1 WETH worth $2000

        (uint96 requestId, bool matched) = P2pFacet(payable(address(diamond)))
            .createAndMatchLendingRequest(
                1000 * 10 ** 18, // Borrow 1000 USDC
                500, // 5% interest
                block.timestamp + 30 days, // Return duration
                block.timestamp + 7 days, // Expiration
                address(mockUSDC), // Borrow USDC
                collateralTokens,
                collateralAmounts,
                false // Don't use existing collateral
            );
        vm.stopPrank();

        // Verify request creation
        assertEq(requestId, 1, "First request should have ID 1");
        assertFalse(matched, "Request shouldn't be matched yet");

        // Check request details
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            requestId
        );
        assertEq(request.author, borrower, "Author should be the borrower");
        assertEq(request.amount, 1000 * 10 ** 18, "Amount should match");
        assertEq(
            request.loanRequestAddr,
            address(mockUSDC),
            "Token should be USDC"
        );
        assertEq(
            uint8(request.status),
            uint8(Status.OPEN),
            "Status should be OPEN"
        );
    }

    function testServiceRequest() public {
        // First create a request
        testCreateLendingRequest();

        // Now lender services the request
        vm.startPrank(lender);
        mockUSDC.approve(address(diamond), 1000 * 10 ** 18);
        P2pFacet(payable(address(diamond))).serviceRequest(
            1,
            address(mockUSDC)
        );
        vm.stopPrank();

        // Verify request was serviced
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            1
        );
        assertEq(
            uint8(request.status),
            uint8(Status.SERVICED),
            "Status should be SERVICED"
        );
        assertEq(request.lender, lender, "Lender should be set");

        // Check borrower received funds
        assertEq(
            mockUSDC.balanceOf(borrower),
            INITIAL_BALANCE + 1000 * 10 ** 18,
            "Borrower should receive the loan amount"
        );
    }

    function testRepayLoan() public {
        // Setup a loan by creating and servicing a request
        uint256 initialBorrowerWETHBalance = mockWETH.balanceOf(borrower);
        testServiceRequest();

        // Calculate full repayment (principal + interest)
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            1
        );
        uint256 fullRepayment = request.totalRepayment;

        // Borrower repays the loan
        vm.startPrank(borrower);
        mockUSDC.approve(address(diamond), fullRepayment);
        P2pFacet(payable(address(diamond))).repayLoan(1, 0); // 0 means full repayment
        vm.stopPrank();

        // Verify loan is closed
        request = P2pFacet(payable(address(diamond))).getRequest(1);
        assertEq(
            uint8(request.status),
            uint8(Status.CLOSED),
            "Status should be CLOSED"
        );

        // Check collateral returned to borrower
        uint256 borrowerWETHBalance = mockWETH.balanceOf(borrower);
        assertEq(
            borrowerWETHBalance,
            initialBorrowerWETHBalance,
            "Borrower should get their collateral back"
        );
    }

    function testLiquidateUserRequest() public {
        // Setup a loan by creating and servicing a request
        testServiceRequest();

        // Decrease collateral value by reducing ETH price
        vm.startPrank(owner);
        mockWETHPriceFeed.setPrice(500 * 10 ** 8); // ETH price drops from $2000 to $500
        vm.stopPrank();

        // Check if position is liquidatable
        bool isLiquidatable = P2pFacet(payable(address(diamond)))
            .isPositionLiquidatable(borrower, 1);
        assertTrue(
            isLiquidatable,
            "Position should be liquidatable after price drop"
        );

        // Liquidator performs liquidation
        vm.startPrank(liquidator);
        mockUSDC.approve(address(diamond), 1050 * 10 ** 18); // Enough to cover loan + interest
        P2pFacet(payable(address(diamond))).liquidateUserRequest(1);
        vm.stopPrank();

        // Verify liquidation
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            1
        );
        assertEq(
            uint8(request.status),
            uint8(Status.LIQUIDATED),
            "Status should be LIQUIDATED"
        );

        // Check liquidator received collateral
        uint256 liquidatorWETHBalance = mockWETH.balanceOf(liquidator);
        assertGt(
            liquidatorWETHBalance,
            INITIAL_BALANCE,
            "Liquidator should receive collateral"
        );
    }

    function testAutoMatchingLoan() public {
        // Lender creates a loan listing
        vm.startPrank(lender);
        mockUSDC.approve(address(diamond), 1000 * 10 ** 18);

        (uint96 listingId, ) = P2pFacet(payable(address(diamond)))
            .createLoanListingWithMatching(
                1000 * 10 ** 18, // Amount
                100 * 10 ** 18, // Min amount
                500 * 10 ** 18, // Max amount
                block.timestamp + 30 days, // Return duration
                300, // 3% interest
                address(mockUSDC),
                false // No auto-matching yet
            );
        vm.stopPrank();

        // Borrower creates a matching request
        vm.startPrank(borrower);
        mockWETH.approve(address(diamond), 1 * 10 ** 18);

        address[] memory collateralTokens = new address[](1);
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralTokens[0] = address(mockWETH);
        collateralAmounts[0] = 1 * 10 ** 18; // 1 WETH worth $2000

        (uint96 requestId, bool matched) = P2pFacet(payable(address(diamond)))
            .createAndMatchLendingRequest(
                500 * 10 ** 18, // Borrow 500 USDC (within min/max range)
                400, // 4% interest - willing to pay more than lender asks
                block.timestamp + 15 days, // Shorter than max duration
                block.timestamp + 7 days, // Expiration
                address(mockUSDC),
                collateralTokens,
                collateralAmounts,
                false // Don't use existing collateral
            );
        vm.stopPrank();

        // Verify matching
        assertTrue(matched, "Request should be automatically matched");

        // Check request details
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            requestId
        );
        assertEq(
            uint8(request.status),
            uint8(Status.SERVICED),
            "Status should be SERVICED"
        );
        assertEq(request.lender, lender, "Lender should be set correctly");

        // Check balances
        assertEq(
            mockUSDC.balanceOf(borrower),
            INITIAL_BALANCE + 500 * 10 ** 18,
            "Borrower should receive loan amount"
        );

        // Check listing was updated
        LoanListing memory listing = P2pFacet(payable(address(diamond)))
            .getLoanListing(listingId);

        assertEq(
            listing.amount,
            500 * 10 ** 18,
            "Listing amount should be reduced"
        );
        assertTrue(
            listing.listingStatus == ListingStatus.OPEN,
            "Listing should still be open with remaining amount"
        );
    }

    function testUseExistingCollateral() public {
        // Borrower first deposits some collateral without creating a loan
        vm.startPrank(borrower);
        mockWETH.approve(address(diamond), 1 * 10 ** 18);

        address[] memory collateralTokens = new address[](1);
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralTokens[0] = address(mockWETH);
        collateralAmounts[0] = 1 * 10 ** 18; // 1 WETH worth $2000

        // Create a deposit-only position
        LendingPoolFacet(payable(address(diamond))).deposit(
            collateralTokens[0],
            collateralAmounts[0],
            true
        );
        vm.stopPrank();

        // Create a loan listing by lender
        vm.startPrank(lender);
        mockUSDC.approve(address(diamond), 1000 * 10 ** 18);

        P2pFacet(payable(address(diamond))).createLoanListingWithMatching(
            1000 * 10 ** 18, // Amount
            100 * 10 ** 18, // Min amount
            500 * 10 ** 18, // Max amount
            30 days, // Return duration
            300, // 3% interest
            address(mockUSDC),
            false // No auto-matching
        );
        vm.stopPrank();

        // Now borrower uses existing collateral for a loan
        vm.startPrank(borrower);

        // Empty arrays for new collateral
        address[] memory noCollateralTokens = new address[](0);
        uint256[] memory noCollateralAmounts = new uint256[](0);

        (uint96 requestId, bool matched) = P2pFacet(payable(address(diamond)))
            .createAndMatchLendingRequest(
                500 * 10 ** 18, // Borrow 500 USDC
                400, // 4% interest
                block.timestamp + 15 days,
                block.timestamp + 7 days,
                address(mockUSDC),
                noCollateralTokens,
                noCollateralAmounts,
                true // Use existing collateral
            );
        vm.stopPrank();

        // Verify matched and using existing collateral
        assertTrue(matched, "Request should be matched");

        // Check request details
        Request memory request = P2pFacet(payable(address(diamond))).getRequest(
            requestId
        );
        assertEq(
            uint8(request.status),
            uint8(Status.SERVICED),
            "Status should be SERVICED"
        );

        // Verify collateral tokens include existing collateral
        assertEq(
            request.collateralTokens.length,
            1,
            "Should use 1 collateral token"
        );
        assertEq(
            request.collateralTokens[0],
            address(mockWETH),
            "Should use WETH collateral"
        );
    }

    // Helper function to generate function selectors from contract name
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
}
