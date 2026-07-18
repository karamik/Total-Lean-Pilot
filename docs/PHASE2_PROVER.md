
# Phase 2: AWS F1 Prover — PLONK kernel на VU9P

prover_tz = """# TOTAL Lean Pilot — Phase 2: AWS F1 Prover
## PLONK ZK-Proof Acceleration on Xilinx VU9P

**Status:** Draft  
**Date:** 2026-07-19  
**Priority:** P0 (блокирует Phase 3 Fee Splitter интеграцию)  
**Owner:** FPGA / Cryptography Team  
**Reviewers:** DevOps, Economics  

---

## 1. Executive Summary

Phase 2 портит PLONK ZK-proof generation на AWS F1 (Xilinx VU9P FPGA). Цель — доказать, что облачный FPGA может генерировать PLONK proofs за < 10 секунд при стоимости < $0.01/tx.

**Ключевые метрики:**
| Метрика | CPU (single core) | GPU (A100) | **AWS F1 (VU9P)** | Цель |
|---------|------------------|------------|-------------------|------|
| Proof time | 35-70 сек | 1.5-3 сек | **5-10 сек** | < 10 сек ✅ |
| Cost/tx | $0.025 | $0.003 | **$0.0046** | < $0.01 ✅ |
| Power | 65W | 300W | **~50W** | — |
| Throughput | 1-2 tx/min | 20-40 tx/min | **6-12 tx/min** | > 5 tx/min |

**Референс:** Zcash Foundation FPGA (BLS12-381, MSM, Pairing) — открытый исходный код, проверено на AWS F1.

---

## 2. AWS F1 Platform

### 2.1 Instance Types

| Instance | FPGAs | vCPU | RAM | DDR4/FPGA | Цена/час | Подходит |
|----------|-------|------|-----|-----------|----------|----------|
| **f1.2xlarge** | 1× VU9P | 8 | 122 GB | 64 GB | **$1.65** | ✅ Dev/Test |
| **f1.4xlarge** | 2× VU9P | 16 | 244 GB | 128 GB | **$3.30** | ✅ Pilot |
| **f1.16xlarge** | 8× VU9P | 64 | 976 GB | 512 GB | **$13.20** | Scale |

### 2.2 VU9P FPGA Specs

| Параметр | Значение |
|----------|----------|
| Процесс | 16nm FinFET |
| Logic Cells | ~2.5M |
| DSP Slices | ~6,800 |
| Block RAM | ~75 Mb |
| UltraRAM | — |
| DDR4 | 64 GB ECC (4× 16 GB) |
| PCIe | Gen3 x16 |
| HBM | — |

### 2.3 AWS F1 Development Flow

```
1. Develop (Local / Cloud9)
   ├── HDK: Hardware Development Kit
   ├── SDK: Software Development Kit
   └── FPGA Developer AMI (Amazon Linux 2)

2. Build (FPGA Developer AMI)
   ├── Vivado 2024.1+ (synthesis, place & route)
   ├── Design checkpoint (.dcp)
   └── AWS Shell integration

3. Create AFI
   ├── Upload design to S3
   ├── aws ec2 create-fpga-image
   └── Wait ~1 hour (build + verify)

4. Deploy
   ├── Launch F1 instance
   ├── Load AFI: fpga-load-local-image
   └── Test: ./test_afi

5. Runtime
   ├── DMA transfer (host ↔ FPGA)
   ├── Register reads/writes
   └── Interrupt handling
```

---

## 3. PLONK Algorithm Mapping

### 3.1 PLONK Pipeline

```
PLONK Proof Generation:

Input: Circuit (constraints), Witness (values), Public inputs

Stage 1: Witness Extension (CPU)
├── Evaluate polynomials from witness
├── Compute wire values
└── Time: ~100 ms (negligible)

Stage 2: FFT / iFFT (NTT) — FPGA
├── Forward NTT: coefficients → evaluations
├── Inverse NTT: evaluations → coefficients
└── Time: ~2-3 сек (VU9P)

Stage 3: Multi-Scalar Multiplication (MSM) — FPGA
├── G1 MSM: commitments in base field
├── G2 MSM: commitments in extension field
└── Time: ~3-5 сек (VU9P)

Stage 4: Polynomial Operations — FPGA
├── Quotient polynomial computation
├── Remainder polynomial
└── Time: ~1-2 сек

Stage 5: Finalization — CPU/FPGA
├── Pairing check
├── Proof serialization
└── Time: ~500 ms

Total: ~5-10 сек
```

### 3.2 FPGA Resource Allocation

| Stage | Логика | DSP | BRAM | Примечание |
|-------|--------|-----|------|------------|
| NTT Butterfly | 30% | 20% | 40% | Parallel radix-2/4 |
| MSM Pippenger | 40% | 50% | 30% | Bucket method |
| Field Arithmetic | 20% | 25% | 20% | Barrett reduction |
| Control/PCIe | 10% | 5% | 10% | DMA, registers |

---

## 4. Implementation

### 4.1 Project Structure

```
prover/
├── fpga/
│   ├── hdl/
│   │   ├── top/
│   │   │   └── cl_total_plonk.sv          # AWS F1 top level
│   │   ├── ntt/
│   │   │   ├── ntt_butterfly.sv           # Radix-2 butterfly
│   │   │   ├── ntt_core.sv                # NTT engine
│   │   │   └── twiddle_rom.sv             # Twiddle factors
│   │   ├── msm/
│   │   │   ├── msm_pippenger.sv           # MSM top level
│   │   │   ├── bucket_accumulator.sv      # Bucket accumulation
│   │   │   └── ec_point_add.sv            # Elliptic curve addition
│   │   ├── field/
│   │   │   ├── fp_mul.sv                  # Field multiplication (Barrett)
│   │   │   ├── fp_add.sv                  # Field addition
│   │   │   └── fp_reduce.sv               # Modular reduction
│   │   ├── common/
│   │   │   ├── axi_dma.sv                 # AXI DMA interface
│   │   │   ├── pcie_interface.sv          # PCIe x16
│   │   │   └── ddr4_controller.sv         # DDR4 interface
│   │   └── testbench/
│   │       └── tb_plonk_prover.sv         # Top-level testbench
│   │
│   ├── constraints/
│   │   └── cl_total_plonk.xdc             # Timing constraints
│   │
│   ├── scripts/
│   │   ├── build_afi.sh                   # Build AFI
│   │   ├── synthesize.sh                  # Vivado synthesis
│   │   └── program_fpga.sh                # Load AFI to F1
│   │
│   └── software/
│       ├── runtime/
│       │   ├── total_prover.cpp           # Host application
│       │   ├── dma_transfer.cpp           # DMA management
│       │   └── fpga_driver.hpp            # FPGA driver
│       └── test/
│           └── test_msm.cpp               # Unit tests
│
├── circuits/
│   └── plonk/
│       ├── circuit.rs                     # Circuit definition
│       ├── witness.rs                     # Witness generation
│       ├── prover.rs                      # Proof generation (CPU fallback)
│       └── verifier.rs                    # Verification
│
└── Cargo.toml                             # Rust workspace
```

### 4.2 Core Modules

#### NTT Butterfly (SystemVerilog)

```systemverilog
// ntt_butterfly.sv
// Radix-2 butterfly for BLS12-381 scalar field (381-bit)

module ntt_butterfly #(
    parameter WIDTH = 381,           // BLS12-381 scalar field
    parameter MODULUS = 381'b00...  // r = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  a,      // Input A
    input  wire [WIDTH-1:0]  b,      // Input B
    input  wire [WIDTH-1:0]  w,      // Twiddle factor
    output reg  [WIDTH-1:0]  a_out,  // A + B * W
    output reg  [WIDTH-1:0]  b_out,  // A - B * W
    output reg               valid
);

    // Pipeline stages for 381-bit arithmetic
    // Stage 1: B * W (Karatsuba multiplication)
    wire [WIDTH*2-1:0] bw_product;
    fp_mul #(.WIDTH(WIDTH)) mul_b_w (
        .clk(clk),
        .a(b),
        .b(w),
        .product(bw_product)
    );

    // Stage 2: Modular reduction (Barrett)
    wire [WIDTH-1:0] bw_reduced;
    fp_reduce #(.WIDTH(WIDTH), .MODULUS(MODULUS)) reduce_bw (
        .clk(clk),
        .in(bw_product),
        .out(bw_reduced)
    );

    // Stage 3: A + bw_reduced, A - bw_reduced
    always @(posedge clk) begin
        if (!rst_n) begin
            valid <= 1'b0;
        end else begin
            a_out <= fp_add(a, bw_reduced, MODULUS);
            b_out <= fp_sub(a, bw_reduced, MODULUS);
            valid <= 1'b1;
        end
    end

endmodule
```

#### MSM Pippenger (SystemVerilog)

```systemverilog
// msm_pippenger.sv
// Pippenger algorithm for multi-scalar multiplication
// Target: 1024 scalars × 1024 points

module msm_pippenger #(
    parameter SCALAR_WIDTH = 253,     // BLS12-381 scalar
    parameter POINT_WIDTH = 381*2,    // G1 affine (x, y)
    parameter NUM_SCALARS = 1024,
    parameter WINDOW_BITS = 8         // 8-bit windows
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [SCALAR_WIDTH-1:0] scalars [0:NUM_SCALARS-1],
    input  wire [POINT_WIDTH-1:0]  points  [0:NUM_SCALARS-1],
    output reg  [POINT_WIDTH-1:0]  result,
    output reg                     done
);

    localparam NUM_WINDOWS = (SCALAR_WIDTH + WINDOW_BITS - 1) / WINDOW_BITS;
    localparam BUCKET_SIZE = (1 << WINDOW_BITS) - 1;  // 255 buckets per window

    // State machine
    typedef enum {IDLE, BUCKET_SORT, BUCKET_SUM, WINDOW_ACCUM, DONE} state_t;
    state_t state;

    // Bucket memory (distributed across BRAM)
    reg [POINT_WIDTH-1:0] buckets [0:NUM_WINDOWS-1][0:BUCKET_SIZE-1];
    reg [POINT_WIDTH-1:0] window_sums [0:NUM_WINDOWS-1];

    // EC point adder instance
    wire [POINT_WIDTH/2-1:0] add_x, add_y;
    wire add_done;
    ec_point_add point_adder (
        .clk(clk),
        .p1_x(buckets[window_idx][bucket_idx]),
        .p1_y(buckets[window_idx][bucket_idx]),
        .p2_x(points[scalar_idx]),
        .p2_y(points[scalar_idx]),
        .p3_x(add_x),
        .p3_y(add_y),
        .done(add_done)
    );

    // Main state machine
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= BUCKET_SORT;
                        scalar_idx <= 0;
                    end
                end

                BUCKET_SORT: begin
                    // Sort points into buckets by scalar windows
                    for (int w = 0; w < NUM_WINDOWS; w++) begin
                        int bucket_idx = (scalars[scalar_idx] >> (w * WINDOW_BITS)) & (BUCKET_SIZE);
                        if (bucket_idx != 0) begin
                            // Trigger point addition
                            buckets[w][bucket_idx-1] <= ec_add(buckets[w][bucket_idx-1], points[scalar_idx]);
                        end
                    end

                    scalar_idx <= scalar_idx + 1;
                    if (scalar_idx >= NUM_SCALARS - 1) begin
                        state <= BUCKET_SUM;
                    end
                end

                BUCKET_SUM: begin
                    // Sum buckets within each window
                    for (int w = 0; w < NUM_WINDOWS; w++) begin
                        window_sums[w] <= buckets[w][BUCKET_SIZE-1];
                        for (int b = BUCKET_SIZE-2; b >= 0; b--) begin
                            window_sums[w] <= ec_add(window_sums[w], buckets[w][b]);
                        end
                    end
                    state <= WINDOW_ACCUM;
                end

                WINDOW_ACCUM: begin
                    // Final accumulation: result = Σ window_sum[i] * 2^(i*WINDOW_BITS)
                    result <= window_sums[NUM_WINDOWS-1];
                    for (int w = NUM_WINDOWS-2; w >= 0; w--) begin
                        // Double result WINDOW_BITS times
                        for (int i = 0; i < WINDOW_BITS; i++) begin
                            result <= ec_double(result);
                        end
                        result <= ec_add(result, window_sums[w]);
                    end
                    state <= DONE;
                end

                DONE: begin
                    done <= 1'b1;
                    if (!start) state <= IDLE;
                end
            endcase
        end
    end

endmodule
```

#### Field Multiplication with Barrett Reduction

```systemverilog
// fp_mul.sv
// 381-bit field multiplication using Karatsuba + Barrett reduction

module fp_mul #(
    parameter WIDTH = 381
)(
    input  wire              clk,
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    output reg  [WIDTH*2-1:0] product
);

    // Karatsuba multiplication
    // a * b = a_hi*b_hi * 2^(2n) + ((a_hi+a_lo)*(b_hi+b_lo) - a_hi*b_hi - a_lo*b_lo) * 2^n + a_lo*b_lo

    localparam HALF = WIDTH / 2;

    wire [HALF-1:0] a_lo = a[HALF-1:0];
    wire [HALF-1:0] a_hi = a[WIDTH-1:HALF];
    wire [HALF-1:0] b_lo = b[HALF-1:0];
    wire [HALF-1:0] b_hi = b[WIDTH-1:HALF];

    reg [WIDTH-1:0] z0, z1, z2;

    always @(posedge clk) begin
        z0 <= a_lo * b_lo;                    // a_lo * b_lo
        z2 <= a_hi * b_hi;                    // a_hi * b_hi
        z1 <= (a_lo + a_hi) * (b_lo + b_hi);  // (a_lo + a_hi) * (b_lo + b_hi)
    end

    always @(posedge clk) begin
        product <= (z2 << (2*HALF)) + ((z1 - z2 - z0) << HALF) + z0;
    end

endmodule
```

### 4.3 Host Software (C++)

```cpp
// total_prover.cpp
// Host application for AWS F1 PLONK prover

#include <iostream>
#include <vector>
#include <chrono>
#include "fpga_driver.hpp"

// BLS12-381 parameters
constexpr size_t SCALAR_WIDTH = 253;
constexpr size_t POINT_WIDTH = 381 * 2;  // G1 affine
constexpr size_t MAX_BATCH_SIZE = 1024;

class TOTALProver {
public:
    TOTALProver() : fpga_(0) {}  // FPGA slot 0

    bool init() {
        // Load AFI
        if (!fpga_.loadAfi("afi-0abcdef1234567890")) {
            std::cerr << "Failed to load AFI" << std::endl;
            return false;
        }

        // Allocate DMA buffers
        dma_buffer_ = fpga_.allocateDmaBuffer(MAX_BATCH_SIZE * POINT_WIDTH / 8);
        if (!dma_buffer_) {
            std::cerr << "Failed to allocate DMA buffer" << std::endl;
            return false;
        }

        std::cout << "FPGA initialized successfully" << std::endl;
        return true;
    }

    // Generate PLONK proof for a batch of transactions
    bool prove(const std::vector<Transaction>& txs, Proof& proof) {
        auto start = std::chrono::high_resolution_clock::now();

        // 1. Generate witness (CPU)
        Witness witness;
        generateWitness(txs, witness);

        // 2. Transfer witness to FPGA via DMA
        fpga_.writeDma(dma_buffer_, witness.data(), witness.size());

        // 3. Start proof generation
        fpga_.writeRegister(0x00, 1);  // Start command

        // 4. Poll for completion
        while (fpga_.readRegister(0x04) == 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }

        // 5. Read proof from FPGA
        fpga_.readDma(proof.data(), proof.size(), dma_buffer_);

        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

        std::cout << "Proof generated in " << duration.count() << " ms" << std::endl;
        return true;
    }

    // Batch proof generation for higher throughput
    bool proveBatch(const std::vector<std::vector<Transaction>>& batches,
                    std::vector<Proof>& proofs) {
        proofs.reserve(batches.size());

        for (const auto& batch : batches) {
            Proof proof;
            if (!prove(batch, proof)) {
                return false;
            }
            proofs.push_back(proof);
        }

        return true;
    }

    ~TOTALProver() {
        if (dma_buffer_) {
            fpga_.freeDmaBuffer(dma_buffer_);
        }
    }

private:
    FPGADriver fpga_;
    void* dma_buffer_ = nullptr;
};

// Main entry point
int main(int argc, char** argv) {
    TOTALProver prover;

    if (!prover.init()) {
        return 1;
    }

    // Test: generate proof for sample transaction
    std::vector<Transaction> txs = {
        {0x1234, 0x5678, 1000},  // from, to, amount
    };

    Proof proof;
    if (prover.prove(txs, proof)) {
        std::cout << "Proof verification: " << (verifyProof(proof) ? "VALID" : "INVALID") << std::endl;
    }

    return 0;
}
```

---

## 5. Build & Deployment

### 5.1 Build AFI

```bash
#!/bin/bash
# build_afi.sh

set -e

# Configuration
DESIGN_NAME="total_plonk_prover"
BUCKET="s3://total-lean-pilot-afis"
REGION="us-east-1"

# Step 1: Synthesis
echo "[1/5] Synthesizing design..."
vivado -mode batch -source scripts/synthesize.tcl

# Step 2: Implementation (place & route)
echo "[2/5] Running implementation..."
vivado -mode batch -source scripts/implement.tcl

# Step 3: Generate bitstream
echo "[3/5] Generating bitstream..."
vivado -mode batch -source scripts/generate_bitstream.tcl

# Step 4: Create tar for AWS
echo "[4/5] Creating AFI tar..."
mkdir -p to_aws
cp ${DESIGN_NAME}.bit to_aws/
cp ${DESIGN_NAME}.hdf to_aws/
tar cvzf ${DESIGN_NAME}.tar.gz to_aws/

# Step 5: Upload to S3 and create AFI
echo "[5/5] Creating AFI..."
aws s3 cp ${DESIGN_NAME}.tar.gz ${BUCKET}/

AFI_ID=$(aws ec2 create-fpga-image \
    --input-storage-location Bucket=${BUCKET},Key=${DESIGN_NAME}.tar.gz \
    --logs-storage-location Bucket=${BUCKET},Key=logs/ \
    --name "total-lean-pilot-${DESIGN_NAME}" \
    --description "TOTAL Lean Pilot PLONK Prover" \
    --region ${REGION} \
    --query 'FpgaImageId' \
    --output text)

echo "AFI created: ${AFI_ID}"
echo "AGFI: $(aws ec2 describe-fpga-images --fpga-image-ids ${AFI_ID} --query 'FpgaImages[0].FpgaImageGlobalId' --output text)"
```

### 5.2 Deploy on F1

```bash
#!/bin/bash
# deploy_f1.sh

INSTANCE_ID="i-0123456789abcdef0"
AFI_ID="afi-0abcdef1234567890"
AGFI_ID="agfi-0abcdef1234567890"

# Launch F1 instance
echo "Launching F1 instance..."
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type f1.2xlarge \
    --key-name total-pilot-key \
    --security-group-ids sg-0123456789abcdef0 \
    --subnet-id subnet-0123456789abcdef0

# Wait for instance
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}

# SSH and load AFI
echo "Loading AFI..."
ssh -i total-pilot-key.pem ec2-user@${INSTANCE_IP} << 'EOF'
    sudo fpga-load-local-image -S 0 -I agfi-0abcdef1234567890
    sudo fpga-describe-local-image -S 0 -H
EOF

# Test
echo "Testing prover..."
ssh -i total-pilot-key.pem ec2-user@${INSTANCE_IP} << 'EOF'
    cd /home/ec2-user/total-prover
    ./test_afi
    ./total_prover --benchmark
EOF
```

### 5.3 Makefile Integration

```makefile
# prover/Makefile

.PHONY: all build simulate test clean afi deploy

# Variables
VIVADO := vivado
XVLOG := xvlog
XELAB := xelab
XSIM := xsim

# Directories
SRC_DIR := fpga/hdl
TB_DIR := fpga/testbench
BUILD_DIR := build
SIM_DIR := sim

# Source files
SV_SOURCES := $(wildcard $(SRC_DIR)/**/*.sv)
TB_SOURCES := $(wildcard $(TB_DIR)/*.sv)

# Targets
all: build

# Synthesis
build:
	mkdir -p $(BUILD_DIR)
	$(VIVADO) -mode batch -source scripts/synthesize.tcl

# Simulation
simulate: $(SV_SOURCES) $(TB_SOURCES)
	mkdir -p $(SIM_DIR)
	$(XVLOG) -sv $(SV_SOURCES) $(TB_SOURCES)
	$(XELAB) -top tb_plonk_prover -snapshot plonk_snap
	$(XSIM) plonk_snap -runall

# Test
 test:
	cd software/test && make test

# Create AFI
afi:
	./scripts/build_afi.sh

# Deploy to F1
deploy:
	./scripts/deploy_f1.sh

# Clean
clean:
	rm -rf $(BUILD_DIR) $(SIM_DIR)
	rm -f *.log *.jou *.str
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

| Модуль | Тест | Метод | Критерий |
|--------|------|-------|----------|
| fp_mul | 381×381 bit mult | Simulation | Результат = expected |
| fp_reduce | Barrett reduction | Simulation | a * b mod p = expected |
| ntt_butterfly | Radix-2 butterfly | Simulation | DFT property holds |
| ec_point_add | G1 addition | Simulation | Group axioms |
| msm_pippenger | 1024-point MSM | Simulation | Результат = reference |

### 6.2 Integration Tests

| Тест | Описание | Критерий |
|------|----------|----------|
| Full PLONK proof | End-to-end proof generation | Proof verifies |
| Batch 100 txs | 100 transactions in batch | < 1000 сек total |
| Stress test | 1000 consecutive proofs | No memory leaks |
| DMA throughput | Host ↔ FPGA transfer | > 10 GB/s |

### 6.3 Benchmarks

```bash
# Run benchmarks
./total_prover --benchmark

# Expected output:
# ========================================
# TOTAL Lean Pilot — Prover Benchmark
# ========================================
# FPGA: AWS F1 f1.2xlarge (VU9P)
# AFI: total-plonk-prover-v1.0
#
# Single transaction proof:
#   Time: 7.2 seconds
#   Cost: $0.0033 ($1.65/hour ÷ 1800 proofs/hour)
#
# Batch of 100 transactions:
#   Time: 720 seconds
#   Throughput: 8.3 tx/min
#   Cost per tx: $0.0033
#
# Comparison:
#   CPU (single core): 45 seconds (6.25× slower)
#   GPU (A100): 2.1 seconds (3.4× faster, but $3/hour)
# ========================================
```

---

## 7. Cost Analysis

### 7.1 AWS F1 Costs (Pilot)

| Режим | Инстанс | Часы/мес | Стоимость |
|-------|---------|----------|-----------|
| Dev/Test | f1.2xlarge | 40 | $66 |
| Continuous | f1.2xlarge | 720 | $1,188 |
| Batch (nightly) | f1.2xlarge | 240 | $396 |
| **Рекомендуемый** | **f1.2xlarge** | **~200** | **~$330** |

### 7.2 Cost per Transaction

```
f1.2xlarge: $1.65/hour = $0.0275/minute

Single proof: 7 seconds = $0.0032
Batch (100): 720 seconds = $0.0032 each

At $0.01/tx fee:
  Revenue per tx: $0.01
  Proof cost:     $0.0032
  Margin:         68%

At scale (f1.16xlarge, 8 FPGAs):
  Throughput: 8× = 66 tx/min
  Cost per tx: $0.0004
  Margin: 96%
```

---

## 8. Risk Mitigation

| Риск | Митигация |
|------|-----------|
| AFI build failure | Local simulation before AWS build |
| FPGA timing violation | Conservative constraints, multi-corner |
| DMA bottleneck | Double buffering, async transfers |
| Power throttling | Monitor FPGA temperature |
| AWS F1 discontinued | RTL portable to Alveo/Versal |
| Proof incorrect | Reference implementation comparison |

---

## 9. Timeline

| Неделя | Задача | Доставка |
|--------|--------|----------|
| W1 | Environment setup | FPGA Developer AMI, Vivado |
| W2 | Core modules | fp_mul, fp_reduce, ec_point_add |
| W3 | NTT engine | ntt_butterfly, ntt_core |
| W4 | MSM engine | msm_pippenger, bucket_accumulator |
| W5 | Integration | Top level, DMA, PCIe |
| W6 | Simulation | All modules verified |
| W7 | AFI build | Create and test AFI |
| W8 | Host software | total_prover.cpp, benchmarks |

---

## 10. References

- [Zcash Foundation FPGA](https://github.com/ZcashFoundation/zcash-fpga) — BLS12-381, MSM, Pairing
- [AWS F1 Developer Guide](https://github.com/aws/aws-fpga) — HDK, SDK, AFI
- [Ingonyama FPGA ZKP](https://www.ingonyama.com/post/hardware-review-gpus-fpgas-and-zero-knowledge-proofs) — MSM optimization
- [PLONK Paper](https://eprint.iacr.org/2019/953) — Original PLONK protocol
- [Barrett Reduction](https://en.wikipedia.org/wiki/Barrett_reduction) — Modular multiplication

---

*Document version: 1.0*  
*Last updated: 2026-07-19*  
*Next review: 2026-08-02*
"""

# Сохраняем
base_path = '/mnt/agents/output/Total-Lean-Pilot'
prover_path = f'{base_path}/docs/PHASE2_PROVER.md'

import os
os.makedirs(os.path.dirname(prover_path), exist_ok=True)

with open(prover_path, 'w', encoding='utf-8') as f:
    f.write(prover_tz)

print(f"Phase 2 Prover spec saved: {prover_path}")
print(f"Size: {len(prover_tz)} chars")
