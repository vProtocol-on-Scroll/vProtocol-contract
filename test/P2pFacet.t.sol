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

contract P2pFacetTest is Test, IDiamondCut {
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

        tokens.push(address(1));
        priceFeeds.push(0x59F1ec1f10bD7eD9B938431086bC1D9e233ECf41);

        diamond.initialize(tokens, priceFeeds);

        vm.deal(_user1, 20 ether);
        vm.deal(_user2, 50 ether);
    }

    function testPriceFeedData() public view {
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        uint256 value = p2pContract.getUsdValue(address(1), 1e18, 18);
        assertGt(value, 1600e18);
    }

    function testLoanListingDuration() public {
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

    function _depositCollateral() public {
        switchSigner(_user1);
        P2pFacet p2pContract = P2pFacet(payable(diamond));

        p2pContract.depositCollateral{value: 10 ether}(tokens[0], 10 ether);
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
