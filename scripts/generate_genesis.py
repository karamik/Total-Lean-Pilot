

genesis_generator = r'''#!/usr/bin/env python3
"""
TOTAL Lean Pilot - Genesis Generator
Creates genesis.json for 3-node PoA devnet with preset validators,
Fee Splitter contract and initial balances.

Usage:
    python3 scripts/generate_genesis.py --output genesis.json --chain-id 888888
    
Options:
    --validators    Number of validators (default: 3)
    --balance       Initial validator balance in ETH (default: 1000)
    --output        Output file path (default: genesis.json)
    --chain-id      Chain ID (default: 888888)
"""

import json
import argparse
import os
from datetime import datetime, timezone
from typing import Dict, List, Any

# Lean Pilot constants
DEFAULT_CHAIN_ID = 888888
DEFAULT_PERIOD = 6           # 6 seconds between blocks
DEFAULT_EPOCH = 100          # 100 blocks per epoch
DEFAULT_GAS_LIMIT = 30_000_000
DEFAULT_BALANCE_ETH = 1000   # ETH per validator

# Preset validator addresses (for reproducibility)
# In production replace with real keys
PRESET_SIGNERS = [
    {
        "name": "validator-1",
        "address": "0xSigner111111111111111111111111111111111111",
        "private_key": "0x1111111111111111111111111111111111111111111111111111111111111111"
    },
    {
        "name": "validator-2", 
        "address": "0xSigner222222222222222222222222222222222222",
        "private_key": "0x2222222222222222222222222222222222222222222222222222222222222222"
    },
    {
        "name": "validator-3",
        "address": "0xSigner333333333333333333333333333333333333",
        "private_key": "0x3333333333333333333333333333333333333333333333333333333333333333"
    }
]

# Fee Splitter address (hardcoded from spec)
FEE_SPLITTER_ADDRESS = "0x00000000000000000000000000000000FEE55917"


def generate_extra_data(signers: List[str]) -> str:
    """
    Generates ExtraData for Clique consensus.
    
    Clique ExtraData format:
    - 32 bytes: vanity (can use for chain name)
    - N x 20 bytes: validator addresses
    - 65 bytes: seal (signature, filled during mining)
    
    Args:
        signers: List of validator addresses (hex strings)
        
    Returns:
        Hex string extra data
    """
    # 32 bytes vanity - "TOTAL" + padding
    vanity = b"TOTAL-LEAN-PILOT" + b'\x00' * 16
    
    # Collect validator addresses
    signer_bytes = b''
    for signer in signers:
        # Remove '0x' prefix if present
        addr = signer.replace('0x', '')
        signer_bytes += bytes.fromhex(addr)
    
    # 65 bytes seal placeholder
    seal = b'\x00' * 65
    
    extra_data = vanity + signer_bytes + seal
    return '0x' + extra_data.hex()


def generate_alloc(validators: List[Dict], balance_wei: str) -> Dict[str, Any]:
    """
    Generates alloc section for genesis.
    
    Args:
        validators: List of validators with addresses
        balance_wei: Balance in wei as hex string
        
    Returns:
        Alloc dictionary for genesis
    """
    alloc = {}
    
    # Validators
    for validator in validators:
        addr = validator["address"].lower()
        alloc[addr] = {
            "balance": balance_wei,
            # Empty code - EOA (Externally Owned Account)
        }
    
    # Fee Splitter contract (predeployed, but no bytecode until deployment)
    alloc[FEE_SPLITTER_ADDRESS.lower()] = {
        "balance": "0x0",
        "code": "0x",  # Empty until deployment
    }
    
    # Pre-funded accounts for testing (faucet)
    faucet_accounts = [
        "0xFaucet111111111111111111111111111111111111",
        "0xFaucet222222222222222222222222222222222222",
        "0xFaucet333333333333333333333333333333333333",
    ]
    for faucet in faucet_accounts:
        alloc[faucet.lower()] = {
            "balance": hex(100 * 10**18)  # 100 ETH for tests
        }
    
    return alloc


def generate_genesis(
    chain_id: int,
    validators: List[Dict],
    period: int,
    epoch: int,
    gas_limit: int,
    balance_eth: int
) -> Dict[str, Any]:
    """
    Generates full genesis.json for Lean Pilot.
    
    Args:
        chain_id: Network ID
        validators: List of validators
        period: Block interval (sec)
        epoch: Epoch length (blocks)
        gas_limit: Block gas limit
        balance_eth: Initial validator balance (ETH)
        
    Returns:
        Genesis configuration dictionary
    """
    # Balance in wei
    balance_wei = hex(balance_eth * 10**18)
    
    # Validator addresses list
    signer_addresses = [v["address"] for v in validators]
    
    # Extra data for Clique
    extra_data = generate_extra_data(signer_addresses)
    
    # Alloc
    alloc = generate_alloc(validators, balance_wei)
    
    genesis = {
        "config": {
            "chainId": chain_id,
            "homesteadBlock": 0,
            "eip150Block": 0,
            "eip155Block": 0,
            "eip158Block": 0,
            "byzantiumBlock": 0,
            "constantinopleBlock": 0,
            "petersburgBlock": 0,
            "istanbulBlock": 0,
            "berlinBlock": 0,
            "londonBlock": 0,
            "clique": {
                "period": period,
                "epoch": epoch
            }
        },
        "nonce": "0x0",
        "timestamp": hex(int(datetime.now(timezone.utc).timestamp())),
        "extraData": extra_data,
        "gasLimit": hex(gas_limit),
        "difficulty": "0x1",
        "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "coinbase": "0x0000000000000000000000000000000000000000",
        "alloc": alloc,
        "number": "0x0",
        "gasUsed": "0x0",
        "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
        "baseFeePerGas": "0x0"
    }
    
    return genesis


def generate_validator_keys(validators: List[Dict], output_dir: str):
    """
    Generates key files for validators.
    
    Args:
        validators: List of validators
        output_dir: Directory to save keys
    """
    os.makedirs(output_dir, exist_ok=True)
    
    keys_info = []
    for validator in validators:
        key_file = os.path.join(output_dir, f"{validator['name']}.key")
        password_file = os.path.join(output_dir, f"{validator['name']}.password")
        
        # Save private key (in production use keystore!)
        with open(key_file, 'w') as f:
            f.write(validator["private_key"])
        
        # Empty password for devnet
        with open(password_file, 'w') as f:
            f.write("")
        
        keys_info.append({
            "name": validator["name"],
            "address": validator["address"],
            "key_file": key_file,
            "password_file": password_file
        })
    
    # Save metadata
    metadata_file = os.path.join(output_dir, "validators.json")
    with open(metadata_file, 'w') as f:
        json.dump(keys_info, f, indent=2)
    
    return keys_info


def validate_genesis(genesis: Dict) -> List[str]:
    """
    Validates genesis configuration.
    
    Args:
        genesis: Genesis dictionary
        
    Returns:
        List of errors (empty if OK)
    """
    errors = []
    
    # Check chainId
    if genesis["config"]["chainId"] != DEFAULT_CHAIN_ID:
        errors.append(f"Chain ID mismatch: expected {DEFAULT_CHAIN_ID}")
    
    # Check Clique config
    clique = genesis["config"].get("clique")
    if not clique:
        errors.append("Missing clique config")
    else:
        if clique.get("period") != DEFAULT_PERIOD:
            errors.append(f"Clique period mismatch: expected {DEFAULT_PERIOD}")
        if clique.get("epoch") != DEFAULT_EPOCH:
            errors.append(f"Clique epoch mismatch: expected {DEFAULT_EPOCH}")
    
    # Check extraData
    extra_data = genesis.get("extraData", "")
    if len(extra_data) < 162:
        errors.append("ExtraData too short for 3 validators")
    
    # Check alloc
    alloc = genesis.get("alloc", {})
    if len(alloc) < 3:
        errors.append("Too few accounts in alloc")
    
    # Check Fee Splitter
    if FEE_SPLITTER_ADDRESS.lower() not in alloc:
        errors.append(f"Fee Splitter address {FEE_SPLITTER_ADDRESS} not in alloc")
    
    # Check gasLimit
    gas_limit = int(genesis.get("gasLimit", "0x0"), 16)
    if gas_limit < 10_000_000:
        errors.append(f"Gas limit too low: {gas_limit}")
    
    return errors


def print_summary(genesis: Dict, validators: List[Dict]):
    """Prints genesis configuration summary."""
    print("=" * 60)
    print("TOTAL LEAN PILOT - GENESIS SUMMARY")
    print("=" * 60)
    print(f"Chain ID:        {genesis['config']['chainId']}")
    print(f"Timestamp:       {genesis['timestamp']}")
    print(f"Gas Limit:       {int(genesis['gasLimit'], 16):,}")
    print(f"Difficulty:      {genesis['difficulty']}")
    print(f"Clique Period:   {genesis['config']['clique']['period']} sec")
    print(f"Clique Epoch:    {genesis['config']['clique']['epoch']} blocks")
    print()
    print("Validators:")
    for i, v in enumerate(validators, 1):
        balance = genesis['alloc'].get(v['address'].lower(), {}).get('balance', '0x0')
        print(f"  {i}. {v['name']}: {v['address']} (balance: {int(balance, 16) / 10**18:.0f} ETH)")
    print()
    print(f"Fee Splitter:    {FEE_SPLITTER_ADDRESS}")
    print(f"Total Accounts:  {len(genesis['alloc'])}")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Generate genesis.json for TOTAL Lean Pilot devnet"
    )
    parser.add_argument(
        "--output", "-o",
        default="genesis.json",
        help="Output file path (default: genesis.json)"
    )
    parser.add_argument(
        "--chain-id",
        type=int,
        default=DEFAULT_CHAIN_ID,
        help=f"Chain ID (default: {DEFAULT_CHAIN_ID})"
    )
    parser.add_argument(
        "--validators",
        type=int,
        default=3,
        choices=[3, 5, 7],
        help="Number of validators (default: 3)"
    )
    parser.add_argument(
        "--balance",
        type=int,
        default=DEFAULT_BALANCE_ETH,
        help=f"Initial validator balance in ETH (default: {DEFAULT_BALANCE_ETH})"
    )
    parser.add_argument(
        "--keys-dir",
        default="validator_keys",
        help="Directory for validator key files (default: validator_keys)"
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate generated genesis"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Suppress output"
    )
    
    args = parser.parse_args()
    
    # Select needed number of validators
    validators = PRESET_SIGNERS[:args.validators]
    
    # Generate genesis
    genesis = generate_genesis(
        chain_id=args.chain_id,
        validators=validators,
        period=DEFAULT_PERIOD,
        epoch=DEFAULT_EPOCH,
        gas_limit=DEFAULT_GAS_LIMIT,
        balance_eth=args.balance
    )
    
    # Validation
    if args.validate:
        errors = validate_genesis(genesis)
        if errors:
            print("Validation errors:")
            for error in errors:
                print(f"  - {error}")
            return 1
        else:
            print("Genesis validation passed")
    
    # Save genesis.json
    with open(args.output, 'w') as f:
        json.dump(genesis, f, indent=2)
    
    # Generate validator keys
    keys_info = generate_validator_keys(validators, args.keys_dir)
    
    # Print summary
    if not args.quiet:
        print_summary(genesis, validators)
        print(f"\nGenesis saved to: {args.output}")
        print(f"Validator keys saved to: {args.keys_dir}/")
        print(f"\nNext steps:")
        print(f"  1. Initialize Geth: geth init --datadir node1 {args.output}")
        print(f"  2. Start validator: geth --datadir node1 --mine --unlock {validators[0]['address']}")
        print(f"  3. Deploy FeeSplitter: make deploy-feesplitter")
    
    return 0


if __name__ == "__main__":
    exit(main())
'''

# Сохраняем
base_path = '/mnt/agents/output/Total-Lean-Pilot'
script_path = f'{base_path}/scripts/generate_genesis.py'

import os
os.makedirs(os.path.dirname(script_path), exist_ok=True)

with open(script_path, 'w', encoding='utf-8') as f:
    f.write(genesis_generator)

# Делаем исполняемым
os.chmod(script_path, 0o755)

print(f"generate_genesis.py saved ({len(genesis_generator)} chars)")
print(f"Path: {script_path}")
