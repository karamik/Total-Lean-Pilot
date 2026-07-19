
# TOTAL Lean Pilot — Makefile
# Управление билдом, тестами, деплоем и мониторингом

.PHONY: all deps build test clean 	build-execution build-prover build-contracts 	test test-integration test-fpga-emulation 	deploy deploy-honeypot 	monitoring-up monitoring-down monitoring-logs 	audit audit-full audit-slither audit-mythril audit-echidna 	benchmark-prover benchmark-tps benchmark-economics 	devnet-up devnet-down celestia-mock prover-dev 	fmt lint coverage snapshot 	help

# ============ CONFIG ============
SHELL := /bin/bash
CONTRACTS_DIR := contracts
EXECUTION_DIR := execution
MONITORING_DIR := monitoring
SCRIPTS_DIR := scripts

# Foundry
FOUNDRY_PROFILE ?= default

# Colors for output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# ============ DEFAULT ============
all: deps build test

# ============ HELP ============
help:
	@echo "$(BLUE)TOTAL Lean Pilot — Available Commands$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup:$(RESET)"
	@echo "  make deps              Install all dependencies"
	@echo ""
	@echo "$(GREEN)Build:$(RESET)"
	@echo "  make build             Build all components"
	@echo "  make build-execution   Build Geth fork"
	@echo "  make build-prover      Build FPGA prover"
	@echo "  make build-contracts   Build Solidity contracts"
	@echo ""
	@echo "$(GREEN)Test:$(RESET)"
	@echo "  make test              Run all tests"
	@echo "  make test-integration  Run integration tests"
	@echo "  make test-fpga-emulation  Run FPGA emulation tests"
	@echo "  make coverage          Generate coverage report"
	@echo "  make snapshot          Check gas snapshot"
	@echo ""
	@echo "$(GREEN)Security Audit:$(RESET)"
	@echo "  make audit             Run full security audit"
	@echo "  make audit-slither     Run Slither analysis"
	@echo "  make audit-mythril     Run Mythril symbolic execution"
	@echo "  make audit-echidna     Run Echidna fuzzing"
	@echo ""
	@echo "$(GREEN)Deploy:$(RESET)"
	@echo "  make deploy            Deploy FeeSplitter"
	@echo "  make deploy-honeypot   Deploy HackerHoneypot (with 1 ETH prize)"
	@echo ""
	@echo "$(GREEN)Devnet:$(RESET)"
	@echo "  make devnet-up         Start local devnet"
	@echo "  make devnet-down       Stop local devnet"
	@echo "  make celestia-mock     Start mock Celestia light node"
	@echo "  make prover-dev        Start prover in CPU mode"
	@echo ""
	@echo "$(GREEN)Monitoring:$(RESET)"
	@echo "  make monitoring-up     Start Prometheus + Grafana"
	@echo "  make monitoring-down   Stop monitoring stack"
	@echo "  make monitoring-logs   View monitoring logs"
	@echo ""
	@echo "$(GREEN)Benchmark:$(RESET)"
	@echo "  make benchmark-prover  Benchmark proof generation"
	@echo "  make benchmark-tps     Benchmark throughput"
	@echo "  make benchmark-economics  Run cost analysis"
	@echo ""
	@echo "$(GREEN)Maintenance:$(RESET)"
	@echo "  make fmt               Format code"
	@echo "  make lint              Run linters"
	@echo "  make clean             Clean build artifacts"

# ============ DEPENDENCIES ============
deps: deps-go deps-foundry deps-celestia
	@echo "$(GREEN)✓ All dependencies installed$(RESET)"

deps-go:
	@echo "$(BLUE)Installing Go dependencies...$(RESET)"
	go mod download
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

deps-foundry:
	@echo "$(BLUE)Installing Foundry...$(RESET)"
	@if ! command -v forge &> /dev/null; then 		curl -L https://foundry.paradigm.xyz | bash; 		$(HOME)/.foundry/bin/foundryup; 	fi
	cd $(CONTRACTS_DIR) && forge install

