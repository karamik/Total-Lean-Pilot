
# Phase 3: Fee Splitter Integration

fee_splitter_tz = """# TOTAL Lean Pilot — Phase 3: Fee Splitter Integration
## Automatic Fee Distribution in Geth

**Status:** Draft  
**Date:** 2026-07-19  
**Priority:** P0 (блокирует Phase 4 DA Integration)  
**Owner:** Smart Contract / Execution Team  
**Reviewers:** DevOps, Economics  

---

## 1. Executive Summary

Phase 3 интегрирует Fee Splitter (Solidity) с Geth execution layer. Каждая транзакция автоматически направляет комиссию в контракт, который распределяет её между Provers (35%), Validators (25%), Treasury (20%), DA Layer (15%) и Burn (5%).

**Ключевые метрики:**
| Метрика | Значение |
|---------|----------|
| Комиссия/tx | $0.01 (pilot) |
| Распределение | 100% (нет утечек) |
| Задержка | 0 (атомарно с транзакцией) |
| Прозрачность | On-chain, verifiable |

---

## 2. Architecture

```
Transaction Flow:

User sends tx ──▶ Geth (execution) ──▶ Fee Splitter (Solidity)
                     │                      │
                     │                      ├──▶ Provers 35%
                     │                      ├──▶ Validators 25%
                     │                      ├──▶ Treasury 20%
                     │                      ├──▶ DA Layer 15%
                     │                      └──▶ Burn 5%
                     │
                     └──▶ Block included ──▶ State updated
```

### 2.1 Integration Points

| Компонент | Файл | Изменение |
|-----------|------|-----------|
| Geth | `core/state_transition.go` | RouteFees() — перенаправление комиссий |
| Geth | `core/txpool/txpool.go` | BaseFee calculation |
| Geth | `eth/backend.go` | Fee Splitter address in config |
| Contract | `FeeSplitter.sol` | receive(), claim(), distribute() |
| RPC | `ethapi/api.go` | eth_feeHistory с split info |

---

## 3. Geth Modifications

### 3.1 State Transition (core/state_transition.go)

```go
package core

import (
	"math/big"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/params"
)

// FeeSplitterAddress — хардкодный адрес контракта
// Должен совпадать с адресом из DeployFeeSplitter.s.sol
var FeeSplitterAddress = common.HexToAddress("0x00000000000000000000000000000000FEE55917")

// IsFeeSplitterEnabled проверяет, активен ли Fee Splitter в данном блоке
func IsFeeSplitterEnabled(config *params.ChainConfig, blockNumber *big.Int) bool {
	return config.ChainID != nil && config.ChainID.Cmp(big.NewInt(888888)) == 0
}

// applyFeeSplit перенаправляет комиссию в Fee Splitter вместо coinbase
func (st *StateTransition) applyFeeSplit() error {
	if !IsFeeSplitterEnabled(st.evm.ChainConfig(), st.evm.Context.BlockNumber) {
		return nil // Стандартное поведение
	}

	// Рассчитываем общую комиссию
	fee := new(big.Int).Mul(
		new(big.Int).SetUint64(st.gasUsed()),
		st.gasPrice,
	)

	if fee.Sign() <= 0 {
		return nil
	}

	// Проверяем, что контракт существует
	if !st.state.Exist(FeeSplitterAddress) {
		// Контракт ещё не задеплоен — отправляем на burn
		burnAddr := common.HexToAddress("0x000000000000000000000000000000000000dEaD")
		st.state.AddBalance(burnAddr, fee)
		log.Debug("FeeSplitter not deployed, burned fees", "amount", fee)
		return nil
	}

	// Переводим комиссию на Fee Splitter
	// Контракт автоматически распределит при receive()
	st.state.SubBalance(st.msg.From(), fee)
	st.state.AddBalance(FeeSplitterAddress, fee)

	// Эмитируем событие для мониторинга
	st.evm.Context.GetHash(0) // Trigger log
	
	log.Info("Fee split applied", 
		"tx", st.msg.Hash(),
		"amount", fee,
		"splitter", FeeSplitterAddress,
	)

	return nil
}

// buyGas модифицирован для учёта Fee Splitter
func (st *StateTransition) buyGas() error {
	// Стандартная логика покупки газа
	mgval := new(big.Int).Mul(new(big.Int).SetUint64(st.msg.Gas()), st.gasPrice)
	if have, want := st.state.GetBalance(st.msg.From()), mgval; have.Cmp(want) < 0 {
		return fmt.Errorf("%w: address %v have %v want %v", ErrInsufficientFunds, st.msg.From().Hex(), have, want)
	}
	
	st.gp.SubGas(st.msg.Gas())
	st.initialGas = st.msg.Gas()
	st.state.SubBalance(st.msg.From(), mgval)
	
	return nil
}

// refundGas модифицирован — остаток возвращается отправителю
func (st *StateTransition) refundGas() {
	// Возвращаем неиспользованный газ
	refund := st.gasUsed()
	st.state.AddBalance(st.msg.From(), new(big.Int).Mul(new(big.Int).SetUint64(refund), st.gasPrice))
	
	// Применяем Fee Splitter на использованный газ
	st.applyFeeSplit()
}
```

### 3.2 BaseFee Calculation (core/txpool/txpool.go)

```go
package txpool

import (
	"math/big"
)

// CalculateBaseFee рассчитывает базовую комиссию для TOTAL Pilot
// Целевая комиссия: $0.01 при курсе ETH $3000
func CalculateBaseFee(parentHeader *types.Header) *big.Int {
	// Для Lean Pilot: фиксированная base fee
	// $0.01 / $3000 = 0.00000333 ETH = 3333 gwei
	baseFee := big.NewInt(3333 * 1e9) // 3333 gwei
	
	// Минимальная комиссия для предотвращения спама
	minFee := big.NewInt(1000 * 1e9) // 1000 gwei
	
	if baseFee.Cmp(minFee) < 0 {
		return minFee
	}
	
	return baseFee
}

// SuggestGasPrice предлагает цену газа с учётом Fee Splitter
func (pool *TxPool) SuggestGasPrice() *big.Int {
	// Базовая цена + небольшой premium
	baseFee := CalculateBaseFee(pool.chain.CurrentBlock().Header())
	premium := new(big.Int).Div(baseFee, big.NewInt(10)) // +10%
	
	return new(big.Int).Add(baseFee, premium)
}
```

### 3.3 Backend Configuration (eth/backend.go)

```go
package eth

import (
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core"
)

// TOTALPilotConfig конфигурация для Lean Pilot
var TOTALPilotConfig = &Config{
	Genesis: &core.Genesis{
		Config: &params.ChainConfig{
			ChainID:             big.NewInt(888888),
			HomesteadBlock:      big.NewInt(0),
			EIP150Block:         big.NewInt(0),
			EIP155Block:         big.NewInt(0),
			EIP158Block:         big.NewInt(0),
			ByzantiumBlock:      big.NewInt(0),
			ConstantinopleBlock: big.NewInt(0),
			PetersburgBlock:     big.NewInt(0),
			IstanbulBlock:       big.NewInt(0),
			BerlinBlock:         big.NewInt(0),
			LondonBlock:         big.NewInt(0),
			Clique: &params.CliqueConfig{
				Period: 6,
				Epoch:  100,
			},
		},
		Alloc: core.GenesisAlloc{
			// Валидаторы
			common.HexToAddress("0x1111111111111111111111111111111111111111"): {
				Balance: new(big.Int).Mul(big.NewInt(1000), big.NewInt(1e18)),
			},
			common.HexToAddress("0x2222222222222222222222222222222222222222"): {
				Balance: new(big.Int).Mul(big.NewInt(1000), big.NewInt(1e18)),
			},
			common.HexToAddress("0x3333333333333333333333333333333333333333"): {
				Balance: new(big.Int).Mul(big.NewInt(1000), big.NewInt(1e18)),
			},
			// Fee Splitter (предустановлен, но без кода)
			core.FeeSplitterAddress: {
				Balance: big.NewInt(0),
			},
		},
	},
	FeeSplitter: &FeeSplitterConfig{
		Address:     core.FeeSplitterAddress,
		EnabledFrom: big.NewInt(0), // С genesis
	},
}

// FeeSplitterConfig конфигурация Fee Splitter
type FeeSplitterConfig struct {
	Address     common.Address
	EnabledFrom *big.Int
}
```

---

## 4. Fee Splitter Contract (Enhanced)

### 4.1 FeeSplitter.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TOTALPilotFeeSplitter
 * @notice Автоматическое распределение комиссий для Lean Pilot
 * @dev Хардкодный split: Provers 35%, Validators 25%, Treasury 20%, DA 15%, Burn 5%
 */
contract TOTALPilotFeeSplitter is ReentrancyGuard, Ownable {
    
    // ============ Constants ============
    
    uint16 public constant PROVERS_SHARE = 3500;      // 35%
    uint16 public constant VALIDATORS_SHARE = 2500;   // 25%
    uint16 public constant TREASURY_SHARE = 2000;     // 20%
    uint16 public constant DA_LAYER_SHARE = 1500;    // 15%
    uint16 public constant BURN_SHARE = 500;         // 5%
    uint16 public constant TOTAL_BASIS = 10000;      // 100%
    
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    // ============ State ============
    
    address public proverAddress;       // AWS F1 operator
    address public validatorAddress;    // Validator set multi-sig
    address public treasuryAddress;     // Team treasury
    address public daLayerAddress;      // Celestia payment wallet
    
    // Accumulated balances per recipient
    mapping(address => uint256) public accruedBalances;
    mapping(address => uint256) public totalClaimed;
    
    // Statistics
    uint256 public totalFeesReceived;
    uint256 public totalFeesDistributed;
    uint256 public transactionCount;
    
    // ============ Events ============
    
    event FeeReceived(
        address indexed sender,
        uint256 amount,
        uint256 timestamp
    );
    
    event FeeDistributed(
        uint256 indexed txCount,
        uint256 totalAmount,
        uint256 proversAmount,
        uint256 validatorsAmount,
        uint256 treasuryAmount,
        uint256 daLayerAmount,
        uint256 burnAmount
    );
    
    event FeesClaimed(
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );
    
    event RecipientUpdated(
        string indexed role,
        address indexed oldAddress,
        address indexed newAddress
    );
    
    // ============ Constructor ============
    
    constructor(
        address _prover,
        address _validator,
        address _treasury,
        address _daLayer
    ) Ownable(msg.sender) {
        require(_prover != address(0), "Invalid prover address");
        require(_validator != address(0), "Invalid validator address");
        require(_treasury != address(0), "Invalid treasury address");
        require(_daLayer != address(0), "Invalid DA layer address");
        
        proverAddress = _prover;
        validatorAddress = _validator;
        treasuryAddress = _treasury;
        daLayerAddress = _daLayer;
    }
    
    // ============ Receive ============
    
    /**
     * @notice Основная точка входа — приём комиссий от Geth
     * @dev Вызывается автоматически при каждой транзакции
     */
    receive() external payable nonReentrant {
        require(msg.value > 0, "Zero fee");
        
        totalFeesReceived += msg.value;
        transactionCount++;
        
        // Распределяем комиссию
        _distribute(msg.value);
        
        emit FeeReceived(msg.sender, msg.value, block.timestamp);
    }
    
    // ============ Distribution ============
    
    function _distribute(uint256 totalAmount) internal {
        uint256 proversAmount = (totalAmount * PROVERS_SHARE) / TOTAL_BASIS;
        uint256 validatorsAmount = (totalAmount * VALIDATORS_SHARE) / TOTAL_BASIS;
        uint256 treasuryAmount = (totalAmount * TREASURY_SHARE) / TOTAL_BASIS;
        uint256 daLayerAmount = (totalAmount * DA_LAYER_SHARE) / TOTAL_BASIS;
        
        // Burn = остаток (защита от rounding errors)
        uint256 distributed = proversAmount + validatorsAmount + treasuryAmount + daLayerAmount;
        uint256 burnAmount = totalAmount - distributed;
        
        // Начисляем балансы
        accruedBalances[proverAddress] += proversAmount;
        accruedBalances[validatorAddress] += validatorsAmount;
        accruedBalances[treasuryAddress] += treasuryAmount;
        accruedBalances[daLayerAddress] += daLayerAmount;
        accruedBalances[BURN_ADDRESS] += burnAmount;
        
        totalFeesDistributed += totalAmount;
        
        emit FeeDistributed(
            transactionCount,
            totalAmount,
            proversAmount,
            validatorsAmount,
            treasuryAmount,
            daLayerAmount,
            burnAmount
        );
    }
    
    // ============ Claims ============
    
    /**
     * @notice Получить накопленные комиссии
     */
    function claim() external nonReentrant {
        uint256 amount = accruedBalances[msg.sender];
        require(amount > 0, "No fees to claim");
        require(msg.sender != BURN_ADDRESS, "Cannot claim burn");
        
        accruedBalances[msg.sender] = 0;
        totalClaimed[msg.sender] += amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FeesClaimed(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @notice Получить комиссии от имени (для автоматизации)
     */
    function claimFor(address recipient) external onlyOwner nonReentrant {
        uint256 amount = accruedBalances[recipient];
        require(amount > 0, "No fees to claim");
        require(recipient != BURN_ADDRESS, "Cannot claim burn");
        
        accruedBalances[recipient] = 0;
        totalClaimed[recipient] += amount;
        
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FeesClaimed(recipient, amount, block.timestamp);
    }
    
    // ============ Admin ============
    
    function setProverAddress(address _newProver) external onlyOwner {
        require(_newProver != address(0), "Invalid address");
        address old = proverAddress;
        proverAddress = _newProver;
        emit RecipientUpdated("prover", old, _newProver);
    }
    
    function setValidatorAddress(address _newValidator) external onlyOwner {
        require(_newValidator != address(0), "Invalid address");
        address old = validatorAddress;
        validatorAddress = _newValidator;
        emit RecipientUpdated("validator", old, _newValidator);
    }
    
    function setTreasuryAddress(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        address old = treasuryAddress;
        treasuryAddress = _newTreasury;
        emit RecipientUpdated("treasury", old, _newTreasury);
    }
    
    function setDaLayerAddress(address _newDaLayer) external onlyOwner {
        require(_newDaLayer != address(0), "Invalid address");
        address old = daLayerAddress;
        daLayerAddress = _newDaLayer;
        emit RecipientUpdated("daLayer", old, _newDaLayer);
    }
    
    // ============ Views ============
    
    function getSplit() external pure returns (
        uint16 provers,
        uint16 validators,
        uint16 treasury,
        uint16 daLayer,
        uint16 burn
    ) {
        return (PROVERS_SHARE, VALIDATORS_SHARE, TREASURY_SHARE, DA_LAYER_SHARE, BURN_SHARE);
    }
    
    function getAccrued(address recipient) external view returns (uint256) {
        return accruedBalances[recipient];
    }
    
    function getTotalClaimed(address recipient) external view returns (uint256) {
        return totalClaimed[recipient];
    }
    
    function getStats() external view returns (
        uint256 totalReceived,
        uint256 totalDistributed,
        uint256 txCount,
        uint256 contractBalance
    ) {
        return (
            totalFeesReceived,
            totalFeesDistributed,
            transactionCount,
            address(this).balance
        );
    }
    
    function getBurnedAmount() external view returns (uint256) {
        return accruedBalances[BURN_ADDRESS];
    }
}
```

---

## 5. RPC Integration

### 5.1 Fee History API (ethapi/api.go)

```go
package ethapi

import (
	"math/big"
	"github.com/ethereum/go-ethereum/common"
)

// FeeSplitInfo информация о распределении комиссий
type FeeSplitInfo struct {
	Provers    *big.Int `json:"provers"`
	Validators *big.Int `json:"validators"`
	Treasury   *big.Int `json:"treasury"`
	DaLayer    *big.Int `json:"daLayer"`
	Burn       *big.Int `json:"burn"`
}

// GetFeeSplitHistory возвращает историю распределения комиссий
func (s *PublicBlockChainAPI) GetFeeSplitHistory(ctx context.Context, blockCount int) ([]FeeSplitInfo, error) {
	// Получаем последние N блоков
	var history []FeeSplitInfo
	
	for i := 0; i < blockCount; i++ {
		blockNum := s.b.CurrentBlock().Number().Int64() - int64(i)
		if blockNum < 0 {
			break
		}
		
		block, _ := s.b.BlockByNumber(ctx, rpc.BlockNumber(blockNum))
		if block == nil {
			continue
		}
		
		// Суммируем комиссии в блоке
		var totalFee *big.Int
		for _, tx := range block.Transactions() {
			fee := new(big.Int).Mul(tx.GasPrice(), new(big.Int).SetUint64(tx.Gas()))
			totalFee.Add(totalFee, fee)
		}
		
		// Рассчитываем split
		split := calculateSplit(totalFee)
		history = append(history, split)
	}
	
	return history, nil
}

func calculateSplit(totalFee *big.Int) FeeSplitInfo {
	basis := big.NewInt(10000)
	
	return FeeSplitInfo{
		Provers:    new(big.Int).Div(new(big.Int).Mul(totalFee, big.NewInt(3500)), basis),
		Validators: new(big.Int).Div(new(big.Int).Mul(totalFee, big.NewInt(2500)), basis),
		Treasury:   new(big.Int).Div(new(big.Int).Mul(totalFee, big.NewInt(2000)), basis),
		DaLayer:    new(big.Int).Div(new(big.Int).Mul(totalFee, big.NewInt(1500)), basis),
		Burn:       new(big.Int).Div(new(big.Int).Mul(totalFee, big.NewInt(500)), basis),
	}
}
```

### 5.2 Custom RPC Methods

```go
// GetFeeSplitterStats — статистика Fee Splitter
func (s *PublicBlockChainAPI) GetFeeSplitterStats(ctx context.Context) (map[string]interface{}, error) {
	// Вызываем view функции контракта
	contractAddr := core.FeeSplitterAddress
	
	// totalFeesReceived
	data := s.b.GetEVM(ctx, nil).Call(
		vm.AccountRef(common.Address{}),
		contractAddr,
		[]byte("0x..."), // selector для getStats()
		0,
		nil,
	)
	
	// Парсим результат
	var stats map[string]interface{}
	// ... decoding
	
	return stats, nil
}
```

---

## 6. Testing

### 6.1 Unit Tests (Solidity)

```solidity
// FeeSplitter.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/FeeSplitter.sol";

contract FeeSplitterTest is Test {
    TOTALPilotFeeSplitter splitter;
    
    address prover = address(0x1);
    address validator = address(0x2);
    address treasury = address(0x3);
    address daLayer = address(0x4);
    address user = address(0x5);
    
    function setUp() public {
        splitter = new TOTALPilotFeeSplitter(prover, validator, treasury, daLayer);
        vm.deal(user, 100 ether);
    }
    
    function test_ReceiveAndSplit() public {
        uint256 amount = 1 ether;
        
        vm.prank(user);
        (bool success, ) = address(splitter).call{value: amount}("");
        assertTrue(success);
        
        // Проверяем распределение
        assertEq(splitter.accruedBalances(prover), amount * 3500 / 10000);
        assertEq(splitter.accruedBalances(validator), amount * 2500 / 10000);
        assertEq(splitter.accruedBalances(treasury), amount * 2000 / 10000);
        assertEq(splitter.accruedBalances(daLayer), amount * 1500 / 10000);
        assertEq(splitter.accruedBalances(splitter.BURN_ADDRESS()), amount * 500 / 10000);
    }
    
    function test_Claim() public {
        vm.deal(address(splitter), 1 ether);
        
        // Начисляем через receive
        vm.prank(user);
        (bool success, ) = address(splitter).call{value: 1 ether}("");
        assertTrue(success);
        
        uint256 proverBalance = splitter.accruedBalances(prover);
        assertGt(proverBalance, 0);
        
        // Claim
        uint256 proverBefore = prover.balance;
        vm.prank(prover);
        splitter.claim();
        
        assertEq(prover.balance - proverBefore, proverBalance);
        assertEq(splitter.accruedBalances(prover), 0);
    }
    
    function test_RevertClaimBurn() public {
        vm.expectRevert("Cannot claim burn");
        vm.prank(splitter.BURN_ADDRESS());
        splitter.claim();
    }
    
    function test_SumEquals100Percent() public {
        vm.deal(address(splitter), 100 ether);
        
        vm.prank(user);
        (bool success, ) = address(splitter).call{value: 100 ether}("");
        assertTrue(success);
        
        uint256 total = splitter.accruedBalances(prover) +
                       splitter.accruedBalances(validator) +
                       splitter.accruedBalances(treasury) +
                       splitter.accruedBalances(daLayer) +
                       splitter.accruedBalances(splitter.BURN_ADDRESS());
        
        assertEq(total, 100 ether);
    }
    
    function testFuzz_Receive(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(user, amount);
        
        vm.prank(user);
        (bool success, ) = address(splitter).call{value: amount}("");
        assertTrue(success);
        
        (uint256 totalReceived,,,) = splitter.getStats();
        assertEq(totalReceived, amount);
    }
}
```

### 6.2 Integration Tests (Go)

```go
package core

import (
	"math/big"
	"testing"
	
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/rawdb"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/params"
)

func TestFeeSplitterIntegration(t *testing.T) {
	// Создаём тестовую базу
	db := rawdb.NewMemoryDatabase()
	
	// Genesis с Fee Splitter
	genesis := &Genesis{
		Config:   params.TestChainConfig,
		Alloc: GenesisAlloc{
			common.HexToAddress("0x1111..."): {Balance: big.NewInt(1e18)},
			FeeSplitterAddress: {Balance: big.NewInt(0)},
		},
	}
	
	// Инициализируем
	genesis.MustCommit(db)
	
	// Создаём state transition
	// ... тест отправки транзакции
	
	// Проверяем, что комиссия ушла в Fee Splitter
	state, _ := state.New(common.Hash{}, state.NewDatabase(db), nil)
	
	// Отправляем транзакцию
	// ...
	
	// Проверяем баланс Fee Splitter
	splitterBalance := state.GetBalance(FeeSplitterAddress)
	if splitterBalance.Sign() <= 0 {
		t.Errorf("Fee Splitter balance is zero")
	}
}
```

---

## 7. Deployment

### 7.1 Deploy Script

```bash
#!/bin/bash
# deploy_fee_splitter.sh

set -e

RPC_URL="http://localhost:8545"
PRIVATE_KEY="0x1111111111111111111111111111111111111111111111111111111111111111"

# Адреса получателей
PROVER="0x1000000000000000000000000000000000000001"
VALIDATOR="0x2000000000000000000000000000000000000002"
TREASURY="0x3000000000000000000000000000000000000003"
DA_LAYER="0x4000000000000000000000000000000000000004"

echo "Deploying FeeSplitter..."

# Деплой через Forge
forge script script/DeployFeeSplitter.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --private-key $PRIVATE_KEY \
    --sig "run()" \
    -vvv

# Получаем адрес контракта
CONTRACT_ADDR=$(cast call --rpc-url $RPC_URL \
    "0x..." \
    "getStats()" | head -1)

echo "FeeSplitter deployed at: $CONTRACT_ADDR"

# Обновляем адрес в Geth config
sed -i "s/FeeSplitterAddress = common.HexToAddress.*/FeeSplitterAddress = common.HexToAddress(\"$CONTRACT_ADDR\")/" \
    execution/core/state_transition.go

echo "Updated Geth config with FeeSplitter address"
```

### 7.2 Verification

```bash
# Проверяем баланс контракта
cast balance 0xFEE...SPLITTER --rpc-url http://localhost:8545

# Проверяем accrued balances
cast call 0xFEE...SPLITTER "accruedBalances(address)" 0xPROVER...

# Отправляем тестовую транзакцию
cast send 0xRECIPIENT --value 0.01ether --rpc-url http://localhost:8545

# Проверяем, что комиссия ушла в контракт
cast balance 0xFEE...SPLITTER --rpc-url http://localhost:8545
```

---

## 8. Monitoring

### 8.1 Metrics

| Метрика | Тип | Описание |
|---------|-----|----------|
| `total_fees_received` | Counter | Всего комиссий получено |
| `total_fees_distributed` | Counter | Всего распределено |
| `transaction_count` | Counter | Количество транзакций |
| `accrued_provers` | Gauge | Накоплено Provers |
| `accrued_validators` | Gauge | Накоплено Validators |
| `accrued_treasury` | Gauge | Накоплено Treasury |
| `accrued_da_layer` | Gauge | Накоплено DA Layer |
| `accrued_burn` | Gauge | Накоплено Burn |
| `claim_count` | Counter | Количество claim'ов |
| `claim_amount` | Counter | Сумма claim'ов |

### 8.2 Alerts

```yaml
alerts:
  - name: FeeSplitterBalanceMismatch
    condition: total_fees_received != total_fees_distributed + contract_balance
    severity: critical
    action: pause_transactions
    
  - name: HighAccumulation
    condition: accrued_provers > 1000 ETH
    severity: warning
    action: notify_provers
    
  - name: ZeroBurn
    condition: accrued_burn == 0 for 1 hour
    severity: warning
    action: check_contract
```

---

## 9. Timeline

| Неделя | Задача | Доставка |
|--------|--------|----------|
| W1 | Geth modifications | state_transition.go, txpool.go |
| W2 | Enhanced contract | FeeSplitter.sol с events, stats |
| W3 | RPC integration | Custom API methods |
| W4 | Unit tests | Solidity + Go tests |
| W5 | Integration tests | End-to-end fee flow |
| W6 | Deployment scripts | Bash + Makefile |
| W7 | Monitoring | Prometheus metrics |
| W8 | Documentation | API docs, runbook |

---

*Document version: 1.0*  
*Last updated: 2026-07-19*  
*Next review: 2026-08-02*
"""

# Сохраняем
base_path = '/mnt/agents/output/Total-Lean-Pilot'
phase3_path = f'{base_path}/docs/PHASE3_FEE_SPLITTER_INTEGRATION.md'

import os
os.makedirs(os.path.dirname(phase3_path), exist_ok=True)

with open(phase3_path, 'w', encoding='utf-8') as f:
    f.write(fee_splitter_tz)

print(f"Phase 3 spec saved: {phase3_path}")
print(f"Size: {len(fee_splitter_tz)} chars")
