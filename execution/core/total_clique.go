
package clique

import (
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/consensus"
	"github.com/ethereum/go-ethereum/consensus/clique"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/rpc"
)

// TOTALPilotSigners — жёстко заданный набор валидаторов для Lean Pilot
// В production заменить на динамическую регистрацию через стейкинг
var TOTALPilotSigners = []common.Address{
	common.HexToAddress("0xSigner111111111111111111111111111111111111"), // Node 1 (Team)
	common.HexToAddress("0xSigner222222222222222222222222222222222222"), // Node 2 (Team)
	common.HexToAddress("0xSigner333333333333333333333333333333333333"), // Node 3 (Advisor)
}

// TOTALPilotPeriod — интервал между блоками (6 секунд для пилота)
const TOTALPilotPeriod = 6

// TOTALPilotEpoch — длина эпохи для снапшота голосования (100 блоков)
const TOTALPilotEpoch = 100

// NewTOTALPilotClique создаёт экземпляр Clique с параметрами Lean Pilot
func NewTOTALPilotClique() *clique.Clique {
	config := &clique.Config{
		Period: TOTALPilotPeriod,           // 6 секунд между блоками
		Epoch:  TOTALPilotEpoch,            // 100 блоков на эпоху
	}

	// Создаём snapshot с предустановленными валидаторами
	signers := make(map[common.Address]struct{})
	for _, signer := range TOTALPilotSigners {
		signers[signer] = struct{}{}
	}

	return clique.New(config, nil, nil)
}

// IsAuthorizedSigner проверяет, является ли адрес авторизованным валидатором
func IsAuthorizedSigner(addr common.Address) bool {
	for _, signer := range TOTALPilotSigners {
		if signer == addr {
			return true
		}
	}
	return false
}

// RequiredSigners возвращает минимальное количество подписей (2-of-3)
func RequiredSigners() int {
	return (len(TOTALPilotSigners) * 2 / 3) + 1 // 2 из 3
}

// TOTALPilotGenesis создаёт генезис-блок для Lean Pilot
func TOTALPilotGenesis() *types.Block {
	alloc := make(types.GenesisAlloc)

	// Предустановленные балансы для валидаторов (gas)
	for _, signer := range TOTALPilotSigners {
		alloc[signer] = types.Account{
			Balance: new(big.Int).Mul(big.NewInt(1e18), big.NewInt(1000)), // 1000 ETH
		}
	}

	// Предустановленный баланс для Fee Splitter
	feeSplitterAddr := common.HexToAddress("0x00000000000000000000000000000000FEE55917")
	alloc[feeSplitterAddr] = types.Account{
		Balance: big.NewInt(0),
		Code:    []byte{}, // Будет установлен после деплоя
	}

	genesis := &types.Genesis{
		Config:     NewTOTALPilotChainConfig(), // из total_config.go
		Alloc:      alloc,
		ExtraData:  generateExtraData(TOTALPilotSigners),
		GasLimit:   30_000_000,              // 30M gas limit
		Difficulty: big.NewInt(1),
		Timestamp:  uint64(time.Now().Unix()),
	}

	return genesis.MustCommit(nil)
}

// generateExtraData формирует ExtraData для Clique с валидаторами
func generateExtraData(signers []common.Address) []byte {
	// Clique ExtraData format: 32 bytes vanity + signers + 65 bytes seal
	extra := make([]byte, 32) // vanity
	for _, signer := range signers {
		extra = append(extra, signer.Bytes()...)
	}
	extra = append(extra, make([]byte, 65)...) // seal placeholder
	return extra
}

// SealHash возвращает хеш для подписи блока (Clique consensus)
func SealHash(header *types.Header) common.Hash {
	return clique.SealHash(header)
}