deps-celestia:
	@echo "$(BLUE)Installing Celestia node...$(RESET)"
	@if ! command -v celestia &> /dev/null; then 		curl -sL https://docs.celestia.org/celestia-node-install.sh | bash; 	fi

deps-monitoring:
	@echo "$(BLUE)Pulling monitoring images...$(RESET)"
	docker pull prom/prometheus:v2.53.0
	docker pull grafana/grafana:11.0.0
	docker pull prom/node-exporter:v1.8.0
	docker pull prom/pushgateway:v1.9.0

# ============ BUILD ============
build: build-contracts build-execution
	@echo "$(GREEN)✓ Build complete$(RESET)"

build-contracts:
	@echo "$(BLUE)Building contracts...$(RESET)"
	cd $(CONTRACTS_DIR) && forge build --force

build-execution:
	@echo "$(BLUE)Building execution layer...$(RESET)"
	cd $(EXECUTION_DIR) && go build -o ../build/total-geth ./cmd/total-geth

build-prover:
	@echo "$(BLUE)Building prover...$(RESET)"
	cd prover && cargo build --release

# ============ TEST ============
test: test-contracts test-execution
	@echo "$(GREEN)✓ All tests passed$(RESET)"

test-contracts:
	@echo "$(BLUE)Running contract tests...$(RESET)"
	cd $(CONTRACTS_DIR) && FOUNDRY_PROFILE=$(FOUNDRY_PROFILE) forge test -vvv

test-execution:
	@echo "$(BLUE)Running execution tests...$(RESET)"
	go test ./$(EXECUTION_DIR)/... -v -race

test-integration:
	@echo "$(BLUE)Running integration tests...$(RESET)"
	cd $(CONTRACTS_DIR) && forge test --match-contract Integration -vvv
	go test ./... -tags=integration -v

test-fpga-emulation:
	@echo "$(BLUE)Running FPGA emulation tests...$(RESET)"
	cd prover && cargo test --features emulation

test-honeypot:
	@echo "$(BLUE)Running honeypot tests...$(RESET)"
	cd $(CONTRACTS_DIR) && forge test --match-contract HackerHoneypot -vvv

# ============ COVERAGE & GAS ============
coverage:
	@echo "$(BLUE)Generating coverage report...$(RESET)"
	cd $(CONTRACTS_DIR) && forge coverage --report lcov
	@echo "$(GREEN)✓ Coverage report: contracts/lcov.info$(RESET)"

snapshot:
	@echo "$(BLUE)Checking gas snapshot...$(RESET)"
	cd $(CONTRACTS_DIR) && forge snapshot --check

gas-report:
	@echo "$(BLUE)Generating gas report...$(RESET)"
	cd $(CONTRACTS_DIR) && FOUNDRY_PROFILE=gas forge test --gas-report > gas-report.txt
	@echo "$(GREEN)✓ Gas report: contracts/gas-report.txt$(RESET)"

# ============ FORMAT & LINT ============
fmt:
	@echo "$(BLUE)Formatting code...$(RESET)"
	cd $(CONTRACTS_DIR) && forge fmt
	cd $(EXECUTION_DIR) && gofmt -w .
	@echo "$(GREEN)✓ Formatted$(RESET)"

lint:
	@echo "$(BLUE)Running linters...$(RESET)"
	cd $(CONTRACTS_DIR) && forge fmt --check
	cd $(EXECUTION_DIR) && golangci-lint run --timeout=5m
	@echo "$(GREEN)✓ Lint passed$(RESET)"

# ============ SECURITY AUDIT ============
audit: audit-slither audit-mythril audit-echidna
	@echo "$(GREEN)✓ Full security audit complete$(RESET)"

audit-full: audit
	cd $(CONTRACTS_DIR) && FOUNDRY_PROFILE=security forge test

audit-slither:
	@echo "$(BLUE)Running Slither...$(RESET)"
	cd $(CONTRACTS_DIR) && slither src/ --config slither.config.json --fail-high

