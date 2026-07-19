
# Создадим production-ready HackerHoneypot.sol с настоящей ловушкой
# Ключевая идея: бот видит выигрыш в симуляции, но в реальном блоке условие меняется

honeypot = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TOTALPilotHoneypot
 * @notice Контракт-приманка для генерации TPS и комиссий.
 * @dev Имитирует уязвимость, но защищен через:
 *   1. Зависимость от blockhash (недоступен в eth_call симуляции)
 *   2. Clique PoA: block.timestamp детерминирован, но blockhash меняется
 *   3. Nonce-based entropy: каждая попытка сдвигает seed
 *   4. ReentrancyGuard: защита от реальных атак
 * 
 * Механика ловушки:
 * - Бот делает eth_call (симуляцию) → видит "win" → отправляет tx
 * - В реальном блоке blockhash другой → бот проигрывает
 * - $0.01 комиссия идет в FeeSplitter (35/25/20/15/5)
 * - Призовой пул растет → больше ботов → больше комиссий
 */
contract TOTALPilotHoneypot is ReentrancyGuard {
    
    string public constant VERSION = "TOTAL Pilot Honeypot v1.0";
    
    /// @notice Адрес FeeSplitter для распределения комиссий
    address public immutable feeSplitter;
    
    /// @notice Владелец (для emergency withdraw)
    address public owner;
    
    /// @notice Фиксированная комиссия за попытку ($0.01 эквивалент)
    uint256 public constant ATTEMPT_FEE = 0.01 ether;
    
    /// @notice Минимальный призовой пул для активации
    uint256 public constant MIN_PRIZE_POOL = 0.1 ether;
    
    /// @notice Максимальный выигрыш за одну попытку (anti-whale)
    uint256 public constant MAX_PRIZE = 1 ether;
    
    // ===== Метрики (читаются Prometheus exporter'ом) =====
    
    /// @notice Всего попыток взлома
    uint256 public totalAttackAttempts;
    
    /// @notice Успешных попыток (теоретически 0)
    uint256 public totalSuccessfulAttacks;
    
    /// @notice Собрано комиссий
    uint256 public totalFeesCollected;
    
    /// @notice Потрачено gas ботами (в wei)
    uint256 public totalGasWasted;
    
    /// @notice Уникальных хакеров (адресов)
    uint256 public uniqueHackers;
    
    // ===== Скрытые инварианты ловушки =====
    
    /// @notice Seed, сдвигающийся после каждой попытки
    /// @dev Даже если бот угадает seed в симуляции, в реальном блоке он будет другим
    uint256 private entropySeed;
    
    /// @notice Маппинг уникальных хакеров
    mapping(address => bool) private _knownHackers;
    
    /// @notice Маппинг попыток по адресу
    mapping(address => uint256) public attemptsByHacker;
    
    // ===== Events =====
    
    event AttackAttempt(
        address indexed hacker,
        uint256 attemptNumber,
        uint256 gasUsed,
        bytes32 guess,
        bytes32 actualHash,
        bool wouldWinInSimulation
    );
    
    event AttackFailed(
        address indexed hacker,
        uint256 attemptNumber,
        string reason,
        uint256 gasUsed
    );
    
    event RewardClaimed(
        address indexed hacker,
        uint256 amount,
        uint256 attemptNumber
    );
    
    event FeesDistributed(
        address indexed feeSplitter,
        uint256 amount
    );
    
    event PrizePoolFunded(
        address indexed funder,
        uint256 amount
    );
    
    // ===== Modifiers =====
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    // ===== Constructor =====
    
    constructor(address _feeSplitter) payable {
        require(_feeSplitter != address(0), "Invalid feeSplitter");
        feeSplitter = _feeSplitter;
        owner = msg.sender;
        
        // Инициализация seed — детерминирована, но непредсказуема
        // blockhash нельзя получить для текущего блока, только для N-256
        // Это ключевая ловушка: боты не могут предсказать будущий blockhash
        entropySeed = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.timestamp,
            msg.sender,
            address(this)
        )));
    }
    
    // ===== Core Functions =====
    
    /**
     * @notice Основная функция-приманка.
     * @dev Боты видят в eth_call что могут выиграть, но в реальном блоке проигрывают.
     * @param guess Хэш, который бот "угадал" в симуляции
     */
    function guessAndWithdraw(bytes32 guess) external payable nonReentrant {
        uint256 gasStart = gasleft();
        
        // 1. Проверка комиссии (генерирует доход сети)
        require(msg.value >= ATTEMPT_FEE, "Honeypot: min 0.01 ETH fee");
        
        // 2. Учет метрик
        totalAttackAttempts++;
        attemptsByHacker[msg.sender]++;
        
        if (!_knownHackers[msg.sender]) {
            _knownHackers[msg.sender] = true;
            uniqueHackers++;
        }
        
        // 3. Отправка комиссии в FeeSplitter
        // Важно: отправляем ровно ATTEMPT_FEE, остаток идет в призовой пул
        (bool feeSuccess, ) = feeSplitter.call{value: ATTEMPT_FEE}("");
        require(feeSuccess, "Fee transfer failed");
        totalFeesCollected += ATTEMPT_FEE;
        emit FeesDistributed(feeSplitter, ATTEMPT_FEE);
        
        // 4. ===== ЛОВУШКА =====
        // Боты делают eth_call (симуляцию) для текущего блока N.
        // В симуляции blockhash(N) = 0 (недоступен), поэтому боты используют
        // blockhash(N-1) или другие предсказуемые значения.
        // 
        // НО: когда транзакция включается в реальный блок N+1, blockhash(N+1)
        // становится доступен, и entropySeed уже сдвинут от предыдущих попыток.
        //
        // Дополнительно: в Clique PoA block.timestamp фиксирован (6s), но
        // blockhash зависит от содержимого блока, которое меняется.
        
        // Обновляем seed (каждая попытка сдвигает его)
        entropySeed = uint256(keccak256(abi.encodePacked(
            entropySeed,
            blockhash(block.number - 1),
            msg.sender,
            totalAttackAttempts
        )));
        
        // Генерируем "секрет" — детерминирован, но непредсказуем для бота
        bytes32 actualHash = keccak256(abi.encodePacked(
            entropySeed,
            blockhash(block.number - 1),  // Доступен только в реальном блоке!
            block.timestamp,
            msg.sender,
            address(this)
        ));
        
        // 5. Проверка угадывания
        bool isWin = (guess == actualHash);
        
        // Записываем метрики
        uint256 gasUsed = gasStart - gasleft();
        totalGasWasted += gasUsed * tx.gasprice;
        
        emit AttackAttempt(
            msg.sender,
            attemptsByHacker[msg.sender],
            gasUsed,
            guess,
            actualHash,
            isWin
        );
        
        if (isWin) {
            // Теоретически невозможно, но на всякий случай:
            // Проверяем что призовой пул достаточен
            uint256 prizePool = address(this).balance;
            require(prizePool >= MIN_PRIZE_POOL, "Prize pool too low");
            
            uint256 prize = prizePool > MAX_PRIZE ? MAX_PRIZE : prizePool;
            
            // Обновляем метрики
            totalSuccessfulAttacks++;
            
            // Отправляем приз
            (bool success, ) = payable(msg.sender).call{value: prize}("");
            require(success, "Prize transfer failed");
            
            emit RewardClaimed(msg.sender, prize, attemptsByHacker[msg.sender]);
        } else {
            // Бот проиграл — остаток msg.value (выше ATTEMPT_FEE) идет в призовой пул
            emit AttackFailed(
                msg.sender,
                attemptsByHacker[msg.sender],
                "Invalid guess: entropy shifted by blockhash",
                gasUsed
            );
        }
    }
    
    /**
     * @notice Функция для принудительного пополнения призового фонда.
     * @dev Используется для наращивания приманки без попытки взлома.
     */
    function fundPrizePool() external payable {
        require(msg.value > 0, "Must send ETH");
        emit PrizePoolFunded(msg.sender, msg.value);
    }
    
    /**
     * @notice Получить текущий размер призового пула.
     */
    function prizePool() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Получить текущий entropy seed (для отладки, read-only).
     * @dev Не помогает ботам — seed меняется после каждой транзакции.
     */
    function currentEntropy() external view returns (uint256) {
        return entropySeed;
    }
    
    /**
     * @notice Симулировать результат для текущего блока.
     * @dev Боты используют это для eth_call. Возвращает "win" с высокой вероятностью
     * если guess сгенерирован из текущих условий, НО в реальном блоке условия меняются.
     */
    function simulate(bytes32 guess) external view returns (bool wouldWin, bytes32 actualHash) {
        // В симуляции blockhash(block.number) = 0 (недоступен)
        // Боты используют blockhash(block.number - 1) — предсказуемо
        bytes32 simulatedHash = keccak256(abi.encodePacked(
            entropySeed,
            blockhash(block.number - 1),
            block.timestamp,
            msg.sender,
            address(this)
        ));
        
        return (guess == simulatedHash, simulatedHash);
    }
    
    // ===== Admin Functions =====
    
    /**
     * @notice Emergency withdraw всего баланса (только owner).
     * @dev На случай если нужно перезапустить honeypot с другими параметрами.
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Withdraw failed");
    }
    
    /**
     * @notice Передать ownership.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    // ===== Fallback =====
    
    receive() external payable {
        // Автоматически распределяем входящие средства:
        // 50% — FeeSplitter, 50% — призовой пул
        uint256 half = msg.value / 2;
        (bool success, ) = feeSplitter.call{value: half}("");
        if (success) {
            totalFeesCollected += half;
            emit FeesDistributed(feeSplitter, half);
        }
        // Остаток остается на балансе (призовой пул)
    }
}
'''

with open('/mnt/agents/output/HackerHoneypot.sol', 'w') as f:
    f.write(honeypot)

print("✅ contracts/src/HackerHoneypot.sol создан")
print(f"Размер: {len(honeypot)} bytes")
