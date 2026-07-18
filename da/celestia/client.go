
# Создадим полную интеграцию Celestia DA для Total-Lean-Pilot
# da/celestia/client.go - основной клиент

da_client = '''// Package celestia provides integration with Celestia Data Availability layer
// for Total-Lean-Pilot rollup.
//
// Architecture:
//   - Geth execution layer produces blocks
//   - Block data (transactions, state diffs) compressed and submitted to Celestia as blobs
//   - Celestia returns height + commitment (DA proof)
//   - DA proof stored in Geth block header (extraData or custom field)
//   - Light node performs DAS (Data Availability Sampling) to verify
//
// Cost: ~$100/month for light node + blob fees
package celestia

import (
	"bytes"
	"compress/zlib"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/celestiaorg/celestia-node/api/client"
	"github.com/celestiaorg/celestia-node/blob"
	"github.com/celestiaorg/celestia-node/nodebuilder/p2p"
	"github.com/celestiaorg/go-square/v3/share"
	"github.com/cosmos/cosmos-sdk/crypto/keyring"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/log"
)

const (
	// Namespace for Total-Lean-Pilot data on Celestia
	// Must be unique to avoid collisions with other rollups
	DefaultNamespace = "total-lean-pilot"

	// Max blob size per transaction (slightly under 8 MiB limit)
	MaxBlobSize = 7 * 1024 * 1024 // 7 MB

	// Compression level for block data
	CompressionLevel = zlib.BestCompression

	// Default timeout for DA operations
	DefaultTimeout = 2 * time.Minute

	// Max gas price for blob submission (in utia)
	// 0.2 TIA = 200000 utia, we allow up to 100x = 20M utia
	DefaultMaxGasPrice = 20000000
)

// DAProof represents a Celestia Data Availability proof
// Stored in block header to verify data availability
type DAProof struct {
	// Celestia block height where blob was included
	Height uint64 `json:"height"`

	// Namespace used for this blob
	Namespace string `json:"namespace"`

	// Blob commitment (unique identifier)
	Commitment string `json:"commitment"`

	// Original data hash (for verification)
	DataHash common.Hash `json:"dataHash"`

	// Compressed data size
	CompressedSize int `json:"compressedSize"`

	// Original data size
	OriginalSize int `json:"originalSize"`

	// Timestamp of submission
	Timestamp time.Time `json:"timestamp"`
}

// MarshalJSON serializes DAProof to JSON bytes
func (p *DAProof) MarshalJSON() ([]byte, error) {
	type Alias DAProof
	return json.Marshal(&struct {
		*Alias
		DataHash string `json:"dataHash"`
	}{
		Alias:    (*Alias)(p),
		DataHash: p.DataHash.Hex(),
	})
}

// UnmarshalJSON deserializes JSON bytes to DAProof
func (p *DAProof) UnmarshalJSON(data []byte) error {
	type Alias DAProof
	aux := &struct {
		*Alias
		DataHash string `json:"dataHash"`
	}{
		Alias: (*Alias)(p),
	}
	if err := json.Unmarshal(data, aux); err != nil {
		return err
	}
	p.DataHash = common.HexToHash(aux.DataHash)
	return nil
}

// ToExtraData serializes DAProof for storage in block header extraData
func (p *DAProof) ToExtraData() ([]byte, error) {
	data, err := p.MarshalJSON()
	if err != nil {
		return nil, err
	}
	// Prepend with magic bytes to identify TOTAL DA proofs
	magic := []byte("TOTALDA:")
	return append(magic, data...), nil
}

// DAProofFromExtraData parses DAProof from block header extraData
func DAProofFromExtraData(extra []byte) (*DAProof, error) {
	magic := []byte("TOTALDA:")
	if !bytes.HasPrefix(extra, magic) {
		return nil, fmt.Errorf("not a TOTAL DA proof")
	}
	data := bytes.TrimPrefix(extra, magic)
	var proof DAProof
	if err := json.Unmarshal(data, &proof); err != nil {
		return nil, err
	}
	return &proof, nil
}

// Config holds Celestia DA client configuration
type Config struct {
	// DA node JSON-RPC endpoint (port 26658)
	// Example: http://localhost:26658
	DAURL string

	// Enable TLS for DA connection
	DATLS bool

	// DA auth token (for protected endpoints)
	DAAuthToken string

	// Consensus node gRPC endpoint (port 9090)
	// Required for blob submission
	// Example: localhost:9090
	CoreGRPC string

	// Enable TLS for gRPC
	CoreTLSEnabled bool

	// gRPC auth token
	CoreAuthToken string

	// Celestia network
	Network string // "celestia", "mocha-4", "arabica"

	// Namespace for this rollup
	Namespace string

	// Keyring configuration
	KeyringDir   string
	KeyName      string
	BackendName  string // "test", "file", "os"

	// Transaction submission mode
	// 0 = immediate (default)
	// 1 = queued (preserves ordering)
	// >1 = parallel (high throughput)
	TxWorkerAccounts int

	// Max gas price willing to pay
	MaxGasPrice int

	// Timeout for DA operations
	Timeout time.Duration
}

// DefaultConfig returns default configuration for Lean Pilot
func DefaultConfig() *Config {
	return &Config{
		DAURL:            "http://localhost:26658",
		DATLS:            false,
		Network:          "mocha-4",
		Namespace:        DefaultNamespace,
		KeyringDir:       "./celestia-keys",
		KeyName:          "total-pilot",
		BackendName:      keyring.BackendTest,
		TxWorkerAccounts: 1, // Queued mode for ordering
		MaxGasPrice:      DefaultMaxGasPrice,
		Timeout:          DefaultTimeout,
	}
}

// Client wraps Celestia node client for TOTAL rollup
type Client struct {
	cfg    *Config
	client *client.Client
	ns     share.Namespace
}

// NewClient creates a new Celestia DA client
func NewClient(cfg *Config) (*Client, error) {
	if cfg == nil {
		cfg = DefaultConfig()
	}

	// Create namespace
	ns, err := share.NewV0Namespace([]byte(cfg.Namespace))
	if err != nil {
		return nil, fmt.Errorf("failed to create namespace: %w", err)
	}

	return &Client{
		cfg: cfg,
		ns:  ns,
	}, nil
}

// Connect establishes connection to Celestia node
func (c *Client) Connect(ctx context.Context) error {
	// Create keyring
	kr, err := client.KeyringWithNewKey(client.KeyringConfig{
		KeyName:     c.cfg.KeyName,
		BackendName: c.cfg.BackendName,
	}, c.cfg.KeyringDir)
	if err != nil {
		return fmt.Errorf("failed to create keyring: %w", err)
	}

	// Build client config
	clientCfg := client.Config{
		ReadConfig: client.ReadConfig{
			BridgeDAAddr: c.cfg.DAURL,
			EnableDATLS:  c.cfg.DATLS,
		},
		SubmitConfig: client.SubmitConfig{
			DefaultKeyName:   c.cfg.KeyName,
			TxWorkerAccounts: c.cfg.TxWorkerAccounts,
		},
	}

	if c.cfg.DAAuthToken != "" {
		clientCfg.ReadConfig.DAAuthToken = c.cfg.DAAuthToken
	}

	// Full client mode (can submit blobs)
	if c.cfg.CoreGRPC != "" {
		network := p2p.Network(c.cfg.Network)
		clientCfg.SubmitConfig.Network = network
		clientCfg.SubmitConfig.CoreGRPCConfig = client.CoreGRPCConfig{
			Addr:       c.cfg.CoreGRPC,
			TLSEnabled: c.cfg.CoreTLSEnabled,
		}
		if c.cfg.CoreAuthToken != "" {
			clientCfg.SubmitConfig.CoreGRPCConfig.AuthToken = c.cfg.CoreAuthToken
		}
		log.Info("Celestia DA client: full mode (can submit blobs)")
	} else {
		log.Info("Celestia DA client: read-only mode")
	}

	// Create client
	cli, err := client.New(ctx, clientCfg, kr)
	if err != nil {
		return fmt.Errorf("failed to create celestia client: %w", err)
	}

	c.client = cli

	// Log account info
	keyInfo, err := kr.Key(c.cfg.KeyName)
	if err == nil {
		addr, _ := keyInfo.GetAddress()
		log.Info("Celestia DA account", "address", addr.String())
	}

	return nil
}

// Close closes the client connection
func (c *Client) Close() error {
	if c.client != nil {
		return c.client.Close()
	}
	return nil
}

// IsConnected returns true if client is connected
func (c *Client) IsConnected() bool {
	return c.client != nil
}

// Balance returns account balance
func (c *Client) Balance(ctx context.Context) (string, error) {
	if c.client == nil {
		return "", fmt.Errorf("client not connected")
	}
	balance, err := c.client.State.Balance(ctx)
	if err != nil {
		return "", err
	}
	return balance.String(), nil
}

// compress compresses data using zlib
func compress(data []byte) ([]byte, error) {
	var buf bytes.Buffer
	w, err := zlib.NewWriterLevel(&buf, CompressionLevel)
	if err != nil {
		return nil, err
	}
	if _, err := w.Write(data); err != nil {
		return nil, err
	}
	if err := w.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// decompress decompresses zlib data
func decompress(data []byte) ([]byte, error) {
	r, err := zlib.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer r.Close()
	return io.ReadAll(r)
}

// SubmitBlock submits block data to Celestia DA layer
// Returns DAProof that can be stored in block header
func (c *Client) SubmitBlock(ctx context.Context, blockData []byte) (*DAProof, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	if c.cfg.CoreGRPC == "" {
		return nil, fmt.Errorf("core gRPC not configured, cannot submit blobs")
	}

	ctx, cancel := context.WithTimeout(ctx, c.cfg.Timeout)
	defer cancel()

	// Compress block data
	compressed, err := compress(blockData)
	if err != nil {
		return nil, fmt.Errorf("failed to compress block data: %w", err)
	}

	// Check size limit
	if len(compressed) > MaxBlobSize {
		return nil, fmt.Errorf("compressed block data exceeds max blob size: %d > %d", len(compressed), MaxBlobSize)
	}

	// Create blob
	b, err := blob.NewBlob(share.ShareVersionZero, c.ns, compressed, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create blob: %w", err)
	}

	// Submit to Celestia
	log.Info("Submitting block to Celestia DA", "size", len(blockData), "compressed", len(compressed))
	height, err := c.client.Blob.Submit(ctx, []*blob.Blob{b}, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to submit blob: %w", err)
	}

	// Build DA proof
	proof := &DAProof{
		Height:         height,
		Namespace:      c.cfg.Namespace,
		Commitment:     hex.EncodeToString(b.Commitment),
		DataHash:       common.BytesToHash(blockData),
		CompressedSize: len(compressed),
		OriginalSize:   len(blockData),
		Timestamp:      time.Now(),
	}

	log.Info("Block submitted to Celestia DA",
		"height", height,
		"commitment", proof.Commitment[:16]+"...",
		"compressionRatio", float64(len(compressed))/float64(len(blockData)),
	)

	return proof, nil
}

// RetrieveBlock retrieves block data from Celestia DA layer
func (c *Client) RetrieveBlock(ctx context.Context, proof *DAProof) ([]byte, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	ctx, cancel := context.WithTimeout(ctx, c.cfg.Timeout)
	defer cancel()

	// Parse commitment
	commitment, err := hex.DecodeString(proof.Commitment)
	if err != nil {
		return nil, fmt.Errorf("failed to decode commitment: %w", err)
	}

	// Retrieve blob
	log.Info("Retrieving block from Celestia DA", "height", proof.Height, "namespace", proof.Namespace)
	retrieved, err := c.client.Blob.Get(ctx, proof.Height, c.ns, commitment)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve blob: %w", err)
	}

	// Decompress
	data, err := decompress(retrieved.Data())
	if err != nil {
		return nil, fmt.Errorf("failed to decompress blob: %w", err)
	}

	// Verify hash
	hash := common.BytesToHash(data)
	if hash != proof.DataHash {
		return nil, fmt.Errorf("data hash mismatch: expected %s, got %s", proof.DataHash.Hex(), hash.Hex())
	}

	log.Info("Block retrieved from Celestia DA", "height", proof.Height, "size", len(data))
	return data, nil
}

// VerifyAvailability performs Data Availability Sampling (DAS)
// to verify that block data is available on Celestia network
func (c *Client) VerifyAvailability(ctx context.Context, proof *DAProof) (bool, error) {
	if c.client == nil {
		return false, fmt.Errorf("client not connected")
	}

	ctx, cancel := context.WithTimeout(ctx, c.cfg.Timeout)
	defer cancel()

	// Parse commitment
	commitment, err := hex.DecodeString(proof.Commitment)
	if err != nil {
		return false, fmt.Errorf("failed to decode commitment: %w", err)
	}

	// Get inclusion proof
	_, err = c.client.Blob.GetProof(ctx, proof.Height, c.ns, commitment)
	if err != nil {
		return false, fmt.Errorf("failed to get inclusion proof: %w", err)
	}

	// If we got here, blob is available (light node performed DAS)
	return true, nil
}

// GetProof returns the inclusion proof for a blob
// Can be used for fraud proofs or challenges
func (c *Client) GetProof(ctx context.Context, proof *DAProof) ([]byte, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	commitment, err := hex.DecodeString(proof.Commitment)
	if err != nil {
		return nil, fmt.Errorf("failed to decode commitment: %w", err)
	}

	proofData, err := c.client.Blob.GetProof(ctx, proof.Height, c.ns, commitment)
	if err != nil {
		return nil, fmt.Errorf("failed to get proof: %w", err)
	}

	return proofData, nil
}

// EstimateGas estimates gas for blob submission
func (c *Client) EstimateGas(dataSize int) uint64 {
	// Use Celestia's default gas estimation
	// blobtypes.DefaultEstimateGas([]uint32{uint32(dataSize)})
	// For now, use rough estimate
	const gasPerByte = 8
	const flatGas = 65000
	return uint64(flatGas + dataSize*gasPerByte)
}
'''

with open('/mnt/agents/output/da_celestia_client.go', 'w') as f:
    f.write(da_client)

print("✅ da/celestia/client.go создан")
print(f"Размер: {len(da_client)} bytes")
