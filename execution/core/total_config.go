// execution/core/total_config.go

package core

import (
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/params"
)

// TotalConfig — расширение стандартного ChainConfig
type TotalConfig struct {
    *params.ChainConfig
    
    // FeeSplitter
    FeeSplitterAddress common.Address `json:"feeSplitterAddress"`
    
    // Distributor (этот нод — execution layer)
    IsDistributor bool `json:"isDistributor"`
}

// DefaultTotalConfig для пилота
func DefaultTotalConfig() *TotalConfig {
    return &TotalConfig{
        ChainConfig: params.TestChainConfig, // или кастомный
        
        // Пустой адрес — будет установлен при деплое
        FeeSplitterAddress: common.Address{},
        IsDistributor:      false,
    }
}
