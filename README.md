<div align="center">

# Total-Lean-Pilot

[![Security Audit CI](https://github.com/karamik/Total-Lean-Pilot/actions/workflows/security-audit.yml/badge.svg)](https://github.com/karamik/Total-Lean-Pilot/actions/workflows/security-audit.yml)
[![Coverage](https://codecov.io/gh/karamik/Total-Lean-Pilot/branch/main/graph/badge.svg)](https://codecov.io/gh/karamik/Total-Lean-Pilot)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)

**Lean Pilot — упрощённая версия TOTAL Protocol. Запуск за 3-6 месяцев, $28K.**

Доказываем экономику ZK-rollup на облачном FPGA перед инвестициями в космический-grade hardware.

</div>

---

## 🔒 Security Status

| Tool | Type | What It Finds | Status |
|------|------|---------------|--------|
| **Slither** | Static Analysis | Reentrancy, unchecked calls, tx.origin | 🔴 Blocks PR on High/Critical |
| **Mythril** | Symbolic Execution | Deep path exploration, edge cases | 🟡 Warns on High/Critical |
| **Echidna** | Property Fuzzing | Invariant violations, 50k transactions | 🔴 Blocks PR on failure |
| **Foundry** | Unit + Invariant Tests | 10k-100k fuzz runs per test | 🔴 Blocks PR on failure |
| **Coverage** | Code Coverage | Line + branch coverage tracking | 📊 Target: >90% |

### FeeSplitter Security Protections

| Vulnerability | Protection | Location |
|---------------|------------|----------|
| Reentrancy | `nonReentrant` + Checks-Effects-Interactions | `claim()` |
| Access Control | `AccessControl` + role-based permissions | `distribute()`, `updateRecipients()` |
| DoS (gas limit) | Pull-over-push + `MAX_RECIPIENTS` | `distribute()` |
| Rounding errors | Basis points (10000) + dust handling | `distribute()` |
| Rug pull | 14-day timelock + max 5% change/epoch | `updateRecipients()` |
| Emergency pause | `Pausable` + `emergencyWithdraw()` | Admin only |
| Failed transfer | No external calls in distribution loop | Pull pattern |

---

## 🎯 Pilot Objectives

| What We Test | How | Success Criteria |
|--------------|-----|------------------|
| PLONK proof generation | AWS F1 VU9P FPGA | < 10 sec/transaction |
| Fee Splitter | Solidity smart contract | Pull-over-push, ReentrancyGuard, timelock |
| DA Layer | Celestia blobspace | < $100/month storage |
| Economics | $0.01/tx fee | Break-even Day 1 |

---

## 🏗️ Architecture

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  User   │────▶│  Geth   │────▶│ AWS F1  │────▶│Celestia │
│ $0.01/tx│◀────│  Fork   │◀────│  VU9P   │◀────│   DA    │
└─────────┘     └────┬────┘     └─────────┘     └─────────┘
                     │
                     ▼
            ┌─────────────────┐
            │  Fee Splitter   │  ← Pull-over-push + ReentrancyGuard
            │  Provers  35%   │  ← nonReentrant claim()
            │  Validators 25% │  ← Role-based access control
            │  Treasury  20%  │  ← 14-day timelock on changes
            │  DA Layer  15%  │  ← Pausable + emergency withdraw
            │  Burn       5%  │
            └─────────────────┘
```

### Components

| Component | Technology | Cost/Month | Status |
|-----------|-----------|------------|--------|
| Execution | Geth fork (Evmos-based) | $140 (2x t3.large) | 🔲 |
| Prover | AWS F1 f1.4xlarge (VU9P) | $2,376 | 🔲 |
| DA Layer | Celestia light node | $100 | 🔲 |
| Validators | PoA, 3 nodes (t3.medium) | $90 | 🔲 |
| Monitoring | Prometheus + Grafana | $50 | 🔲 |
| Fee Splitter | Solidity 0.8.26 | $0 (gas only) | ✅ |
| **Total OPEX** | — | **~$2,800/month** | — |

---

## 💰 Economics

### Revenue Model

| Parameter | Value |
|-----------|-------|
| TPS capacity | 100-500 |
| Fee | $0.01 (pilot premium) |
| Utilization | 10% |
| Effective TPS | 10-50 |
| Transactions/day | 864K - 4.3M |
| Revenue/day | $8,640 - $43,200 |
| Revenue/month | ~$260K - $1.3M |

### Cost Structure

| Item | Month | 6 Months |
|------|-------|----------|
| AWS F1 prover | $2,376 | $14,256 |
| Execution nodes | $140 | $840 |
| Celestia DA | $100 | $600 |
| Validators | $90 | $540 |
| Monitoring | $50 | $300 |
| **Total OPEX** | **$2,756** | **$16,536** |
| NRE (audit, dev) | — | $11,000 |
| **Grand Total** | — | **~$28,000** |

### Break-even

```
Break-even = OPEX / (Fee x TPS x 86400 x 30)
           = $2,756 / ($0.01 x 1 x 86400 x 30)
           = $2,756 / $25,920
           = 0.11 TPS

→ Break-even at any utilization > 0.1%
```

### Realistic Scenarios

| Scenario | Utilization | TPS | Revenue/Month | Margin |
|----------|-------------|-----|---------------|--------|
| Conservative | 1% | 1-5 | $26K | 89% |
| Realistic | 5% | 5-25 | $130K | 98% |
| Optimistic | 20% | 20-100 | $520K | 99.5% |

---

## 🚀 Quick Start

### Prerequisites

- AWS account with F1 access
- Go 1.22+
- Node.js 20+
- Foundry (`forge`, `cast`)
- Celestia light node

### 1. Clone & Setup

```bash
git clone https://github.com/karamik/Total-Lean-Pilot.git
cd Total-Lean-Pilot

# Install dependencies
make deps  # Geth, Foundry, Celestia CLI
```

### 2. Install Contract Dependencies

```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
```

### 3. Run Tests

```bash
# Quick run (CI profile)
FOUNDRY_PROFILE=ci forge test

# Security audit (100k fuzz runs)
FOUNDRY_PROFILE=security forge test

# Gas analysis
FOUNDRY_PROFILE=gas forge test --gas-report

# Slither static analysis
slither src/FeeSplitter.sol --config slither.config.json

# Mythril symbolic execution
myth analyze src/FeeSplitter.sol --solc-json mythril.config.json

# Echidna property fuzzing
echidna test/FeeSplitterEchidna.sol --contract FeeSplitterEchidna --config echidna.config.yml
```

### 4. Start Local Devnet

```bash
# Terminal 1: Execution node
make devnet-up

# Terminal 2: Celestia light node (mock for local dev)
make celestia-mock

# Terminal 3: Prover (CPU mode for dev)
make prover-dev
```

### 5. Deploy Fee Splitter

```bash
cd contracts/
forge build
forge script script/DeployFeeSplitter.s.sol --rpc-url http://localhost:8545 --broadcast
```

### 6. Send Test Transaction

```bash
cast send 0xFEE...SPLITTER --value 0.01ether --rpc-url http://localhost:8545
```

---

## 📁 Repository Structure

```
Total-Lean-Pilot/
├── README.md                 # This file
├── Makefile                  # Common tasks
├── LICENSE                   # MIT License
│
├── .github/
│   ├── workflows/
│   │   └── security-audit.yml   # CI: 11 jobs, security focus
│   └── dependabot.yml           # Auto dependency updates
│
├── docs/                     # Documentation
│   ├── ARCHITECTURE.md       # System design
│   ├── ECONOMICS.md          # Financial model
│   ├── PROVER.md             # FPGA prover spec
│   ├── DA_INTEGRATION.md     # Celestia integration
│   ├── API.md                # RPC API reference
│   ├── DEPLOYMENT.md         # Deployment guide
│   └── SECURITY.md           # Security model & audit results
│
├── execution/                # Geth fork (Evmos-based)
│   ├── cmd/
│   │   └── total-geth/
│   ├── core/
│   │   ├── total_config.go   # Chain config + FeeSplitter address
│   │   ├── fee_routing.go    # Fee -> Splitter (pull pattern)
│   │   └── total_clique.go   # Modified PoA consensus
│   └── go.mod
│
├── prover/                   # ZK Prover (AWS F1)
│   ├── fpga/
│   │   ├── hdl/              # Verilog/VHDL kernels
│   │   ├── host/             # C++ host code
│   │   └── aie/              # AI Engine kernels
│   ├── circuits/
│   │   └── plonk/
│   │       ├── witness.rs
│   │       ├── prover.rs
│   │       └── verifier.rs
│   └── Cargo.toml
│
├── contracts/                # Solidity smart contracts
│   ├── foundry.toml          # Optimized compiler config
│   ├── remappings.txt        # Import mappings
│   ├── slither.config.json   # Slither settings
│   ├── mythril.config.json   # Mythril settings
│   ├── echidna.config.yml    # Echidna fuzzing config
│   ├── src/
│   │   ├── FeeSplitter.sol   # Main fee distribution (secure)
│   │   └── ProverRegistry.sol # Prover staking
│   ├── script/
│   │   └── DeployFeeSplitter.s.sol
│   └── test/
│       ├── FeeSplitter.t.sol      # Unit + security tests
│       └── FeeSplitterEchidna.sol # Property fuzzing target
│
├── da/                       # Data Availability
│   ├── celestia/
│   │   ├── client.go         # Blob submission
│   │   └── index.go          # DA index
│   └── ipfs/                 # (future: archival)
│
├── validator/                # PoA validator set
│   ├── clique/
│   │   └── total_clique.go   # Modified clique
│   └── docker/
│       └── docker-compose.yml
│
├── monitoring/               # Prometheus + Grafana
│   ├── prometheus.yml
│   └── dashboards/
│       └── total-overview.json
│
└── scripts/                  # Deployment & ops
    ├── generate_genesis.py   # Genesis generator
    ├── validate_genesis.py   # Genesis validator
    ├── deploy-testnet.sh
    ├── deploy-mainnet.sh
    └── benchmark.sh
```

---

## 🔧 Development

### Build

```bash
# All components
make build

# Individual components
make build-execution
make build-prover
make build-contracts
```

### Test

```bash
# Unit tests
make test

# Integration tests
make test-integration

# FPGA emulation (no hardware needed)
make test-fpga-emulation

# Full security audit (all tools)
make audit

# Individual audit tools
make audit-slither
make audit-mythril
make audit-echidna
```

### Benchmark

```bash
# Proof generation benchmark
make benchmark-prover

# End-to-end throughput
make benchmark-tps

# Cost analysis
make benchmark-economics
```

---

## 🛡️ Security

### Audit Tools Matrix

| Tool | Type | Finds | CI Time | Blocks PR |
|------|------|-------|---------|-----------|
| **Slither** | Static Analysis | Known vulnerability patterns | 3 min | 🔴 Yes (High/Critical) |
| **Mythril** | Symbolic Execution | Deep path exploration | 15 min | 🟡 Warns |
| **Echidna** | Property Fuzzing | Invariant violations | 30 min | 🔴 Yes |
| **Foundry** | Unit/Invariant | Functionality, regression | 2-45 min | 🔴 Yes |

### Running Security Audit Locally

```bash
# Full audit
make audit-full

# Individual tools
cd contracts

# Slither
slither src/FeeSplitter.sol --config slither.config.json

# Mythril
myth analyze src/FeeSplitter.sol --solc-json mythril.config.json --execution-timeout 600

# Echidna
echidna test/FeeSplitterEchidna.sol --contract FeeSplitterEchidna --config echidna.config.yml
```

---

## 🛣️ Roadmap

| Phase | Weeks | What | Status |
|-------|-------|------|--------|
| **Phase 1: Foundation** | W1-2 | Fork Geth, PoA validators, Celestia | ✅ Complete |
| **Phase 2: Prover** | W3-4 | PLONK on AWS F1 VU9P | 🔄 In Progress |
| **Phase 3: Fee Splitter** | W5-6 | Solidity contract + security audit | ✅ Complete |
| **Phase 4: DA Integration** | W7-8 | Blob submission from Geth | 🔲 |
| **Phase 5: Testnet** | W9-10 | Public testnet, faucet, Blockscout | 🔲 |
| **Phase 6: Pilot Mainnet** | W11-14 | Security audit, mainnet deployment | 🔲 |
| **Phase 7: Evaluation** | W15-24 | Metrics, user feedback, optimization | 🔲 |

---

## 🌌 Path to Full Version

```
Lean Pilot (3-6 months, $28K)
    │ Revenue > $100K/month
    ▼
Scale-up (6-12 months, $200K-500K)
    │ Multiple F1 instances
    │ PoS validators (20+)
    │ Celestia + IPFS
    ▼
Full Version (2-3 years, $5M+)
    │ Sentinel Space Core (XQRVC1902)
    │ OCP v2.0 Orbital BFT
    │ On-orbit reconfiguration
    ▼
Space Network (5+ years)
    │ Satellite constellation
    │ Inter-satellite links
    │ Deep space missions
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture |
| [ECONOMICS.md](docs/ECONOMICS.md) | Financial model & break-even analysis |
| [PROVER.md](docs/PROVER.md) | FPGA prover specification |
| [DA_INTEGRATION.md](docs/DA_INTEGRATION.md) | Celestia integration guide |
| [API.md](docs/API.md) | RPC API reference |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Deployment guide |
| [SECURITY.md](docs/SECURITY.md) | Security model & audit results |

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

### Requirements

- All tests pass (`forge test`)
- Slither finds no High/Critical issues
- Code coverage > 90%
- Code formatted (`forge fmt`)
- Gas snapshot checked (`forge snapshot --check`)

---

## ⚠️ Disclaimer

This is a **pilot project**. Not intended for production use without thorough security audit. The space-grade hardware (Sentinel Space Core) is a future roadmap item — this pilot uses cloud FPGA for rapid validation.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

Built with 💜 for the future of decentralized space infrastructure

**TOTAL Protocol — From Earth to Orbit**

</div>
