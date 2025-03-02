// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../contracts/facets/YieldOptimizationFacet.sol";
// import "../contracts/libraries/LibDiamond.sol";
// import "../contracts/libraries/LibAppStorage.sol";
// import "../contracts/mocks/MockERC20.sol";
// import "../contracts/Diamond.sol";
// import "../contracts/facets/DiamondCutFacet.sol";
// import "../contracts/facets/DiamondLoupeFacet.sol";
// import "../contracts/upgradeInitializers/DiamondInit.sol";

// contract YieldOptimizationTest is Test {
//     // Diamond and facets
//     Diamond diamond;
//     DiamondCutFacet dCutFacet;
//     DiamondLoupeFacet dLoupe;
//     YieldOptimizationFacet yieldFacet;
//     DiamondInit diamondInit;

//     // Mock tokens
//     MockERC20 protocolToken;
//     MockERC20 rewardToken;

//     // Test users
//     address admin = address(0x1);
//     address user1 = address(0x2);
//     address user2 = address(0x3);
//     address user3 = address(0x4);

//     // Constants
//     uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
//     uint256 constant STAKE_AMOUNT = 10_000 * 10 ** 18;
//     uint256 constant MIN_LOCK_PERIOD = 7 days;
//     uint256 constant MAX_LOCK_PERIOD = 365 days;
//     uint256 constant BASIS_POINTS = 10000;

//     // Events to test
//     event Staked(address indexed user, uint256 amount, uint256 duration);
//     event Unstaked(address indexed user, uint256 amount);
//     event YieldStrategyUpdated(uint256 strategyId, uint256[] allocationWeights);
//     event CompoundingExecuted(
//         address indexed user,
//         address indexed token,
//         uint256 amount
//     );
//     event YieldSystemInitialized(address indexed rewardToken);

//     function setUp() public {
//         vm.startPrank(admin);

//         // Create and deploy mock tokens
//         protocolToken = new MockERC20("Protocol Token", "PTKN", 18);
//         rewardToken = new MockERC20("Reward Token", "RTKN", 18);

//         // Mint initial supplies
//         protocolToken.mint(admin, INITIAL_SUPPLY);
//         rewardToken.mint(admin, INITIAL_SUPPLY);

//         // Distribute tokens to test users
//         protocolToken.transfer(user1, 100_000 * 10 ** 18);
//         protocolToken.transfer(user2, 100_000 * 10 ** 18);
//         protocolToken.transfer(user3, 100_000 * 10 ** 18);

//         // Create and deploy Diamond and facets
//         dCutFacet = new DiamondCutFacet();
//         diamond = new Diamond(admin, address(dCutFacet));
//         dLoupe = new DiamondLoupeFacet();
//         yieldFacet = new YieldOptimizationFacet();
//         diamondInit = new DiamondInit();

//         // Build cut struct for diamond initialization
//         IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](2);

//         // DiamondLoupeFacet
//         cuts[0] = IDiamondCut.FacetCut({
//             facetAddress: address(dLoupe),
//             action: IDiamondCut.FacetCutAction.Add,
//             functionSelectors: getFunctionSelectors("DiamondLoupeFacet")
//         });

//         // YieldOptimizationFacet
//         cuts[1] = IDiamondCut.FacetCut({
//             facetAddress: address(yieldFacet),
//             action: IDiamondCut.FacetCutAction.Add,
//             functionSelectors: getFunctionSelectors("YieldOptimizationFacet")
//         });

//         // Initialize diamond with cuts
//         bytes memory initData = abi.encodeWithSelector(
//             DiamondInit.init.selector,
//             address(protocolToken)
//         );

//         IDiamondCut(address(diamond)).diamondCut(
//             cuts,
//             address(diamondInit),
//             initData
//         );

//         address[] memory tokens;
//         address[] memory priceFeeds;

//         diamond.initialize(tokens, priceFeeds, address(protocolToken));

//         // Initialize the yield system
//         YieldOptimizationFacet(payable(address(diamond))).initializeYieldSystem(
//             address(rewardToken)
//         );

//         // Mint rewards to the contract
//         rewardToken.mint(address(diamond), 10_000_000 * 10 ** 18);

//         vm.stopPrank();
//     }

//     function test_InitializeYieldSystem() public {
//         vm.startPrank(admin);

//         // Create new diamond for this test
//         DiamondCutFacet newCutFacet = new DiamondCutFacet();
//         Diamond newDiamond = new Diamond(admin, address(newCutFacet));
//         YieldOptimizationFacet newYieldFacet = new YieldOptimizationFacet();

//         // Add facet to diamond
//         IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
//         cuts[0] = IDiamondCut.FacetCut({
//             facetAddress: address(newYieldFacet),
//             action: IDiamondCut.FacetCutAction.Add,
//             functionSelectors: getFunctionSelectors("YieldOptimizationFacet")
//         });

