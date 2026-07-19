
Celestia Data Availability Integration
Overview
Total-Lean-Pilot использует Celestia как Data Availability (DA) layer для дешёвого и надёжного хранения rollup данных.
Почему Celestia:
Дёшево: ~$100/мес за light node + blob fees
Надёжно: Data Availability Sampling (DAS) — тысячи light nodes проверяют доступность
Масштабируемо: 8 MiB blob limit, параллельная отправка
Модульно: Независим от execution layer
Architecture
plain
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Geth      │────▶│  Compress   │────▶│  Celestia   │
│  (Block)    │     │   (zlib)    │     │  (BlobTx)   │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │  DA Proof   │
                                        │  height     │
                                        │  commitment │
                                        └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │ Block Header│
                                        │  extraData  │
                                        └─────────────┘
Flow
1. Block Production (Write)
Geth производит блок (transactions, state root)
Блок сериализуется через RLP
Данные сжимаются zlib (compression ratio ~40-70%)
Сжатые данные отправляются в Celestia как blob
Celestia возвращает height + commitment
DA proof записывается в block.Header.Extra
Блок добавляется в DA index
2. Block Sync (Read)
Нода получает блок с DA proof в header
Извлекает height, namespace, commitment
Запрашивает blob у Celestia light node
Проверяет Data Availability через DAS
Декомпрессирует данные
Восстанавливает блок
3. Verification
Inclusion Proof: blob.GetProof() — доказательство включения в блок
Availability: Light node выполняет DAS (выборочную проверку)
Data Integrity: SHA256 хэш данных сравнивается с DataHash в proof
Configuration
Environment Variables
bash
# DA node (JSON-RPC, port 26658)
export CELESTIA_DA_URL=http://localhost:26658
export CELESTIA_DA_TLS=false
export CELESTIA_DA_AUTH_TOKEN=""

# Consensus node (gRPC, port 9090) — нужен для отправки blobs
export CELESTIA_CORE_GRPC=localhost:9090
export CELESTIA_CORE_TLS=false
export CELESTIA_CORE_AUTH_TOKEN=""

# Network: "celestia" (mainnet), "mocha-4" (testnet), "arabica" (devnet)
export CELESTIA_NETWORK=mocha-4

# Namespace (уникальный для вашего rollup)
export CELESTIA_NAMESPACE=total-lean-pilot

# Keyring
export CELESTIA_KEYRING_DIR=./celestia-keys
export CELESTIA_KEY_NAME=total-pilot
export CELESTIA_BACKEND=test  # test | file | os

# Submission mode
export CELESTIA_TX_WORKERS=1  # 0=immediate, 1=queued, >1=parallel

# Gas
export CELESTIA_MAX_GAS_PRICE=20000000  # utia
Config File (JSON)
JSON
{
  "daURL": "http://localhost:26658",
  "daTLS": false,
  "daAuthToken": "",
  "coreGRPC": "localhost:9090",
  "coreTLSEnabled": false,
  "coreAuthToken": "",
  "network": "mocha-4",
  "namespace": "total-lean-pilot",
  "keyringDir": "./celestia-keys",
  "keyName": "total-pilot",
  "backendName": "test",
  "txWorkerAccounts": 1,
  "maxGasPrice": 20000000,
  "timeout": 120000000000
}
Setup
1. Install celestia-node
bash
# Binary
curl -sL https://docs.celestia.org/celestia-node-install.sh | bash

# Or from source
git clone https://github.com/celestiaorg/celestia-node.git
cd celestia-node
git checkout v0.28.2
go build ./cmd/celestia
2. Initialize Light Node
bash
# Mainnet
celestia light init

# Testnet (Mocha)
celestia light init --p2p.network mocha

# Devnet (Arabica)
celestia light init --p2p.network arabica
3. Start Light Node
bash
# Mainnet
celestia light start --core.ip rpc.celestia.pops.one   --core.port 9090 --p2p.network celestia

# Testnet
celestia light start --core.ip rpc-mocha.pops.one   --core.port 9090 --p2p.network mocha-4
4. Fund Account
bash
# Get address
celestia state account-address

# Fund via faucet (testnet)
# https://mocha.celenium.io/faucet

# Check balance
celestia state balance
5. Test Blob Submission
bash
# Submit blob
celestia blob submit 0x746f74616c2d6c65616e2d70696c6f74 "Hello TOTAL!"

