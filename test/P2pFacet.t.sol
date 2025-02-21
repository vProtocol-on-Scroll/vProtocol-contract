// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/interfaces/IDiamondCut.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/facets/OwnershipFacet.sol";
import "forge-std/Test.sol";
import "../contracts/Diamond.sol";

import {P2pFacet} from "../contracts/facets/P2pFacet.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/utils/validators/Error.sol";

import {LibGettersImpl} from "../contracts/libraries/LibGetters.sol";
import {AppStorage} from "../contracts/utils/functions/AppStorage.sol";

import {Event} from "../contracts/model/Event.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract P2pFacetTest is Test, IDiamondCut, AppStorage {
    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    P2pFacet p2pF;

    address[] tokens;
    address[] priceFeeds;

    address _user1 = makeAddr("user 1");
    address _user2 = makeAddr("user 2");

    // Mock tokens
    MockToken usdc = MockToken(0x43d12Fb3AfCAd5347fA764EeAB105478337b7200);
    MockToken weth = MockToken(0x6bF14CB0A831078629D993FDeBcB182b21A8774C);
    MockToken wbtc = MockToken(0xCaca6BFdeDA537236Ee406437D2F8a400026C589);

    // Mock price feeds
    MockPriceFeed usdcPriceFeed = MockPriceFeed(mkaddr("USDC Price Feed"));
    MockPriceFeed wethPriceFeed = MockPriceFeed(mkaddr("WETH Price Feed"));
    MockPriceFeed wbtcPriceFeed = MockPriceFeed(mkaddr("WBTC Price Feed"));

    // Test users
    address lender1 = address(0x1);
    address lender2 = address(0x2);
    address borrower1 = address(0x3);
    address borrower2 = address(0x4);
    address deployer = address(0x5);
    address treasury = address(0x6);

    // Constants
    uint256 USDC_PRICE = 1 * 10 ** 8; // $1.00
    uint256 WETH_PRICE = 2000 * 10 ** 8; // $2,000
    uint256 WBTC_PRICE = 30000 * 10 ** 8; // $30,000

    // Setup variables
    uint96 lendingListingId;
    uint96 borrowRequestId;

    function setUp() public {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        p2pF = new P2pFacet();

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](3);

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
                facetAddress: address(p2pF),
                action: FacetCutAction.Add,
                functionSelectors: generateSelectors("P2pFacet")
            })
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        //call a function
        DiamondLoupeFacet(address(diamond)).facetAddresses();

        // ETH
        tokens.push(address(1));
        // priceFeeds.push(0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41);
        priceFeeds.push(0x6bF14CB0A831078629D993FDeBcB182b21A8774C);

        // USDC
        tokens.push(0x1D738a3436A8C49CefFbaB7fbF04B660fb528CbD);
        priceFeeds.push(0x43d12Fb3AfCAd5347fA764EeAB105478337b7200);

        tokens.push(address(usdc));
        priceFeeds.push(address(usdc));

        tokens.push(address(weth));
        priceFeeds.push(address(weth));

        tokens.push(address(wbtc));
        priceFeeds.push(address(wbtc));

        diamond.initialize(tokens, priceFeeds, address(diamond));

        P2pFacet(payable(diamond)).setSwapRouter(
            0xfB5f26851E03449A0403Ca945eBB4201415fd1fc
        );

        vm.deal(_user1, 20 ether);
        vm.deal(_user2, 50 ether);
    }

    function testPriceFeedData() public view {
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 value = p2pContract.getUsdValue(address(1), 1e18, 18);
        assertGt(value, 1600e18);
    }

    function testLoanListingDuration() public {
        switchSigner(_user1);
        _depositCollateral();
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 _amount = 1 ether;
        uint256 _min_amount = 0.1 ether;
        uint256 _max_amount = 1 ether;
        uint256 _returnDate = block.timestamp + 365 days;
        uint16 _interestRate = 1000;
        address _loanCurrency = tokens[0];

        p2pContract.createLoanListing{value: 1 ether}(
            _amount,
            _min_amount,
            _max_amount,
            _returnDate,
            _interestRate,
            _loanCurrency
        );

        LoanListing memory _listing = p2pContract.getLoanListing(1);
        assertEq(_listing.amount, _amount);
        assertEq(_listing.returnDuration, 365 days);
        assertEq(uint8(_listing.listingStatus), uint8(ListingStatus.OPEN));
    }

    function testRequestExpiration() public {
        switchSigner(_user1);
        _depositCollateral();

        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = tokens[0];

        p2pContract.createLendingRequest(
            _amount,
            _interest,
            _returnDuration,
            _expirationDate,
            _loanCurrency
        );

        Request memory _requestBeforeTimeWarp = p2pContract.getRequest(1);
        assertEq(_requestBeforeTimeWarp.amount, _amount);
        assertEq(
            _requestBeforeTimeWarp.expirationDate,
            block.timestamp + 1 days
        );
        assertEq(uint8(_requestBeforeTimeWarp.status), uint8(Status.OPEN));

        vm.warp(block.timestamp + 2 days);

        switchSigner(_user2);
        vm.expectRevert(Protocol__RequestNotOpen.selector);
        p2pContract.serviceRequest{value: 10 ether}(1, tokens[0]);
    }

    function testRequestCancellation() public {
        switchSigner(_user1);
        _depositCollateral();

        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = tokens[0];

        p2pContract.createLendingRequest(
            _amount,
            _interest,
            _returnDuration,
            _expirationDate,
            _loanCurrency
        );

        Request memory _requestBeforeClosing = p2pContract.getRequest(1);
        assertEq(uint8(_requestBeforeClosing.status), uint8(Status.OPEN));

        p2pContract.closeRequest(1);

        switchSigner(_user2);
        vm.expectRevert(Protocol__RequestNotOpen.selector);
        p2pContract.serviceRequest{value: 10 ether}(1, tokens[0]);

        Request memory _requestAfterClosing = p2pContract.getRequest(1);
        assertEq(uint8(_requestAfterClosing.status), uint8(Status.CLOSED));
    }

    function testStalePriceFeed() public {
        switchSigner(_user1);
        _depositCollateral();
        _createLendingRequest();

        P2pFacet p2pContract = P2pFacet(payable(diamond));

        vm.warp(block.timestamp + 4 hours);

        switchSigner(_user2);
        vm.expectRevert(Protocol__PriceStale.selector);
        p2pContract.serviceRequest{value: 7 ether}(1, tokens[0]);
    }

    function testP2pFailSafeMechanism() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        vm.expectEmit(true, false, false, true);
        emit Event.P2pFailSafeStatus(true);
        p2pContract.activtateFailSafe(true);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        _depositCollateral();

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        _createLendingRequest();

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.serviceRequest{value: 1 ether}(1, tokens[0]);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.withdrawCollateral(tokens[0], 2 ether);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.repayLoan{value: 2 ether}(1, 2 ether);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.requestLoanFromListing(1, 2 ether);
    }

    function testLiquidationCriteria() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        switchSigner(_user1);
        _depositCollateral();
        uint256 _amount = 0.2 ether;
        uint16 _interest = 200;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = tokens[0];

        p2pContract.createLendingRequest(
            _amount,
            _interest,
            _returnDuration,
            _expirationDate,
            _loanCurrency
        );
        switchSigner(_user2);
        _serviceRequest();
        assertFalse(p2pContract.checkLiquidationEligibility(_user1));

        switchSigner(_user1);
        _createLendingRequest();

        switchSigner(_user2);
        p2pContract.serviceRequest{value: 7 ether}(2, tokens[0]);
        assertTrue(p2pContract.checkLiquidationEligibility(_user1));
    }

    function testLiquidateUserRequest() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        switchSigner(_user1);
        _depositCollateral();
        _createLendingRequest();

        switchSigner(_user2);
        _serviceRequest();

        p2pContract.liquidateUserRequest(1);
    }

    // Helper function to create a lending listing
    function createLendingListing(
        address user,
        uint256 amount,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 returnDuration,
        uint16 interest,
        address token
    ) internal returns (uint96) {
        vm.startPrank(user);

        (uint96 listingId, ) = P2pFacet(payable(diamond))
            .createLoanListingWithMatching(
                amount,
                minAmount,
                maxAmount,
                block.timestamp + returnDuration,
                interest,
                token,
                false // no auto-matching
            );

        vm.stopPrank();
        return listingId;
    }

    // Helper function to create a borrowing request
    function createBorrowingRequest(
        address user,
        uint256 amount,
        uint16 interest,
        uint256 returnDuration,
        uint256 expirationDate,
        address token
    ) internal returns (uint96) {
        vm.startPrank(user);

        // First deposit collateral
        // For simplicity, deposit WETH worth 3x the loan value
        uint256 usdLoanValue = amount; // assuming USDC
        uint256 wethRequired = ((usdLoanValue * 3 * 10 ** 18) / WETH_PRICE) *
            10 ** 8;
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        p2pContract.depositCollateral(address(weth), wethRequired);

        // Create borrow request
        (uint96 requestId, ) = p2pContract.createAndMatchLendingRequest(
            amount,
            interest,
            block.timestamp + returnDuration,
            block.timestamp + expirationDate,
            token
        );

        vm.stopPrank();
        return requestId;
    }

    // Test: Create a lending listing
    function testCreateLendingListing() public {
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1,000 USDC
            100 * 10 ** 6, // min 100 USDC
            500 * 10 ** 6, // max 500 USDC
            30 days, // 30 day loans
            500, // 5% interest
            address(usdc) // USDC
        );

        // Assert listing was created
        assertTrue(listingId > 0, "Listing should be created");
    }

    // Test: Create a borrowing request
    function testCreateBorrowingRequest() public {
        // First deposit collateral for borrower
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
        vm.stopPrank();

        uint96 requestId = createBorrowingRequest(
            borrower1,
            500 * 10 ** 6, // 500 USDC
            600, // 6% interest
            30 days, // 30 day loan
            7 days, // expires in 7 days
            address(usdc) // USDC
        );

        // Assert request was created
        assertTrue(requestId > 0, "Request should be created");
    }

    // Test: Auto-match a borrowing request with existing lending offer
    function testAutoMatchBorrowRequest() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a lending offer first
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1,000 USDC
            100 * 10 ** 6, // min 100 USDC
            500 * 10 ** 6, // max 500 USDC
            30 days, // 30 day loans
            500, // 5% interest
            address(usdc) // USDC
        );

        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
        vm.stopPrank();

        // Create borrowing request with auto-match
        vm.startPrank(borrower1);
        (uint96 requestId, bool matched) = p2pContract
            .createAndMatchLendingRequest(
                300 * 10 ** 6, // 300 USDC
                600, // 6% interest (higher than lender's 5%)
                block.timestamp + 15 days, // 15 day loan (shorter than lender's 30 days)
                block.timestamp + 7 days, // expires in 7 days
                address(usdc) // USDC
            );
        vm.stopPrank();

        // Assert auto-matching worked
        assertTrue(matched, "Request should be auto-matched");

        // Check borrower received the funds
        assertEq(
            usdc.balanceOf(borrower1),
            300 * 10 ** 6,
            "Borrower should receive USDC"
        );

        // Check lending listing was updated
        // This assumes we have a getter for listings
        // If not available, we'd check events instead
    }

    // Test: Auto-match a lending offer with existing borrowing requests
    function testAutoMatchLendingOffer() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a borrowing request first
        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 2 * 10 ** 18); // 2 WETH
        vm.stopPrank();

        uint96 requestId = createBorrowingRequest(
            borrower1,
            500 * 10 ** 6, // 500 USDC
            700, // 7% interest
            30 days, // 30 day loan
            7 days, // expires in 7 days
            address(usdc) // USDC
        );

        // Create lending offer with auto-match
        vm.startPrank(lender1);
        (uint96 listingId, uint96[] memory matchedRequests) = p2pContract
            .createLoanListingWithMatching(
                1000 * 10 ** 6, // 1,000 USDC
                100 * 10 ** 6, // min 100 USDC
                500 * 10 ** 6, // max 500 USDC
                block.timestamp + 45 days, // 45 day loans
                500, // 5% interest (lower than borrower's 7%)
                address(usdc), // USDC
                true // auto-match enabled
            );
        vm.stopPrank();

        // Assert auto-matching worked
        assertEq(matchedRequests.length, 1, "Should match one request");
        assertEq(matchedRequests[0], requestId, "Should match our request");

        // Check borrower received the funds
        assertEq(
            usdc.balanceOf(borrower1),
            500 * 10 ** 6,
            "Borrower should receive USDC"
        );
    }

    // Test: Multiple matches in a single lending offer
    function testMultipleMatchesInLendingOffer() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create multiple borrowing requests
        // Deposit collateral for borrowers
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 3 * 10 ** 18); // 3 WETH
        vm.stopPrank();

        vm.startPrank(borrower2);
        p2pContract.depositCollateral(address(weth), 2 * 10 ** 18); // 2 WETH
        vm.stopPrank();

        uint96 requestId1 = createBorrowingRequest(
            borrower1,
            200 * 10 ** 6, // 200 USDC
            800, // 8% interest
            20 days, // 20 day loan
            7 days, // expires in 7 days
            address(usdc) // USDC
        );

        uint96 requestId2 = createBorrowingRequest(
            borrower2,
            300 * 10 ** 6, // 300 USDC
            700, // 7% interest
            25 days, // 25 day loan
            7 days, // expires in 7 days
            address(usdc) // USDC
        );

        // Create lending offer with auto-match
        vm.startPrank(lender1);
        (uint96 listingId, uint96[] memory matchedRequests) = p2pContract
            .createLoanListingWithMatching(
                1000 * 10 ** 6, // 1,000 USDC
                100 * 10 ** 6, // min 100 USDC
                500 * 10 ** 6, // max 500 USDC
                block.timestamp + 30 days, // 30 day loans
                600, // 6% interest (lower than both borrowers)
                address(usdc), // USDC
                true // auto-match enabled
            );
        vm.stopPrank();

        // Assert auto-matching worked for both requests
        assertEq(matchedRequests.length, 2, "Should match two requests");

        // Since we prioritize higher interest rates, first match should be requestId1
        assertEq(
            matchedRequests[0],
            requestId1,
            "First match should be highest interest"
        );
        assertEq(
            matchedRequests[1],
            requestId2,
            "Second match should be second highest interest"
        );

        // Check borrowers received the funds
        assertEq(
            usdc.balanceOf(borrower1),
            200 * 10 ** 6,
            "Borrower1 should receive USDC"
        );
        assertEq(
            usdc.balanceOf(borrower2),
            300 * 10 ** 6,
            "Borrower2 should receive USDC"
        );

        // Check remaining balance in lender's offer
        // 1000 - 200 - 300 = 500 USDC should remain
        // This assumes we have a getter for listings
        // If not available, we'd check events instead
    }

    // Test: No matches available
    function testNoMatchesAvailable() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a borrowing request for WETH
        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(wbtc), 0.5 * 10 ** 8); // 0.5 WBTC
        vm.stopPrank();

        uint96 requestId = createBorrowingRequest(
            borrower1,
            1 * 10 ** 18, // 1 WETH
            700, // 7% interest
            30 days, // 30 day loan
            7 days, // expires in 7 days
            address(weth) // WETH
        );

        // Create lending offer for USDC with auto-match (should find no matches)
        vm.startPrank(lender1);
        (uint96 listingId, uint96[] memory matchedRequests) = p2pContract
            .createLoanListingWithMatching(
                1000 * 10 ** 6, // 1,000 USDC
                100 * 10 ** 6, // min 100 USDC
                500 * 10 ** 6, // max 500 USDC
                block.timestamp + 30 days, // 30 day loans
                500, // 5% interest
                address(usdc), // USDC
                true // auto-match enabled
            );
        vm.stopPrank();

        // Assert no matches were found
        assertEq(matchedRequests.length, 0, "Should not find any matches");
    }

    // Test: Matching with interest rate constraints
    function testMatchingWithInterestConstraints() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a lending offer with low interest
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1,000 USDC
            100 * 10 ** 6, // min 100 USDC
            500 * 10 ** 6, // max 500 USDC
            30 days, // 30 day loans
            300, // 3% interest
            address(usdc) // USDC
        );

        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
        vm.stopPrank();

        // Create borrowing request with auto-match but lower interest (shouldn't match)
        vm.startPrank(borrower1);
        (uint96 requestId, bool matched) = p2pContract
            .createAndMatchLendingRequest(
                300 * 10 ** 6, // 300 USDC
                200, // 2% interest (lower than lender's 3%)
                block.timestamp + 15 days, // 15 day loan
                block.timestamp + 7 days, // expires in 7 days
                address(usdc) // USDC
            );
        vm.stopPrank();

        // Assert auto-matching failed due to interest rate
        assertFalse(
            matched,
            "Request should not be auto-matched due to interest rate"
        );

        // Check borrower didn't receive funds
        assertEq(
            usdc.balanceOf(borrower1),
            0,
            "Borrower should not receive USDC"
        );
    }

    // Test: Matching with amount constraints
    function testMatchingWithAmountConstraints() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a lending offer
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1,000 USDC
            200 * 10 ** 6, // min 200 USDC
            500 * 10 ** 6, // max 500 USDC
            30 days, // 30 day loans
            500, // 5% interest
            address(usdc) // USDC
        );

        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
        vm.stopPrank();

        // Create borrowing request with auto-match but amount too small (shouldn't match)
        vm.startPrank(borrower1);
        (uint96 requestId1, bool matched1) = p2pContract
            .createAndMatchLendingRequest(
                150 * 10 ** 6, // 150 USDC (below min 200)
                600, // 6% interest
                block.timestamp + 15 days, // 15 day loan
                block.timestamp + 7 days, // expires in 7 days
                address(usdc) // USDC
            );
        vm.stopPrank();

        // Assert auto-matching failed due to amount
        assertFalse(
            matched1,
            "Request should not be auto-matched due to amount too small"
        );

        // Create borrowing request with auto-match but amount too large (shouldn't match)
        vm.startPrank(borrower1);
        (uint96 requestId2, bool matched2) = p2pContract
            .createAndMatchLendingRequest(
                600 * 10 ** 6, // 600 USDC (above max 500)
                600, // 6% interest
                block.timestamp + 15 days, // 15 day loan
                block.timestamp + 7 days, // expires in 7 days
                address(usdc) // USDC
            );
        vm.stopPrank();

        // Assert auto-matching failed due to amount
        assertFalse(
            matched2,
            "Request should not be auto-matched due to amount too large"
        );
    }

    // Test: Matching with duration constraints
    function testMatchingWithDurationConstraints() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        // Create a lending offer
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1,000 USDC
            100 * 10 ** 6, // min 100 USDC
            500 * 10 ** 6, // max 500 USDC
            30 days, // 30 day loans
            500, // 5% interest
            address(usdc) // USDC
        );

        // Deposit collateral for borrower
        vm.startPrank(borrower1);
        p2pContract.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
        vm.stopPrank();

        // Create borrowing request with auto-match but longer duration (shouldn't match)
        vm.startPrank(borrower1);
        (uint96 requestId, bool matched) = p2pContract
            .createAndMatchLendingRequest(
                300 * 10 ** 6, // 300 USDC
                600, // 6% interest
                block.timestamp + 45 days, // 45 day loan (longer than lender's 30 days)
                block.timestamp + 7 days, // expires in 7 days
                address(usdc) // USDC
            );
        vm.stopPrank();

        // Assert auto-matching failed due to duration
        assertFalse(
            matched,
            "Request should not be auto-matched due to duration"
        );

        // Check borrower didn't receive funds
        assertEq(
            usdc.balanceOf(borrower1),
            0,
            "Borrower should not receive USDC"
        );
    }

    function _depositCollateral() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        p2pContract.depositCollateral{value: 10 ether}(tokens[0], 10 ether);
    }

    function _createLendingRequest() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = tokens[0];

        p2pContract.createLendingRequest(
            _amount,
            _interest,
            _returnDuration,
            _expirationDate,
            _loanCurrency
        );
    }

    function _serviceRequest() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        p2pContract.serviceRequest{value: 7 ether}(1, tokens[0]);
    }

    function fundAccounts() internal {
        // Mint tokens to test accounts

        // USDC
        usdc.mint(lender1, 10000 * 10 ** 6); // 10,000 USDC
        usdc.mint(lender2, 20000 * 10 ** 6); // 20,000 USDC

        // WETH
        weth.mint(borrower1, 10 * 10 ** 18); // 10 WETH
        weth.mint(borrower2, 5 * 10 ** 18); // 5 WETH

        // WBTC
        wbtc.mint(borrower1, 1 * 10 ** 8); // 1 WBTC
        wbtc.mint(borrower2, 0.5 * 10 ** 8); // 0.5 WBTC

        // Approve spending
        vm.startPrank(lender1);
        usdc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lender2);
        usdc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower1);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower2);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

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

contract MockToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Test helpers
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

contract MockPriceFeed {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 price_, uint8 decimals_) {
        _price = price_;
        _decimals = decimals_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp - 1 hours, block.timestamp, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // Test helper
    function setPrice(int256 price_) public {
        _price = price_;
    }
}
