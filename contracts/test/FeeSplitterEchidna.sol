// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../src/FeeSplitter.sol";

/**
 * @title FeeSplitterEchidna
 * @notice Property-based fuzzing target for FeeSplitter
 */
contract FeeSplitterEchidna is FeeSplitter {
    
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalClaimed;
    
    constructor() FeeSplitter(
        _setupRecipients(),
        _setupWeights(),
        address(0x10000),  // distributor
        address(0x30000)   // admin
    ) {}
    
    function _setupRecipients() internal pure returns (address[] memory) {
        address[] memory r = new address[](3);
        r[0] = address(0x10001);
        r[1] = address(0x10002);
        r[2] = address(0x10003);
        return r;
    }
    
    function _setupWeights() internal pure returns (uint256[] memory) {
        uint256[] memory w = new uint256[](3);
        w[0] = 5000;  // 50%
        w[1] = 3000;  // 30%
        w[2] = 2000;  // 20%
        return w;
    }
    
    // PROPERTY: Сумма pending == баланс контракта
    function echidna_pending_sum_eq_balance() public view returns (bool) {
        uint256 totalPending = 0;
        address[] memory recs = getRecipients();
        for (uint i = 0; i < recs.length; i++) {
            totalPending += pendingRewards[recs[i]];
        }
        return totalPending == address(this).balance;
    }
    
    // PROPERTY: totalClaimed только растёт
    function echidna_claimed_monotonic() public view returns (bool) {
        return ghost_totalClaimed <= totalDistributed;
    }
    
    // PROPERTY: Weights всегда 100%
    function echidna_weights_sum_100() public view returns (bool) {
        uint256 totalWeight = 0;
        address[] memory recs = getRecipients();
        for (uint i = 0; i < recs.length; i++) {
            totalWeight += weights[recs[i]];
        }
        return totalWeight == BASIS_POINTS;
    }
    
    // WRAPPER: deposit с ghost var
    function deposit() public payable {
        ghost_totalDeposited += msg.value;
    }
    
    // WRAPPER: distribute от имени distributor
    function distributeWrapper() public {
        vm.prank(address(0x10000));
        distribute();
    }
    
    // WRAPPER: claim с отслеживанием
    function claimWrapper(uint8 recipientIdx) public {
        address[] memory recs = getRecipients();
        require(recipientIdx < recs.length, "Invalid index");
        
        uint256 beforeClaim = totalClaimed[recs[recipientIdx]];
        vm.prank(recs[recipientIdx]);
        claim();
        uint256 afterClaim = totalClaimed[recs[recipientIdx]];
        ghost_totalClaimed += (afterClaim - beforeClaim);
    }
    
    address internal constant VM_ADDRESS = address(710970926830142000036062260230027005165362933471);
    Vm internal constant vm = Vm(VM_ADDRESS);
}

interface Vm {
    function prank(address) external;
}