//         IDiamondCut(address(newDiamond)).diamondCut(cuts, address(0), "");

//         // Test initialization
//         vm.expectEmit(true, true, true, true);
//         emit YieldSystemInitialized(address(rewardToken));

//         YieldOptimizationFacet(payable(address(newDiamond)))
//             .initializeYieldSystem(address(rewardToken));

//         // Test can't initialize twice
//         vm.expectRevert("Already initialized");
//         YieldOptimizationFacet(payable(address(newDiamond)))
//             .initializeYieldSystem(address(rewardToken));

//         vm.stopPrank();
//     }

//     function test_StakeTokens() public {
//         vm.startPrank(user1);

//         uint256 stakeAmount = 10_000 * 10 ** 18;
//         uint256 lockDuration = 90 days;

//         // Approve tokens
//         protocolToken.approve(address(diamond), stakeAmount);

//         // Calculate expected multiplier
//         uint256 expectedMultiplier = BASIS_POINTS +
//             (lockDuration * BASIS_POINTS) /
//             MAX_LOCK_PERIOD;

//         // Test stake event
//         vm.expectEmit(true, true, true, true);
//         emit Staked(user1, stakeAmount, lockDuration);

//         // Stake tokens
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             lockDuration,
//             true
//         );

//         // Get user stake info
//         (
//             uint256 amount,
//             uint256 lockEnd,
//             uint256 loyaltyMultiplier,
//             uint256 pendingRewards
//         ) = YieldOptimizationFacet(payable(address(diamond))).getUserStakeInfo(
//                 user1
//             );

//         // Verify stake info
//         assertEq(amount, stakeAmount, "Stake amount incorrect");
//         assertEq(lockEnd, block.timestamp + lockDuration, "Lock end incorrect");
//         assertEq(
//             loyaltyMultiplier,
//             expectedMultiplier,
//             "Loyalty multiplier incorrect"
//         );
//         assertEq(pendingRewards, 0, "Initial pending rewards should be 0");

//         vm.stopPrank();
//     }

//     function test_StakeTokensInvalidDuration() public {
//         vm.startPrank(user1);

//         uint256 stakeAmount = 10_000 * 10 ** 18;

//         // Approve tokens
//         protocolToken.approve(address(diamond), stakeAmount);

//         // Test too short duration
//         uint256 tooShortDuration = 6 days;
//         vm.expectRevert("Invalid duration");
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             tooShortDuration,
//             true
//         );

//         // Test too long duration
//         uint256 tooLongDuration = 366 days;
//         vm.expectRevert("Invalid duration");
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             tooLongDuration,
//             true
//         );

//         vm.stopPrank();
//     }

//     function test_UnstakeTokens() public {
//         // First stake some tokens
//         vm.startPrank(user1);
//         uint256 stakeAmount = 10_000 * 10 ** 18;
//         uint256 lockDuration = 30 days;

//         protocolToken.approve(address(diamond), stakeAmount);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             lockDuration,
//             false
//         );

//         // Try to unstake before lock period ends
//         vm.expectRevert("Still locked");
//         YieldOptimizationFacet(payable(address(diamond))).unstake(stakeAmount);

//         // Fast forward past lock period
//         vm.warp(block.timestamp + lockDuration + 1);

//         // Test unstake event
//         vm.expectEmit(true, true, true, true);
//         emit Unstaked(user1, stakeAmount);

//         // Balance before unstake
//         uint256 balanceBefore = protocolToken.balanceOf(user1);

//         // balance of protocol
//         uint256 protocolTokenBalance = protocolToken.balanceOf(
//             address(diamond)
//         );

//         console.log(protocolTokenBalance);

//         // Unstake tokens
//         YieldOptimizationFacet(payable(address(diamond))).unstake(stakeAmount);

//         // Verify balance after unstake
//         uint256 balanceAfter = protocolToken.balanceOf(user1);
//         assertEq(
//             balanceAfter,
//             balanceBefore + stakeAmount,
//             "Unstaked amount not received"
//         );

//         // Verify stake is cleared
//         (uint256 amount, , , ) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user1);
//         assertEq(amount, 0, "Stake not fully unstaked");

//         vm.stopPrank();
//     }

//     function test_UpdateStrategy() public {
//         vm.startPrank(admin);

//         uint256 strategyId = 1;
//         uint256[] memory allocationWeights = new uint256[](3);
//         allocationWeights[0] = 5000; // 50%
//         allocationWeights[1] = 3000; // 30%
//         allocationWeights[2] = 2000; // 20%

//         // Test strategy update event
//         vm.expectEmit(true, true, true, true);
//         emit YieldStrategyUpdated(strategyId, allocationWeights);

