// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/types/ClankerWarsTypes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BattleFactory
 * @notice Creates and manages agent battles
 */
contract BattleFactory is Ownable, ReentrancyGuard {
    // ============ State Variables ============
    
    uint256 public nextBattleId;
    
    // Battle ID => Battle
    mapping(uint256 => ClankerWarsTypes.Battle) public battles;
    
    // Agent => current battle (if any)
    mapping(address => uint256) public agentCurrentBattle;
    
    // Market => is valid
    mapping(address => bool) public validMarkets;
    
    // Authorized creators
    mapping(address => bool) public isBattleCreator;
    
    address public coreContract;
    address public oracleContract;
    
    // Battle parameters
    uint256 public minBattleDuration = 1 hours;
    uint256 public maxBattleDuration = 24 hours;
    uint256 public defaultBattleDuration = 4 hours;
    
    // ============ Events ============
    
    event BattleCreated(
        uint256 indexed battleId,
        address indexed agentA,
        address indexed agentB,
        address market,
        uint256 startTime,
        uint256 endTime
    );
    
    event BattleCancelled(
        uint256 indexed battleId,
        string reason
    );
    
    event BattleResolved(
        uint256 indexed battleId,
        address indexed winner,
        bytes32 resolutionData
    );
    
    event MarketAdded(address indexed market);
    
    event MarketRemoved(address indexed market);
    
    event BattleCreatorAdded(address indexed creator);
    
    event BattleCreatorRemoved(address indexed creator);
    
    // ============ Errors ============
    
    error InvalidAgents();
    error SameAgent();
    error InvalidMarket();
    error InvalidDuration();
    error BattleNotFound();
    error BattleNotActive();
    error BattleAlreadyResolved();
    error AgentInBattle(address agent);
    error NotBattleCreator();
    error NotCoreContract();
    error NotOracle();
    error InvalidWinner();
    error BattleStillActive();
    error InvalidTiming();
    
    // ============ Modifiers ============
    
    modifier onlyCore() {
        if (msg.sender != coreContract) revert NotCoreContract();
        _;
    }
    
    modifier onlyOracle() {
        if (msg.sender != oracleContract) revert NotOracle();
        _;
    }
    
    modifier onlyCreator() {
        if (!isBattleCreator[msg.sender] && msg.sender != owner()) {
            revert NotBattleCreator();
        }
        _;
    }
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {
        nextBattleId = 1;
    }
    
    // ============ External Functions ============
    
    /**
     * @notice Set core and oracle contracts
     */
    function setCoreContracts(
        address _coreContract,
        address _oracleContract
    ) external onlyOwner {
        require(coreContract == address(0), "Already set");
        coreContract = _coreContract;
        oracleContract = _oracleContract;
    }
    
    /**
     * @notice Create a new battle
     * @param agentA First agent
     * @param agentB Second agent
     * @param market Market to trade on
     * @param duration Battle duration in seconds
     */
    function createBattle(
        address agentA,
        address agentB,
        address market,
        uint256 duration
    ) external onlyCreator nonReentrant returns (uint256 battleId) {
        if (agentA == agentB) revert SameAgent();
        if (!validMarkets[market]) revert InvalidMarket();
        if (duration < minBattleDuration || duration > maxBattleDuration) {
            revert InvalidDuration();
        }
        
        // Check agents aren't already in battles
        if (agentCurrentBattle[agentA] != 0) revert AgentInBattle(agentA);
        if (agentCurrentBattle[agentB] != 0) revert AgentInBattle(agentB);
        
        battleId = nextBattleId++;
        
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        
        battles[battleId] = ClankerWarsTypes.Battle({
            id: battleId,
            agentA: agentA,
            agentB: agentB,
            market: market,
            startTime: startTime,
            endTime: endTime,
            stakePoolA: 0,
            stakePoolB: 0,
            winner: address(0),
            status: ClankerWarsTypes.BattleStatus.Active,
            resolutionData: bytes32(0),
            protocolFee: 0
        });
        
        agentCurrentBattle[agentA] = battleId;
        agentCurrentBattle[agentB] = battleId;
        
        emit BattleCreated(battleId, agentA, agentB, market, startTime, endTime);
        
        return battleId;
    }
    
    /**
     * @notice Update battle stake pools (called by core)
     * @param battleId Battle ID
     * @param poolA Pool A amount
     * @param poolB Pool B amount
     */
    function updateStakePools(
        uint256 battleId,
        uint256 poolA,
        uint256 poolB
    ) external onlyCore {
        ClankerWarsTypes.Battle storage battle = battles[battleId];
        battle.stakePoolA = poolA;
        battle.stakePoolB = poolB;
    }
    
    /**
     * @notice Resolve a battle (called by oracle)
     * @param battleId Battle ID
     * @param winner Winning agent address
     * @param resolutionData Additional resolution data
     */
    function resolveBattle(
        uint256 battleId,
        address winner,
        bytes32 resolutionData
    ) external onlyOracle {
        ClankerWarsTypes.Battle storage battle = battles[battleId];
        
        if (battle.id == 0) revert BattleNotFound();
        if (battle.status != ClankerWarsTypes.BattleStatus.Active) revert BattleNotActive();
        if (block.timestamp < battle.endTime) revert BattleStillActive();
        if (winner != battle.agentA && winner != battle.agentB && winner != address(0)) {
            revert InvalidWinner();
        }
        
        battle.winner = winner;
        battle.resolutionData = resolutionData;
        battle.status = ClankerWarsTypes.BattleStatus.Resolved;
        
        // Clear agent battles
        agentCurrentBattle[battle.agentA] = 0;
        agentCurrentBattle[battle.agentB] = 0;
        
        emit BattleResolved(battleId, winner, resolutionData);
    }
    
    /**
     * @notice Cancel a battle (admin only)
     * @param battleId Battle ID
     * @param reason Reason for cancellation
     */
    function cancelBattle(uint256 battleId, string calldata reason) external onlyCore {
        ClankerWarsTypes.Battle storage battle = battles[battleId];
        
        if (battle.id == 0) revert BattleNotFound();
        if (battle.status != ClankerWarsTypes.BattleStatus.Active) revert BattleNotActive();
        
        battle.status = ClankerWarsTypes.BattleStatus.Cancelled;
        
        // Clear agent battles
        agentCurrentBattle[battle.agentA] = 0;
        agentCurrentBattle[battle.agentB] = 0;
        
        emit BattleCancelled(battleId, reason);
    }
    
    /**
     * @notice Set protocol fee for a battle (called by core)
     */
    function setProtocolFee(uint256 battleId, uint256 fee) external onlyCore {
        battles[battleId].protocolFee = fee;
    }
    
    /**
     * @notice Admin: Add a valid market
     * @param market Market address
     */
    function addMarket(address market) external onlyOwner {
        validMarkets[market] = true;
        emit MarketAdded(market);
    }
    
    /**
     * @notice Admin: Remove a market
     * @param market Market address
     */
    function removeMarket(address market) external onlyOwner {
        validMarkets[market] = false;
        emit MarketRemoved(market);
    }
    
    /**
     * @notice Admin: Add battle creator
     * @param creator Address to add
     */
    function addBattleCreator(address creator) external onlyOwner {
        isBattleCreator[creator] = true;
        emit BattleCreatorAdded(creator);
    }
    
    /**
     * @notice Admin: Remove battle creator
     * @param creator Address to remove
     */
    function removeBattleCreator(address creator) external onlyOwner {
        isBattleCreator[creator] = false;
        emit BattleCreatorRemoved(creator);
    }
    
    /**
     * @notice Admin: Update battle duration limits
     */
    function setDurationLimits(
        uint256 minDuration,
        uint256 maxDuration
    ) external onlyOwner {
        require(minDuration < maxDuration, "Invalid limits");
        minBattleDuration = minDuration;
        maxBattleDuration = maxDuration;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get battle details
     * @param battleId Battle ID
     */
    function getBattle(uint256 battleId)
        external
        view
        returns (ClankerWarsTypes.Battle memory)
    {
        return battles[battleId];
    }
    
    /**
     * @notice Check if agent is in an active battle
     * @param agent Agent address
     */
    function isInBattle(address agent) external view returns (bool) {
        uint256 battleId = agentCurrentBattle[agent];
        if (battleId == 0) return false;
        
        ClankerWarsTypes.Battle storage battle = battles[battleId];
        return battle.status == ClankerWarsTypes.BattleStatus.Active;
    }
    
    /**
     * @notice Get active battles count
     */
    function getActiveBattleCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextBattleId; i++) {
            if (battles[i].status == ClankerWarsTypes.BattleStatus.Active) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @notice Get battles paginated
     * @param offset Starting index
     * @param limit Maximum to return
     */
    function getBattles(uint256 offset, uint256 limit)
        external
        view
        returns (ClankerWarsTypes.Battle[] memory)
    {
        uint256 total = nextBattleId - 1;
        if (offset >= total) return new ClankerWarsTypes.Battle[](0);
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        
        uint256 count = end - offset;
        ClankerWarsTypes.Battle[] memory result = new ClankerWarsTypes.Battle[](count);
        
        for (uint256 i = 0; i < count; i++) {
            result[i] = battles[offset + i + 1];
        }
        
        return result;
    }
    
    /**
     * @notice Check if battle can be resolved
     * @param battleId Battle ID
     */
    function canResolve(uint256 battleId) external view returns (bool) {
        ClankerWarsTypes.Battle storage battle = battles[battleId];
        if (battle.id == 0) return false;
        if (battle.status != ClankerWarsTypes.BattleStatus.Active) return false;
        return block.timestamp >= battle.endTime;
    }
}
