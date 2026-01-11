# Vultara Smart Contract

ERC-4626 Vault contract for the Vultara Protocol on Base.

## Overview

VultaraVault is an ERC-4626 compliant tokenized vault that:
- Accepts USDC deposits
- Issues vault shares (vUSDC) representing ownership
- Designed for integration with Thetanuts V4 options strategies

## Tech Stack

- **Solidity** ^0.8.20
- **Foundry** - Development framework
- **OpenZeppelin** v5.5 - Security contracts

## Project Structure

```
contract/
├── src/
│   └── VultaraVault.sol    # Main vault contract
├── test/
│   └── VultaraVault.t.sol  # Test suite
├── script/
│   └── DeployVultaraVault.s.sol  # Deployment script
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

2. Fill in your private key and RPC URL

3. Deploy:
```bash
source .env
forge script script/DeployVultaraVault.s.sol:DeployVultaraVault \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify
```

## Contract Addresses

| Network | Contract | Address |
|---------|----------|---------|
| Base Sepolia | VultaraVault | `TBD` |
| Base Sepolia | USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

## Key Features

- **ERC-4626 Compliant**: Standard vault interface for DeFi composability
- **Reentrancy Protected**: Using OpenZeppelin's ReentrancyGuard
- **Ownable**: Admin functions protected by ownership
- **Performance Fee**: Configurable fee up to 20%
- **Strategy Ready**: Placeholder for Thetanuts V4 integration

## Security

- OpenZeppelin v5.5 audited contracts
- Reentrancy protection on all state-changing functions
- Owner-only admin functions
- Emergency withdrawal mechanism

## License

MIT