//         // Update strategy
//         YieldOptimizationFacet(payable(address(diamond))).updateStrategy(
//             strategyId,
//             allocationWeights
//         );

//         // Non-admin cannot update strategy
//         vm.stopPrank();
//         vm.startPrank(user1);

//         vm.expectRevert("Not authorized");
//         YieldOptimizationFacet(payable(address(diamond))).updateStrategy(
//             strategyId,
//             allocationWeights
//         );

//         vm.stopPrank();
//     }

//     function test_InvalidStrategyUpdate() public {
//         vm.startPrank(admin);

//         uint256 strategyId = 1;
//         uint256[] memory invalidWeights = new uint256[](3);
//         invalidWeights[0] = 5000; // 50%
//         invalidWeights[1] = 3000; // 30%
//         invalidWeights[2] = 1000; // 10% (total only 90%)

//         // Total doesn't equal 100%
//         vm.expectRevert("Weights must total 100%");
//         YieldOptimizationFacet(payable(address(diamond))).updateStrategy(
//             strategyId,
//             invalidWeights
//         );

//         vm.stopPrank();
//     }

//     function test_RewardAccrual() public {
//         // Setup: stake tokens and fast forward time
//         vm.startPrank(user1);
//         uint256 stakeAmount = 50_000 * 10 ** 18;
//         uint256 lockDuration = 90 days;

//         protocolToken.approve(address(diamond), stakeAmount);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             lockDuration,
//             false
//         );

//         // Fast forward 30 days
//         vm.warp(block.timestamp + 30 days);

//         // Check pending rewards
//         (, , , uint256 pendingRewards) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user1);
//         assertTrue(pendingRewards > 0, "No rewards accrued after time passed");

//         // Claim rewards
//         uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
//         YieldOptimizationFacet(payable(address(diamond))).claimRewards();
//         uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);

//         // Verify rewards were transferred
//         assertEq(
//             rewardBalanceAfter,
//             rewardBalanceBefore + pendingRewards,
//             "Rewards not transferred correctly"
//         );

//         // Check that pending rewards are reset
//         (, , , pendingRewards) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user1);
//         assertEq(pendingRewards, 0, "Pending rewards not reset after claim");

//         vm.stopPrank();
//     }

//     function test_AutoCompounding() public {
//         // Setup: Admin mints reward tokens to the diamond for distribution
//         vm.startPrank(admin);
//         rewardToken.mint(address(diamond), 100_000 * 10 ** 18);
//         vm.stopPrank();

//         // User stakes with auto-compound enabled
//         vm.startPrank(user2);
//         uint256 stakeAmount = 20_000 * 10 ** 18;
//         uint256 lockDuration = 180 days;

//         protocolToken.approve(address(diamond), stakeAmount);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             lockDuration,
//             true
//         );

//         // Fast forward 30 days
//         vm.warp(block.timestamp + 30 days);

//         // Check pending rewards before compounding
//         (, , , uint256 pendingRewardsBefore) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user2);
//         assertTrue(pendingRewardsBefore > 0, "No rewards accrued");

//         // Execute auto-compounding (can be called by anyone, typically by a keeper)
//         vm.stopPrank();
//         vm.startPrank(admin);

//         YieldOptimizationFacet(payable(address(diamond)))
//             .executeAutoCompounding();

//         // Check stake amount after compounding
//         (
//             uint256 newStakeAmount,
//             ,
//             ,
//             uint256 pendingRewardsAfter
//         ) = YieldOptimizationFacet(payable(address(diamond))).getUserStakeInfo(
//                 user2
//             );

//         // Verify stake increased and rewards were reset
//         assertTrue(
//             newStakeAmount > stakeAmount,
//             "Stake not increased after compounding"
//         );
//         assertEq(pendingRewardsAfter, 0, "Rewards not reset after compounding");
//         assertEq(
//             newStakeAmount,
//             stakeAmount + pendingRewardsBefore,
//             "Compounded amount incorrect"
//         );

//         vm.stopPrank();
//     }

//     function test_MultipleUsers_RewardDistribution() public {
//         // Setup: Three users with different stake amounts and durations

//         // User 1: Large stake, medium duration
//         vm.startPrank(user1);
//         uint256 stakeAmount1 = 50_000 * 10 ** 18;
//         uint256 lockDuration1 = 90 days;
//         protocolToken.approve(address(diamond), stakeAmount1);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount1,
//             lockDuration1,
//             false
//         );
//         vm.stopPrank();

//         // User 2: Medium stake, long duration
//         vm.startPrank(user2);
//         uint256 stakeAmount2 = 30_000 * 10 ** 18;
//         uint256 lockDuration2 = 180 days;
//         protocolToken.approve(address(diamond), stakeAmount2);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount2,
//             lockDuration2,
//             true
//         );
//         vm.stopPrank();

