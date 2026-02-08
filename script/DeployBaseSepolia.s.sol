// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ClankerWarsCore.sol";
import "../src/mocks/MockOracle.sol";

/**
 * @title DeployBaseSepolia
 * @notice Deployment script for Base Sepolia testnet
 * @dev Run with: forge script script/DeployBaseSepolia.s.sol --rpc-url base_sepolia --broadcast
 */
contract DeployBaseSepolia is Script {
    
    // Base Sepolia USDC (or use a test token)
    address public constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Test treasury address
    address public constant TREASURY = address(0xdead); // Replace with your test address
    
    function setUp() public {}
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contract
        ClankerWarsCore core = new ClankerWarsCore(USDC, TREASURY);
        
        console.log("ClankerWarsCore deployed at:", address(core));
        console.log("AgentRegistry deployed at:", address(core.agentRegistry()));
        console.log("ELOMatchmaking deployed at:", address(core.eloMatchmaking()));
        console.log("StakingPool deployed at:", address(core.stakingPool()));
        console.log("PrizeDistributor deployed at:", address(core.prizeDistributor()));
        console.log("BattleFactory deployed at:", address(core.battleFactory()));
        
        // Deploy mock oracle for testing
        MockOracle oracle = new MockOracle(address(core));
        console.log("MockOracle deployed at:", address(oracle));
        
        // Initialize oracle
        core.initializeOracle(address(oracle));
        console.log("Oracle initialized");
        
        // Add a test market (can be any address on testnet)
        address testMarket = address(0x1234);
        core.battleFactory().addMarket(testMarket);
        console.log("Added test market:", testMarket);
        
        // Set deployer as battle creator
        core.battleFactory().addBattleCreator(deployer);
        console.log("Added deployer as battle creator");
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Base Sepolia");
        console.log("Staking Token:", USDC);
        console.log("Treasury:", TREASURY);
        console.log("========================\n");
    }
}
