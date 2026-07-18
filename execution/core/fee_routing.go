
package core

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/state"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/params"
)

// TOTALPilotFeeSplitterAddress — хардкодный адрес контракта Fee Splitter
// Должен совпадать с адресом из DeployFeeSplitter.s.sol
var TOTALPilotFeeSplitterAddress = common.HexToAddress("0x00000000000000000000000000000000FEE55917")

// IsTOTALPilot проверяет, активен ли Lean Pilot режим
func IsTOTALPilot(config *params.ChainConfig, blockNumber *big.Int) bool {
	return config.ChainID != nil && config.ChainID.Cmp(TOTALPilotChainID) == 0
}

// RouteFees перенаправляет комиссии от транзакций в Fee Splitter
// Вместо стандартного майнинга — прозрачное распределение
func RouteFees(
	statedb *state.StateDB,
	config *params.ChainConfig,
	blockNumber *big.Int,
	tx *types.Transaction,
	receipt *types.Receipt,
) error {
	if !IsTOTALPilot(config, blockNumber) {
		return nil // Стандартное поведение для не-TOTAL сетей
	}

	// Рассчитываем общую комиссию: gasUsed * gasPrice
	fee := new(big.Int).Mul(
		new(big.Int).SetUint64(receipt.GasUsed),
		tx.GasPrice(),
	)

	if fee.Sign() <= 0 {
		return nil // Нечего распределять
	}

	// Проверяем, что Fee Splitter контракт существует
	if !statedb.Exist(TOTALPilotFeeSplitterAddress) {
		// Контракт ещё не задеплоен — отправляем на burn address
		statedb.AddBalance(common.HexToAddress("0x000000000000000000000000000000000000dEaD"), fee)
		return nil
	}

	// Отправляем комиссию на Fee Splitter
	// Контракт автоматически распределит при receive()
	statedb.AddBalance(TOTALPilotFeeSplitterAddress, fee)

	// Логируем для мониторинга
	statedb.AddLog(&types.Log{
		Address: TOTALPilotFeeSplitterAddress,
		Topics: []common.Hash{
			common.HexToHash("0xFeeSplitEventSignature"), // TODO: реальный хеш события
		},
		Data: fee.Bytes(),
	})

	return nil
}

// CalculateBaseFee рассчитывает базовую комиссию для TOTAL Pilot
// Фиксированная комиссия $0.01 эквивалент при текущем курсе ETH
func CalculateBaseFee(parentHeader *types.Header) *big.Int {
	// Для пилота: фиксированная base fee ~$0.01
	// При ETH = $3000: 0.01 / 3000 = 0.00000333 ETH = 3333 gwei
	baseFee := new(big.Int).SetUint64(3333 * 1e9) // 3333 gwei

	// Минимальная комиссия для предотвращения спама
	minFee := new(big.Int).SetUint64(1000 * 1e9) // 1000 gwei minimum

	if baseFee.Cmp(minFee) < 0 {
		return minFee
	}

	return baseFee
}

// VerifyFeeSplit проверяет корректность распределения комиссий в блоке
func VerifyFeeSplit(
	statedb *state.StateDB,
	block *types.Block,
) (bool, map[string]*big.Int) {
	if !IsTOTALPilot(block.Header().Config, block.Number()) {
		return true, nil // Не TOTAL сеть — проверка не нужна
	}

	// Собираем все комиссии из транзакций
	totalFees := big.NewInt(0)
	for _, tx := range block.Transactions() {
		fee := new(big.Int).Mul(
			new(big.Int).SetUint64(tx.Gas()),
			tx.GasPrice(),
		)
		totalFees.Add(totalFees, fee)
	}

	// Проверяем баланс Fee Splitter
	splitterBalance := statedb.GetBalance(TOTALPilotFeeSplitterAddress)

	// Ожидаемый баланс = сумма всех комиссий
	expected := totalFees

	// Допуск 0.1% на rounding errors
	tolerance := new(big.Int).Div(expected, big.NewInt(1000))
	diff := new(big.Int).Sub(splitterBalance, expected)
	if diff.Sign() < 0 {
		diff.Neg(diff)
	}

	if diff.Cmp(tolerance) > 0 {
		return false, map[string]*big.Int{
			"expected": expected,
			"actual":   splitterBalance,
			"diff":     diff,
		}
	}

	return true, map[string]*big.Int{
		"total_fees": totalFees,
		"splitter":   splitterBalance,
	}
}