//         // User 3: Small stake, short duration
//         vm.startPrank(user3);
//         uint256 stakeAmount3 = 10_000 * 10 ** 18;
//         uint256 lockDuration3 = 30 days;
//         protocolToken.approve(address(diamond), stakeAmount3);
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount3,
//             lockDuration3,
//             false
//         );
//         vm.stopPrank();

//         // Fast forward 60 days
//         vm.warp(block.timestamp + 60 days);

//         // Get rewards for all users
//         (, , , uint256 rewards1) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user1);
//         (, , , uint256 rewards2) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user2);
//         (, , , uint256 rewards3) = YieldOptimizationFacet(
//             payable(address(diamond))
//         ).getUserStakeInfo(user3);

//         // Verify reward distribution is proportional to stake and multipliers
//         // User 2 should have highest rewards due to longer lock (higher multiplier)
//         assertTrue(
//             rewards2 > rewards3,
//             "User with longer lock should have higher rewards"
//         );

//         // User 1 should have higher rewards than User 3 due to larger stake
//         assertTrue(
//             rewards1 > rewards3,
//             "User with larger stake should have higher rewards"
//         );

//         console.log("User 1 rewards:", rewards1);
//         console.log("User 2 rewards:", rewards2);
//         console.log("User 3 rewards:", rewards3);
//     }

//     function test_LoyaltyMultiplierEffects() public {
//         // Test with different lock durations to verify loyalty multiplier effects

//         // Stake with minimum duration (7 days)
//         vm.startPrank(user1);
//         uint256 stakeAmount = 10_000 * 10 ** 18;
//         protocolToken.approve(address(diamond), stakeAmount * 3); // Approve for all three stakes

//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             7 days,
//             false
//         );

//         // Stake with medium duration (180 days)
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             180 days,
//             false
//         );

//         // Stake with maximum duration (365 days)
//         YieldOptimizationFacet(payable(address(diamond))).stake(
//             stakeAmount,
//             365 days,
//             false
//         );

//         // Fast forward 30 days
//         vm.warp(block.timestamp + 30 days);

//         // Calculate expected multipliers
//         uint256 shortMultiplier = BASIS_POINTS +
//             (7 days * BASIS_POINTS) /
//             MAX_LOCK_PERIOD;
//         uint256 mediumMultiplier = BASIS_POINTS +
//             (180 days * BASIS_POINTS) /
//             MAX_LOCK_PERIOD;
//         uint256 maxMultiplier = BASIS_POINTS +
//             (365 days * BASIS_POINTS) /
//             MAX_LOCK_PERIOD;

//         // Expected multipliers: ~10% for 7 days, ~50% for 180 days, 100% for 365 days
//         assertTrue(
//             mediumMultiplier > shortMultiplier,
//             "Medium multiplier should be higher than short"
//         );
//         assertTrue(
//             maxMultiplier > mediumMultiplier,
//             "Max multiplier should be higher than medium"
//         );
//         assertEq(
//             maxMultiplier,
//             BASIS_POINTS * 2,
//             "Max multiplier should be 2x"
//         );

//         vm.stopPrank();
//     }

//     // Helper function to get function selectors from a facet
//     function getFunctionSelectors(
//         string memory _facetName
//     ) internal returns (bytes4[] memory selectors) {
//         if (
//             keccak256(abi.encodePacked(_facetName)) ==
//             keccak256(abi.encodePacked("DiamondLoupeFacet"))
//         ) {
//             selectors = new bytes4[](5);
//             selectors[0] = DiamondLoupeFacet.facets.selector;
//             selectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
//             selectors[2] = DiamondLoupeFacet.facetAddresses.selector;
//             selectors[3] = DiamondLoupeFacet.facetAddress.selector;
//             selectors[4] = DiamondLoupeFacet.supportsInterface.selector;
//         } else if (
//             keccak256(abi.encodePacked(_facetName)) ==
//             keccak256(abi.encodePacked("YieldOptimizationFacet"))
//         ) {
//             selectors = new bytes4[](9);
//             selectors[0] = YieldOptimizationFacet
//                 .initializeYieldSystem
//                 .selector;
//             selectors[1] = YieldOptimizationFacet.stake.selector;
//             selectors[2] = YieldOptimizationFacet.unstake.selector;
//             selectors[3] = YieldOptimizationFacet.claimRewards.selector;
//             selectors[4] = YieldOptimizationFacet.updateStrategy.selector;
//             selectors[5] = YieldOptimizationFacet
//                 .executeAutoCompounding
//                 .selector;
//             selectors[6] = YieldOptimizationFacet.updateBoostTiers.selector;
//             selectors[7] = YieldOptimizationFacet.getUserStakeInfo.selector;
//             selectors[8] = bytes4(keccak256("receive()"));
//         }
//         return selectors;
//     }
// }
