
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/HackerHoneypot.sol";

/**
 * @title DeployHoneypot
 * @notice Deploy honeypot with initial prize pool
 * @dev Usage:
 *   forge script script/DeployHoneypot.s.sol --rpc-url $RPC_URL --broadcast --value 1ether
 */
contract DeployHoneypot is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeSplitter = vm.envAddress("FEE_SPLITTER_ADDRESS");

        // Initial prize pool from --value flag
        uint256 prizePool = msg.value;

        require(feeSplitter != address(0), "FEE_SPLITTER_ADDRESS not set");

        vm.startBroadcast(deployerPrivateKey);

        TOTALPilotHoneypot honeypot = new TOTALPilotHoneypot{value: prizePool}(feeSplitter);

        console.log("Honeypot deployed at:", address(honeypot));
        console.log("Prize pool:", prizePool);
        console.log("FeeSplitter:", feeSplitter);
        console.log("Attempt fee:", honeypot.ATTEMPT_FEE());

        vm.stopBroadcast();
    }
}
