

## `docs/API.md`

```markdown
# TOTAL Lean Pilot: Arbitrage & MEV Bot Integration Guide

Добро пожаловать в руководство по интеграции высокочастотных торговых систем и арбитражных ботов с сетью TOTAL Lean Pilot.

## ⚡ Ключевые параметры для HFT/MEV

| Параметр | Значение | Почему важно |
|----------|----------|--------------|
| **Фиксированная комиссия** | $0.01/tx | Предсказуемые затраты, нет gas wars |
| **Proof Generation** | 5–10 сек (AWS F1) | Финальность быстрее основных L2 |
| **Консенсус** | Clique PoA | Мгновенное включение, нет мемпул-задержек |
| **Block Time** | 6 сек | Баланс скорости и стабильности |
| **DA Layer** | Celestia Blobspace | Дешёвое хранение, DAS-верификация |

> **Важно:** Это пилотная сеть. Не используйте для production без аудита контрактов.

---

## 🔌 1. JSON-RPC Эндпоинты

### Текущие эндпоинты (Testnet)

| Протокол | URL | Статус |
|----------|-----|--------|
| HTTP RPC | `https://rpc-pilot.totalprotocol.org` | 🔲 |
| WebSocket | `wss://ws-pilot.totalprotocol.org` | 🔲 |
| HTTP RPC (Local) | `http://localhost:8545` | ✅ Devnet |

> Эндпоинты будут доступны после Phase 5 (Public Testnet). Сейчас запускайте локальный devnet: `make devnet-up`

### Рекомендуемые провайдеры для ботов

```javascript
// WebSocket — для HFT (минимальная latency)
const wsProvider = new ethers.WebSocketProvider("wss://ws-pilot.totalprotocol.org");

// HTTP — для batch запросов
const httpProvider = new ethers.JsonRpcProvider("https://rpc-pilot.totalprotocol.org");
```

---

## 🔧 2. Кастомные RPC-методы

### `total_getFeeSplitInfo`

Мониторинг объёма комиссий и активности сети.

**Запрос:**
```json
{
  "jsonrpc": "2.0",
  "method": "total_getFeeSplitInfo",
  "params": [],
  "id": 1
}
```

**Ответ:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "feeSplitterAddress": "0x00000000000000000000000000000000FEE55917",
    "totalFeesReceived": "0xde0b6b3a7640000",
    "accruedProvers": "0x4da4b4e9fb0000",
    "accruedValidators": "0x3782dace9d0000",
    "accruedTreasury": "0x2c68af0bb14000",
    "accruedDA": "0x21e19e0c9bab2400",
    "accruedBurn": "0xb1a2bc2ec5000",
    "pendingClaims": "0x0",
    "lastDistributionBlock": 1234567
  }
}
```

**Поля:**

| Поле | Тип | Описание |
|------|-----|----------|
| `feeSplitterAddress` | address | Адрес FeeSplitter контракта |
| `totalFeesReceived` | uint256 (hex) | Всего получено комиссий (wei) |
| `accruedProvers` | uint256 (hex) | Начислено пруверам |
| `accruedValidators` | uint256 (hex) | Начислено валидаторам |
| `accruedTreasury` | uint256 (hex) | Начислено в treasury |
| `accruedDA` | uint256 (hex) | Начислено DA layer |
| `accruedBurn` | uint256 (hex) | Сожжено |
| `pendingClaims` | uint256 (hex) | Невостребованные rewards |
| `lastDistributionBlock` | uint64 | Последний блок распределения |

---

### `total_getDAProof`

Получение Celestia DA proof для блока.

**Запрос:**
```json
{
  "jsonrpc": "2.0",
  "method": "total_getDAProof",
  "params": ["0x1234..."],
  "id": 1
}
```

**Ответ:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "height": 1234567,
    "namespace": "total-lean-pilot",
    "commitment": "0xabcd...",
    "dataHash": "0xef01...",
    "compressedSize": 20480,
    "originalSize": 51200,
    "timestamp": "2026-07-19T04:30:00Z"
  }
}
```

---

## 🏗️ 3. Системные контракты

| Контракт | Адрес (Devnet) | Описание |
|----------|---------------|----------|
| **FeeSplitter** | `0x00000000000000000000000000000000FEE55917` | Распределение комиссий 35/25/20/15/5 |
| **ProverRegistry** | Predeploy | Регистрация и стейкинг пруверов |

> Адреса mainnet будут объявлены после деплоя. Для devnet адрес FeeSplitter выдаётся при `forge script DeployFeeSplitter.s.sol --broadcast`

---

## 💰 4. Claim Rewards (для ботов-валидаторов)

Если ваш бот запущен на валидаторской ноде — забирайте 25% комиссий:

```solidity
// FeeSplitter.sol
function claim() external nonReentrant;
```

**Пример (Ethers.js v6):**
```javascript
const feeSplitter = new ethers.Contract(
    "0x00000000000000000000000000000000FEE55917",
    ["function claim() external", "function pendingRewards(address) view returns (uint256)"],
    wallet
);

// Проверить начислено
const pending = await feeSplitter.pendingRewards(wallet.address);
console.log(`Pending: ${ethers.formatEther(pending)} ETH`);

// Забрать
const tx = await feeSplitter.claim();
await tx.wait();
```

---

## 🤖 5. Production-Ready Bot Template

### Node.js / Ethers.js v6

```javascript
const { ethers } = require("ethers");

// ============ CONFIG ============
const CONFIG = {
    WS_URL: process.env.TOTAL_WS_URL || "wss://ws-pilot.totalprotocol.org",
    HTTP_URL: process.env.TOTAL_HTTP_URL || "https://rpc-pilot.totalprotocol.org",
    PRIVATE_KEY: process.env.BOT_PRIVATE_KEY,
    FEE_SPLITTER: "0x00000000000000000000000000000000FEE55917",
    MAX_SLIPPAGE_BPS: 50,        // 0.5%
    MIN_PROFIT_USD: 1.0,         // $1 минимум
    GAS_LIMIT: 100000,
    POLL_INTERVAL_MS: 100,       // 10Hz polling
};

// ============ SETUP ============
if (!CONFIG.PRIVATE_KEY) {
    throw new Error("BOT_PRIVATE_KEY required");
}

const wsProvider = new ethers.WebSocketProvider(CONFIG.WS_URL);
const httpProvider = new ethers.JsonRpcProvider(CONFIG.HTTP_URL);
const wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, httpProvider);

// FeeSplitter ABI (минимальный)
const FEE_SPLITTER_ABI = [
    "function claim() external",
    "function pendingRewards(address) view returns (uint256)",
    "event Claimed(address indexed recipient, uint256 amount)"
];

const feeSplitter = new ethers.Contract(CONFIG.FEE_SPLITTER, FEE_SPLITTER_ABI, wallet);

// ============ METRICS ============
const metrics = {
    blocksSeen: 0,
    txsSent: 0,
    txsConfirmed: 0,
    errors: 0,
    startTime: Date.now()
};

// ============ ARBITRAGE LOGIC ============
class ArbitrageEngine {
    constructor() {
        this.opportunities = new Map();
        this.lastBlock = 0;
    }

    async scanBlock(blockNumber) {
        // TODO: Реальная логика сканирования пулов
        // Пример: проверка спреда между двумя DEX на этом блоке
        
        const mockSpread = Math.random() * 0.02; // 0-2%
        const profitable = mockSpread > 0.005;   // >0.5% спред
        
        return profitable ? {
            path: ["WETH", "USDC", "WETH"],
            expectedProfit: mockSpread * 1000, // $ при $1000 капитале
            targetContract: CONFIG.FEE_SPLITTER // placeholder
        } : null;
    }
}

const engine = new ArbitrageEngine();

// ============ MAIN LOOP ============
async function onNewBlock(blockNumber) {
    metrics.blocksSeen++;
    const start = Date.now();

    try {
        // 1. Сканируем возможности
        const opp = await engine.scanBlock(blockNumber);
        
        if (!opp || opp.expectedProfit < CONFIG.MIN_PROFIT_USD) {
            return; // Нет профита
        }

        console.log(`[Block ${blockNumber}] Opportunity: $${opp.expectedProfit.toFixed(2)} profit`);

        // 2. Отправляем транзакцию
        const tx = await wallet.sendTransaction({
            to: opp.targetContract,
            value: ethers.parseEther("0.01"), // Фиксированная комиссия пилота
            gasLimit: CONFIG.GAS_LIMIT,
            // Нет gasPrice — PoA, фиксированная комиссия
        });

        metrics.txsSent++;
        console.log(`[Block ${blockNumber}] Tx sent: ${tx.hash}`);

        // 3. Ждём подтверждения (Clique = мгновенно)
        const receipt = await tx.wait();
        metrics.txsConfirmed++;
        
        const latency = Date.now() - start;
        console.log(`[Block ${blockNumber}] ✅ Confirmed in ${receipt.blockNumber}. Latency: ${latency}ms`);

    } catch (err) {
        metrics.errors++;
        console.error(`[Block ${blockNumber}] ❌ Error:`, err.message);
    }
}

// ============ EVENT LISTENERS ============
wsProvider.on("block", onNewBlock);

wsProvider.on("error", (err) => {
    console.error("WebSocket error:", err);
    metrics.errors++;
    // Auto-reconnect handled by ethers
});

// ============ PERIODIC TASKS ============
// Claim rewards каждые 10 минут
setInterval(async () => {
    try {
        const pending = await feeSplitter.pendingRewards(wallet.address);
        if (pending > ethers.parseEther("0.001")) {
            const tx = await feeSplitter.claim();
            await tx.wait();
            console.log(`💰 Claimed ${ethers.formatEther(pending)} ETH rewards`);
        }
    } catch (err) {
        console.error("Claim failed:", err.message);
    }
}, 10 * 60 * 1000);

// Log metrics каждую минуту
setInterval(() => {
    const elapsed = (Date.now() - metrics.startTime) / 1000;
    const tps = metrics.txsConfirmed / elapsed;
    console.log(`\n📊 Metrics: ${metrics.blocksSeen} blocks | ${metrics.txsSent}/${metrics.txsConfirmed} txs | ${metrics.errors} errors | ${tps.toFixed(2)} tx/sec\n`);
}, 60 * 1000);

// ============ GRACEFUL SHUTDOWN ============
process.on("SIGINT", async () => {
    console.log("\n🛑 Shutting down...");
    await wsProvider.destroy();
    process.exit(0);
});

console.log("=== TOTAL Lean Pilot Arbitrage Bot ===");
console.log(`Address: ${wallet.address}`);
console.log(`Connected to: ${CONFIG.WS_URL}`);
```

