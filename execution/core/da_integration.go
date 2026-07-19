
package core

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/log"
	"github.com/ethereum/go-ethereum/rlp"

	"github.com/karamik/Total-Lean-Pilot/da/celestia"
)

// DAIntegration wraps Celestia DA client for Geth integration
type DAIntegration struct {
	client  *celestia.Client
	indexer *celestia.DAIndexer
	enabled bool
}

// NewDAIntegration creates DA integration (nil if disabled)
func NewDAIntegration(cfg *celestia.Config) (*DAIntegration, error) {
	if cfg == nil || cfg.DAURL == "" {
		log.Info("Celestia DA: disabled (no config)")
		return &DAIntegration{enabled: false}, nil
	}

	client, err := celestia.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create celestia client: %w", err)
	}

	if err := client.Connect(context.Background()); err != nil {
		log.Warn("Celestia DA: failed to connect, running in mock mode", "err", err)
		return &DAIntegration{enabled: false}, nil
	}

	indexer := celestia.NewDAIndexer(client, "./data/da-index")
	if err := indexer.Start(context.Background()); err != nil {
		return nil, fmt.Errorf("failed to start DA indexer: %w", err)
	}

	log.Info("Celestia DA: enabled",
		"url", cfg.DAURL,
		"namespace", cfg.Namespace,
		"network", cfg.Network,
	)

	return &DAIntegration{
		client:  client,
		indexer: indexer,
		enabled: true,
	}, nil
}

// Enabled returns true if DA is enabled
func (da *DAIntegration) Enabled() bool {
	return da.enabled
}

// Stop stops DA integration
func (da *DAIntegration) Stop() {
	if da.indexer != nil {
		da.indexer.Stop()
	}
	if da.client != nil {
		da.client.Close()
	}
}

// SubmitBlock submits block data to Celestia and returns DA proof for header
func (da *DAIntegration) SubmitBlock(block *types.Block) (*celestia.DAProof, error) {
	if !da.enabled {
		return nil, nil
	}

	// Serialize block data (header + transactions)
	blockData, err := rlp.EncodeToBytes(block)
	if err != nil {
		return nil, fmt.Errorf("failed to encode block: %w", err)
	}

	// Submit to Celestia
	ctx := context.Background()
	proof, err := da.client.SubmitBlock(ctx, blockData)
	if err != nil {
		// Fallback: log error but don't fail block production
		log.Error("Celestia DA submission failed", "blockNum", block.Number(), "err", err)
		return nil, nil
	}

	// Index the block
	da.indexer.AddBlock(block.NumberU64(), block.Hash(), proof)

	log.Info("Block submitted to Celestia DA",
		"blockNum", block.NumberU64(),
		"blockHash", block.Hash().Hex()[:16],
		"celestiaHeight", proof.Height,
		"compression", fmt.Sprintf("%.1f%%", 100*float64(proof.CompressedSize)/float64(proof.OriginalSize)),
	)

	return proof, nil
}

// GetBlock retrieves block data from Celestia by block number
func (da *DAIntegration) GetBlock(blockNum uint64) (*types.Block, error) {
	if !da.enabled {
		return nil, fmt.Errorf("DA not enabled")
	}

	// Get DA proof from index
	proof, ok := da.indexer.GetProof(blockNum)
	if !ok {
		return nil, fmt.Errorf("no DA proof found for block %d", blockNum)
	}

	// Retrieve from Celestia
	ctx := context.Background()
	blockData, err := da.client.RetrieveBlock(ctx, proof)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve block from DA: %w", err)
	}

	// Decode block
	var block types.Block
	if err := rlp.DecodeBytes(blockData, &block); err != nil {
		return nil, fmt.Errorf("failed to decode block: %w", err)
	}

	return &block, nil
}

// VerifyBlock verifies DA availability for a block
func (da *DAIntegration) VerifyBlock(blockNum uint64) (bool, error) {
	if !da.enabled {
		return true, nil // If DA disabled, assume valid
	}

	proof, ok := da.indexer.GetProof(blockNum)
	if !ok {
		return false, fmt.Errorf("no DA proof for block %d", blockNum)
	}

	ctx := context.Background()
	return da.client.VerifyAvailability(ctx, proof)
}

// InjectDAProof injects DA proof into block header extraData
func InjectDAProof(header *types.Header, proof *celestia.DAProof) error {
	if proof == nil {
		return nil
	}

	extraData, err := proof.ToExtraData()
	if err != nil {
		return fmt.Errorf("failed to serialize DA proof: %w", err)
	}

	// Check size limit (extraData max 32 bytes normally, but we extend for DA)
	if len(extraData) > 1024 {
		return fmt.Errorf("DA proof too large for header: %d bytes", len(extraData))
	}

	header.Extra = extraData
	return nil
}

// ExtractDAProof extracts DA proof from block header extraData
func ExtractDAProof(header *types.Header) (*celestia.DAProof, error) {
	if len(header.Extra) == 0 {
		return nil, nil
	}

	proof, err := celestia.DAProofFromExtraData(header.Extra)
	if err != nil {
		// Not a TOTAL DA proof (maybe standard Clique extraData)
		return nil, nil
	}

	return proof, nil
}

// DAStats returns DA statistics
func (da *DAIntegration) DAStats() (uint64, uint64) {
	if !da.enabled || da.indexer == nil {
		return 0, 0
	}
	return da.indexer.Stats()
}

// DABackend interface for mocking in tests
type DABackend interface {
	SubmitBlock(block *types.Block) (*celestia.DAProof, error)
	GetBlock(blockNum uint64) (*types.Block, error)
	VerifyBlock(blockNum uint64) (bool, error)
	Enabled() bool
}

// MockDABackend for testing without real Celestia connection
type MockDABackend struct{}

func (m *MockDABackend) SubmitBlock(block *types.Block) (*celestia.DAProof, error) {
	return &celestia.DAProof{
		Height:     12345,
		Namespace:  "mock",
		Commitment: "mock-commitment",
		DataHash:   block.Hash(),
	}, nil
}
func (m *MockDABackend) GetBlock(blockNum uint64) (*types.Block, error) { return nil, nil }
func (m *MockDABackend) VerifyBlock(blockNum uint64) (bool, error)      { return true, nil }
func (m *MockDABackend) Enabled() bool                                   { return true }
