// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/FeeSplitter.sol";

contract FeeSplitterTest is Test {
    FeeSplitter splitter;
    
    address admin = address(1);
    address distributor = address(2);
    address prover = address(3);
    address validator = address(4);
    address treasury = address(5);
    address da = address(6);
    address burn = address(7);
    
    address[] recipients;
    uint256[] weights;
    
    function setUp() public {
        recipients = new address[](5);
        recipients[0] = prover;
        recipients[1] = validator;
        recipients[2] = treasury;
        recipients[3] = da;
        recipients[4] = burn;
        
        weights = new uint256[](5);
        weights[0] = 3500;
        weights[1] = 2500;
        weights[2] = 2000;
        weights[3] = 1500;
        weights[4] = 500;
        
        splitter = new FeeSplitter(recipients, weights, distributor, admin);
    }
    
    // ============ БАЗОВЫЕ ТЕСТЫ ============
    
    function test_Deploy() public {
        assertEq(splitter.getPendingReward(prover), 0);
        assertTrue(splitter.hasRole(splitter.ADMIN_ROLE(), admin));
        assertTrue(splitter.hasRole(splitter.DISTRIBUTOR_ROLE(), distributor));
    }
    
    function test_Distribute() public {
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(distributor);
        splitter.distribute();
        
        assertEq(splitter.getPendingReward(prover), 0.35 ether);
        assertEq(splitter.getPendingReward(validator), 0.25 ether);
        assertEq(splitter.getPendingReward(treasury), 0.20 ether);
        assertEq(splitter.getPendingReward(da), 0.15 ether);
        assertEq(splitter.getPendingReward(burn), 0.05 ether);
    }
    
    function test_Claim() public {
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(distributor);
        splitter.distribute();
        
        uint256 balanceBefore = prover.balance;
        
        vm.prank(prover);
        splitter.claim();
        
        assertEq(prover.balance - balanceBefore, 0.35 ether);
        assertEq(splitter.getPendingReward(prover), 0);
    }
    
    // ============ SECURITY ТЕСТЫ ============
    
    function test_RevertIf_NotDistributor() public {
        vm.expectRevert();
        splitter.distribute();
    }
    
    function test_RevertIf_DistributeTooSoon() public {
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(distributor);
        splitter.distribute();
        
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(distributor);
        vm.expectRevert("Too soon");
        splitter.distribute();
    }
    
    function test_RevertIf_NothingToClaim() public {
        vm.prank(prover);
        vm.expectRevert("Nothing to claim");
        splitter.claim();
    }
    
    function test_PullPattern_NoAutoTransfer() public {
        vm.deal(address(splitter), 1 ether);
        
        uint256 balanceBefore = prover.balance;
        
        vm.prank(distributor);
        splitter.distribute();
        
        assertEq(prover.balance, balanceBefore);
    }
    
    function test_TimelockOnWeightChange() public {
        address[] memory newRecipients = new address[](1);
        newRecipients[0] = address(999);
        
        uint256[] memory newWeights = new uint256[](1);
        newWeights[0] = 10000;
        
        vm.prank(admin);
        vm.expectRevert("Timelock active");
        splitter.updateRecipients(newRecipients, newWeights);
    }
    
    function test_WeightsMustSumTo100() public {
        vm.warp(block.timestamp + 15 days);
        
        address[] memory newRecipients = new address[](2);
        newRecipients[0] = address(998);
        newRecipients[1] = address(999);
        
        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 5000;
        newWeights[1] = 4000; // Сумма 9000, не 10000
        
        vm.prank(admin);
        vm.expectRevert("Must sum to 100%");
        splitter.updateRecipients(newRecipients, newWeights);
    }
    
    function test_MaxRecipients() public {
        vm.warp(block.timestamp + 15 days);
        
        address[] memory tooMany = new address[](51);
        uint256[] memory w = new uint256[](51);
        
        vm.prank(admin);
        vm.expectRevert("Too many");
        splitter.updateRecipients(tooMany, w);
    }
    
    function test_EmergencyWithdraw() public {
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(admin);
        splitter.pause();
        
        uint256 balanceBefore = admin.balance;
        
        vm.prank(admin);
        splitter.emergencyWithdraw(admin);
        
        assertEq(admin.balance - balanceBefore, 1 ether);
    }
    
    function test_RevertIf_EmergencyWhenNotPaused() public {
        vm.prank(admin);
        vm.expectRevert();
        splitter.emergencyWithdraw(admin);
    }
    
    // ============ REENTRANCY ТЕСТ (контракт-атакер) ============
    
    function test_ReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(splitter));
        
        // Меняем recipients чтобы attacker был в списке
        vm.warp(block.timestamp + 15 days);
        
        address[] memory newRecipients = new address[](1);
        newRecipients[0] = address(attacker);
        
        uint256[] memory newWeights = new uint256[](1);
        newWeights[0] = 10000;
        
        vm.prank(admin);
        splitter.updateRecipients(newRecipients, newWeights);
        
        vm.deal(address(splitter), 1 ether);
        
        vm.prank(distributor);
        splitter.distribute();
        
        vm.expectRevert("ReentrancyGuard: reentrant call");
        attacker.attack();
    }
    
    // ============ DUST ТЕСТ ============
    
    function test_DustHandling() public {
        vm.deal(address(splitter), 1 wei);
        
        vm.prank(distributor);
        splitter.distribute();
        
        // Последний recipient (burn) получает остаток
        assertEq(splitter.getPendingReward(burn), 1);
    }
}

// Контракт-атакер для теста reentrancy
contract ReentrancyAttacker {
    FeeSplitter public splitter;
    uint256 public attackCount;
    
    constructor(address _splitter) {
        splitter = FeeSplitter(_splitter);
    }
    
    function attack() external {
        splitter.claim();
    }
    
    receive() external payable {
        if (attackCount < 5) {
            attackCount++;
            splitter.claim(); // Попытка reentrancy
        }
    }
}
