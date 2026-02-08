// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ClankerWarsTypes
 * @notice Shared types and data structures for ClankerWars
 */
library ClankerWarsTypes {
    enum BattleStatus {
        Pending,      // Waiting for both agents to join
        Active,       // Battle in progress
        Resolved,     // Winner determined
        Cancelled     // Battle cancelled
    }

    enum AgentStatus {
        Unregistered,
        Active,
        Banned,
        Retired
    }

    struct Agent {
        address owner;
        bytes32 strategyHash;     // Hash of agent's strategy/config
        string metadataURI;       // IPFS link to agent details
        uint256 eloRating;
        uint256 totalBattles;
        uint256 wins;
        uint256 losses;
        uint256 totalStakedOn;    // Total amount staked on this agent
        AgentStatus status;
        uint256 registeredAt;
    }

    struct Battle {
        uint256 id;
        address agentA;
        address agentB;
        address market;           // Market being traded (e.g., ETH/USD feed)
        uint256 startTime;
        uint256 endTime;
        uint256 stakePoolA;       // Total staked on agent A
        uint256 stakePoolB;       // Total staked on agent B
        address winner;           // Winner address (zero if draw/cancelled)
        BattleStatus status;
        bytes32 resolutionData;   // Oracle resolution data
        uint256 protocolFee;      // Fee collected from this battle
    }

    struct Stake {
        address user;
        address agent;
        uint256 amount;
        uint256 battleId;
        uint256 stakedAt;
        bool claimed;
        uint256 winnings;         // Calculated at resolution
    }

    event AgentRegistered(
        address indexed agent,
        address indexed owner,
        bytes32 strategyHash,
        uint256 initialElo
    );

    event BattleCreated(
        uint256 indexed battleId,
        address indexed agentA,
        address indexed agentB,
        address market,
        uint256 startTime,
        uint256 endTime
    );

    event StakePlaced(
        uint256 indexed battleId,
        address indexed user,
        address indexed agent,
        uint256 amount
    );

    event BattleResolved(
        uint256 indexed battleId,
        address indexed winner,
        uint256 prizePool,
        uint256 protocolFee
    );

    event PrizeClaimed(
        uint256 indexed battleId,
        address indexed user,
        uint256 amount
    );

    event EloUpdated(
        address indexed agent,
        uint256 oldRating,
        uint256 newRating,
        bool won
    );
}
