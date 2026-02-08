// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IOracle.sol";
import "../ClankerWarsCore.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockOracle
 * @notice Mock oracle for testing battle resolution
 */
contract MockOracle is IOracle, Ownable {
    
    struct ResolutionRequest {
        uint256 battleId;
        address agentA;
        address agentB;
        address market;
        uint256 startTime;
        uint256 endTime;
        bool resolved;
        address winner;
        bytes32 resolutionData;
    }
    
    mapping(uint256 => ResolutionRequest) public requests;
    ClankerWarsCore public core;
    
    bool public autoResolve = false;
    address public defaultWinner;
    
    event ResolutionRequested(
        uint256 indexed battleId,
        address indexed agentA,
        address indexed agentB
    );
    
    event ResolutionSubmitted(
        uint256 indexed battleId,
        address indexed winner,
        bytes32 resolutionData
    );
    
    constructor(address _core) Ownable(msg.sender) {
        core = ClankerWarsCore(_core);
    }
    
    function requestResolution(
        uint256 battleId,
        address agentA,
        address agentB,
        address market,
        uint256 startTime,
        uint256 endTime
    ) external override {
        requests[battleId] = ResolutionRequest({
            battleId: battleId,
            agentA: agentA,
            agentB: agentB,
            market: market,
            startTime: startTime,
            endTime: endTime,
            resolved: false,
            winner: address(0),
            resolutionData: bytes32(0)
        });
        
        emit ResolutionRequested(battleId, agentA, agentB);
        
        if (autoResolve) {
            address winner = defaultWinner != address(0) ? defaultWinner : agentA;
            submitResolution(battleId, winner, keccak256(abi.encodePacked(block.timestamp)));
        }
    }
    
    function getResolution(uint256 battleId)
        external
        view
        override
        returns (address winner, bytes32 resolutionData, bool resolved)
    {
        ResolutionRequest memory req = requests[battleId];
        return (req.winner, req.resolutionData, req.resolved);
    }
    
    function reportResolution(
        uint256 battleId,
        address winner,
        bytes32 resolutionData
    ) external override {
        // Only core can report
        require(msg.sender == address(core), "Only core");
        
        ResolutionRequest storage req = requests[battleId];
        req.resolved = true;
        req.winner = winner;
        req.resolutionData = resolutionData;
    }
    
    // Admin function to submit resolution
    function submitResolution(
        uint256 battleId,
        address winner,
        bytes32 resolutionData
    ) public onlyOwner {
        ResolutionRequest storage req = requests[battleId];
        require(!req.resolved, "Already resolved");
        
        req.resolved = true;
        req.winner = winner;
        req.resolutionData = resolutionData;
        
        emit ResolutionSubmitted(battleId, winner, resolutionData);
        
        // Call core to finalize
        core.finalizeResolution(battleId, winner, resolutionData);
    }
    
    function setAutoResolve(bool _autoResolve, address _defaultWinner) external onlyOwner {
        autoResolve = _autoResolve;
        defaultWinner = _defaultWinner;
    }
}
