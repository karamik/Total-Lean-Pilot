package core

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/params"
)

// TOTAL Pilot Config константы
var (
	TOTALPilotChainID      = big.NewInt(888888)                                // ID сети из спецификации Lean Pilot
	TOTALPilotFeeSplitter  = common.HexToAddress("0x00000000000000000000000000000000FEE55917") // Хардкодный адрес контракта
)

// NewTOTALPilotChainConfig создает дефолтный конфиг для запуска пилота с нулевого блока
func NewTOTALPilotChainConfig() *params.ChainConfig {
	return &params.ChainConfig {
		ChainID:             TOTALPilotChainID,
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
	}
}
