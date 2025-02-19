// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/facets/RewardDistributionFacet.sol";
import "../contracts/libraries/LibDiamond.sol";
import "../contracts/libraries/LibAppStorage.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/Diamond.sol";
import "../contracts/facets/DiamondCutFacet.sol";
import "../contracts/facets/DiamondLoupeFacet.sol";
import "../contracts/upgradeInitializers/DiamondInit.sol";
import "./helpers/StorageHelper.sol";
contract RewardDistributionTest is Test, StorageHelper {
    // Diamond and facets
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    RewardDistributionFacet rewardFacet;
    DiamondInit diamondInit;

    // Mock tokens
    MockERC20 protocolToken;

    // Test users
    address admin = address(0x1);
    address lender = address(0x2);
    address borrower = address(0x3);
    address liquidator = address(0x4);
    address staker = address(0x5);

    // Constants
    uint256 constant INITIAL_SUPPLY = 1_000_000 ether; // 1 million tokens
    uint256 constant PROTOCOL_FEES = 100_000 ether;    // 100k tokens

    // Events to test
    event PoolsUpdated(uint256 lenderPool, uint256 borrowerPool, uint256 liquidatorPool, uint256 stakerPool);
    event RewardDistributed(address indexed user, address indexed token, uint256 amount);
    event RewardConfigUpdated(uint256 lenderShare, uint256 borrowerShare, uint256 liquidatorShare, uint256 stakerShare);

    function setUp() public {

        vm.warp(block.timestamp + 1000 days);
        vm.startPrank(admin);

        // Create and deploy mock tokens
        protocolToken = new MockERC20("Protocol Token", "PTKN", 18);
        protocolToken.mint(admin, INITIAL_SUPPLY);
        
        // Create diamond and facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(admin, address(dCutFacet));
        dLoupe = new DiamondLoupeFacet();
        rewardFacet = new RewardDistributionFacet();
        diamondInit = new DiamondInit();

        // Build cut struct
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);
        
        // DiamondLoupeFacet
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(dLoupe),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectors("DiamondLoupeFacet")
        });
        
        // RewardDistributionFacet
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: address(rewardFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: getFunctionSelectors("RewardDistributionFacet")
        });

        // Initialize diamond
        bytes memory initData = abi.encodeWithSelector(
            DiamondInit.init.selector,
            address(protocolToken)
        );
        
        IDiamondCut(address(diamond)).diamondCut(cuts, address(diamondInit), initData);

        // Initialize reward distribution
        RewardDistributionFacet(address(diamond)).initializeRewardDistribution(address(protocolToken));
        
        // Transfer protocol tokens to diamond for reward distribution
        protocolToken.transfer(address(diamond), PROTOCOL_FEES);
        
        // Setup mock user activities
        setupMockUserActivities();
        
        vm.stopPrank();
    }

    function setupMockUserActivities() internal {
        // Set up protocol fees
        setProtocolFees(PROTOCOL_FEES);
        
        // Initialize reward config with default values
        RewardConfig storage config = getRewardConfig();
        config.lenderShare = 4000;    // 40%
        config.borrowerShare = 2000;  // 20%
        config.liquidatorShare = 1000; // 10%
        config.stakerShare = 3000;    // 30%
        
        config.lenderRewardRate = 500;      // 5% APR  
        config.borrowerRewardRate = 300;    // 3% APR
        config.liquidatorRewardRate = 500;  // 5% of liquidated amount
        config.stakerRewardRate = 1000;     // 10% APR
        
        // Setup lender activity
        UserActivity storage lenderActivity = getUserActivity(lender);
        lenderActivity.totalLendingAmount = 50_000 * 10**18;
        lenderActivity.lastLenderRewardUpdate = block.timestamp - 30 days;
        
        // Setup borrower activity
        UserActivity storage borrowerActivity = getUserActivity(borrower);
        borrowerActivity.totalBorrowingAmount = 30_000 * 10**18;
        borrowerActivity.lastBorrowerRewardUpdate = block.timestamp - 30 days;
        
        // Setup liquidator activity
        UserActivity storage liquidatorActivity = getUserActivity(liquidator);  
        liquidatorActivity.totalLiquidationAmount = 10_000 * 10**18;
        
        // Setup staker activity
        UserStake storage stakerStake = getUserStake(staker);
        stakerStake.amount = 20_000 * 10**18;
        stakerStake.lockStart = block.timestamp - 60 days;
        stakerStake.loyaltyMultiplier = 15000; // 1.5x (using BASIS_POINTS = 10000)
    }

    function test_DistributeProtocolFees() public {
        vm.startPrank(admin);
        
        uint256 totalFees = 50_000 * 10**18;
        setProtocolFees(totalFees); // Set fees directly to specific amount
        
        // Expected pool allocations
        uint256 expectedLenderPool = (totalFees * 4000) / 10000; // 40%
        uint256 expectedBorrowerPool = (totalFees * 2000) / 10000; // 20%
        uint256 expectedLiquidatorPool = (totalFees * 1000) / 10000; // 10%
        uint256 expectedStakerPool = (totalFees * 3000) / 10000; // 30%
        
        // Distribute fees
        RewardDistributionFacet(address(diamond)).distributeProtocolFees(totalFees);
        
        // Verify pool balances after distribution
        RewardPools storage pools = getRewardPools();
        assertEq(pools.lenderPool, expectedLenderPool, "Lender pool not updated correctly");
        assertEq(pools.borrowerPool, expectedBorrowerPool, "Borrower pool not updated correctly");
        assertEq(pools.liquidatorPool, expectedLiquidatorPool, "Liquidator pool not updated correctly");
        assertEq(pools.stakerPool, expectedStakerPool, "Staker pool not updated correctly");
        
        // Verify protocol fees were reduced
        assertEq(getProtocolFees(), 0, "Protocol fees not reduced correctly");
        
        vm.stopPrank();
    }

    function test_UpdateRewardConfig() public {
        vm.startPrank(admin);
        
        uint256 newLenderShare = 3000;    // 30%
        uint256 newBorrowerShare = 3000;  // 30%
        uint256 newLiquidatorShare = 2000; // 20%
        uint256 newStakerShare = 2000;    // 20%
        
        // Update config
        RewardDistributionFacet(address(diamond)).updateRewardConfig(
            newLenderShare,
            newBorrowerShare,
            newLiquidatorShare,
            newStakerShare
        );
        
        // Verify config was updated
        RewardConfig storage config = getRewardConfig();
        assertEq(config.lenderShare, newLenderShare, "Lender share not updated");
        assertEq(config.borrowerShare, newBorrowerShare, "Borrower share not updated");
        assertEq(config.liquidatorShare, newLiquidatorShare, "Liquidator share not updated");
        assertEq(config.stakerShare, newStakerShare, "Staker share not updated");
        
        // Non-admin cannot update config
        vm.stopPrank();
        vm.startPrank(lender);
        
        vm.expectRevert("Not authorized");
        RewardDistributionFacet(address(diamond)).updateRewardConfig(
            newLenderShare,
            newBorrowerShare,
            newLiquidatorShare,
            newStakerShare
        );
        
        vm.stopPrank();
    }


    function test_InvalidRewardConfig() public {
        vm.startPrank(admin);
        
        // Total not equal to 100%
        vm.expectRevert("Shares must total 100%");
        RewardDistributionFacet(address(diamond)).updateRewardConfig(
            5000, // 50%
            3000, // 30%
            1000, // 10%
            500  // 5% (total: 95%)
        );
        
        vm.stopPrank();
    }

    function test_ClaimRewards() public {
        // First distribute fees to pools
        vm.startPrank(admin);
        RewardDistributionFacet(address(diamond)).distributeProtocolFees(PROTOCOL_FEES);
        vm.stopPrank();
        
        // Test claiming lender rewards
        vm.startPrank(lender);
        
        // Get expected rewards
        PoolType[] memory lenderPools = new PoolType[](1);
        lenderPools[0] = PoolType.LENDER;
        
        uint256 expectedRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(lender, PoolType.LENDER);
        assertTrue(expectedRewards > 0, "Expected lender rewards to be greater than 0");
        
        // Get balance before claim
        uint256 balanceBefore = protocolToken.balanceOf(lender);
        
        // Test reward distribution event
        vm.expectEmit(true, true, true, true);
        emit RewardDistributed(lender, address(protocolToken), expectedRewards);
        
        // Claim rewards
        RewardDistributionFacet(address(diamond)).claimRewards(lender, lenderPools);
        
        // Verify balance after claiming
        uint256 balanceAfter = protocolToken.balanceOf(lender);
        assertEq(balanceAfter, balanceBefore + expectedRewards, "Incorrect reward amount transferred");
        
        // Verify rewards are reset
        uint256 remainingRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(lender, PoolType.LENDER);
        assertEq(remainingRewards, 0, "Rewards should be reset after claiming");
        
        vm.stopPrank();
    }

    function test_ClaimMultiplePoolRewards() public {
        // First distribute fees to pools
        vm.startPrank(admin);
        RewardDistributionFacet(address(diamond)).distributeProtocolFees(PROTOCOL_FEES);
        
        // Setup user with multiple reward types
        LibAppStorage.Layout storage s = LibAppStorage.layout();
        
        address multiUser = address(0x6);
        // Setup lending activity
        s.userActivities[multiUser].totalLendingAmount = 40_000 ether;
        s.userActivities[multiUser].lastLenderRewardUpdate = block.timestamp - 30 days;
        
        // Setup borrowing activity
        s.userActivities[multiUser].totalBorrowingAmount = 20_000 ether;
        s.userActivities[multiUser].lastBorrowerRewardUpdate = block.timestamp - 30 days;
        
        // Setup liquidation activity
        s.userActivities[multiUser].totalLiquidationAmount = 5_000 ether;
        
        vm.stopPrank();
        
        // Test claiming from multiple pools
        vm.startPrank(multiUser);
        
        // Create array of pool types to claim from
        PoolType[] memory pools = new PoolType[](3);
        pools[0] = PoolType.LENDER;
        pools[1] = PoolType.BORROWER;
        pools[2] = PoolType.LIQUIDATOR;
        
        // Calculate expected rewards from each pool
        uint256 lenderRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(multiUser, PoolType.LENDER);
        uint256 borrowerRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(multiUser, PoolType.BORROWER);
        uint256 liquidatorRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(multiUser, PoolType.LIQUIDATOR);
        uint256 totalExpectedRewards = lenderRewards + borrowerRewards + liquidatorRewards;
        
        // Get balance before claim
        uint256 balanceBefore = protocolToken.balanceOf(multiUser);
        
        // Claim rewards from all pools
        RewardDistributionFacet(address(diamond)).claimRewards(multiUser, pools);
        
        // Verify balance after claiming
        uint256 balanceAfter = protocolToken.balanceOf(multiUser);
        assertEq(balanceAfter, balanceBefore + totalExpectedRewards, "Incorrect total reward amount");
        
        // Verify all rewards are reset
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 remainingRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(multiUser, pools[i]);
            assertEq(remainingRewards, 0, string(abi.encodePacked("Rewards for pool ", vm.toString(uint256(pools[i])), " should be reset")));
        }
        
        vm.stopPrank();
    }

    function test_RewardCalculations() public {
        // Test accurate reward calculations for different activity types
        
        // 1. Lender rewards calculation
        uint256 lenderRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(lender, PoolType.LENDER);
        
        // Verify against expected calculation
        LibAppStorage.Layout storage s = LibAppStorage.layout();
        uint256 lendingAmount = s.userActivities[lender].totalLendingAmount;
        uint256 timePassed = block.timestamp - s.userActivities[lender].lastLenderRewardUpdate;
        uint256 expectedLenderRewards = (lendingAmount * timePassed * s.rewardConfig.lenderRewardRate) / (365 days * 10000);
        
        assertEq(lenderRewards, expectedLenderRewards, "Lender reward calculation mismatch");
        
        // 2. Borrower rewards calculation
        uint256 borrowerRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(borrower, PoolType.BORROWER);
        
        uint256 borrowingAmount = s.userActivities[borrower].totalBorrowingAmount;
        uint256 borrowTimePassed = block.timestamp - s.userActivities[borrower].lastBorrowerRewardUpdate;
        uint256 expectedBorrowerRewards = (borrowingAmount * borrowTimePassed * s.rewardConfig.borrowerRewardRate) / (365 days * 10000);
        
        assertEq(borrowerRewards, expectedBorrowerRewards, "Borrower reward calculation mismatch");
        
        // 3. Liquidator rewards calculation
        uint256 liquidatorRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(liquidator, PoolType.LIQUIDATOR);
        
        uint256 liquidationAmount = s.userActivities[liquidator].totalLiquidationAmount;
        uint256 expectedLiquidatorRewards = (liquidationAmount * s.rewardConfig.liquidatorRewardRate) / 10000;
        
        assertEq(liquidatorRewards, expectedLiquidatorRewards, "Liquidator reward calculation mismatch");
        
        // 4. Staker rewards calculation
        uint256 stakerRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(staker, PoolType.STAKER);
        
        uint256 stakeAmount = s.userStakes[staker].amount;
        uint256 stakeTimePassed = block.timestamp - s.userStakes[staker].lockStart;
        uint256 multiplier = s.userStakes[staker].loyaltyMultiplier;
        uint256 expectedStakerRewards = (stakeAmount * stakeTimePassed * multiplier * s.rewardConfig.stakerRewardRate) 
            / (365 days * 10000 * 10000); // Divided by BASIS_POINTS twice
        
        assertEq(stakerRewards, expectedStakerRewards, "Staker reward calculation mismatch");
    }

    function test_InsufficientRewardsPool() public {
        // Setup: Add some rewards to the lender pool, but less than will be calculated
        vm.startPrank(admin);
        
        uint256 smallPoolAmount = 1 ether; // Small amount to pool
        LibAppStorage.Layout storage s = LibAppStorage.layout();
        s.rewardPools.lenderPool = smallPoolAmount;
        
        // Setup user with large expected rewards
        address testUser = address(0x7);
        s.userActivities[testUser].totalLendingAmount = 1_000_000 ether; // Large lending amount
        s.userActivities[testUser].lastLenderRewardUpdate = block.timestamp - 180 days; // Long time period
        
        vm.stopPrank();
        
        // Calculate expected reward (which will be higher than pool balance)
        uint256 expectedReward = RewardDistributionFacet(address(diamond)).calculatePoolRewards(testUser, PoolType.LENDER);
        assertTrue(expectedReward > smallPoolAmount, "Test requires expected reward > pool balance");
        
        // Claim rewards (should be limited by pool balance)
        vm.startPrank(testUser);
        
        PoolType[] memory pools = new PoolType[](1);
        pools[0] = PoolType.LENDER;
        
        uint256 balanceBefore = protocolToken.balanceOf(testUser);
        RewardDistributionFacet(address(diamond)).claimRewards(testUser, pools);
        uint256 balanceAfter = protocolToken.balanceOf(testUser);
        
        // Verify only pool balance was transferred, not full expected reward
        assertEq(balanceAfter - balanceBefore, smallPoolAmount, "Should only receive amount available in pool");
        
        // Verify pool is now empty
        assertEq(s.rewardPools.lenderPool, 0, "Pool should be emptied");
        
        vm.stopPrank();
    }

    function test_EmptyPoolClaim() public {
        // Setup user with rewards from empty pool
        vm.startPrank(admin);
        
        address testUser = address(0x8);
        LibAppStorage.Layout storage s = LibAppStorage.layout();
        s.userActivities[testUser].totalLendingAmount = 10_000 ether;
        s.userActivities[testUser].lastLenderRewardUpdate = block.timestamp - 30 days;
        
        // Ensure pool is empty
        s.rewardPools.lenderPool = 0;
        
        vm.stopPrank();
        
        // Try to claim from empty pool
        vm.startPrank(testUser);
        
        PoolType[] memory pools = new PoolType[](1);
        pools[0] = PoolType.LENDER;
        
        // Should revert because there are no rewards to claim
        vm.expectRevert("No rewards to claim");
        RewardDistributionFacet(address(diamond)).claimRewards(testUser, pools);
        
        vm.stopPrank();
    }

    function test_NonExistentUserClaim() public {
        // First distribute fees to pools to ensure they have funds
        vm.startPrank(admin);
        RewardDistributionFacet(address(diamond)).distributeProtocolFees(10_000 ether);
        vm.stopPrank();
        
        // Address that has no activity in the protocol
        address nonUser = address(0x9);
        
        vm.startPrank(nonUser);
        
        PoolType[] memory pools = new PoolType[](1);
        pools[0] = PoolType.LENDER;
        
        // Should revert because there are no rewards to claim
        vm.expectRevert("No rewards to claim");
        RewardDistributionFacet(address(diamond)).claimRewards(nonUser, pools);
        
        vm.stopPrank();
    }

    function test_GetPendingRewards() public {
        // Setup user with multiple reward types
        vm.startPrank(admin);
        
        address testUser = address(0xA);
        LibAppStorage.Layout storage s = LibAppStorage.layout();
        
        // Setup activity in all reward pools
        s.userActivities[testUser].totalLendingAmount = 40_000 ether;
        s.userActivities[testUser].lastLenderRewardUpdate = block.timestamp - 30 days;
        
        s.userActivities[testUser].totalBorrowingAmount = 20_000 ether;
        s.userActivities[testUser].lastBorrowerRewardUpdate = block.timestamp - 30 days;
        
        s.userActivities[testUser].totalLiquidationAmount = 5_000 ether;
        
        s.userStakes[testUser].amount = 15_000 ether;
        s.userStakes[testUser].lockStart = block.timestamp - 45 days;
        s.userStakes[testUser].loyaltyMultiplier = 12500; // 1.25x
        
        // Add referral rewards
        s.referralRewards[testUser] = 2_000 ether;
        
        vm.stopPrank();
        
        // Get pending rewards
        (
            uint256 lenderRewards,
            uint256 borrowerRewards,
            uint256 liquidatorRewards,
            uint256 stakerRewards,
            uint256 referralRewards,
            uint256 totalRewards
        ) = RewardDistributionFacet(address(diamond)).getPendingRewards(testUser);
        
        // Verify each reward type is calculated correctly
        uint256 expectedLenderRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(testUser, PoolType.LENDER);
        uint256 expectedBorrowerRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(testUser, PoolType.BORROWER);
        uint256 expectedLiquidatorRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(testUser, PoolType.LIQUIDATOR);
        uint256 expectedStakerRewards = RewardDistributionFacet(address(diamond)).calculatePoolRewards(testUser, PoolType.STAKER);
        uint256 expectedReferralRewards = s.referralRewards[testUser];
        
        assertEq(lenderRewards, expectedLenderRewards, "Lender rewards mismatch");
        assertEq(borrowerRewards, expectedBorrowerRewards, "Borrower rewards mismatch");
        assertEq(liquidatorRewards, expectedLiquidatorRewards, "Liquidator rewards mismatch");
        assertEq(stakerRewards, expectedStakerRewards, "Staker rewards mismatch");
        assertEq(referralRewards, expectedReferralRewards, "Referral rewards mismatch");
        
        // Verify total is correct sum
        uint256 expectedTotal = expectedLenderRewards + expectedBorrowerRewards + 
                               expectedLiquidatorRewards + expectedStakerRewards + 
                               expectedReferralRewards;
        assertEq(totalRewards, expectedTotal, "Total rewards calculation incorrect");
    }

    // Helper function to get function selectors
    function getFunctionSelectors(string memory _facetName) internal pure returns (bytes4[] memory selectors) {
        if (keccak256(abi.encodePacked(_facetName)) == keccak256(abi.encodePacked("DiamondLoupeFacet"))) {
            selectors = new bytes4[](5);
            selectors[0] = DiamondLoupeFacet.facets.selector;
            selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
            selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
            selectors[3] = DiamondLoupeFacet.facetAddress.selector;
            selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
        } else if (keccak256(abi.encodePacked(_facetName)) == keccak256(abi.encodePacked("RewardDistributionFacet"))) {
            selectors = new bytes4[](10);
            selectors[0] = RewardDistributionFacet.initializeRewardDistribution.selector;
            selectors[1] = RewardDistributionFacet.distributeProtocolFees.selector;
            selectors[2] = RewardDistributionFacet.claimRewards.selector;
            selectors[3] = RewardDistributionFacet.updateRewardConfig.selector;
            selectors[4] = RewardDistributionFacet.calculatePoolRewards.selector;
            selectors[5] = RewardDistributionFacet.pauseRewards.selector;
            selectors[6] = RewardDistributionFacet.unpauseRewards.selector;
            selectors[7] = RewardDistributionFacet.addToRewardPool.selector;
            selectors[8] = RewardDistributionFacet.addReferralReward.selector;
            selectors[9] = RewardDistributionFacet.getPendingRewards.selector;
        }
        return selectors;
    }
}