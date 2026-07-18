
# TOTAL Lean Pilot — Makefile
.PHONY: all deps build test clean devnet-up devnet-down deploy-feesplitter benchmark

# === Variables ===
GO_VERSION := 1.22
FOUNDRY_VERSION := nightly
CELESTIA_VERSION := v0.28.0

# === Default ===
all: deps build

# === Dependencies ===
deps: deps-go deps-foundry deps-celestia

deps-go:
	@echo "==> Installing Go dependencies..."
	go mod tidy

deps-foundry:
	@echo "==> Installing Foundry..."
	@if ! command -v forge &> /dev/null; then 		curl -L https://foundry.paradigm.xyz | bash; 		foundryup; 	fi
	forge install

deps-celestia:
	@echo "==> Installing Celestia CLI..."
	@if ! command -v celestia &> /dev/null; then 		curl -sL https://docs.celestia.org/install.sh | bash; 	fi

# === Build ===
build: build-execution build-contracts

build-execution:
	@echo "==> Building execution node..."
	cd execution && go build -o bin/total-geth ./cmd/total-geth

build-contracts:
	@echo "==> Building smart contracts..."
	cd contracts && forge build

build-prover:
	@echo "==> Building prover (CPU emulation mode)..."
	cd prover && cargo build --release

# === Test ===
test: test-contracts test-execution

test-contracts:
	@echo "==> Testing smart contracts..."
	cd contracts && forge test -vvv

test-execution:
	@echo "==> Testing execution node..."
	cd execution && go test ./core/... -v

test-integration:
	@echo "==> Running integration tests..."
	./scripts/test-integration.sh

test-fpga-emulation:
	@echo "==> Running FPGA emulation tests..."
	cd prover && cargo test --features emulation

# === Devnet ===
devnet-up:
	@echo "==> Starting local devnet..."
	docker-compose -f validator/docker/docker-compose.yml up -d
	@echo "Devnet started at http://localhost:8545"

devnet-down:
	@echo "==> Stopping devnet..."
	docker-compose -f validator/docker/docker-compose.yml down

# === Celestia ===
celestia-mock:
	@echo "==> Starting Celestia mock (local dev)..."
	./scripts/celestia-mock.sh

celestia-light:
	@echo "==> Starting Celestia light node..."
	celestia light init --p2p.network celestia || true
	celestia light start --core.ip rpc.celestia.pops.one

# === Deployment ===
deploy-feesplitter:
	@echo "==> Deploying FeeSplitter..."
	cd contracts && forge script script/DeployFeeSplitter.s.sol \
		--rpc-url http://localhost:8545 \
		--broadcast \
		--private-key $(PRIVATE_KEY)

# === Benchmark ===
benchmark-prover:
	@echo "==> Benchmarking prover..."
	cd prover && cargo bench

benchmark-tps:
	@echo "==> Benchmarking TPS..."
	./scripts/benchmark-tps.sh

benchmark-economics:
	@echo "==> Running economic simulation..."
	python3 scripts/economics_sim.py

# === Monitoring ===
monitoring-up:
	@echo "==> Starting monitoring stack..."
	docker-compose -f monitoring/docker-compose.yml up -d

# === Clean ===
clean:
	@echo "==> Cleaning build artifacts..."
	rm -rf execution/bin/
	rm -rf contracts/out/
	rm -rf contracts/cache/
	rm -rf prover/target/

# === Help ===
help:
	@echo "TOTAL Lean Pilot — Available commands:"
	@echo ""
	@echo "  make deps              Install all dependencies"
	@echo "  make build             Build all components"
	@echo "  make test              Run all tests"
	@echo "  make devnet-up         Start local devnet"
	@echo "  make devnet-down       Stop local devnet"
	@echo "  make deploy-feesplitter Deploy FeeSplitter contract"
	@echo "  make benchmark-tps     Benchmark throughput"
	@echo "  make clean             Clean build artifacts"
