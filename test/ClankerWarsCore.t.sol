// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ClankerWarsCore.sol";
import "../src/mocks/MockOracle.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Test USDC", "TUSDC") {
        _mint(msg.sender, 1000000 * 10**6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ClankerWarsCoreTest is Test {
    ClankerWarsCore public core;
    MockOracle public oracle;
    MockERC20 public token;
    
    address public owner = address(1);
    address public treasury = address(2);
    address public agentA = address(3);
    address public agentB = address(4);
    address public user1 = address(5);
    address public user2 = address(6);
    address public market = address(7);
    
    bytes32 public constant STRATEGY_HASH_A = keccak256("strategy_a");
    bytes32 public constant STRATEGY_HASH_B = keccak256("strategy_b");
    
    function setUp() public {
        vm.startPrank(owner);
        token = new MockERC20();
        core = new ClankerWarsCore(address(token), treasury);
        
        oracle = new MockOracle(address(core));
        core.initializeOracle(address(oracle));
        
        core.battleFactory().addMarket(market);
        core.battleFactory().addBattleCreator(owner);
        
        // Enable auto-resolve for oracle
        oracle.setAutoResolve(false, address(0));
        vm.stopPrank();
        
        // Fund agents and users
        vm.deal(agentA, 1 ether);
        vm.deal(agentB, 1 ether);
        token.mint(user1, 10000e6);
        token.mint(user2, 10000e6);
    }
    
    function test_FullBattleFlow() public {
        // 1. Register agents
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        assertTrue(core.agentRegistry().isAgent(agentA));
        assertTrue(core.agentRegistry().isAgent(agentB));
        
        // 2. Create battle
        vm.prank(owner);
        uint256 battleId = core.createBattle(agentA, agentB, market, 4 hours);
        
        assertEq(battleId, 1);
        
        // 3. Users place stakes
        vm.startPrank(user1);
        token.approve(address(core), 500e6);
        core.placeStake(battleId, agentA, 500e6);
        vm.stopPrank();
        
        vm.startPrank(user2);
        token.approve(address(core), 300e6);
        core.placeStake(battleId, agentB, 300e6);
        vm.stopPrank();
        
        // Verify stakes
        assertEq(core.stakingPool().totalStakedOnAgent(battleId, agentA), 500e6);
        assertEq(core.stakingPool().totalStakedOnAgent(battleId, agentB), 300e6);
        
        // 4. Wait for battle to end
        vm.warp(block.timestamp + 5 hours);
        
        // 5. Resolve battle (agentA wins)
        vm.prank(owner);
        core.finalizeResolution(battleId, agentA, keccak256("agent_a_wins"));
        
        // 6. Verify ELO updates
        ClankerWarsTypes.Agent memory agentAData = core.agentRegistry().getAgent(agentA);
        assertEq(agentAData.wins, 1);
        assertGt(agentAData.eloRating, 1200);
        
        ClankerWarsTypes.Agent memory agentBData = core.agentRegistry().getAgent(agentB);
        assertEq(agentBData.losses, 1);
        assertLt(agentBData.eloRating, 1200);
        
        // 7. Winner claims prize
        uint256 user1BalanceBefore = token.balanceOf(user1);
        
        vm.prank(user1);
        core.claimWinnings(battleId, agentA);
        
        uint256 user1BalanceAfter = token.balanceOf(user1);
        
        // User1 should get their stake back + share of losing pool (minus protocol fee)
        // Total pool: 800, Fee: 20 (2.5%), Prize: 780
        // User1 staked 500/500 on winning side, gets full 780 + original 500
        // Actually they get 780 (prize) proportional to their stake
        assertGt(user1BalanceAfter, user1BalanceBefore);
    }
    
    function test_StakingAndClaiming() public {
        // Setup
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        vm.prank(owner);
        uint256 battleId = core.createBattle(agentA, agentB, market, 4 hours);
        
        // User stakes
        vm.startPrank(user1);
        token.approve(address(core), 100e6);
        core.placeStake(battleId, agentA, 100e6);
        vm.stopPrank();
        
        assertEq(core.stakingPool().userTotalStake(user1), 100e6);
        
        // Resolve battle
        vm.warp(block.timestamp + 5 hours);
        vm.prank(owner);
        core.finalizeResolution(battleId, agentA, keccak256("result"));
        
        // Claim
        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        core.claimWinnings(battleId, agentA);
        uint256 balanceAfter = token.balanceOf(user1);
        
        assertGt(balanceAfter, balanceBefore);
    }
    
    function test_AutoMatchmaking() public {
        // Register agents
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        // Find match
        vm.prank(owner);
        uint256 battleId = core.findMatch(agentA, market, 4 hours);
        
        assertEq(battleId, 1);
        
        ClankerWarsTypes.Battle memory battle = core.battleFactory().getBattle(battleId);
        assertTrue(battle.agentA == agentA || battle.agentB == agentA);
    }
    
    function test_ProtocolFeeAccumulation() public {
        // Setup and run battle
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        vm.prank(owner);
        uint256 battleId = core.createBattle(agentA, agentB, market, 4 hours);
        
        vm.startPrank(user1);
        token.approve(address(core), 1000e6);
        core.placeStake(battleId, agentA, 1000e6);
        vm.stopPrank();
        
        vm.startPrank(user2);
        token.approve(address(core), 1000e6);
        core.placeStake(battleId, agentB, 1000e6);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 5 hours);
        vm.prank(owner);
        core.finalizeResolution(battleId, agentA, keccak256("result"));
        
        // Check fee accumulation
        uint256 expectedFee = 2000e6 * 250 / 10000; // 2.5% of 2000
        assertEq(core.prizeDistributor().accumulatedFees(), expectedFee);
        
        // Withdraw fees
        uint256 treasuryBalanceBefore = token.balanceOf(treasury);
        
        vm.prank(owner);
        core.prizeDistributor().withdrawFees();
        
        uint256 treasuryBalanceAfter = token.balanceOf(treasury);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedFee);
    }
    
    function test_Revert_UnauthorizedStake() public {
        // Setup battle
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        // Don't create battle, try to stake on non-existent battle
        vm.startPrank(user1);
        token.approve(address(core), 100e6);
        vm.expectRevert();
        core.placeStake(999, agentA, 100e6);
        vm.stopPrank();
    }
    
    function test_GetBattleInfo() public {
        vm.prank(agentA);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_A, "ipfs://agentA");
        
        vm.prank(agentB);
        core.registerAgent{value: 0.001 ether}(STRATEGY_HASH_B, "ipfs://agentB");
        
        vm.prank(owner);
        uint256 battleId = core.createBattle(agentA, agentB, market, 4 hours);
        
        (ClankerWarsTypes.Battle memory battle, 
         ClankerWarsTypes.Agent memory agentAData,
         ClankerWarsTypes.Agent memory agentBData) = core.getBattleInfo(battleId);
        
        assertEq(battle.agentA, agentA);
        assertEq(agentAData.strategyHash, STRATEGY_HASH_A);
        assertEq(agentBData.strategyHash, STRATEGY_HASH_B);
    }
}
