// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../src/FeeSplitter.sol";

contract DeployFeeSplitter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Адреса для пилота (замени на реальные!)
        address prover = vm.envAddress("PROVER_ADDRESS");      // 35%
        address validator = vm.envAddress("VALIDATOR_ADDRESS"); // 25%
        address treasury = vm.envAddress("TREASURY_ADDRESS");   // 20%
        address da = vm.envAddress("DA_ADDRESS");               // 15%
        address burn = vm.envAddress("BURN_ADDRESS");           // 5%
        
        address admin = vm.envAddress("ADMIN_ADDRESS");
        // Distributor = execution layer (Geth fork)
        address distributor = vm.envAddress("DISTRIBUTOR_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        address[] memory recipients = new address[](5);
        recipients[0] = prover;
        recipients[1] = validator;
        recipients[2] = treasury;
        recipients[3] = da;
        recipients[4] = burn;
        
        uint256[] memory weights = new uint256[](5);
        weights[0] = 3500;  // 35.00%
        weights[1] = 2500;  // 25.00%
        weights[2] = 2000;  // 20.00%
        weights[3] = 1500;  // 15.00%
        weights[4] = 500;   // 5.00%
        
        FeeSplitter splitter = new FeeSplitter(
            recipients,
            weights,
            distributor,
            admin
        );
        
        console.log("FeeSplitter deployed at:", address(splitter));
        
        vm.stopBroadcast();
    }
}
