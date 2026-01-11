# Vultara Smart Contracts

Smart contracts for the Vultara Protocol on Base.

## Deployed Contracts

| Network | Contract | Address |
|---------|----------|---------|
| Base Sepolia | VultaraETHVault | `0xedef77ed8a73d9a6ed9b4309451e5fce6705b677` |

## Contracts

### VultaraETHVault (Primary)
Native ETH vault that:
- Accepts ETH deposits directly (no approval needed)
- Issues vault shares (vETH) representing ownership
- Designed for integration with Thetanuts V4 options strategies

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

### Deploy to Base Sepolia

1. Copy environment file:
```bash
cp .env.example .env
```

2. Fill in your private key and RPC URL (Base Sepolia)

3. Deploy ETH Vault:
```bash
source .env
forge script script/DeployETHVault.s.sol:DeployETHVault \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify
```

## Key Features

### VultaraETHVault
- **Native ETH**: No token approvals needed
- **Simple UX**: Single transaction deposit
- **Reentrancy Protected**: Using OpenZeppelin's ReentrancyGuard
- **Ownable**: Admin functions protected by ownership
- **Min Deposit**: 0.001 ETH

## Security

- OpenZeppelin v5.5 audited contracts
- Reentrancy protection on all state-changing functions
- Owner-only admin functions
- Emergency withdrawal mechanism

## License

MIT
