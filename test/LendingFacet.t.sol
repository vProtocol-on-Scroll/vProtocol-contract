// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/Diamond.sol";
import "../contracts/upgradeInitializers/DiamondInit.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "../contracts/facets/LendingPoolFacet.sol";
import "../contracts/facets/GettersFacet.sol";
import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/libraries/LibAppStorage.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockPriceFeed.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract LendingPoolFacetTest is Test {
    // Diamond contracts
    Diamond diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    OwnershipFacet ownershipFacet;
    LendingPoolFacet lendingPoolFacet;
    GettersFacet gettersFacet;
    DiamondInit diamondInit;

    // Mock contracts
    MockERC20 mockUSDC;
    MockERC20 mockWETH;
    MockPriceFeed mockUSDCPriceFeed;
    MockPriceFeed mockWETHPriceFeed;

    MockERC20 protocolToken;

    // Test addresses
    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address protocolFeeRecipient = address(0x4);

    // Constants
    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 18; // 10000 tokens with 18 decimals

    function setUp() public {
        // Setup accounts
        vm.startPrank(owner);

        // Deploy mock tokens
        mockUSDC = new MockERC20("USDC", "USDC", 6, 10000 * 10 ** 6);
        mockWETH = new MockERC20("WETH", "WETH", 18, 10000 * 10 ** 18);

        // Deploy mock price feeds
        mockUSDCPriceFeed = new MockPriceFeed(1 * 10 ** 8, 8); // $1.00 USD with 8 decimals
        mockWETHPriceFeed = new MockPriceFeed(2000 * 10 ** 8, 8); // $2000.00 USD with 8 decimals

        // Setup diamond
        diamondCutFacet = new DiamondCutFacet();
        diamond = new Diamond(owner, address(diamondCutFacet));

        // Build diamond cut for facets
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);

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

        // Add LendingPoolFacet
        lendingPoolFacet = new LendingPoolFacet();
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: address(lendingPoolFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateSelectors("LendingPoolFacet")
        });

        // Add GettersFacet
        gettersFacet = new GettersFacet();
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: address(gettersFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateSelectors("GettersFacet")
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

        protocolToken = new MockERC20(
            "PROTOCOL",
            "PROTOCOL",
            18,
            100000000000000000e18
        );

        // Initialize the Diamond with tokens
        Diamond(payable(address(diamond))).initialize(
            tokens,
            priceFeeds,
            address(protocolToken)
        );

        // Add supported tokens
        for (uint i = 0; i < tokens.length; i++) {
            LendingPoolFacet(payable(address(diamond))).addSupportedToken(
                tokens[i],
                7500, // 75% LTV
                8500, // 85% liquidation threshold
                11000, // 110% liquidation bonus
                true // is loanable
            );
        }

        // Initialize lending pool
        LendingPoolFacet(payable(address(diamond))).initializeLendingPool(
            2000, // 20% reserve factor
            8000, // 80% optimal utilization
            500, // 5% base rate
            1000 // 10% slope rate
        );

        // Give tokens to test users
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);
        mockWETH.mint(user1, INITIAL_BALANCE);
        mockWETH.mint(user2, INITIAL_BALANCE);
        mockUSDC.mint(owner, 100000000000000000 * 10 ** 18);
        mockWETH.mint(owner, 100000000000000000 * 10 ** 18);

        vm.warp(block.timestamp + 1000000000000000000);

        vm.stopPrank();
    }

    function testDepositToLendingPool() public {
        // User1 approves and deposits USDC
        vm.startPrank(user1);
        mockUSDC.approve(address(diamond), 1000 * 10 ** 18);
        uint256 shares = LendingPoolFacet(payable(diamond)).deposit(
            address(mockUSDC),
            1000 * 10 ** 18,
            true // as collateral
        );
        // vm.stopPrank();

        // Verify deposit
        assertGt(shares, 0, "Should receive shares for deposit");

        // Get user position
        // vm.startPrank(user1);
        uint256 collateral = GettersFacet(payable(address(diamond)))
            .getUserTokenCollateral(user1, address(mockUSDC));
        // vm.stopPrank();

        // Verify collateral was recorded correctly
        assertEq(
            collateral,
            1000 * 10 ** 18,
            "Collateral position should match deposit"
        );
    }

    function testBorrowFromLendingPool() public {
        // First user1 deposits collateral
        vm.startPrank(owner);
        mockUSDC.approve(address(diamond), 100000 * 10 ** 18);
        LendingPoolFacet(payable(address(diamond))).deposit(
            address(mockUSDC),
            100000 * 10 ** 18,
            true // as collateral
        );
        vm.stopPrank();

        vm.startPrank(user1);
        mockWETH.approve(address(diamond), 5 * 10 ** 18); // 5 WETH worth $10,000
        LendingPoolFacet(payable(address(diamond))).deposit(
            address(mockWETH),
            5 * 10 ** 18,
            true // as collateral
        );

        // Then user1 borrows USDC using ETH as collateral
        address[] memory collateralTokens = new address[](1);
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralTokens[0] = address(mockWETH);
        collateralAmounts[0] = 0; // No new collateral, using existing collateral

        // Should be able to borrow ~$7,500 worth (75% LTV) of USDC
        uint256 loanId = LendingPoolFacet(payable(address(diamond)))
            .createPosition(
                collateralTokens,
                collateralAmounts,
                address(mockUSDC),
                7500 * 10 ** 6, // Borrow 7,500 USDC (75% of the $10,000 collateral)
                true // use existing collateral
            );
        vm.stopPrank();

        // Verify loan creation
        assertGt(loanId, 0, "Should create a valid loan ID");

        // Check borrowed amount in user USDC balance
        assertEq(
            mockUSDC.balanceOf(user1),
            INITIAL_BALANCE + (7500 * 10 ** 6),
            "User should receive the borrowed amount"
        );

        // Verify loan details
        (
            PoolLoanDetails memory loanDetails,
            ,
            uint256 healthFactor
        ) = LendingPoolFacet(payable(address(diamond))).getLoanDetails(loanId);

        assertEq(loanDetails.borrower, user1, "Loan borrower should be user1");
        assertEq(
            loanDetails.borrowToken,
            address(mockUSDC),
            "Borrowed token should be USDC"
        );
        assertEq(
            loanDetails.borrowAmount,
            7500 * 10 ** 6,
            "Borrowed amount should match"
        );
        assertGt(
            healthFactor,
            10000,
            "Health factor should be healthy (>100%)"
        );
    }

    function testRepayLoan() public {
        // Setup a loan first
        testBorrowFromLendingPool();

        // Get the loan ID (should be 1)
        uint256 loanId = 1;

        // User1 repays partial loan
        vm.startPrank(user1);
        mockUSDC.approve(address(diamond), 2000 * 10 ** 18);
        uint256 amountRepaid = LendingPoolFacet(payable(address(diamond)))
            .repay(loanId, 2000 * 10 ** 6);
        vm.stopPrank();

        // Verify partial repayment
        assertEq(amountRepaid, 2000 * 10 ** 6, "Repaid amount should match");

        // Check loan still exists but with reduced amount
        (
            PoolLoanDetails memory loanDetails,
            uint256 currentDebt,
            uint256 healthFactor
        ) = LendingPoolFacet(payable(address(diamond))).getLoanDetails(loanId);

        assertEq(
            uint8(loanDetails.status),
            uint8(LoanStatus.ACTIVE),
            "Loan should still be active"
        );
        assertEq(
            loanDetails.borrowAmount,
            5500 * 10 ** 6,
            "Remaining amount should be reduced"
        );

        // Wait for interest to accrue
        vm.warp(block.timestamp + 1000000000000000000);

        (loanDetails, currentDebt, healthFactor) = LendingPoolFacet(
            payable(address(diamond))
        ).getLoanDetails(loanId);

        // Now repay the full loan
        vm.startPrank(user1);
        mockUSDC.approve(address(diamond), currentDebt);
        amountRepaid = LendingPoolFacet(payable(address(diamond))).repay(
            loanId,
            0
        ); // 0 means full repayment
        vm.stopPrank();

        // Verify full repayment
        assertGt(
            amountRepaid,
            5500 * 10 ** 6,
            "Full repayment should include interest"
        );

        // Loan should now be repaid
        (loanDetails, currentDebt, healthFactor) = LendingPoolFacet(
            payable(address(diamond))
        ).getLoanDetails(loanId);

        assertEq(
            uint8(loanDetails.status),
            uint8(LoanStatus.REPAID),
            "Loan should be marked as repaid"
        );
    }

    function testLiquidation() public {
        // Setup a loan first
        testBorrowFromLendingPool();

        // Get the loan ID (should be 1)
        uint256 loanId = 1;

        // Decrease collateral value by reducing ETH price
        vm.startPrank(owner);
        mockWETHPriceFeed.setPrice(800 * 10 ** 8); // ETH price drops from $2000 to $1200
        vm.stopPrank();

        // Check that the loan is now liquidatable
        bool isLiquidatable = LendingPoolFacet(payable(address(diamond)))
            .isLoanLiquidatable(loanId);
        assertTrue(
            isLiquidatable,
            "Loan should be liquidatable after price drop"
        );

        // User2 liquidates the loan
        vm.startPrank(user2);
        mockUSDC.approve(address(diamond), 8000 * 10 ** 18); // Enough to cover full loan
        uint256 collateralReceived = LendingPoolFacet(payable(address(diamond)))
            .liquidateLoan(loanId);
        vm.stopPrank();

        // Verify liquidation
        assertGt(collateralReceived, 0, "Liquidator should receive collateral");
        assertGt(
            mockWETH.balanceOf(user2),
            INITIAL_BALANCE,
            "Liquidator should have received ETH collateral"
        );

        // Loan should now be liquidated
        (PoolLoanDetails memory loanDetails, , ) = LendingPoolFacet(
            payable(address(diamond))
        ).getLoanDetails(loanId);

        assertEq(
            uint8(loanDetails.status),
            uint8(LoanStatus.LIQUIDATED),
            "Loan should be marked as liquidated"
        );
    }

    function testWithdraw() public {
        // First deposit
        testDepositToLendingPool();

        // Then withdraw
        vm.startPrank(user1);
        uint256 amountWithdrawn = LendingPoolFacet(payable(address(diamond)))
            .withdraw(
                address(mockUSDC),
                500 * 10 ** 18,
                false // not from vault
            );
        vm.stopPrank();

        // Verify withdrawal
        assertEq(
            amountWithdrawn,
            500 * 10 ** 18,
            "Withdrawn amount should match"
        );

        // Check user position after withdrawal
        vm.startPrank(user1);
        uint256 collateral = GettersFacet(payable(address(diamond)))
            .getUserTokenCollateral(user1, address(mockUSDC));
        vm.stopPrank();

        assertEq(
            collateral,
            500 * 10 ** 18,
            "Collateral should be reduced by withdrawal amount"
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
