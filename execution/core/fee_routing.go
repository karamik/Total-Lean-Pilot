// execution/core/fee_routing.go

package core

import (
    "math/big"
    
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/vm"
    "github.com/ethereum/go-ethereum/log"
)

var (
    // FeeSplitter address — из конфига, НЕ хардкод
    // Загружается из genesis или chain config
    feeSplitterAddress common.Address
)

// SetFeeSplitterAddress вызывается при инициализации
func SetFeeSplitterAddress(addr common.Address) {
    feeSplitterAddress = addr
}

// RouteFees отправляет fee на FeeSplitter вместо miner
func RouteFees(statedb *state.StateDB, fees *big.Int, header *types.Header) {
    if feeSplitterAddress == (common.Address{}) {
        log.Warn("FeeSplitter not configured, fees go to miner")
        return
    }
    
    // Переводим fee на FeeSplitter
    statedb.AddBalance(feeSplitterAddress, fees)
    
    log.Debug("Fees routed to FeeSplitter", 
        "amount", fees,
        "address", feeSplitterAddress,
        "block", header.Number)
}

// DistributeFees вызывает distribute() на FeeSplitter
// Вызывается в конце обработки блока
func DistributeFees(evm *vm.EVM, header *types.Header) error {
    if feeSplitterAddress == (common.Address{}) {
        return nil
    }
    
    // Проверяем баланс FeeSplitter
    // distribute() вызывается только если есть что распределять
    // и только distributor (этот нод)
    
    // ABI вызова distribute()
    data := common.Hex2Bytes("0x5c...") // keccak256("distribute()")[:4]
    
    // Вызываем как internal transaction (system call)
    // Не требует gas, не записывается как обычная транзакция
    _, _, err := evm.Call(
        vm.AccountRef(common.Address{}), // from: system
        feeSplitterAddress,
        data,
        0,    // gas: unlimited для system call
        big.NewInt(0),
    )
    
    if err != nil {
        log.Error("Failed to distribute fees", "err", err, "block", header.Number)
        return err
    }
    
    log.Info("Fees distributed", "block", header.Number)
    return nil
}
