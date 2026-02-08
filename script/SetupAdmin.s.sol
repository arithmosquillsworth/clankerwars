// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ClankerWarsCore.sol";

/**
 * @title SetupAdmin
 * @notice Post-deployment configuration script
 * @dev Run after deploying contracts
 */
contract SetupAdmin is Script {
    
    function setUp() public {}
    
    function run() public {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address coreAddress = vm.envAddress("CORE_ADDRESS");
        
        ClankerWarsCore core = ClankerWarsCore(coreAddress);
        
        vm.startBroadcast(adminPrivateKey);
        
        // Add battle creators
        address[] memory creators = vm.envAddress("BATTLE_CREATORS", ",");
        for (uint i = 0; i < creators.length; i++) {
            core.battleFactory().addBattleCreator(creators[i]);
            console.log("Added battle creator:", creators[i]);
        }
        
        // Add markets
        address[] memory markets = vm.envAddress("MARKETS", ",");
        for (uint i = 0; i < markets.length; i++) {
            core.battleFactory().addMarket(markets[i]);
            console.log("Added market:", markets[i]);
        }
        
        // Update stake limits if needed
        // core.stakingPool().setStakeLimits(minStake, maxStake);
        
        vm.stopBroadcast();
        
        console.log("Admin setup complete");
    }
}
