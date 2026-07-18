# Total-Lean-Pilot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Pilot](https://img.shields.io/badge/status-pilot-teal.svg)]()
[![TPS: 100-500](https://img.shields.io/badge/TPS-100--500-blue.svg)]()
[![Proof: PLONK](https://img.shields.io/badge/proof-PLONK-purple.svg)]()
[![DA: Celestia](https://img.shields.io/badge/DA-Celestia-green.svg)]()

> **Lean Pilot** — упрощённая версия TOTAL Protocol. Запуск за 3-6 месяцев, $28K, без CAPEX на железо.
> 
> Доказываем экономику ZK-rollup на облачном FPGA перед инвестициями в космический-grade hardware.

---

## 🎯 Цель пилота

| Что проверяем | Как | Критерий успеха |
|---------------|-----|-----------------|
| PLONK proof generation | AWS F1 VU9P FPGA | < 10 сек/транзакция |
| Fee Splitter | Solidity smart contract | Прозрачное распределение |
| DA Layer | Celestia blobspace | < $100/мес за storage |
| Экономика | $0.01/tx комиссия | Break-even Day 1 |

---

## 🏗️ Архитектура

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  User   │────▶│  Geth   │────▶│ AWS F1  │────▶│Celestia │
│ $0.01/tx│◀────│  Fork   │◀────│  VU9P   │◀────│   DA    │
└─────────┘     └────┬────┘     └─────────┘     └─────────┘
                     │
                     ▼
            ┌─────────────────┐
            │  Fee Splitter   │
            │  Provers  35%   │
            │  Validators 25% │
            │  Treasury  20%  │
            │  DA Layer  15%  │
            │  Burn       5%  │
            └─────────────────┘
```

### Компоненты

| Компонент | Технология | Стоимость/мес | Статус |
|-----------|-----------|---------------|--------|
| **Execution** | Geth fork (Evmos-based) | $140 (2× t3.large) | 🔲 |
| **Prover** | AWS F1 f1.4xlarge (VU9P) | $2,376 | 🔲 |
| **DA Layer** | Celestia light node | $100 | 🔲 |
| **Validators** | PoA, 3 nodes (t3.medium) | $90 | 🔲 |
| **Monitoring** | Prometheus + Grafana | $50 | 🔲 |
| **Fee Splitter** | Solidity 0.8.26 | $0 (gas only) | 🔲 |
| **Итого** | — | **~$2,800/мес** | — |

---

## 🚀 Quick Start

### Prerequisites

- AWS account with F1 access
- Go 1.22+
- Node.js 20+
- Foundry (forge, cast)
- Celestia light node

### 1. Clone & Setup

```bash
git clone https://github.com/karamik/Total-Lean-Pilot.git
cd Total-Lean-Pilot

# Install dependencies
make deps  # Geth, Foundry, Celestia CLI
```

### 2. Start Local Devnet

```bash
# Terminal 1: Execution node
make devnet-up

# Terminal 2: Celestia light node (mock for local dev)
make celestia-mock

# Terminal 3: Prover (CPU mode for dev)
make prover-dev
```

### 3. Deploy Fee Splitter

```bash
cd contracts/
forge build
forge script script/DeployFeeSplitter.s.sol --rpc-url http://localhost:8545 --broadcast
```

### 4. Send Test Transaction

```bash
cast send 0xFEE...SPLITTER --value 0.01ether --rpc-url http://localhost:8545
```

---

## 📁 Repository Structure

```
Total-Lean-Pilot/
├── README.md                 # This file
├── Makefile                  # Common tasks
├──
├── docs/                     # Documentation
│   ├── ARCHITECTURE.md       # System design
│   ├── ECONOMICS.md          # Financial model
│   ├── PROVER.md             # FPGA prover spec
│   └── DA_INTEGRATION.md     # Celestia integration
│
├── execution/                # Geth fork (Evmos-based)
│   ├── cmd/
│   │   └── total-geth/
│   ├── core/
│   │   ├── total_config.go   # Chain config
│   │   └── fee_routing.go    # Fee → Splitter
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
│   ├── src/
│   │   ├── FeeSplitter.sol   # Main fee distribution
│   │   └── ProverRegistry.sol # Prover staking
│   ├── script/
│   │   └── DeployFeeSplitter.s.sol
│   └── test/
│       └── FeeSplitter.t.sol
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
    ├── deploy-testnet.sh
    ├── deploy-mainnet.sh
    └── benchmark.sh
```

---

## 📊 Economics

### Revenue Model

| Параметр | Значение |
|----------|----------|
| TPS capacity | 100-500 |
| Комиссия | $0.01 (pilot premium) |
| Utilization | 10% |
| Effective TPS | 10-50 |
| Транзакций/день | 864K - 4.3M |
| Доход/день | $8,640 - $43,200 |
| **Доход/мес** | **~$260K - $1.3M** |

### Cost Structure

| Статья | Месяц | 6 месяцев |
|--------|-------|-----------|
| AWS F1 prover | $2,376 | $14,256 |
| Execution nodes | $140 | $840 |
| Celestia DA | $100 | $600 |
| Validators | $90 | $540 |
| Monitoring | $50 | $300 |
| **Итого OPEX** | **$2,756** | **$16,536** |
| NRE (audit, dev) | — | $11,000 |
| **Grand Total** | — | **~$28,000** |

### Break-even

```
Break-even = OPEX / (Комиссия × TPS × 86400 × 30)
           = $2,756 / ($0.01 × 1 × 86400 × 30)
           = $2,756 / $25,920
           = 0.11 TPS

→ Break-even при любом utilization > 0.1%
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

## 🛣️ Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Fork Geth, add TOTAL config
- [ ] Deploy 3-node PoA validator set
- [ ] Setup Celestia light node
- [ ] Basic RPC endpoint

### Phase 2: Prover (Week 3-4)
- [ ] Port PLONK kernel to AWS F1 VU9P
- [ ] Create AFI (Amazon FPGA Image)
- [ ] Integrate with Geth
- [ ] Test proof generation (< 10 сек)

### Phase 3: Fee Splitter (Week 5-6)
- [ ] Deploy Solidity contract
- [ ] Integrate with Geth fee routing
- [ ] Test distribution
- [ ] Add claim functionality

### Phase 4: DA Integration (Week 7-8)
- [ ] Blob submission from Geth
- [ ] DA commitment in blocks
- [ ] Retrieval API
- [ ] Cost tracking

### Phase 5: Testnet (Week 9-10)
- [ ] Public testnet
- [ ] Faucet
- [ ] Explorer (Blockscout)
- [ ] Bug bounty (internal)

### Phase 6: Pilot Mainnet (Week 11-14)
- [ ] Security audit
- [ ] Mainnet deployment
- [ ] Onboarding first users
- [ ] Monitoring & alerts

### Phase 7: Evaluation (Week 15-24)
- [ ] Metrics collection
- [ ] User feedback
- [ ] Performance optimization
- [ ] Decision: scale or pivot

---

## 🌌 Path to Full Version

```
Lean Pilot (3-6 мес, $28K)
    │ Revenue > $100K/мес
    ▼
Scale-up (6-12 мес, $200K-500K)
    │ Multiple F1 instances
    │ PoS validators (20+)
    │ Celestia + IPFS
    ▼
Full Version (2-3 года, $5M+)
    │ Sentinel Space Core (XQRVC1902)
    │ OCP v2.0 Orbital BFT
    │ On-orbit reconfiguration
    ▼
Space Network (5+ лет)
    │ Satellite constellation
    │ Inter-satellite links
    │ Deep space missions
```

---

## 📚 Documentation

| Документ | Описание |
|----------|----------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Системная архитектура |
| [ECONOMICS.md](docs/ECONOMICS.md) | Финансовая модель |
| [PROVER.md](docs/PROVER.md) | Спецификация FPGA prover |
| [DA_INTEGRATION.md](docs/DA_INTEGRATION.md) | Интеграция Celestia |
| [API.md](docs/API.md) | RPC API reference |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Гайд по деплою |

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## ⚠️ Disclaimer

**This is a pilot project.** Not intended for production use without thorough security audit. The space-grade hardware (Sentinel Space Core) is a future roadmap item — this pilot uses cloud FPGA for rapid validation.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🔗 Links

- [TOTAL Protocol Full Documentation](https://github.com/karamik/Total-Protocol)
- [Sentinel Space Core FPGA Spec](https://github.com/karamik/Total-Protocol/blob/main/docs/SENTINEL_SPACE_CORE.md)
- [Fee Splitter Economics](https://github.com/karamik/Total-Protocol/blob/main/docs/FEE_SPLITTER.md)
- [DA Layer Integration](https://github.com/karamik/Total-Protocol/blob/main/docs/DA_LAYER.md)

---

<p align="center">
  <strong>Built with 💜 for the future of decentralized space infrastructure</strong><br>
  <sub>TOTAL Protocol — From Earth to Orbit</sub>
</p>
