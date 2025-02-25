// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Diamond} from "../contracts/Diamond.sol";
import {DiamondCutFacet} from "../contracts/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../contracts/facets/DiamondLoupeFacet.sol";
import {P2pFacet} from "../contracts/facets/P2pFacet.sol";
import {LibDiamond} from "../contracts/libraries/LibDiamond.sol";
import {IDiamondCut} from "../contracts/interfaces/IDiamondCut.sol";
// import {MockToken} from "./mocks/MockToken.sol";
// import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {Constants} from "../contracts/utils/constants/Constant.sol";
import "../contracts/model/Protocol.sol";
import "../contracts/model/Event.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '../contracts/utils/validators/Error.sol';

contract P2pFacetTest is Test {
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    P2pFacet p2pF;

    // Mock tokens
    MockToken usdc;
    MockToken weth;
    MockToken wbtc;

    // Mock price feeds
    MockPriceFeed usdcPriceFeed;
    MockPriceFeed wethPriceFeed;
    MockPriceFeed wbtcPriceFeed;

    // Test accounts
    address lender1 = makeAddr("lender1");
    address lender2 = makeAddr("lender2");
    address borrower1 = makeAddr("borrower1");
    address borrower2 = makeAddr("borrower2");
    address _user1 = makeAddr("user1");
    address _user2 = makeAddr("user2");

    // Price constants
    int256 constant USDC_PRICE = 1 * 10**8; // $1.00
    int256 constant WETH_PRICE = 2000 * 10**8; // $2000
    int256 constant WBTC_PRICE = 30000 * 10**8; // $30000

    address constant NATIVE_TOKEN = 0x0000000000000000000000000000000000000001;

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockToken("USD Coin", "USDC", 6);
        weth = new MockToken("Wrapped ETH", "WETH", 18);
        wbtc = new MockToken("Wrapped BTC", "WBTC", 8);
 // Deploy mock price feeds
        usdcPriceFeed = new MockPriceFeed(USDC_PRICE, 8);
        wethPriceFeed = new MockPriceFeed(WETH_PRICE, 8);
        wbtcPriceFeed = new MockPriceFeed(WBTC_PRICE, 8);

        // Deploy Diamond with facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        p2pF = new P2pFacet();

        // Build cut struct for facets
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](2);

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(dLoupe),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectors("DiamondLoupeFacet")
        });

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(p2pF),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectors("P2pFacet")
        });

        // Upgrade diamond with facets
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");

        // Setup supported tokens and price feeds
        address[] memory tokens = new address[](4);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);
        tokens[2] = address(wbtc);
        tokens[3] = NATIVE_TOKEN;

        address[] memory priceFeeds = new address[](4);
        priceFeeds[0] = address(usdcPriceFeed);
        priceFeeds[1] = address(wethPriceFeed);
        priceFeeds[2] = address(wbtcPriceFeed);
        priceFeeds[3] = address(wethPriceFeed);

        // Initialize diamond with tokens and price feeds
        diamond.initialize(tokens, priceFeeds, address(diamond));

        P2pFacet(payable(diamond)).addCollateralTokens(tokens,priceFeeds);
        // Fund test accounts
        fundAccounts();

        vm.warp(360 days);
    }

    

    function testLoanListingDuration() public {
        switchSigner(_user1);
        _depositCollateral();
        

        uint256 _amount = 1 ether;
        uint256 _min_amount = 0.1 ether;
        uint256 _max_amount = 1 ether;
        uint256 _returnDate = block.timestamp + 365 days;
        uint16 _interestRate = 1000;
        address _loanCurrency = NATIVE_TOKEN;

        P2pFacet(payable(diamond)).createLoanListing{value: 1 ether}(
            _amount,
            _min_amount,
            _max_amount,
            _returnDate,
            _interestRate,
            _loanCurrency
        );

        LoanListing memory _listing =  P2pFacet(payable(diamond)).getLoanListing(1);
        assertEq(_listing.amount, _amount);
        assertEq(_listing.returnDuration, 365 days);
        assertEq(uint8(_listing.listingStatus), uint8(ListingStatus.OPEN));
    }

    function testMockPriceFeed() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        TokenData memory tokendata = p2pContract.getTokenData(address(usdc));
        console.log(tokendata.priceFeed);
        MockPriceFeed(tokendata.priceFeed).latestRoundData();
        uint256 value = p2pContract.getUsdValue(address(usdc), 1e18, 18);
        assertGt(value, 0, "Price feed should return a non-zero value");
    }

    function testRequestExpiration() public {
        switchSigner(_user1);
        _depositCollateral();

        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = NATIVE_TOKEN;

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
        vm.expectRevert("Request expired");
        p2pContract.serviceRequest{value: 10 ether}(1, NATIVE_TOKEN);
    }

    function testRequestCancellation() public {
        switchSigner(_user1);
        _depositCollateral();

        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = NATIVE_TOKEN;

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
        vm.expectRevert("Request not open");
        p2pContract.serviceRequest{value: 10 ether}(1, NATIVE_TOKEN);

        Request memory _requestAfterClosing = p2pContract.getRequest(1);
        assertEq(uint8(_requestAfterClosing.status), uint8(Status.CLOSED));
    }

    function testP2pFailSafeMechanism() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        vm.expectEmit(true, false, false, true);
        emit Event.P2pFailSafeStatus(true);
        p2pContract.activtateFailSafe(true);

        switchSigner(_user1);
        vm.expectRevert(Protocol__P2pIsStopped.selector);
        _depositCollateral();

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        _createLendingRequest();

        switchSigner(_user2);
        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.serviceRequest{value: 1 ether}(1, NATIVE_TOKEN);

        switchSigner(_user1);
        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.withdrawCollateral(NATIVE_TOKEN, 2 ether);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.repayLoan{value: 2 ether}(1, 2 ether);

        vm.expectRevert(Protocol__P2pIsStopped.selector);
        p2pContract.requestLoanFromListing(1, 2 ether);
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

        // If using native token, send ETH with the tx
        if (token == NATIVE_TOKEN) {
            (uint96 listingId, ) = P2pFacet(payable(diamond))
                .createLoanListingWithMatching{value: amount}(
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
        } else {
            // Ensure token is approved
            IERC20(token).approve(address(diamond), amount);
            
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
        uint256 wethRequired;
        
        if (token == address(usdc)) {
            // Converting USDC amount to WETH equivalent with 3x collateral
            wethRequired = (amount * 3 * 10**18) / (uint256(USDC_PRICE) * 10**12 / uint256(WETH_PRICE));
        } else if (token == address(wbtc)) {
            // Converting WBTC amount to WETH equivalent with 3x collateral
            wethRequired = (amount * 3 * 10**18) / (uint256(WBTC_PRICE) * 10**10 / uint256(WETH_PRICE));
        } else if (token == address(weth) || token == NATIVE_TOKEN) {
            // Direct WETH or ETH - use 3x collateral
            wethRequired = amount * 3;
        }
        
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        p2pContract.depositCollateral(address(weth), wethRequired);

        // Create borrow request
        (uint96 requestId, bool matched) = p2pContract.createAndMatchLendingRequest(
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
        
        // Verify listing details
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        LoanListing memory listing = p2pContract.getLoanListing(listingId);
        assertEq(listing.author, lender1);
        assertEq(listing.amount, 1000 * 10 ** 6);
        assertEq(listing.tokenAddress, address(usdc));
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
        
        // Verify request details
        Request memory request = p2pContract.getRequest(requestId);
        assertEq(request.author, borrower1);
        assertEq(request.amount, 500 * 10 ** 6);
        assertEq(request.loanRequestAddr, address(usdc));
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
        p2pContract.depositCollateral(address(weth), 2 * 10 ** 18); // 2 WETH
        vm.stopPrank();

        // Create borrowing request with auto-match
        vm.startPrank(borrower1);
        LoanListing memory listingN = p2pContract.getLoanListing(1);

        uint96 matchedListingId = p2pContract.findMatchingLendingOffer(
            address(usdc),
            300 * 10 ** 6,
            600,
            15 days
        );
        console.log(matchedListingId);

        (uint96 requestId, bool matched) = p2pContract.createAndMatchLendingRequest(
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
        LoanListing memory listing = p2pContract.getLoanListing(listingId);
        assertEq(listing.amount, 700 * 10 ** 6, "Listing amount should be reduced");
    }

    // Test: Auto-match a lending offer with existing borrowing requests
    function testAutoMatchLendingOffer() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        
        // Create a borrowing request first
        // Deposit collateral for borrower

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
        IERC20(address(usdc)).approve(address(diamond), 1000 * 10 ** 6);
        
        (uint96 listingId, uint96[] memory matchedRequests) = p2pContract.createLoanListingWithMatching(
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
        assertGt(matchedRequests.length, 0, "Should match at least one request");
        
        if (matchedRequests.length > 0) {
            assertEq(matchedRequests[0], requestId, "Should match our request");
        }

        // Check borrower received the funds
        assertEq(
            usdc.balanceOf(borrower1),
            500 * 10 ** 6,
            "Borrower should receive USDC"
        );
    }

    // Helper functions
    function _depositCollateral() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        p2pContract.depositCollateral{value: 10 ether}(NATIVE_TOKEN, 10 ether);
    }

    function _createLendingRequest() public {
        P2pFacet p2pContract = P2pFacet(payable(diamond));
        uint256 _amount = 7 ether;
        uint16 _interest = 500;
        uint256 _returnDuration = block.timestamp + 30 days;
        uint256 _expirationDate = block.timestamp + 1 days;
        address _loanCurrency = NATIVE_TOKEN;

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
        p2pContract.serviceRequest{value: 7 ether}(1, NATIVE_TOKEN);
    }

    function fundAccounts() internal {
        // Give native ETH to test users
        vm.deal(lender1, 100 ether);
        vm.deal(lender2, 100 ether);
        vm.deal(borrower1, 100 ether);
        vm.deal(borrower2, 100 ether);
        vm.deal(_user1, 1000 ether);
        vm.deal(_user2, 1000 ether);
        
        // Mint tokens to test accounts

        // USDC
        usdc.mint(lender1, 10000 * 10 ** 6); // 10,000 USDC
        usdc.mint(lender2, 20000 * 10 ** 6); // 20,000 USDC
        usdc.mint(_user1, 10000 * 10 ** 6); // 10,000 USDC
        usdc.mint(_user2, 20000 * 10 ** 6); // 20,000 USDC

        // WETH
        weth.mint(borrower1, 10 * 10 ** 18); // 10 WETH
        weth.mint(borrower2, 5 * 10 ** 18); // 5 WETH
        weth.mint(_user1, 10 * 10 ** 18); // 10 WETH
        weth.mint(_user2, 5 * 10 ** 18); // 5 WETH

        // WBTC
        wbtc.mint(borrower1, 1 * 10 ** 8); // 1 WBTC
        wbtc.mint(borrower2, 0.5 * 10 ** 8); // 0.5 WBTC
        wbtc.mint(_user1, 1 * 10 ** 8); // 1 WBTC
        wbtc.mint(_user2, 0.5 * 10 ** 8); // 0.5 WBTC

        // Approve spending
        vm.startPrank(lender1);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lender2);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower1);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower2);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(_user1);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(_user2);
        usdc.approve(address(diamond), type(uint256).max);
        weth.approve(address(diamond), type(uint256).max);
        wbtc.approve(address(diamond), type(uint256).max);
        vm.stopPrank(); 

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

    // Helper function to get function selectors from a facet
    function getFunctionSelectors(
        string memory _facetName
    ) internal view returns (bytes4[] memory selectors) {
        if (
            keccak256(abi.encodePacked(_facetName)) ==
            keccak256(abi.encodePacked("DiamondLoupeFacet"))
        ) {
            selectors = new bytes4[](5);
            selectors[0] = DiamondLoupeFacet.facets.selector;
            selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
            selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            selectors[3] = DiamondLoupeFacet.facetAddress.selector;
            selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
        } else if (
            keccak256(abi.encodePacked(_facetName)) ==
            keccak256(abi.encodePacked("P2pFacet"))
        ) {
            selectors = new bytes4[](24);
            selectors[0] = bytes4(keccak256("depositCollateral(address,uint256)"));
            selectors[1] = bytes4(keccak256("withdrawCollateral(address,uint256)"));
            selectors[2] = bytes4(keccak256("createLendingRequest(uint256,uint16,uint256,uint256,address)"));
            selectors[3] = bytes4(keccak256("createAndMatchLendingRequest(uint256,uint16,uint256,uint256,address)"));
            selectors[4] = bytes4(keccak256("createLoanListingWithMatching(uint256,uint256,uint256,uint256,uint16,address,bool)"));
            selectors[5] = bytes4(keccak256("serviceRequest(uint96,address)"));
            selectors[6] = bytes4(keccak256("repayLoan(uint96,uint256)"));
            selectors[7] = bytes4(keccak256("closeRequest(uint96)"));
            selectors[8] = bytes4(keccak256("requestLoanFromListing(uint96,uint256)"));
            selectors[9] = bytes4(keccak256("liquidateUserRequest(uint96)"));
            selectors[10] = bytes4(keccak256("getRequest(uint96)"));
            selectors[11] = bytes4(keccak256("getLoanListing(uint96)"));
            selectors[12] = bytes4(keccak256("getUserPosition(address)"));
            selectors[13] = bytes4(keccak256("getUserCollateral(address)"));
            selectors[14] = bytes4(keccak256("getUserCollateralAmount(address,address)"));
            selectors[15] = bytes4(keccak256("getCollateralValue(address)"));
            selectors[16] = bytes4(keccak256("getTokenData(address)"));
            selectors[17] = bytes4(keccak256("getSupportedTokens()"));
            selectors[18] = bytes4(keccak256("activtateFailSafe(bool)"));
            selectors[19] = bytes4(keccak256("getUsdValue(address,uint256,uint8)"));
            selectors[20] = bytes4(keccak256("addCollateralTokens(address[],address[])"));
            selectors[21] = bytes4(keccak256("createLoanListing(uint256,uint256,uint256,uint256,uint16,address)"));
            selectors[22] = bytes4(keccak256("findMatchingLendingOffer(address,uint256,uint16,uint256)"));
            selectors[23] = bytes4(keccak256("receive()"));
        }
        return selectors;
    }


    function testRepaymentCalculation() public {
        // Test that interest calculations are correct
        uint256 principal = 1000 * 10 ** 6; // 1000 USDC
        uint16 interest = 500; // 5%
        
        uint96 listingId = createLendingListing(
            lender1,
            principal,
            principal,
            principal,
            30 days,
            interest,
            address(usdc)
        );

        switchSigner(borrower1);
        P2pFacet(payable(diamond)).depositCollateral(address(weth), 2 * 10 ** 18); // 2 WETH as collateral
        
        // Request and get the loan
        P2pFacet(payable(diamond)).requestLoanFromListing(listingId, principal);
        
        // Calculate expected repayment
        uint256 expectedRepayment = principal + (principal * interest) / 10000;
        
        // Get actual required repayment
        Request memory request = P2pFacet(payable(diamond)).getRequest(1);
        assertEq(request.totalRepayment, expectedRepayment, "Incorrect repayment calculation");
    }


    function testPartialRepayment() public {
        // Test partial loan repayment
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6, // 1000 USDC
            1000 * 10 ** 6,
            1000 * 10 ** 6,
            30 days,
            500, // 5%
            address(usdc)
        );
        vm.stopPrank();

        switchSigner(borrower1);
        P2pFacet(payable(diamond)).depositCollateral(address(weth), 2 * 10 ** 18);
        P2pFacet(payable(diamond)).requestLoanFromListing(listingId, 1000 * 10 ** 6);
        
        // Repay half the loan
        uint256 partialAmount = 500 * 10 ** 6;
        P2pFacet(payable(diamond)).repayLoan(1, partialAmount);
        
        Request memory request = P2pFacet(payable(diamond)).getRequest(1);
        assertEq(request.totalRepayment, 550 * 10 ** 6, "Incorrect remaining loan amount");
    }

    // function testMultipleCollateralTypes() public {
    //     // Test using multiple collateral types for a loan
    //     switchSigner(borrower1);
    //     p2pF.depositCollateral(address(weth), 1 * 10 ** 18); // 1 WETH
    //     p2pF.depositCollateral(address(wbtc), 0.1 * 10 ** 8); // 0.1 WBTC
        
    //     switchSigner(lender1);
    //     uint96 listingId = createLendingListing(
    //         lender1,
    //         2000 * 10 ** 6, // 2000 USDC
    //         2000 * 10 ** 6,
    //         2000 * 10 ** 6,
    //         30 days,
    //         500,
    //         address(usdc)
    //     );

    //     switchSigner(borrower1);
    //     p2pF.requestLoanFromListing(listingId, 2000 * 10 ** 6);
        
    //     // Verify both collateral types are properly locked
    //     (address[] memory tokens, uint256[] memory amounts) = p2pF.getUserCollateral(borrower1);
    //     assertEq(tokens.length, 2, "Should have 2 collateral types");
    //     assertTrue(amounts[0] > 0 && amounts[1] > 0, "Both collateral amounts should be non-zero");
    // }

    function testCollateralWithdrawalRestrictions() public {
        // Test collateral withdrawal restrictions when loan is active
        switchSigner(borrower1);
        P2pFacet(payable(diamond)).depositCollateral(address(weth), 1.5 ether);
        
        // switchSigner(lender1);
        uint96 listingId = createLendingListing(
            lender1,
            1000 * 10 ** 6,
            1000 * 10 ** 6,
            1000 * 10 ** 6,
            30 days,
            500,
            address(usdc)
        );

        switchSigner(borrower1);
        P2pFacet(payable(diamond)).requestLoanFromListing(listingId, 1000 * 10 ** 6);
        
        // Attempt to withdraw collateral
        vm.expectRevert(Protocol__InsufficientCollateralDeposited.selector);
        P2pFacet(payable(diamond)).withdrawCollateral(address(weth), 1 * 10 ** 18);
    }

    // function testLoanRefinancing() public {
    //     // Test loan refinancing with better terms
    //     switchSigner(lender1);
    //     uint96 listingId1 = createLendingListing(
    //         lender1,
    //         1000 * 10 ** 6,
    //         1000 * 10 ** 6,
    //         1000 * 10 ** 6,
    //         30 days,
    //         700, // 7%
    //         address(usdc)
    //     );

    //     switchSigner(borrower1);
    //     p2pF.depositCollateral(address(weth), 2 * 10 ** 18);
    //     p2pF.requestLoanFromListing(listingId1, 1000 * 10 ** 6);
        
    //     // Create new listing with better terms
    //     switchSigner(lender2);
    //     uint96 listingId2 = createLendingListing(
    //         lender2,
    //         1000 * 10 ** 6,
    //         1000 * 10 ** 6,
    //         1000 * 10 ** 6,
    //         30 days,
    //         500, // 5%
    //         address(usdc)
    //     );

    //     // Refinance the loan
    //     switchSigner(borrower1);
    //     p2pF.refinanceLoan(1, listingId2);
        
    //     Request memory newRequest = p2pF.getRequest(2);
    //     assertEq(newRequest.interest, 500, "Interest rate should be updated");
    // }

    function testFallback() public {
        // Test fallback function reverts
        (bool success, ) = address(p2pF).call(abi.encodeWithSignature("nonexistentFunction()"));
        assertFalse(success, "Should revert on undefined function");
    }

    function testReceiveFunction() public {
        // Test receive function accepts ETH
        (bool success, ) = address(p2pF).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");
        assertEq(address(p2pF).balance, 1 ether, "Balance should match sent amount");
    }

    // function testInitialization() public {
    //     // Test protocol initialization
    //     (address[] memory tokens, address[] memory priceFeeds) = p2pF.getSupportedTokens();
        
    //     assertEq(tokens.length, 3, "Should have 3 supported tokens");
    //     assertEq(priceFeeds.length, 3, "Should have 3 price feeds");
        
    //     assertEq(tokens[0], address(usdc), "USDC address mismatch");
    //     assertEq(tokens[1], address(weth), "WETH address mismatch");
    //     assertEq(tokens[2], address(wbtc), "WBTC address mismatch");
        
    //     assertEq(priceFeeds[0], address(usdcPriceFeed), "USDC price feed mismatch");
    //     assertEq(priceFeeds[1], address(wethPriceFeed), "WETH price feed mismatch");
    //     assertEq(priceFeeds[2], address(wbtcPriceFeed), "WBTC price feed mismatch");
    // }

    // function testOperationsIntegration() public {
    //     // Test that Operations functions are accessible
    //     switchSigner(borrower1);
    //     p2pF.depositCollateral(address(weth), 1 ether);
        
    //     uint256 collateralValue = p2pF.getCollateralValue(borrower1);
    //     assertTrue(collateralValue > 0, "Collateral value should be non-zero");
    // }

    // function testGettersIntegration() public {
    //     // Test that Getters functions are accessible
    //     switchSigner(borrower1);
    //     p2pF.depositCollateral(address(weth), 1 ether);
        
    //     (address[] memory tokens, uint256[] memory amounts) = p2pF.getUserCollateral(borrower1);
    //     assertEq(tokens.length, amounts.length, "Arrays should have same length");
    //     assertTrue(amounts[0] > 0, "Should have collateral amount");
    // }
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
        
        uint256 currentAllowance = _allowances[sender][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, msg.sender, currentAllowance - amount);
            }
        }
        
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");

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