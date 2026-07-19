
package celestia

import (
	"encoding/json"
	"os"
)

// LoadConfig loads Celestia DA config from JSON file
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	// Set defaults for empty fields
	if cfg.Namespace == "" {
		cfg.Namespace = DefaultNamespace
	}
	if cfg.Network == "" {
		cfg.Network = "mocha-4"
	}
	if cfg.KeyName == "" {
		cfg.KeyName = "total-pilot"
	}
	if cfg.BackendName == "" {
		cfg.BackendName = "test"
	}
	if cfg.KeyringDir == "" {
		cfg.KeyringDir = "./celestia-keys"
	}
	if cfg.TxWorkerAccounts == 0 {
		cfg.TxWorkerAccounts = 1
	}
	if cfg.MaxGasPrice == 0 {
		cfg.MaxGasPrice = DefaultMaxGasPrice
	}
	if cfg.Timeout == 0 {
		cfg.Timeout = DefaultTimeout
	}

	return &cfg, nil
}

// SaveConfig saves config to JSON file
func SaveConfig(path string, cfg *Config) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}
