// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ELOMatchmaking.sol";

contract ELOMatchmakingTest is Test {
    ELOMatchmaking public matchmaking;
    
    address public agentA = address(1);
    address public agentB = address(2);
    address public agentC = address(3);
    
    function setUp() public {
        matchmaking = new ELOMatchmaking();
    }
    
    function test_CalculateExpectedScore_EqualElo() public {
        uint256 expected = matchmaking.calculateExpectedScore(1200, 1200);
        assertEq(expected, 500000); // 0.5 * 1e6
    }
    
    function test_CalculateExpectedScore_Favorite() public {
        uint256 expected = matchmaking.calculateExpectedScore(1400, 1200);
        assertGt(expected, 500000);
    }
    
    function test_CalculateExpectedScore_Underdog() public {
        uint256 expected = matchmaking.calculateExpectedScore(1200, 1400);
        assertLt(expected, 500000);
    }
    
    function test_CalculateRatingChange() public {
        // Evenly matched, both with some experience
        (int256 changeWinner, int256 changeLoser) = matchmaking.calculateRatingChange(
            1200,
            1200,
            50,
            50
        );
        
        assertGt(changeWinner, 0);
        assertLt(changeLoser, 0);
        assertEq(changeWinner, -changeLoser); // Equal changes for evenly matched
    }
    
    function test_CalculateRatingChange_Upset() public {
        // Underdog wins (1200 beats 1400)
        (int256 changeWinner, int256 changeLoser) = matchmaking.calculateRatingChange(
            1200, // Winner's ELO
            1400, // Loser's ELO
            50,
            50
        );
        
        // Underdog gets more points
        assertGt(changeWinner, 16); // More than base 16 (half of K=32)
    }
    
    function test_GetKFactor() public {
        assertEq(matchmaking.getKFactor(10), 40);   // New player
        assertEq(matchmaking.getKFactor(50), 32);   // Established
        assertEq(matchmaking.getKFactor(150), 24);  // Veteran
    }
    
    function test_CanMatch() public {
        // Initially can match
        assertTrue(matchmaking.canMatch(agentA, agentB, 1200, 1200));
        
        // Record a battle
        matchmaking.recordBattle(agentA, agentB);
        
        // Immediately after, can't match due to cooldown
        assertFalse(matchmaking.canMatch(agentA, agentB, 1200, 1200));
        
        // After cooldown, can match again
        vm.warp(block.timestamp + 2 hours);
        assertTrue(matchmaking.canMatch(agentA, agentB, 1200, 1200));
    }
    
    function test_CanMatch_EloRange() public {
        // Too far apart
        assertFalse(matchmaking.canMatch(agentA, agentB, 1200, 1800));
        
        // Within range
        assertTrue(matchmaking.canMatch(agentA, agentB, 1200, 1300));
    }
    
    function test_FindBestMatch() public {
        address[] memory candidates = new address[](3);
        candidates[0] = agentA;
        candidates[1] = agentB;
        candidates[2] = agentC;
        
        uint256[] memory elos = new uint256[](3);
        elos[0] = 1200;
        elos[1] = 1250; // Closest match
        elos[2] = 1500; // Too far
        
        (int256 bestMatch, uint256 ratingDiff) = matchmaking.findBestMatch(
            address(4), // Searching agent with ELO 1230
            1230,
            candidates,
            elos
        );
        
        assertEq(bestMatch, 1); // agentB at index 1
        assertEq(ratingDiff, 20); // |1230 - 1250|
    }
    
    function test_GetCooldownRemaining() public {
        matchmaking.recordBattle(agentA, agentB);
        
        uint256 remaining = matchmaking.getCooldownRemaining(agentA);
        assertGt(remaining, 0);
        assertLe(remaining, 1 hours);
        
        // After cooldown
        vm.warp(block.timestamp + 2 hours);
        remaining = matchmaking.getCooldownRemaining(agentA);
        assertEq(remaining, 0);
    }
    
    function test_GetMatchQuality() public {
        uint256 quality = matchmaking.getMatchQuality(1200, 1200);
        assertEq(quality, 100); // Perfect match
        
        quality = matchmaking.getMatchQuality(1200, 1700); // 500 diff = max
        assertEq(quality, 0); // At max range
        
        quality = matchmaking.getMatchQuality(1200, 1250); // 50 diff
        assertEq(quality, 90); // Good match
        
        quality = matchmaking.getMatchQuality(1200, 1500); // 300 diff
        assertEq(quality, 40); // Okay match
    }
}
