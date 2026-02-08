// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/types/ClankerWarsTypes.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakingPool
 * @notice Manages user staking on agents for battles
 */
contract StakingPool is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ State Variables ============
    
    IERC20 public immutable stakingToken; // USDC or other stable
    address public coreContract;
    address public prizeDistributor;
    
    // Battle ID => Stakes array
    mapping(uint256 => ClankerWarsTypes.Stake[]) public battleStakes;
    
    // Battle ID => Agent => Total staked
    mapping(uint256 => mapping(address => uint256)) public totalStakedOnAgent;
    
    // Battle ID => User => Agent => Stake index
    mapping(uint256 => mapping(address => mapping(address => uint256))) public userStakeIndex;
    
    // User => total active stake (across all battles)
    mapping(address => uint256) public userTotalStake;
    
    // Battle minimum and maximum stakes
    uint256 public minStake = 1e6; // 1 USDC (6 decimals)
    uint256 public maxStake = 10000e6; // 10,000 USDC
    
    // Total stakes created
    uint256 public totalStakes;
    
    // ============ Events ============
    
    event StakePlaced(
        uint256 indexed battleId,
        address indexed user,
        address indexed agent,
        uint256 amount,
        uint256 stakeIndex
    );
    
    event StakeWithdrawn(
        uint256 indexed battleId,
        address indexed user,
        uint256 amount
    );
    
    event WinningsClaimed(
        uint256 indexed battleId,
        address indexed user,
        uint256 amount
    );
    
    event StakeLimitsUpdated(uint256 minStake, uint256 maxStake);
    
    // ============ Errors ============
    
    error InvalidBattle();
    error InvalidAgent();
    error InvalidAmount();
    error BelowMinStake();
    error AboveMaxStake();
    error InsufficientBalance();
    error BattleNotResolved();
    error AlreadyClaimed();
    error NoStakeFound();
    error NotCoreContract();
    error TransferFailed();
    error StakingEnded();
    error BattleNotActive();
    
    // ============ Modifiers ============
    
    modifier onlyCore() {
        if (msg.sender != coreContract) revert NotCoreContract();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }
    
    // ============ External Functions ============
    
    /**
     * @notice Set the core contract address
     * @param _coreContract The ClankerWarsCore address
     */
    function setCoreContract(address _coreContract) external {
        require(coreContract == address(0), "Already set");
        coreContract = _coreContract;
    }
    
    /**
     * @notice Set the prize distributor address
     * @param _prizeDistributor The PrizeDistributor address
     */
    function setPrizeDistributor(address _prizeDistributor) external onlyCore {
        require(prizeDistributor == address(0), "Already set");
        prizeDistributor = _prizeDistributor;
    }
    
    /**
     * @notice Transfer accumulated fees to prize distributor (called by core or prize distributor)
     * @param amount Amount to transfer
     */
    function transferFees(uint256 amount) external {
        require(msg.sender == coreContract || msg.sender == prizeDistributor, "Unauthorized");
        stakingToken.safeTransfer(prizeDistributor, amount);
    }
    
    /**
     * @notice Place a stake on an agent for a battle (called by core)
     * @param battleId The battle ID
     * @param user The user placing the stake
     * @param agent The agent to stake on
     * @param amount Amount to stake
     */
    function stakeFor(
        uint256 battleId,
        address user,
        address agent,
        uint256 amount
    ) external onlyCore nonReentrant {
        if (amount < minStake) revert BelowMinStake();
        if (amount > maxStake) revert AboveMaxStake();
        if (amount == 0) revert InvalidAmount();

        // Transfer tokens from core contract (tokens were already pulled from user by core)
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create stake record
        uint256 stakeIdx = battleStakes[battleId].length;

        battleStakes[battleId].push(ClankerWarsTypes.Stake({
            user: user,
            agent: agent,
            amount: amount,
            battleId: battleId,
            stakedAt: block.timestamp,
            claimed: false,
            winnings: 0
        }));

        userStakeIndex[battleId][user][agent] = stakeIdx;
        totalStakedOnAgent[battleId][agent] += amount;
        userTotalStake[user] += amount;
        totalStakes++;

        emit StakePlaced(battleId, user, agent, amount, stakeIdx);
    }
    
    /**
     * @notice Record winnings for a stake (called by core on resolution)
     * @param battleId The battle ID
     * @param stakeIndex Index of the stake
     * @param winnings Amount won
     */
    function recordWinnings(
        uint256 battleId,
        uint256 stakeIndex,
        uint256 winnings
    ) external onlyCore {
        ClankerWarsTypes.Stake storage s = battleStakes[battleId][stakeIndex];
        s.winnings = winnings;
    }
    
    /**
     * @notice Claim winnings for a resolved battle (called by core)
     * @param user The user claiming winnings
     * @param battleId The battle ID
     * @param agent The agent staked on
     */
    function claimWinningsFor(address user, uint256 battleId, address agent) external onlyCore nonReentrant {
        uint256 stakeIdx = userStakeIndex[battleId][user][agent];
        ClankerWarsTypes.Stake storage s = battleStakes[battleId][stakeIdx];
        
        if (s.user != user) revert NoStakeFound();
        if (s.claimed) revert AlreadyClaimed();
        if (s.winnings == 0) revert BattleNotResolved();
        
        s.claimed = true;
        userTotalStake[user] -= s.amount;
        
        // Transfer winnings to user
        stakingToken.safeTransfer(user, s.winnings);
        
        emit WinningsClaimed(battleId, user, s.winnings);
    }
    
    /**
     * @notice Batch claim winnings for multiple battles
     * @param battleIds Array of battle IDs
     * @param agents Array of agents (must match battleIds length)
     */
    function batchClaimWinnings(
        uint256[] calldata battleIds,
        address[] calldata agents
    ) external nonReentrant {
        require(battleIds.length == agents.length, "Length mismatch");
        
        uint256 totalClaim;
        
        for (uint256 i = 0; i < battleIds.length; i++) {
            uint256 stakeIdx = userStakeIndex[battleIds[i]][msg.sender][agents[i]];
            ClankerWarsTypes.Stake storage s = battleStakes[battleIds[i]][stakeIdx];
            
            if (s.user != msg.sender || s.claimed || s.winnings == 0) {
                continue;
            }
            
            s.claimed = true;
            userTotalStake[msg.sender] -= s.amount;
            totalClaim += s.winnings;
            
            emit WinningsClaimed(battleIds[i], msg.sender, s.winnings);
        }
        
        if (totalClaim > 0) {
            stakingToken.safeTransfer(msg.sender, totalClaim);
        }
    }
    
    /**
     * @notice Admin: Update stake limits
     * @param _minStake New minimum stake
     * @param _maxStake New maximum stake
     */
    function setStakeLimits(uint256 _minStake, uint256 _maxStake) external onlyCore {
        require(_minStake < _maxStake, "Invalid limits");
        minStake = _minStake;
        maxStake = _maxStake;
        emit StakeLimitsUpdated(_minStake, _maxStake);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get stake details
     * @param battleId Battle ID
     * @param index Stake index
     */
    function getStake(uint256 battleId, uint256 index)
        external
        view
        returns (ClankerWarsTypes.Stake memory)
    {
        return battleStakes[battleId][index];
    }
    
    /**
     * @notice Get user's stake on a specific agent in a battle
     * @param battleId Battle ID
     * @param user User address
     * @param agent Agent address
     */
    function getUserStake(uint256 battleId, address user, address agent)
        external
        view
        returns (ClankerWarsTypes.Stake memory)
    {
        uint256 idx = userStakeIndex[battleId][user][agent];
        return battleStakes[battleId][idx];
    }
    
    /**
     * @notice Get total number of stakes for a battle
     * @param battleId Battle ID
     */
    function getBattleStakeCount(uint256 battleId) external view returns (uint256) {
        return battleStakes[battleId].length;
    }
    
    /**
     * @notice Get all stakes for a battle (paginated)
     * @param battleId Battle ID
     * @param offset Starting index
     * @param limit Maximum to return
     */
    function getBattleStakes(
        uint256 battleId,
        uint256 offset,
        uint256 limit
    ) external view returns (ClankerWarsTypes.Stake[] memory) {
        uint256 total = battleStakes[battleId].length;
        if (offset >= total) return new ClankerWarsTypes.Stake[](0);
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        
        uint256 count = end - offset;
        ClankerWarsTypes.Stake[] memory result = new ClankerWarsTypes.Stake[](count);
        
        for (uint256 i = 0; i < count; i++) {
            result[i] = battleStakes[battleId][offset + i];
        }
        
        return result;
    }
    
    /**
     * @notice Calculate potential winnings for a stake
     * @param battleId Battle ID
     * @param agent Agent staked on
     * @param amount Stake amount
     */
    function calculatePotentialWinnings(
        uint256 battleId,
        address agent,
        uint256 amount
    ) external view returns (uint256) {
        uint256 totalPool = totalStakedOnAgent[battleId][agent];
        uint256 oppositePool = totalStakedOnAgent[battleId][getOpponent(battleId, agent)];
        
        if (totalPool == 0) return 0;
        
        // Proportional share of opposite pool + original stake
        uint256 share = (amount * oppositePool) / totalPool;
        return amount + share;
    }
    
    /**
     * @notice Helper to get opponent (would be provided by core in practice)
     */
    function getOpponent(uint256, address) internal pure returns (address) {
        // This is a placeholder - actual implementation uses core contract
        return address(0);
    }
}
