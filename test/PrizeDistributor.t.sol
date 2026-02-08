// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PrizeDistributor.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**6); // 1M tokens with 6 decimals
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PrizeDistributorTest is Test {
    PrizeDistributor public distributor;
    MockERC20 public token;
    
    address public owner = address(1);
    address public treasury = address(2);
    address public coreContract = address(3);
    address public agentA = address(4);
    address public agentB = address(5);
    address public user1 = address(6);
    address public user2 = address(7);
    
    function setUp() public {
        vm.startPrank(owner);
        token = new MockERC20("Test USDC", "TUSDC");
        distributor = new PrizeDistributor(address(token), treasury);
        distributor.setCoreContract(coreContract);
        vm.stopPrank();
    }
    
    function test_CalculateDistribution() public {
        uint256 poolA = 1000e6; // 1000 USDC
        uint256 poolB = 2000e6; // 2000 USDC
        
        (uint256 winnerPool, uint256 totalPrize, uint256 protocolFee, uint8 winningAgent) = 
            distributor.calculateDistribution(poolA, poolB, agentA, agentA, agentB);
        
        assertEq(winnerPool, poolA);
        assertEq(winningAgent, 0);
        assertEq(protocolFee, (poolA + poolB) * 250 / 10000); // 2.5%
        assertEq(totalPrize, poolA + poolB - protocolFee);
    }
    
    function test_CalculateDistribution_Draw() public {
        uint256 poolA = 1000e6;
        uint256 poolB = 2000e6;
        
        (uint256 winnerPool, uint256 totalPrize, uint256 protocolFee, uint8 winningAgent) = 
            distributor.calculateDistribution(poolA, poolB, address(0), agentA, agentB);
        
        assertEq(winningAgent, 2); // Draw
        assertEq(protocolFee, 0); // No fee on draws
        assertEq(totalPrize, poolA + poolB);
    }
    
    function test_DistributePrizes() public {
        uint256 poolA = 1000e6;
        uint256 poolB = 2000e6;
        uint256 totalPool = poolA + poolB;
        uint256 expectedFee = totalPool * 250 / 10000;
        
        // Fund distributor
        token.mint(address(distributor), totalPool);
        
        vm.prank(coreContract);
        (uint256 totalPrize, uint256 protocolFee) = distributor.distributePrizes(
            1, // battleId
            agentA,
            poolA,
            poolB,
            agentA,
            agentB
        );
        
        assertEq(protocolFee, expectedFee);
        assertEq(totalPrize, totalPool - expectedFee);
        assertEq(distributor.accumulatedFees(), expectedFee);
    }
    
    function test_CalculateUserWinnings() public {
        uint256 userStake = 100e6; // 100 USDC
        uint256 winnerPool = 1000e6; // Total on winning side
        uint256 totalPrize = 2700e6; // After 2.5% fee from 3000 total
        
        uint256 winnings = distributor.calculateUserWinnings(userStake, winnerPool, totalPrize);
        
        // User gets proportional share: (100/1000) * 2700 = 270
        assertEq(winnings, 270e6);
    }
    
    function test_WithdrawFees() public {
        uint256 poolA = 1000e6;
        uint256 poolB = 2000e6;
        
        // Fund and distribute
        token.mint(address(distributor), poolA + poolB);
        
        vm.prank(coreContract);
        distributor.distributePrizes(1, agentA, poolA, poolB, agentA, agentB);
        
        uint256 expectedFee = (poolA + poolB) * 250 / 10000;
        
        // Withdraw fees
        vm.prank(owner);
        distributor.withdrawFees();
        
        assertEq(token.balanceOf(treasury), expectedFee);
        assertEq(distributor.accumulatedFees(), 0);
    }
    
    function test_Revert_WithdrawFees_NoFees() public {
        vm.prank(owner);
        vm.expectRevert(PrizeDistributor.NoFeesToWithdraw.selector);
        distributor.withdrawFees();
    }
    
    function test_SetTreasury() public {
        address newTreasury = address(8);
        
        vm.prank(owner);
        distributor.setTreasury(newTreasury);
        
        // New treasury should receive future fees
        uint256 poolA = 1000e6;
        uint256 poolB = 2000e6;
        token.mint(address(distributor), poolA + poolB);
        
        vm.prank(coreContract);
        distributor.distributePrizes(1, agentA, poolA, poolB, agentA, agentB);
        
        vm.prank(owner);
        distributor.withdrawFees();
        
        assertGt(token.balanceOf(newTreasury), 0);
    }
    
    function test_GetFeeRate() public {
        assertEq(distributor.getFeeRate(), 250); // 2.5% in BPS
    }
    
    function test_CalculateFee() public {
        uint256 amount = 10000e6;
        uint256 fee = distributor.calculateFee(amount);
        assertEq(fee, 250e6); // 2.5% of 10000
    }
}
