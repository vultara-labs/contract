# Vultara Smart Contracts

Smart contracts for the Vultara Protocol on Base Mainnet.

## Deployed Contracts

| Network | Contract | Address |
|---------|----------|---------|
| Base Mainnet | VultaraETHVault | `0xEe0fA979928eb331050EDC0B2b027b97d0144F5a` |

## Contracts

### VultaraETHVault (Primary)
Native ETH vault that:
- Accepts ETH deposits directly (no approval needed)
- Issues vault shares (vETH) representing ownership
- Integrates with Thetanuts V4 options strategies

## Tech Stack

- **Solidity** ^0.8.20
- **Foundry** - Development framework
- **OpenZeppelin** v5.5 - Security contracts

## Project Structure

```
contract/
├── src/
│   └── VultaraETHVault.sol   # ETH vault (primary)
├── test/
│   └── VultaraETHVault.t.sol # Test suite
├── script/
│   └── DeployETHVault.s.sol  # ETH vault deployment
└── lib/
    ├── forge-std/
    └── openzeppelin-contracts/
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install Dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test -vv
```

### Deploy to Base Mainnet

1. Set your private key:
```bash
export PRIVATE_KEY=0x...
```

2. Deploy ETH Vault:
```bash
forge create --rpc-url https://mainnet.base.org --private-key $PRIVATE_KEY src/VultaraETHVault.sol:VultaraETHVault --broadcast
```

3. Verify on Basescan (optional):
```bash
forge verify-contract <DEPLOYED_ADDRESS> src/VultaraETHVault.sol:VultaraETHVault --chain base --etherscan-api-key <API_KEY>
```

## Key Features

### VultaraETHVault
- **Native ETH**: No token approvals needed
- **Dynamic Share Price (Real Yield)**: Shares appreciate in value as strategies earn premiums (ERC-4626 style)
- **Withdrawal Queue System**: Solves liquidity lock issues by queuing withdrawals for the next epoch
- **Simple UX**: Single transaction deposit
- **Reentrancy Protected**: Using OpenZeppelin's ReentrancyGuard
- **Ownable**: Admin functions protected by ownership
- **Min Deposit**: 0.001 ETH
- **Performance Fee**: 10% on Profits (Adjustable, Max 20%)

## Security

- OpenZeppelin v5.5 audited contracts
- Reentrancy protection on all state-changing functions
- Owner-only admin functions
- Emergency withdrawal mechanism

## License

MIT