---

## 📊 6. Python / Web3.py Template

```python
import os
import asyncio
from web3 import Web3, WebsocketProvider
from eth_account import Account

# Config
WS_URL = os.getenv("TOTAL_WS_URL", "wss://ws-pilot.totalprotocol.org")
PRIVATE_KEY = os.getenv("BOT_PRIVATE_KEY")
FEE_SPLITTER = "0x00000000000000000000000000000000FEE55917"

if not PRIVATE_KEY:
    raise ValueError("BOT_PRIVATE_KEY required")

# Setup
w3 = Web3(WebsocketProvider(WS_URL))
account = Account.from_key(PRIVATE_KEY)

# FeeSplitter ABI (minimal)
FEE_SPLITTER_ABI = [
    {"inputs": [], "name": "claim", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [{"name": "recipient", "type": "address"}], "name": "pendingRewards", "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view", "type": "function"}
]

fee_splitter = w3.eth.contract(address=FEE_SPLITTER, abi=FEE_SPLITTER_ABI)

async def on_block(block_number):
    print(f"New block: {block_number}")
    
    # Your arbitrage logic here
    # ...
    
    # Send tx
    tx = {
        'to': FEE_SPLITTER,
        'value': w3.to_wei(0.01, 'ether'),
        'gas': 100000,
        'nonce': w3.eth.get_transaction_count(account.address),
        'chainId': 888888  # TOTAL Lean Pilot ChainID
    }
    
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    
    print(f"Tx confirmed: {tx_hash.hex()} in block {receipt.blockNumber}")

# Subscribe to new blocks
block_filter = w3.eth.filter('latest')

async def main():
    print(f"Bot: {account.address}")
    while True:
        for block_hash in block_filter.get_new_entries():
            block = w3.eth.get_block(block_hash)
            await on_block(block.number)
        await asyncio.sleep(0.1)

if __name__ == "__main__":
    asyncio.run(main())
```

---

## 🚨 7. Rate Limits & Best Practices

| Лимит | Значение | Рекомендация |
|-------|----------|--------------|
| WebSocket connections | 100/IP | Используйте 1 persistent connection |
| HTTP requests | 1000/min | Batch запросы где возможно |
| Block subscription | Unlimited | Используйте `eth_subscribe` вместо polling |
| Tx per block | Unlimited (PoA) | Но учитывайте 6s block time |

### Anti-Patterns

❌ **Не делайте:**
- Создавать новый HTTP connection на каждый запрос
- Отправлять транзакции без проверки nonce
- Игнорировать `tx.wait()` — теряете статус
- Хардкодить gasPrice (PoA игнорирует, но лучше не рисковать)

✅ **Делайте:**
- WebSocket + `eth_subscribe("newHeads")`
- Nonce management (local counter + `eth_getTransactionCount` fallback)
- Error handling с exponential backoff
- Мониторинг через Prometheus (см. `monitoring/`)

---

## 🔗 8. Links

- [Репозиторий](https://github.com/karamik/Total-Lean-Pilot)
- [FeeSplitter Security Audit](../contracts/test/FeeSplitter.t.sol)
- [Economics Model](ECONOMICS.md)
- [Deployment Guide](DEPLOYMENT.md)

---

*Built for arbitrageurs, by builders. Low fees, fast finality, transparent economics.*
```

