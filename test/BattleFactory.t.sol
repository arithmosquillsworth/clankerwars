// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BattleFactory.sol";

contract BattleFactoryTest is Test {
    BattleFactory public factory;
    
    address public owner = address(1);
    address public coreContract = address(2);
    address public oracleContract = address(3);
    address public creator = address(4);
    address public agentA = address(5);
    address public agentB = address(6);
    address public market = address(7);
    
    function setUp() public {
        vm.startPrank(owner);
        factory = new BattleFactory();
        factory.setCoreContracts(coreContract, oracleContract);
        factory.addMarket(market);
        factory.addBattleCreator(creator);
        vm.stopPrank();
    }
    
    function test_CreateBattle() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        assertEq(battleId, 1);
        
        ClankerWarsTypes.Battle memory battle = factory.getBattle(battleId);
        assertEq(battle.agentA, agentA);
        assertEq(battle.agentB, agentB);
        assertEq(battle.market, market);
        assertEq(uint256(battle.status), uint256(ClankerWarsTypes.BattleStatus.Active));
        
        assertTrue(factory.isInBattle(agentA));
        assertTrue(factory.isInBattle(agentB));
    }
    
    function test_Revert_CreateBattle_SameAgent() public {
        vm.prank(creator);
        vm.expectRevert(BattleFactory.SameAgent.selector);
        factory.createBattle(agentA, agentA, market, 4 hours);
    }
    
    function test_Revert_CreateBattle_InvalidMarket() public {
        vm.prank(creator);
        vm.expectRevert(BattleFactory.InvalidMarket.selector);
        factory.createBattle(agentA, agentB, address(0), 4 hours);
    }
    
    function test_Revert_CreateBattle_InvalidDuration() public {
        vm.prank(creator);
        vm.expectRevert(BattleFactory.InvalidDuration.selector);
        factory.createBattle(agentA, agentB, market, 30 minutes);
    }
    
    function test_Revert_CreateBattle_AgentInBattle() public {
        vm.prank(creator);
        factory.createBattle(agentA, agentB, market, 4 hours);
        
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(BattleFactory.AgentInBattle.selector, agentA));
        factory.createBattle(agentA, address(8), market, 4 hours);
    }
    
    function test_ResolveBattle() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        // Warp past end time
        vm.warp(block.timestamp + 5 hours);
        
        vm.prank(oracleContract);
        factory.resolveBattle(battleId, agentA, keccak256("result"));
        
        ClankerWarsTypes.Battle memory battle = factory.getBattle(battleId);
        assertEq(battle.winner, agentA);
        assertEq(uint256(battle.status), uint256(ClankerWarsTypes.BattleStatus.Resolved));
        
        assertFalse(factory.isInBattle(agentA));
        assertFalse(factory.isInBattle(agentB));
    }
    
    function test_Revert_ResolveBattle_TooEarly() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        // Try to resolve before end time
        vm.prank(oracleContract);
        vm.expectRevert(BattleFactory.BattleStillActive.selector);
        factory.resolveBattle(battleId, agentA, keccak256("result"));
    }
    
    function test_CancelBattle() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        vm.prank(coreContract);
        factory.cancelBattle(battleId, "Test cancellation");
        
        ClankerWarsTypes.Battle memory battle = factory.getBattle(battleId);
        assertEq(uint256(battle.status), uint256(ClankerWarsTypes.BattleStatus.Cancelled));
        
        assertFalse(factory.isInBattle(agentA));
        assertFalse(factory.isInBattle(agentB));
    }
    
    function test_UpdateStakePools() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        vm.prank(coreContract);
        factory.updateStakePools(battleId, 1000e6, 2000e6);
        
        ClankerWarsTypes.Battle memory battle = factory.getBattle(battleId);
        assertEq(battle.stakePoolA, 1000e6);
        assertEq(battle.stakePoolB, 2000e6);
    }
    
    function test_AddRemoveMarket() public {
        address newMarket = address(8);
        
        vm.prank(owner);
        factory.addMarket(newMarket);
        assertTrue(factory.validMarkets(newMarket));
        
        vm.prank(owner);
        factory.removeMarket(newMarket);
        assertFalse(factory.validMarkets(newMarket));
    }
    
    function test_AddRemoveBattleCreator() public {
        address newCreator = address(9);
        
        vm.prank(owner);
        factory.addBattleCreator(newCreator);
        assertTrue(factory.isBattleCreator(newCreator));
        
        vm.prank(owner);
        factory.removeBattleCreator(newCreator);
        assertFalse(factory.isBattleCreator(newCreator));
    }
    
    function test_GetBattles() public {
        vm.prank(creator);
        factory.createBattle(agentA, agentB, market, 4 hours);
        
        vm.warp(block.timestamp + 1); // Different timestamp
        vm.prank(creator);
        factory.createBattle(address(10), address(11), market, 4 hours);
        
        ClankerWarsTypes.Battle[] memory battles = factory.getBattles(0, 10);
        assertEq(battles.length, 2);
    }
    
    function test_CanResolve() public {
        vm.prank(creator);
        uint256 battleId = factory.createBattle(agentA, agentB, market, 4 hours);
        
        assertFalse(factory.canResolve(battleId));
        
        vm.warp(block.timestamp + 5 hours);
        assertTrue(factory.canResolve(battleId));
    }
}