# Get blob (replace height and commitment)
celestia blob get <height> 0x746f74616c2d6c65616e2d70696c6f74 <commitment>
Go Integration
Basic Usage
go
import "github.com/karamik/Total-Lean-Pilot/da/celestia"

// Create client
cfg := celestia.DefaultConfig()
cfg.DAURL = "http://localhost:26658"
cfg.CoreGRPC = "localhost:9090"
cfg.Network = "mocha-4"

client, err := celestia.NewClient(cfg)
if err != nil { panic(err) }

err = client.Connect(context.Background())
if err != nil { panic(err) }
defer client.Close()

// Submit block data
proof, err := client.SubmitBlock(ctx, blockData)
if err != nil { panic(err) }

fmt.Printf("Block submitted at Celestia height %d
", proof.Height)

// Retrieve block data
data, err := client.RetrieveBlock(ctx, proof)
if err != nil { panic(err) }
With Geth Integration
go
import "github.com/karamik/Total-Lean-Pilot/execution/core"

// Create DA integration
cfg := celestia.DefaultConfig()
da, err := core.NewDAIntegration(cfg)
if err != nil { panic(err) }

// In block production:
proof, err := da.SubmitBlock(block)
if err != nil { log.Error("DA submission failed", err) }

// Inject proof into header
err = core.InjectDAProof(block.Header(), proof)

// In block sync:
proof, err := core.ExtractDAProof(header)
if err != nil { /* handle */ }

block, err := da.GetBlock(blockNum)
Cost Analysis
Light Node
Таблица
Resource	Cost/Month
VPS (2 vCPU, 4GB RAM)	~$20
Storage (100GB SSD)	~$10
Bandwidth	~$20
Total Infrastructure	~$50
Blob Fees
Таблица
Parameter	Value
Gas per byte	8 utia
Flat gas (PFB)	65,000
Average block size	50 KB
Compressed block	20 KB
Gas per block	~65,000 + 20,000*8 = 225,000
Gas price	0.02 utia
Fee per block	~4,500 utia = 0.0045 TIA
Blocks/day (6s)	14,400
Daily blob cost	~65 TIA (~$13 at $0.20/TIA)
Monthly blob cost	~$400
Total DA Cost
Таблица
Component	Monthly
Light node	$50
Blob fees	$400
Total	~$450
Note: На пилоте используем testnet (бесплатно). Mainnet переход при revenue >$100K/мес.
Performance
Таблица
Metric	Value
Blob submission latency	5-15 seconds
Blob retrieval latency	2-5 seconds
Compression ratio	40-70%
Max blob size	7 MB (conservative)
Max blocks per blob	1 (each block separate)
Parallel submissions	Up to 8 per block (with TxWorkerAccounts)
Security
Threat Model
Таблица
Threat	Mitigation
Data withholding	DAS — light nodes выборочно проверяют доступность
Invalid data	Inclusion proof + data hash verification
Censorship	Multiple Celestia validators, permissionless
Light node compromise	Can switch to another light node or full node
Eclipse attack	Bootstrap from multiple peers, checkpoint sync
Verification Levels
Light: DAS sampling (99.9% confidence)
Medium: Inclusion proof + data hash
Full: Download and verify all data
Troubleshooting
"failed to submit blobs due to insufficient gas price"
bash
# Increase max gas price
export CELESTIA_MAX_GAS_PRICE=50000000

# Or use third-party estimator
export CELESTIA_ESTIMATOR_ADDRESS=rpc-mocha.pops.one:9090
"context deadline exceeded"
bash
# Increase timeout
export CELESTIA_TIMEOUT=300s

# Check network connectivity
ping rpc-mocha.pops.one
"account for signer not found"
bash
# Fund account
celestia state account-address
# -> copy address
# -> fund via faucet
"header: syncing in progress"
bash
# Wait for sync or use fast sync
celestia light start --headers.trusted-hash <hash>
Migration to Mainnet
Fund mainnet account with TIA tokens
Update network to "celestia"
Update endpoints to mainnet RPC
Monitor costs — adjust blob size/batch frequency
Enable parallel submission (TxWorkerAccounts > 1) для высокой нагрузки
References
Celestia Docs
Go Client Tutorial
Blob Submission
Light Node Quickstart
