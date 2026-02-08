// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ClankerWarsCore.sol";
import "../src/mocks/MockOracle.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title DeployBase
 * @notice Deployment script for Base mainnet
 * @dev Run with: forge script script/DeployBase.s.sol --rpc-url base --broadcast
 */
contract DeployBase is Script {
    
    // Base mainnet USDC
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Protocol treasury (replace with actual address before deploying)
    address public constant TREASURY = address(0x0); // TODO: Set before deploy
    
    function setUp() public {}
    
    function run() public {
        require(TREASURY != address(0), "Set TREASURY address before deploying");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contract (this deploys all sub-contracts)
        ClankerWarsCore core = new ClankerWarsCore(USDC, TREASURY);
        
        console.log("ClankerWarsCore deployed at:", address(core));
        console.log("AgentRegistry deployed at:", address(core.agentRegistry()));
        console.log("ELOMatchmaking deployed at:", address(core.eloMatchmaking()));
        console.log("StakingPool deployed at:", address(core.stakingPool()));
        console.log("PrizeDistributor deployed at:", address(core.prizeDistributor()));
        console.log("BattleFactory deployed at:", address(core.battleFactory()));
        
        // Add initial markets
        // ETH/USD price feed on Base
        address ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
        core.battleFactory().addMarket(ETH_USD_FEED);
        console.log("Added ETH/USD market:", ETH_USD_FEED);
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Base Mainnet");
        console.log("Staking Token: USDC (", USDC, ")");
        console.log("Treasury:", TREASURY);
        console.log("========================\n");
    }
}
