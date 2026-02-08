// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IStakingPool {
    function transferFees(uint256 amount) external;
}

/**
 * @title PrizeDistributor
 * @notice Handles prize distribution with 2.5% protocol fee
 */
contract PrizeDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    // Protocol fee: 2.5% = 250 basis points
    uint256 public constant PROTOCOL_FEE_BPS = 250;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // ============ State Variables ============
    
    IERC20 public immutable stakingToken;
    address public coreContract;
    address public protocolTreasury;
    address public stakingPool;
    
    // Accumulated fees
    uint256 public accumulatedFees;
    
    // Total distributed
    uint256 public totalDistributed;
    uint256 public totalFeesCollected;
    
    // ============ Events ============
    
    event PrizeDistributed(
        uint256 indexed battleId,
        address indexed winner,
        uint256 totalPool,
        uint256 winnerPrize,
        uint256 protocolFee
    );
    
    event FeesWithdrawn(address indexed to, uint256 amount);
    
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    
    // ============ Errors ============
    
    error InvalidAmount();
    error InvalidTreasury();
    error NotCoreContract();
    error TransferFailed();
    error NoFeesToWithdraw();
    
    // ============ Modifiers ============
    
    modifier onlyCore() {
        if (msg.sender != coreContract) revert NotCoreContract();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _stakingToken,
        address _protocolTreasury
    ) Ownable(msg.sender) {
        if (_protocolTreasury == address(0)) revert InvalidTreasury();
        stakingToken = IERC20(_stakingToken);
        protocolTreasury = _protocolTreasury;
    }
    
    // ============ External Functions ============
    
    /**
     * @notice Set the core contract address
     * @param _coreContract The ClankerWarsCore address
     */
    function setCoreContract(address _coreContract) external onlyOwner {
        require(coreContract == address(0), "Already set");
        coreContract = _coreContract;
    }
    
    /**
     * @notice Set the staking pool address
     * @param _stakingPool The StakingPool address
     */
    function setStakingPool(address _stakingPool) external onlyOwner {
        require(stakingPool == address(0), "Already set");
        stakingPool = _stakingPool;
    }
    
    /**
     * @notice Calculate distribution for a battle
     * @param poolA Total staked on agent A
     * @param poolB Total staked on agent B
     * @param winner The winning agent (address(0) for draw)
     * @return winnerPool Total pool for winners (before fee)
     * @return totalPrize Total prize after fee
     * @return protocolFee Fee amount
     * @return winningAgent Which agent won (0 = A, 1 = B, 2 = draw)
     */
    function calculateDistribution(
        uint256 poolA,
        uint256 poolB,
        address winner,
        address agentA,
        address agentB
    ) external pure returns (
        uint256 winnerPool,
        uint256 totalPrize,
        uint256 protocolFee,
        uint8 winningAgent
    ) {
        uint256 totalPool = poolA + poolB;
        
        if (totalPool == 0) {
            return (0, 0, 0, 2);
        }
        
        // Determine winner
        if (winner == agentA) {
            winnerPool = poolA;
            winningAgent = 0;
        } else if (winner == agentB) {
            winnerPool = poolB;
            winningAgent = 1;
        } else {
            // Draw - return all stakes
            return (0, totalPool, 0, 2);
        }
        
        // Calculate fee from total pool
        protocolFee = (totalPool * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        totalPrize = totalPool - protocolFee;
    }
    
    /**
     * @notice Distribute prizes for a battle (called by core)
     * @param battleId Battle ID
     * @param winner Winning agent address
     * @param poolA Stake pool A
     * @param poolB Stake pool B
     * @param agentA Agent A address
     * @param agentB Agent B address
     * @return totalPrize Total prize pool after fee
     * @return protocolFee Fee collected
     */
    function distributePrizes(
        uint256 battleId,
        address winner,
        uint256 poolA,
        uint256 poolB,
        address agentA,
        address agentB
    ) external onlyCore returns (uint256 totalPrize, uint256 protocolFee) {
        uint256 totalPool = poolA + poolB;
        
        if (totalPool == 0) {
            return (0, 0);
        }
        
        // Calculate fee
        protocolFee = (totalPool * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        totalPrize = totalPool - protocolFee;
        
        // Accumulate fees
        accumulatedFees += protocolFee;
        totalFeesCollected += protocolFee;
        totalDistributed += totalPrize;
        
        emit PrizeDistributed(
            battleId,
            winner,
            totalPool,
            totalPrize,
            protocolFee
        );
        
        return (totalPrize, protocolFee);
    }
    
    /**
     * @notice Calculate individual winnings
     * @param userStake User's stake amount
     * @param winnerPool Total pool on winning agent
     * @param totalPrize Total prize pool (after fee)
     * @return winnings User's winnings
     */
    function calculateUserWinnings(
        uint256 userStake,
        uint256 winnerPool,
        uint256 totalPrize
    ) external pure returns (uint256 winnings) {
        if (winnerPool == 0) return 0;
        
        // Proportional share: (userStake / winnerPool) * totalPrize
        // To maintain precision: (userStake * totalPrize) / winnerPool
        winnings = (userStake * totalPrize) / winnerPool;
    }
    
    /**
     * @notice Admin: Withdraw accumulated fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert NoFeesToWithdraw();
        
        accumulatedFees = 0;
        
        // Pull fees from staking pool
        IStakingPool(stakingPool).transferFees(amount);
        
        // Now transfer to treasury
        stakingToken.safeTransfer(protocolTreasury, amount);
        
        emit FeesWithdrawn(protocolTreasury, amount);
    }
    
    /**
     * @notice Admin: Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidTreasury();
        
        address oldTreasury = protocolTreasury;
        protocolTreasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @notice Admin: Emergency withdraw any ERC20
     * @param token Token to withdraw
     * @param to Recipient
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get current fee rate
     */
    function getFeeRate() external pure returns (uint256) {
        return PROTOCOL_FEE_BPS;
    }
    
    /**
     * @notice Calculate fee for a given amount
     * @param amount Amount to calculate fee on
     */
    function calculateFee(uint256 amount) external pure returns (uint256) {
        return (amount * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
    }
}
