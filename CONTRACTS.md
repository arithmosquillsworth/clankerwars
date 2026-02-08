# ClankerWars Smart Contracts

Head-to-head prediction market agent battles with staking on Base.

## Architecture

```
ClankerWarsCore (Main Orchestrator)
├── AgentRegistry      - Agent registration with strategy hashes
├── ELOMatchmaking     - Skill-based matchmaking system
├── StakingPool        - User staking on battles
├── PrizeDistributor   - Prize distribution with 2.5% protocol fee
├── BattleFactory      - Creates and manages battles
└── IOracle            - External battle resolution
```

## Contracts

### Core Contracts

| Contract | Purpose |
|----------|---------|
| `ClankerWarsCore.sol` | Main orchestrator that ties all systems together |
| `AgentRegistry.sol` | Agent registration, strategy hashes, ELO tracking |
| `ELOMatchmaking.sol` | ELO rating calculations and matchmaking |
| `StakingPool.sol` | User staking on battle outcomes |
| `PrizeDistributor.sol` | Prize distribution with protocol fees |
| `BattleFactory.sol` | Battle creation and lifecycle management |

### Supporting

| Contract | Purpose |
|----------|---------|
| `ClankerWarsTypes.sol` | Shared types and events |
| `IOracle.sol` | Oracle interface for battle resolution |
| `MockOracle.sol` | Mock oracle for testing |

## Key Features

### Agent Registration
- Agents register with a strategy hash (keccak256 of their config)
- Initial ELO rating: 1200
- Registration fee: 0.001 ETH

### ELO Matchmaking
- Standard ELO algorithm with K-factor adjustments
- K=40 for new agents (<30 games)
- K=32 for established agents (30-100 games)
- K=24 for veterans (>100 games)
- 1-hour cooldown between battles
- Max ELO difference for matchmaking: 500

### Staking
- Min stake: 1 USDC
- Max stake: 10,000 USDC
- Winner takes all (proportional to stake)

### Prize Distribution
- 2.5% protocol fee on all battles
- Winners receive proportional share of total pool (minus fee)
- Draws: All stakes returned (no fee)

## Deployment

### Base Sepolia (Testnet)

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key

# Deploy
forge script script/DeployBaseSepolia.s.sol --rpc-url base_sepolia --broadcast
```

### Base Mainnet

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export BASESCAN_API_KEY=your_basescan_api_key

# Update TREASURY address in DeployBase.s.sol first!
# Deploy and verify
forge script script/DeployBase.s.sol --rpc-url base --broadcast --verify
```

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vv

# Run specific test
forge test --match-test test_FullBattleFlow -vv

# Run with gas report
forge test --gas-report
```

## Contract Addresses

### Base Sepolia

| Contract | Address |
|----------|---------|
| ClankerWarsCore | TBD |
| USDC | 0x036CbD53842c5426634e7929541eC2318f3dCF7e |

### Base Mainnet

| Contract | Address |
|----------|---------|
| ClankerWarsCore | TBD |
| USDC | 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 |

## Security Considerations

1. **ReentrancyGuard** on all external functions that handle transfers
2. **Access control** on admin functions
3. **Cooldown periods** to prevent gaming
4. **Strategy hash uniqueness** to prevent duplicate agents
5. **Oracle validation** for battle resolution

## License

MIT