audit-mythril:
	@echo "$(BLUE)Running Mythril...$(RESET)"
	cd $(CONTRACTS_DIR) && 	myth analyze src/FeeSplitter.sol --solc-json mythril.config.json --execution-timeout 600 && 	myth analyze src/HackerHoneypot.sol --solc-json mythril.config.json --execution-timeout 600

audit-echidna:
	@echo "$(BLUE)Running Echidna...$(RESET)"
	cd $(CONTRACTS_DIR) && 	echidna test/FeeSplitterEchidna.sol --contract FeeSplitterEchidna --config echidna.config.yml

# ============ DEPLOY ============
deploy: deploy-feestplitter
	@echo "$(GREEN)✓ Deployed$(RESET)"

deploy-feestplitter:
	@echo "$(BLUE)Deploying FeeSplitter...$(RESET)"
	cd $(CONTRACTS_DIR) && 	forge script script/DeployFeeSplitter.s.sol 		--rpc-url $(RPC_URL) 		--broadcast 		--verify

deploy-honeypot:
	@echo "$(BLUE)Deploying HackerHoneypot with 1 ETH prize pool...$(RESET)"
	@if [ -z "$(FEE_SPLITTER_ADDRESS)" ]; then 		echo "$(RED)Error: FEE_SPLITTER_ADDRESS not set$(RESET)"; 		exit 1; 	fi
	cd $(CONTRACTS_DIR) && 	forge script script/DeployHoneypot.s.sol 		--rpc-url $(RPC_URL) 		--broadcast 		--value 1ether 		--verify
	@echo "$(GREEN)✓ Honeypot deployed with 1 ETH prize pool$(RESET)"

# ============ DEVNET ============
devnet-up:
	@echo "$(BLUE)Starting local devnet...$(RESET)"
	./$(SCRIPTS_DIR)/devnet-up.sh

devnet-down:
	@echo "$(BLUE)Stopping devnet...$(RESET)"
	./$(SCRIPTS_DIR)/devnet-down.sh

celestia-mock:
	@echo "$(BLUE)Starting mock Celestia light node...$(RESET)"
	celestia light start --core.ip localhost --core.port 9090 --p2p.network private

prover-dev:
	@echo "$(BLUE)Starting prover in CPU mode...$(RESET)"
	cd prover && cargo run --bin prover-dev -- --mode cpu

# ============ MONITORING ============
monitoring-up:
	@echo "$(BLUE)Starting monitoring stack...$(RESET)"
	cd $(MONITORING_DIR) && docker-compose up -d
	@echo "$(GREEN)✓ Monitoring started$(RESET)"
	@echo "  Grafana:    http://localhost:3000 (admin/total-pilot-2026)"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Pushgateway: http://localhost:9091"

monitoring-down:
	@echo "$(BLUE)Stopping monitoring stack...$(RESET)"
	cd $(MONITORING_DIR) && docker-compose down
	@echo "$(GREEN)✓ Monitoring stopped$(RESET)"

monitoring-logs:
	cd $(MONITORING_DIR) && docker-compose logs -f

monitoring-restart: monitoring-down monitoring-up

# ============ BENCHMARK ============
benchmark-prover:
	@echo "$(BLUE)Benchmarking proof generation...$(RESET)"
	cd prover && cargo bench

benchmark-tps:
	@echo "$(BLUE)Benchmarking throughput...$(RESET)"
	./$(SCRIPTS_DIR)/benchmark-tps.sh

benchmark-economics:
	@echo "$(BLUE)Running cost analysis...$(RESET)"
	python3 $(SCRIPTS_DIR)/benchmark-economics.py

# ============ CLEAN ============
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(RESET)"
	cd $(CONTRACTS_DIR) && forge clean
	rm -rf build/
	rm -rf $(CONTRACTS_DIR)/out/
	rm -rf $(CONTRACTS_DIR)/cache/
	go clean -cache
	@echo "$(GREEN)✓ Cleaned$(RESET)"

# ============ INFO ============
info:
	@echo "$(BLUE)TOTAL Lean Pilot$(RESET)"
	@echo "ChainID: 888888"
	@echo "Block Time: 6s"
	@echo "Fee: $0.01/tx"
	@echo "Break-even: 0.11 TPS"
