
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TOTALPilotFeeSplitter} from "../src/FeeSplitter.sol";

/**
 * @title DeployFeeSplitter
 * @notice Скрипт деплоя FeeSplitter для Lean Pilot
 * @dev Использование: forge script script/DeployFeeSplitter.s.sol --rpc-url <URL> --broadcast --private-key <KEY>
 */
contract DeployFeeSplitter is Script {

    // Адреса операторов инфраструктуры (заменить на реальные перед деплоем)
    address constant PROVER_OPERATOR = address(0x1000000000000000000000000000000000000001);
    address constant VALIDATOR_OPERATOR = address(0x2000000000000000000000000000000000000002);
    address constant TREASURY_MULTISIG = address(0x3000000000000000000000000000000000000003);
    address constant DA_LAYER_WALLET = address(0x4000000000000000000000000000000000000004);

    function run() public returns (TOTALPilotFeeSplitter splitter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        splitter = new TOTALPilotFeeSplitter(
            PROVER_OPERATOR,
            VALIDATOR_OPERATOR,
            TREASURY_MULTISIG,
            DA_LAYER_WALLET
        );

        vm.stopBroadcast();

        console.log("FeeSplitter deployed at:", address(splitter));
        console.log("Prover (35%):     ", PROVER_OPERATOR);
        console.log("Validator (25%): ", VALIDATOR_OPERATOR);
        console.log("Treasury (20%):  ", TREASURY_MULTISIG);
        console.log("DA Layer (15%):  ", DA_LAYER_WALLET);
        console.log("Burn (5%):       ", splitter.BURN_ADDRESS());

        return splitter;
    }

    /**
     * @notice Валидация развёрнутого контракта — проверка сплита
     */
    function validate(address splitterAddr) public payable {
        require(msg.value >= 0.01 ether, "Send at least 0.01 ETH for validation");

        TOTALPilotFeeSplitter splitter = TOTALPilotFeeSplitter(payable(splitterAddr));

        uint256 balanceBefore = splitter.accruedBalances(PROVER_OPERATOR);

        (bool success, ) = splitterAddr.call{value: msg.value}("");
        require(success, "Fee split failed");

        uint256 balanceAfter = splitter.accruedBalances(PROVER_OPERATOR);
        uint256 expected = (msg.value * 3500) / 10000;

        require(balanceAfter - balanceBefore == expected, "Prover share mismatch");

        console.log("Validation passed! Prover received:", expected);
    }
}
