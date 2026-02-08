// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./types/ClankerWarsTypes.sol";
import "./interfaces/IOracle.sol";
import "./AgentRegistry.sol";
import "./ELOMatchmaking.sol";
import "./StakingPool.sol";
import "./PrizeDistributor.sol";
import "./BattleFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ClankerWarsCore
 * @notice Main orchestrator contract for ClankerWars
 */
contract ClankerWarsCore is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ State Variables ============
    
    AgentRegistry public agentRegistry;
    ELOMatchmaking public eloMatchmaking;
    StakingPool public stakingPool;
    PrizeDistributor public prizeDistributor;
    BattleFactory public battleFactory;
    IOracle public oracle;
    
    IERC20 public stakingToken;
    
    // Auto-matchmaking enabled
    bool public autoMatchmakingEnabled = true;
    
    // ============ Events ============
    
    event BattleCreatedAndJoined(
        uint256 indexed battleId,
        address indexed agentA,
        address indexed agentB,
        address market
    );
    
    event BattleResolvedWithPrizes(
        uint256 indexed battleId,
        address indexed winner,
        uint256 totalPrize,
        uint256 protocolFee
    );
    
    event StakePlacedAndTracked(
        uint256 indexed battleId,
        address indexed user,
        address indexed agent,
        uint256 amount
    );
    
    event SystemInitialized(
        address registry,
        address matchmaking,
        address staking,
        address prize,
        address factory,
        address oracle
    );
    
    // ============ Errors ============
    
    error InvalidAddress();
    error AlreadyInitialized();
    error NotInitialized();
    error AgentNotActive();
    error BattleCreationFailed();
    error StakeFailed();
    error ResolutionFailed();
    error Unauthorized();
    error TransferFailed();
    
    // ============ Constructor ============
    
    constructor(
        address _stakingToken,
        address _treasury
    ) Ownable(msg.sender) {
        if (_stakingToken == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }
        
        stakingToken = IERC20(_stakingToken);
        
        // Deploy all sub-contracts
        agentRegistry = new AgentRegistry();
        eloMatchmaking = new ELOMatchmaking();
        stakingPool = new StakingPool(_stakingToken);
        prizeDistributor = new PrizeDistributor(_stakingToken, _treasury);
        battleFactory = new BattleFactory();
        
        // Set this contract as core for sub-contracts
        agentRegistry.setCoreContract(address(this));
        stakingPool.setCoreContract(address(this));
        stakingPool.setPrizeDistributor(address(prizeDistributor));
        prizeDistributor.setCoreContract(address(this));
        prizeDistributor.setStakingPool(address(stakingPool));
        // battleFactory core contracts set in initializeOracle
    }
    
    // ============ External Functions ============
    
    /**
     * @notice Initialize oracle (separate due to potential external dependency)
     * @param _oracle Oracle contract address
     */
    function initializeOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert InvalidAddress();
        oracle = IOracle(_oracle);
        battleFactory.setCoreContracts(address(this), _oracle);
    }
    
    /**
     * @notice Register a new agent
     * @param strategyHash Hash of agent strategy
     * @param metadataURI URI to agent metadata
     */
    function registerAgent(
        bytes32 strategyHash,
        string calldata metadataURI
    ) external payable {
        agentRegistry.registerAgentFor{value: msg.value}(msg.sender, strategyHash, metadataURI);
    }
    
    /**
     * @notice Create a battle between two agents
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
    ) external returns (uint256 battleId) {
        // Verify agents are active
        if (!agentRegistry.canBattle(agentA)) revert AgentNotActive();
        if (!agentRegistry.canBattle(agentB)) revert AgentNotActive();
        
        battleId = battleFactory.createBattle(agentA, agentB, market, duration);
        
        emit BattleCreatedAndJoined(battleId, agentA, agentB, market);
    }
    
    /**
     * @notice Find and create a match for an agent (auto-matchmaking)
     * @param agent The agent seeking a match
     * @param market Preferred market
     * @param duration Battle duration
     */
    function findMatch(
        address agent,
        address market,
        uint256 duration
    ) external returns (uint256 battleId) {
        if (!autoMatchmakingEnabled) revert Unauthorized();
        if (!agentRegistry.canBattle(agent)) revert AgentNotActive();
        
        ClankerWarsTypes.Agent memory agentData = agentRegistry.getAgent(agent);
        
        // Get active agents
        address[] memory activeAgents = agentRegistry.getActiveAgents();
        
        // Build ELO array
        uint256[] memory elos = new uint256[](activeAgents.length);
        for (uint256 i = 0; i < activeAgents.length; i++) {
            elos[i] = agentRegistry.getAgent(activeAgents[i]).eloRating;
        }
        
        // Find best match
        (int256 bestMatchIdx, ) = eloMatchmaking.findBestMatch(
            agent,
            agentData.eloRating,
            activeAgents,
            elos
        );
        
        if (bestMatchIdx < 0) revert BattleCreationFailed();
        
        address opponent = activeAgents[uint256(bestMatchIdx)];
        
        battleId = battleFactory.createBattle(agent, opponent, market, duration);
    }
    
    function placeStake(
        uint256 battleId,
        address agent,
        uint256 amount
    ) external nonReentrant {
        // Verify battle is active and agent is in it
        ClankerWarsTypes.Battle memory battle = battleFactory.getBattle(battleId);
        if (battle.status != ClankerWarsTypes.BattleStatus.Active) revert BattleCreationFailed();
        if (agent != battle.agentA && agent != battle.agentB) revert Unauthorized();

        // Transfer tokens from user to this contract first
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve staking pool to pull tokens
        stakingToken.approve(address(stakingPool), amount);

        // Place stake through staking pool (for the user)
        stakingPool.stakeFor(battleId, msg.sender, agent, amount);

        // Update battle pools in factory
        uint256 poolA = stakingPool.totalStakedOnAgent(battleId, battle.agentA);
        uint256 poolB = stakingPool.totalStakedOnAgent(battleId, battle.agentB);
        battleFactory.updateStakePools(battleId, poolA, poolB);

        emit StakePlacedAndTracked(battleId, msg.sender, agent, amount);
    }
    
    /**
     * @notice Request battle resolution from oracle
     * @param battleId Battle ID
     */
    function requestResolution(uint256 battleId) external {
        ClankerWarsTypes.Battle memory battle = battleFactory.getBattle(battleId);
        
        if (battle.status != ClankerWarsTypes.BattleStatus.Active) revert ResolutionFailed();
        if (block.timestamp < battle.endTime) revert ResolutionFailed();
        
        oracle.requestResolution(
            battleId,
            battle.agentA,
            battle.agentB,
            battle.market,
            battle.startTime,
            battle.endTime
        );
    }
    
    /**
     * @notice Callback from oracle to finalize battle resolution
     * @param battleId Battle ID
     * @param winner Winning agent address
     * @param resolutionData Additional resolution data
     */
    function finalizeResolution(
        uint256 battleId,
        address winner,
        bytes32 resolutionData
    ) external nonReentrant {
        // In production, verify this came from oracle
        // For now, owner can call directly for testing
        if (msg.sender != owner() && msg.sender != address(oracle)) {
            revert Unauthorized();
        }
        
        ClankerWarsTypes.Battle memory battle = battleFactory.getBattle(battleId);
        
        // Resolve battle in factory
        battleFactory.resolveBattle(battleId, winner, resolutionData);
        
        // Distribute prizes
        (uint256 totalPrize, uint256 protocolFee) = prizeDistributor.distributePrizes(
            battleId,
            winner,
            battle.stakePoolA,
            battle.stakePoolB,
            battle.agentA,
            battle.agentB
        );
        
        battleFactory.setProtocolFee(battleId, protocolFee);
        
        // Update ELO ratings
        if (winner != address(0)) {
            address loser = (winner == battle.agentA) ? battle.agentB : battle.agentA;
            
            ClankerWarsTypes.Agent memory winnerData = agentRegistry.getAgent(winner);
            ClankerWarsTypes.Agent memory loserData = agentRegistry.getAgent(loser);
            
            (int256 changeWinner, int256 changeLoser) = eloMatchmaking.calculateRatingChange(
                winnerData.eloRating,
                loserData.eloRating,
                winnerData.totalBattles,
                loserData.totalBattles
            );
            
            agentRegistry.updateAgentStats(winner, true, changeWinner);
            agentRegistry.updateAgentStats(loser, false, changeLoser);
            
            eloMatchmaking.recordBattle(winner, loser);
        }
        
        // Calculate and record individual winnings
        _calculateAndRecordWinnings(battleId, battle, winner);
        
        emit BattleResolvedWithPrizes(battleId, winner, totalPrize, protocolFee);
    }
    
    /**
     * @notice Claim winnings for a battle
     * @param battleId Battle ID
     * @param agent Agent staked on
     */
    function claimWinnings(uint256 battleId, address agent) external nonReentrant {
        stakingPool.claimWinningsFor(msg.sender, battleId, agent);
    }
    
    /**
     * @notice Batch claim winnings
     * @param battleIds Array of battle IDs
     * @param agents Array of agents
     */
    function batchClaimWinnings(
        uint256[] calldata battleIds,
        address[] calldata agents
    ) external nonReentrant {
        stakingPool.batchClaimWinnings(battleIds, agents);
    }
    
    // ============ Internal Functions ============
    
    function _calculateAndRecordWinnings(
        uint256 battleId,
        ClankerWarsTypes.Battle memory battle,
        address winner
    ) internal {
        if (winner == address(0)) {
            // Draw - everyone gets their stake back
            return;
        }
        
        uint256 totalPrize = (battle.stakePoolA + battle.stakePoolB) - battle.protocolFee;
        uint256 winnerPool = (winner == battle.agentA) ? battle.stakePoolA : battle.stakePoolB;
        
        if (winnerPool == 0) return;
        
        // Get all stakes for this battle
        uint256 stakeCount = stakingPool.getBattleStakeCount(battleId);
        
        for (uint256 i = 0; i < stakeCount; i++) {
            ClankerWarsTypes.Stake memory stake = stakingPool.getStake(battleId, i);
            
            if (stake.agent == winner) {
                uint256 winnings = prizeDistributor.calculateUserWinnings(
                    stake.amount,
                    winnerPool,
                    totalPrize
                );
                
                stakingPool.recordWinnings(battleId, i, winnings);
            } else {
                // Losing stakes get 0
                stakingPool.recordWinnings(battleId, i, 0);
            }
        }
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Add a valid market for battles
     * @param market Market address (e.g., price feed)
     */
    function addMarket(address market) external onlyOwner {
        battleFactory.addMarket(market);
    }
    
    /**
     * @notice Remove a market
     * @param market Market address
     */
    function removeMarket(address market) external onlyOwner {
        battleFactory.removeMarket(market);
    }
    
    /**
     * @notice Add battle creator
     * @param creator Address that can create battles
     */
    function addBattleCreator(address creator) external onlyOwner {
        battleFactory.addBattleCreator(creator);
    }
    
    /**
     * @notice Remove battle creator
     * @param creator Address to remove
     */
    function removeBattleCreator(address creator) external onlyOwner {
        battleFactory.removeBattleCreator(creator);
    }
    
    /**
     * @notice Toggle auto-matchmaking
     */
    function setAutoMatchmaking(bool enabled) external onlyOwner {
        autoMatchmakingEnabled = enabled;
    }
    
    /**
     * @notice Cancel a battle (emergency)
     */
    function emergencyCancelBattle(uint256 battleId, string calldata reason) external onlyOwner {
        battleFactory.cancelBattle(battleId, reason);
    }
    
    /**
     * @notice Withdraw accumulated protocol fees
     */
    function withdrawProtocolFees() external onlyOwner {
        prizeDistributor.withdrawFees();
    }
    
    /**
     * @notice Withdraw stuck tokens
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get full battle info
     */
    function getBattleInfo(uint256 battleId)
        external
        view
        returns (
            ClankerWarsTypes.Battle memory battle,
            ClankerWarsTypes.Agent memory agentA,
            ClankerWarsTypes.Agent memory agentB
        )
    {
        battle = battleFactory.getBattle(battleId);
        agentA = agentRegistry.getAgent(battle.agentA);
        agentB = agentRegistry.getAgent(battle.agentB);
    }
    
    /**
     * @notice Check if user has claimable winnings
     */
    function getClaimableWinnings(
        uint256 battleId,
        address user,
        address agent
    ) external view returns (uint256) {
        ClankerWarsTypes.Stake memory stake = stakingPool.getUserStake(battleId, user, agent);
        if (stake.claimed) return 0;
        return stake.winnings;
    }
}
