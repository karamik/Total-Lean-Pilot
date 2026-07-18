// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title TOTALPilotFeeSplitter
 * @dev Прозрачное распределение входящего потока комиссий согласно спецификации Lean Pilot.
 */
contract TOTALPilotFeeSplitter {
    
    // Пропорции распределения (базис 10000 = 100%)
    uint16 public constant PROVERS_SHARE = 3500;    // 35%
    uint16 public constant VALIDATORS_SHARE = 2500; // 25%
    uint16 public constant TREASURY_SHARE = 2000;   // 20%
    uint16 public constant DA_LAYER_SHARE = 1500;   // 15%
    uint16 public constant BURN_SHARE = 500;       // 5%
    
    address public immutable proverAddress;
    address public immutable validatorAddress;
    address public immutable treasuryAddress;
    address public immutable daLayerAddress;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    mapping(address => uint256) public accruedBalances;
    
    event FeesDistributed(uint256 totalAmount, uint256 provers, uint256 validators, uint256 treasury, uint256 da, uint256 burned);
    event Withdrawn(address indexed recipient, uint256 amount);

    constructor(
        address _prover,
        address _validator,
        address _treasury,
        address _daLayer
    ) {
        require(_prover != address(0) && _validator != address(0) && _treasury != address(0) && _daLayer != address(0), "Zero address forbidden");
        proverAddress = _prover;
        validatorAddress = _validator;
        treasuryAddress = _treasury;
        daLayerAddress = _daLayer;
    }

    /**
     * @dev Прием нативных монет из Geth и мгновенный сплит по пулам балансов
     */
    receive() external payable {
        uint256 total = msg.value;
        require(total > 0, "No value sent");
        
        uint256 p = (total * PROVERS_SHARE) / 10000;
        uint256 v = (total * VALIDATORS_SHARE) / 10000;
        uint256 t = (total * TREASURY_SHARE) / 10000;
        uint256 d = (total * DA_LAYER_SHARE) / 10000;
        
        // Остаток уходит в гарантированный дефляционный Burn (5%)
        uint256 b = total - (p + v + t + d);
        
        accruedBalances[proverAddress] += p;
        accruedBalances[validatorAddress] += v;
        accruedBalances[treasuryAddress] += t;
        accruedBalances[daLayerAddress] += d;
        
        payable(BURN_ADDRESS).transfer(b);
        
        emit FeesDistributed(total, p, v, t, d, b);
    }

    /**
     * @dev Запрос вывода накопленных средств операторами инфраструктуры
     */
    function claim() external {
        uint256 amount = accruedBalances[msg.sender];
        require(amount > 0, "Empty balance");
        
        accruedBalances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        
        emit Withdrawn(msg.sender, amount);
    }
}
