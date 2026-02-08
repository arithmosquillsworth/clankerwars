// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/types/ClankerWarsTypes.sol";

/**
 * @title ELOMatchmaking
 * @notice ELO rating system for agent matchmaking
 * @dev Based on standard ELO algorithm with K-factor adjustments
 */
contract ELOMatchmaking {
    // ============ Constants ============
    
    // Base K-factor for rating calculations
    uint256 public constant K_FACTOR_BASE = 32;
    
    // K-factor adjustments based on agent experience
    uint256 public constant K_FACTOR_NEW = 40;      // Agents with < 30 games
    uint256 public constant K_FACTOR_ESTABLISHED = 32; // Agents with 30-100 games
    uint256 public constant K_FACTOR_VETERAN = 24;   // Agents with > 100 games
    
    // Thresholds for K-factor selection
    uint256 public constant GAMES_NEW = 30;
    uint256 public constant GAMES_ESTABLISHED = 100;
    
    // Rating floor and ceiling
    uint256 public constant RATING_FLOOR = 100;
    uint256 public constant RATING_CEILING = 3000;
    
    // Matchmaking parameters
    uint256 public constant MATCHMAKING_RANGE_INITIAL = 200;  // Initial ELO range to search
    uint256 public constant MATCHMAKING_RANGE_MAX = 500;      // Max ELO range
    uint256 public constant MATCHMAKING_COOLDOWN = 1 hours;   // Min time between battles
    
    // ============ State Variables ============
    
    // Agent's last battle timestamp (for cooldown)
    mapping(address => uint256) public lastBattleTime;
    
    // Expected score cache for gas optimization
    mapping(bytes32 => uint256) private expectedScoreCache;
    
    // ============ Events ============
    
    event EloCalculated(
        address indexed agentA,
        address indexed agentB,
        uint256 expectedScoreA,
        uint256 expectedScoreB,
        int256 changeA,
        int256 changeB
    );
    
    event MatchFound(
        address indexed agentA,
        address indexed agentB,
        uint256 eloA,
        uint256 eloB,
        uint256 ratingDiff
    );
    
    // ============ Errors ============
    
    error SameAgent();
    error InvalidElo();
    error CooldownActive(address agent);
    
    // ============ External Functions ============
    
    /**
     * @notice Calculate expected score for a match
     * @param eloA ELO rating of agent A
     * @param eloB ELO rating of agent B
     * @return expectedScore Expected score for agent A (scaled by 1e6)
     */
    function calculateExpectedScore(uint256 eloA, uint256 eloB)
        public
        pure
        returns (uint256 expectedScore)
    {
        if (eloA == eloB) {
            return 500000; // 0.5 * 1e6
        }
        
        // ELO expected score formula: 1 / (1 + 10^((Rb-Ra)/400))
        // Using approximation for gas efficiency
        int256 ratingDiff = int256(eloB) - int256(eloA);
        
        if (ratingDiff >= 400) {
            return 10000; // ~0.01 * 1e6 (strong underdog)
        } else if (ratingDiff <= -400) {
            return 990000; // ~0.99 * 1e6 (strong favorite)
        }
        
        // Precomputed lookup table for efficiency
        // Index is (ratingDiff + 400) / 40
        uint256[21] memory lookup = [
            uint256(990000), // -400
            964000,          // -360
            924000,          // -320
            867000,          // -280
            794000,          // -240
            709000,          // -200
            617000,          // -160
            525000,          // -120
            438000,          // -80
            360000,          // -40
            500000,          // 0
            640000,          // +40
            562000,          // +80
            475000,          // +120
            383000,          // +160
            291000,          // +200
            206000,          // +240
            133000,          // +280
            76000,           // +320
            36000,           // +360
            10000            // +400
        ];
        
        uint256 index = uint256((ratingDiff + 400) / 40);
        if (index > 20) index = 20;
        
        return lookup[index];
    }
    
    /**
     * @notice Calculate ELO rating change after a match
     * @param eloWinner Winner's ELO
     * @param eloLoser Loser's ELO
     * @param gamesPlayedWinner Winner's total games played
     * @param gamesPlayedLoser Loser's total games played
     * @return changeWinner Rating change for winner (can be negative if upset)
     * @return changeLoser Rating change for loser
     */
    function calculateRatingChange(
        uint256 eloWinner,
        uint256 eloLoser,
        uint256 gamesPlayedWinner,
        uint256 gamesPlayedLoser
    ) external pure returns (int256 changeWinner, int256 changeLoser) {
        uint256 expectedWinner = calculateExpectedScore(eloWinner, eloLoser);
        uint256 expectedLoser = 1000000 - expectedWinner;
        
        uint256 kWinner = getKFactor(gamesPlayedWinner);
        uint256 kLoser = getKFactor(gamesPlayedLoser);
        
        // Winner gets: K * (1 - expected)
        // Since expected is in 1e6, we need to adjust
        changeWinner = int256((kWinner * (1000000 - expectedWinner)) / 1000000);
        
        // Loser gets: K * (0 - expected) = -K * expected
        changeLoser = -int256((kLoser * expectedLoser) / 1000000);
        
        // Ensure minimum change of 1
        if (changeWinner < 1) changeWinner = 1;
        if (changeLoser > -1) changeLoser = -1;
    }
    
    /**
     * @notice Get appropriate K-factor based on games played
     * @param gamesPlayed Number of games played
     */
    function getKFactor(uint256 gamesPlayed) public pure returns (uint256) {
        if (gamesPlayed < GAMES_NEW) {
            return K_FACTOR_NEW;
        } else if (gamesPlayed < GAMES_ESTABLISHED) {
            return K_FACTOR_ESTABLISHED;
        } else {
            return K_FACTOR_VETERAN;
        }
    }
    
    /**
     * @notice Check if two agents can be matched
     * @param agentA First agent
     * @param agentB Second agent
     * @param eloA ELO of agent A
     * @param eloB ELO of agent B
     */
    function canMatch(
        address agentA,
        address agentB,
        uint256 eloA,
        uint256 eloB
    ) external view returns (bool) {
        if (agentA == agentB) return false;

        // Check cooldowns (allow if never battled - lastBattleTime is 0)
        uint256 lastBattleA = lastBattleTime[agentA];
        uint256 lastBattleB = lastBattleTime[agentB];
        if (lastBattleA > 0 && block.timestamp < lastBattleA + MATCHMAKING_COOLDOWN) {
            return false;
        }
        if (lastBattleB > 0 && block.timestamp < lastBattleB + MATCHMAKING_COOLDOWN) {
            return false;
        }

        // Check ELO range
        uint256 eloDiff = eloA > eloB ? eloA - eloB : eloB - eloA;
        if (eloDiff > MATCHMAKING_RANGE_MAX) {
            return false;
        }

        return true;
    }
    
    /**
     * @notice Record that agents battled (updates cooldown)
     * @param agentA First agent
     * @param agentB Second agent
     */
    function recordBattle(address agentA, address agentB) external {
        lastBattleTime[agentA] = block.timestamp;
        lastBattleTime[agentB] = block.timestamp;
        
        emit MatchFound(agentA, agentB, 0, 0, 0);
    }
    
    /**
     * @notice Find best match for an agent from a list
     * @param agent The agent to match
     * @param elo Agent's ELO
     * @param candidates Array of candidate agents
     * @param elos Array of candidate ELOs
     * @return bestMatch Index of best match in candidates (-1 if none found)
     * @return ratingDiff ELO difference with best match
     */
    function findBestMatch(
        address agent,
        uint256 elo,
        address[] calldata candidates,
        uint256[] calldata elos
    ) external view returns (int256 bestMatch, uint256 ratingDiff) {
        require(candidates.length == elos.length, "Length mismatch");
        
        bestMatch = -1;
        ratingDiff = type(uint256).max;
        
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == agent) continue;
            
            // Check cooldown (skip if never battled)
            uint256 lastBattle = lastBattleTime[candidates[i]];
            if (lastBattle > 0 && block.timestamp < lastBattle + MATCHMAKING_COOLDOWN) {
                continue;
            }
            
            uint256 diff = elo > elos[i] ? elo - elos[i] : elos[i] - elo;
            
            if (diff < ratingDiff && diff <= MATCHMAKING_RANGE_MAX) {
                ratingDiff = diff;
                bestMatch = int256(i);
            }
        }
    }
    
    /**
     * @notice Apply rating floor and ceiling
     * @param newRating Calculated new rating
     */
    function applyRatingBounds(uint256 newRating) external pure returns (uint256) {
        if (newRating < RATING_FLOOR) return RATING_FLOOR;
        if (newRating > RATING_CEILING) return RATING_CEILING;
        return newRating;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get time until agent can battle again
     * @param agent Agent address
     */
    function getCooldownRemaining(address agent) external view returns (uint256) {
        uint256 lastBattle = lastBattleTime[agent];
        if (block.timestamp >= lastBattle + MATCHMAKING_COOLDOWN) {
            return 0;
        }
        return lastBattle + MATCHMAKING_COOLDOWN - block.timestamp;
    }
    
    /**
     * @notice Get match quality score (0-100)
     * @param eloA ELO of agent A
     * @param eloB ELO of agent B
     */
    function getMatchQuality(uint256 eloA, uint256 eloB) external pure returns (uint256) {
        uint256 diff = eloA > eloB ? eloA - eloB : eloB - eloA;
        if (diff >= MATCHMAKING_RANGE_MAX) return 0;
        return 100 - ((diff * 100) / MATCHMAKING_RANGE_MAX);
    }
}
