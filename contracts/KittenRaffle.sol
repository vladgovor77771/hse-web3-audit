// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Base64} from "./base64/base64.sol"; // просто либа

/// @title KittenRaffle
/// @author CatLoveDAO
/// @notice Этот проект позволяет участвовать в розыгрыше и выиграть милого котенка NFT. Протокол должен делать следующее:
/// 1. Вызовите функцию `enterRaffle` с следующими параметрами:
///    1. `address[] participants`: Список адресов участников. Вы можете использовать это, чтобы ввести себя несколько раз или себя и группу своих друзей.
/// 2. Дублирующиеся адреса не допускаются
/// 3. Пользователям разрешается получить возврат их билета и `value`, если они вызовут функцию `refund`
/// 4. Каждые X секунд розыгрыш сможет определить победителя и сминтить случайного котенка
/// 5. Владелец протокола устанавливает feeAddress для получения части `value`, а остальные средства отправляются победителю котенка.
contract KittenRaffle is ERC721, Ownable {
    using Address for address payable;

    uint256 public immutable entranceFee;

    address[] public players;
    uint256 public raffleDuration;
    uint256 public raffleStartTime;
    address public previousWinner;

    // Мы используем упаковку хранилища для экономии газа
    address public feeAddress;
    uint64 public totalFees = 0;

    // отображения для отслеживания характеристик токенов
    mapping(uint256 => uint256) public tokenIdToRarity;
    mapping(uint256 => string) public rarityToUri;
    mapping(uint256 => string) public rarityToName;

    // Статистика для обычного котенка (британский короткошерстный)
    string private commonImageUri = "ipfs://ref";
    uint256 public constant COMMON_RARITY = 70;
    string private constant COMMON = "common";

    // Статистика для редкого котенка (сиамский)
    string private rareImageUri = "ipfs://ref";
    uint256 public constant RARE_RARITY = 25;
    string private constant RARE = "rare";

    // Статистика для легендарного котенка (мейн-кун)
    string private legendaryImageUri = "ipfs://ref";
    uint256 public constant LEGENDARY_RARITY = 5;
    string private constant LEGENDARY = "legendary";

    // События
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);
    event FeeAddressChanged(address newFeeAddress);

    /// @param _entranceFee стоимость в wei для входа в розыгрыш
    /// @param _feeAddress адрес для отправки комиссии
    /// @param _raffleDuration длительность розыгрыша в секундах
    constructor(
        uint256 _entranceFee,
        address _feeAddress,
        uint256 _raffleDuration
    ) ERC721("Kitten Raffle", "KR") {
        entranceFee = _entranceFee;
        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;

        rarityToUri[COMMON_RARITY] = commonImageUri;
        rarityToUri[RARE_RARITY] = rareImageUri;
        rarityToUri[LEGENDARY_RARITY] = legendaryImageUri;

        rarityToName[COMMON_RARITY] = COMMON;
        rarityToName[RARE_RARITY] = RARE;
        rarityToName[LEGENDARY_RARITY] = LEGENDARY;
    }

    /// @notice так игроки входят в розыгрыш
    /// @notice они должны заплатить входную плату * количество игроков
    /// @notice дублирующиеся участники не допускаются
    /// @param newPlayers список игроков для входа в розыгрыш
    function enterRaffle(address[] memory newPlayers) public payable {
        require(
            msg.value == entranceFee * newPlayers.length,
            unicode"KittenRaffle: Необходимо отправить достаточно для участия в розыгрыше"
        );
        for (uint256 i = 0; i < newPlayers.length; i++) {
            players.push(newPlayers[i]);
        }

        // Проверка на дубликаты
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = i + 1; j < players.length; j++) {
                require(
                    players[i] != players[j],
                    unicode"KittenRaffle: Дублирующийся игрок"
                );
            }
        }
        emit RaffleEnter(newPlayers);
    }

    /// @param playerIndex индекс игрока для возврата. Вы можете найти его внешне, вызвав `getActivePlayerIndex`
    /// @dev Эта функция позволит иметь пустые места в массиве
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(
            playerAddress == msg.sender,
            unicode"KittenRaffle: Только игрок может получить возврат"
        );
        require(
            playerAddress != address(0),
            unicode"KittenRaffle: Игрок уже получил возврат или не активен"
        );

        payable(msg.sender).sendValue(entranceFee);

        players[playerIndex] = address(0);
        emit RaffleRefunded(playerAddress);
    }

    /// @notice способ получить индекс в массиве
    /// @param player адрес игрока в розыгрыше
    /// @return индекс игрока в массиве, если он не активен, возвращает 0
    function getActivePlayerIndex(
        address player
    ) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        return 0;
    }

    /// @notice эта функция выберет победителя и сминтит котенка
    /// @notice должно быть не менее 4 игроков, и должно пройти установленное время
    /// @notice предыдущий победитель хранится в переменной previousWinner
    /// @dev мы используем хеш данных в блокчейне для генерации случайных чисел
    /// @dev мы сбрасываем массив активных игроков после выбора победителя
    /// @dev мы отправляем 80% собранных средств победителю, остальные 20% отправляются на feeAddress
    function selectWinner() external {
        require(
            block.timestamp >= raffleStartTime + raffleDuration,
            unicode"KittenRaffle: Розыгрыш еще не закончился"
        );
        require(
            players.length >= 4,
            unicode"KittenRaffle: Необходимо минимум 4 игрока"
        );
        uint256 winnerIndex = uint256(
            keccak256(
                abi.encodePacked(msg.sender, block.timestamp, block.difficulty)
            )
        ) % players.length;
        address winner = players[winnerIndex];
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees += uint64(fee);

        uint256 tokenId = totalSupply();

        // Мы используем другой RNG, отличный от winnerIndex, чтобы определить редкость
        uint256 rarity = uint256(
            keccak256(abi.encodePacked(msg.sender, block.difficulty))
        ) % 100;
        if (rarity <= COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity <= COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success, ) = winner.call{value: prizePool}("");
        require(
            success,
            unicode"KittenRaffle: Не удалось отправить призовой фонд победителю"
        );
        _safeMint(winner, tokenId);
    }

    /// @notice эта функция будет выводить комиссию на feeAddress
    function withdrawFees() external {
        require(
            address(this).balance == uint256(totalFees),
            unicode"KittenRaffle: В настоящее время активны игроки!"
        );
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success, ) = feeAddress.call{value: feesToWithdraw}("");
        require(success, unicode"KittenRaffle: Не удалось вывести комиссию");
    }

    /// @notice только владелец контракта может изменить feeAddress
    /// @param newFeeAddress новый адрес для отправки комиссии
    function changeFeeAddress(address newFeeAddress) external onlyOwner {
        feeAddress = newFeeAddress;
        emit FeeAddressChanged(newFeeAddress);
    }

    /// @notice эта функция вернет true, если msg.sender является активным игроком
    function _isActivePlayer() internal view returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /// @notice это может быть константной переменной
    function _baseURI() internal pure returns (string memory) {
        return "data:application/json;base64,";
    }

    /// @notice эта функция вернет URI для токена
    /// @param tokenId Id NFT
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(
            _exists(tokenId),
            unicode"KittenRaffle: Запрос URI для несуществующего токена"
        );

        uint256 rarity = tokenIdToRarity[tokenId];
        string memory imageURI = rarityToUri[rarity];
        string memory rareName = rarityToName[rarity];

        return
            string(
                abi.encodePacked(
                    _baseURI(),
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name(),
                                unicode'", "description":"Очаровательный котенок!", ',
                                '"attributes": [{"trait_type": "rarity", "value": ',
                                rareName,
                                '}], "image":"',
                                imageURI,
                                '"}'
                            )
                        )
                    )
                )
            );
    }
}
