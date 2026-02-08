// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/types/ClankerWarsTypes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AgentRegistry
 * @notice Manages agent registration with strategy hashes
 */
contract AgentRegistry is Ownable, ReentrancyGuard {
    // ============ State Variables ============
    
    mapping(address => ClankerWarsTypes.Agent) public agents;
    mapping(address => bool) public isAgent;
    mapping(bytes32 => bool) public strategyHashUsed;
    
    address[] public allAgents;
    
    uint256 public constant INITIAL_ELO = 1200;
    uint256 public constant MIN_REGISTRATION_FEE = 0.001 ether;
    uint256 public registrationFee = MIN_REGISTRATION_FEE;
    
    // ============ Events ============
    
    event AgentRegistered(
        address indexed agent,
        address indexed owner,
        bytes32 strategyHash,
        uint256 eloRating,
        string metadataURI
    );
    
    event AgentUpdated(
        address indexed agent,
        bytes32 newStrategyHash,
        string newMetadataURI
    );
    
    event AgentStatusChanged(
        address indexed agent,
        ClankerWarsTypes.AgentStatus oldStatus,
        ClankerWarsTypes.AgentStatus newStatus
    );
    
    event RegistrationFeeUpdated(uint256 oldFee, uint256 newFee);
    
    // ============ Errors ============
    
    error AgentAlreadyRegistered();
    error AgentNotRegistered();
    error StrategyHashAlreadyUsed();
    error InvalidStrategyHash();
    error InsufficientFee();
    error NotAgentOwner();
    error AgentBanned();
    error AgentRetired();
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {}
    
    // ============ External Functions ============
    
    /**
     * @notice Register a new agent
     * @param strategyHash Hash of the agent's strategy configuration
     * @param metadataURI IPFS or other URI to agent metadata
     */
    function registerAgent(
        bytes32 strategyHash,
        string calldata metadataURI
    ) external payable nonReentrant {
        if (isAgent[msg.sender]) revert AgentAlreadyRegistered();
        if (strategyHash == bytes32(0)) revert InvalidStrategyHash();
        if (strategyHashUsed[strategyHash]) revert StrategyHashAlreadyUsed();
        if (msg.value < registrationFee) revert InsufficientFee();
        
        agents[msg.sender] = ClankerWarsTypes.Agent({
            owner: msg.sender,
            strategyHash: strategyHash,
            metadataURI: metadataURI,
            eloRating: INITIAL_ELO,
            totalBattles: 0,
            wins: 0,
            losses: 0,
            totalStakedOn: 0,
            status: ClankerWarsTypes.AgentStatus.Active,
            registeredAt: block.timestamp
        });
        
        isAgent[msg.sender] = true;
        strategyHashUsed[strategyHash] = true;
        allAgents.push(msg.sender);
        
        emit AgentRegistered(
            msg.sender,
            msg.sender,
            strategyHash,
            INITIAL_ELO,
            metadataURI
        );
    }
    
    /**
     * @notice Update agent strategy (can only be done if no active battles)
     * @param newStrategyHash New strategy hash
     * @param newMetadataURI New metadata URI
     */
    function updateAgent(
        bytes32 newStrategyHash,
        string calldata newMetadataURI
    ) external {
        if (!isAgent[msg.sender]) revert AgentNotRegistered();
        if (newStrategyHash == bytes32(0)) revert InvalidStrategyHash();
        if (strategyHashUsed[newStrategyHash]) revert StrategyHashAlreadyUsed();
        
        ClankerWarsTypes.Agent storage agent = agents[msg.sender];
        
        // Clear old strategy hash
        strategyHashUsed[agent.strategyHash] = false;
        
        // Update to new
        agent.strategyHash = newStrategyHash;
        agent.metadataURI = newMetadataURI;
        strategyHashUsed[newStrategyHash] = true;
        
        emit AgentUpdated(msg.sender, newStrategyHash, newMetadataURI);
    }
    
    /**
     * @notice Update agent statistics after battle
     * @param agent Agent address
     * @param won Whether the agent won
     * @param eloChange ELO rating change
     */
    function updateAgentStats(
        address agent,
        bool won,
        int256 eloChange
    ) external {
        // Only callable by core contract
        // Will be validated in ClankerWarsCore
        
        ClankerWarsTypes.Agent storage a = agents[agent];
        
        uint256 oldElo = a.eloRating;
        
        if (won) {
            a.wins++;
            a.eloRating = uint256(int256(oldElo) + eloChange);
        } else {
            a.losses++;
            a.eloRating = uint256(int256(oldElo) + eloChange);
        }
        
        a.totalBattles++;
        
        emit ClankerWarsTypes.EloUpdated(agent, oldElo, a.eloRating, won);
    }
    
    /**
     * @notice Admin: Ban an agent
     * @param agent Agent to ban
     */
    function banAgent(address agent) external onlyOwner {
        if (!isAgent[agent]) revert AgentNotRegistered();
        
        ClankerWarsTypes.AgentStatus oldStatus = agents[agent].status;
        agents[agent].status = ClankerWarsTypes.AgentStatus.Banned;
        
        emit AgentStatusChanged(agent, oldStatus, ClankerWarsTypes.AgentStatus.Banned);
    }
    
    /**
     * @notice Admin: Unban an agent
     * @param agent Agent to unban
     */
    function unbanAgent(address agent) external onlyOwner {
        if (!isAgent[agent]) revert AgentNotRegistered();
        
        ClankerWarsTypes.AgentStatus oldStatus = agents[agent].status;
        agents[agent].status = ClankerWarsTypes.AgentStatus.Active;
        
        emit AgentStatusChanged(agent, oldStatus, ClankerWarsTypes.AgentStatus.Active);
    }
    
    /**
     * @notice Agent owner: Retire the agent
     */
    function retireAgent() external {
        if (!isAgent[msg.sender]) revert AgentNotRegistered();
        
        ClankerWarsTypes.AgentStatus oldStatus = agents[msg.sender].status;
        agents[msg.sender].status = ClankerWarsTypes.AgentStatus.Retired;
        
        emit AgentStatusChanged(msg.sender, oldStatus, ClankerWarsTypes.AgentStatus.Retired);
    }
    
    /**
     * @notice Admin: Update registration fee
     * @param newFee New fee amount
     */
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = registrationFee;
        registrationFee = newFee;
        emit RegistrationFeeUpdated(oldFee, newFee);
    }
    
    /**
     * @notice Admin: Withdraw registration fees
     */
    function withdrawFees() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get agent details
     * @param agent Agent address
     */
    function getAgent(address agent)
        external
        view
        returns (ClankerWarsTypes.Agent memory)
    {
        return agents[agent];
    }
    
    /**
     * @notice Check if agent can participate in battles
     * @param agent Agent address
     */
    function canBattle(address agent) external view returns (bool) {
        if (!isAgent[agent]) return false;
        ClankerWarsTypes.AgentStatus status = agents[agent].status;
        return status == ClankerWarsTypes.AgentStatus.Active;
    }
    
    /**
     * @notice Get all active agents
     * @return Array of active agent addresses
     */
    function getActiveAgents() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < allAgents.length; i++) {
            if (agents[allAgents[i]].status == ClankerWarsTypes.AgentStatus.Active) {
                activeCount++;
            }
        }
        
        address[] memory active = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allAgents.length; i++) {
            if (agents[allAgents[i]].status == ClankerWarsTypes.AgentStatus.Active) {
                active[index++] = allAgents[i];
            }
        }
        
        return active;
    }
    
    /**
     * @notice Get total number of registered agents
     */
    function getAgentCount() external view returns (uint256) {
        return allAgents.length;
    }
}
