// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract FeeSplitter is ReentrancyGuard, AccessControl, Pausable {
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_RECIPIENTS = 50;
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 6;
    uint256 public constant WEIGHT_CHANGE_DELAY = 14 days;
    
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    address[] public recipients;
    mapping(address => uint256) public weights;
    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public totalClaimed;
    
    uint256 public lastDistributionBlock;
    uint256 public lastWeightUpdate;
    uint256 public totalDistributed;
    
    event RewardAccrued(address indexed recipient, uint256 amount);
    event Claimed(address indexed recipient, uint256 amount);
    event RecipientsUpdated(address[] recipients, uint256[] weights);
    event EmergencyWithdrawal(address indexed to, uint256 amount);
    
    constructor(
        address[] memory _recipients,
        uint256[] memory _weights,
        address _distributor,
        address _admin
    ) {
        require(_recipients.length == _weights.length, "Length mismatch");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(_distributor != address(0) && _admin != address(0), "Zero address");
        
        uint256 totalWeight = 0;
        for (uint i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == BASIS_POINTS, "Weights must sum to 100%");
        
        recipients = _recipients;
        for (uint i = 0; i < _recipients.length; i++) {
            weights[_recipients[i]] = _weights[i];
        }
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _distributor);
        _grantRole(PAUSER_ROLE, _admin);
        
        lastWeightUpdate = block.timestamp;
    }
    
    function distribute() external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused {
        require(
            block.number >= lastDistributionBlock + MIN_DISTRIBUTION_INTERVAL,
            "Too soon"
        );
        
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        
        uint256 distributedSum = 0;
        uint256 recipientCount = recipients.length;
        
        for (uint i = 0; i < recipientCount - 1; i++) {
            address recipient = recipients[i];
            uint256 share = (balance * weights[recipient]) / BASIS_POINTS;
            pendingRewards[recipient] += share;
            distributedSum += share;
            emit RewardAccrued(recipient, share);
        }
        
        address lastRecipient = recipients[recipientCount - 1];
        uint256 lastShare = balance - distributedSum;
        pendingRewards[lastRecipient] += lastShare;
        emit RewardAccrued(lastRecipient, lastShare);
        
        lastDistributionBlock = block.number;
        totalDistributed += balance;
    }
    
    function claim() external nonReentrant whenNotPaused {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "Nothing to claim");
        
        pendingRewards[msg.sender] = 0;
        totalClaimed[msg.sender] += amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Claimed(msg.sender, amount);
    }
    
    function updateRecipients(
        address[] calldata _recipients,
        uint256[] calldata _weights
    ) external onlyRole(ADMIN_ROLE) {
        require(
            block.timestamp >= lastWeightUpdate + WEIGHT_CHANGE_DELAY,
            "Timelock active"
        );
        require(_recipients.length == _weights.length, "Length mismatch");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many");
        
        uint256 totalWeight = 0;
        for (uint i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == BASIS_POINTS, "Must sum to 100%");
        
        for (uint i = 0; i < recipients.length; i++) {
            delete weights[recipients[i]];
        }
        
        recipients = _recipients;
        for (uint i = 0; i < _recipients.length; i++) {
            weights[_recipients[i]] = _weights[i];
        }
        
        lastWeightUpdate = block.timestamp;
        emit RecipientsUpdated(_recipients, _weights);
    }
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    function emergencyWithdraw(address to) external onlyRole(ADMIN_ROLE) whenPaused {
        require(to != address(0), "Zero address");
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        require(success, "Transfer failed");
        emit EmergencyWithdrawal(to, balance);
    }
    
    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }
    
    function getPendingReward(address recipient) external view returns (uint256) {
        return pendingRewards[recipient];
    }
    
    receive() external payable {}
}
