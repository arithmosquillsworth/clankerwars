// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    
    address public owner = address(1);
    address public agent1 = address(2);
    address public agent2 = address(3);
    address public user = address(4);
    
    bytes32 public constant STRATEGY_HASH_1 = keccak256("strategy1");
    bytes32 public constant STRATEGY_HASH_2 = keccak256("strategy2");
    string public constant METADATA_URI = "ipfs://QmTest";
    
    function setUp() public {
        vm.prank(owner);
        registry = new AgentRegistry();
        
        // Fund agents for registration
        vm.deal(agent1, 1 ether);
        vm.deal(agent2, 1 ether);
        vm.deal(user, 1 ether);
    }
    
    function test_RegisterAgent() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        assertTrue(registry.isAgent(agent1));
        
        ClankerWarsTypes.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.owner, agent1);
        assertEq(agent.strategyHash, STRATEGY_HASH_1);
        assertEq(agent.metadataURI, METADATA_URI);
        assertEq(agent.eloRating, 1200);
        assertEq(uint256(agent.status), uint256(ClankerWarsTypes.AgentStatus.Active));
    }
    
    function test_Revert_RegisterAgent_AlreadyRegistered() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        vm.prank(agent1);
        vm.expectRevert(AgentRegistry.AgentAlreadyRegistered.selector);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_2, METADATA_URI);
    }
    
    function test_Revert_RegisterAgent_DuplicateStrategy() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        vm.prank(agent2);
        vm.expectRevert(AgentRegistry.StrategyHashAlreadyUsed.selector);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
    }
    
    function test_Revert_RegisterAgent_InsufficientFee() public {
        vm.prank(agent1);
        vm.expectRevert(AgentRegistry.InsufficientFee.selector);
        registry.registerAgent{value: 0.0001 ether}(STRATEGY_HASH_1, METADATA_URI);
    }
    
    function test_UpdateAgent() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        bytes32 newHash = keccak256("new_strategy");
        string memory newUri = "ipfs://QmNew";
        
        vm.prank(agent1);
        registry.updateAgent(newHash, newUri);
        
        ClankerWarsTypes.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.strategyHash, newHash);
        assertEq(agent.metadataURI, newUri);
    }
    
    function test_BanAndUnbanAgent() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        // Ban agent
        vm.prank(owner);
        registry.banAgent(agent1);
        
        assertFalse(registry.canBattle(agent1));
        
        // Unban agent
        vm.prank(owner);
        registry.unbanAgent(agent1);
        
        assertTrue(registry.canBattle(agent1));
    }
    
    function test_RetireAgent() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        vm.prank(agent1);
        registry.retireAgent();
        
        assertFalse(registry.canBattle(agent1));
    }
    
    function test_UpdateAgentStats() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        // Only core contract should be able to call this
        vm.prank(address(this));
        registry.updateAgentStats(agent1, true, 25);
        
        ClankerWarsTypes.Agent memory agent = registry.getAgent(agent1);
        assertEq(agent.wins, 1);
        assertEq(agent.totalBattles, 1);
        assertEq(agent.eloRating, 1225);
    }
    
    function test_GetActiveAgents() public {
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        vm.prank(agent2);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_2, METADATA_URI);
        
        address[] memory active = registry.getActiveAgents();
        assertEq(active.length, 2);
    }
    
    function test_WithdrawFees() public {
        uint256 initialBalance = owner.balance;
        
        vm.prank(agent1);
        registry.registerAgent{value: 0.001 ether}(STRATEGY_HASH_1, METADATA_URI);
        
        vm.prank(owner);
        registry.withdrawFees();
        
        assertGt(owner.balance, initialBalance);
    }
}
