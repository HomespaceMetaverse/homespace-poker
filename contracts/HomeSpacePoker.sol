//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

// OpenZepelin
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Debug
import "hardhat/console.sol";

import "./Libs/LibCard.sol";
import "./Libs/LibPlayer.sol";
import "./Libs/LibCard.sol";


/**
    Error codes:
    - G0 = Wrong amount of cards
    - G1 = Game was already started
    - G2 = Not enough game place left
    - G3 = Already joined
    - G4 = Invalid "Big blind" player ID
    - G5 = Required "Big blind" amount is incorrect
    - G6 = Player did not join yet
    - G7 = Revealed card is invalid
    - G8 = Game did not start
    - G9 = not enough players
    - G10 = Not enough chips
 */
contract HomeSpacePoker is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using LibCard for LibCard.Card;

    event GameCreated(uint256 indexed gameId);
    event GameStarted(uint256 indexed gameId);
    event GameEnded(uint256 indexed gameId);
    event GamePendingPayoff(uint256 indexed gameId);
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event PlayerLeft(uint256 indexed gameId, address indexed player);
    event PlayerTurn(uint256 indexed gameId, address indexed player, bool lastRound);
    event RoundEnd(uint256 indexed gameId, uint8 indexed round);

    enum GameStatus {NotStarted, Started, PendingPayoff, Ended}
    enum Combinations {High, Pair, Too_Pair, Three, Straight, Flush, Full_House, Four, Straight_Flush}

    uint256 constant public MIN_PLAYERS = 2;
    uint256 constant public MAX_PLAYERS = 5;

    struct DealerCards {
        LibCard.Card[] revealedCards;
        EnumerableSet.Bytes32Set cards;
    }

    struct Player {
        address player;
        uint256 balance;
        LibPlayer.PlayerStatus playerStatus;
        EnumerableSet.Bytes32Set cards;
        uint256 bet;
        uint256 spent;
        LibCard.Card[] revealedCards;
    }

    struct Game {
        GameStatus status;
        uint8 round;
        uint8 turn;
        uint8 joined;
        DealerCards dealerCards;
        mapping(uint256 => Player) players;
        uint256 pot;
        uint256 smallBlindAmount;
        uint256 currentBet;
        uint8 smallBlindPlayerId;
    }

    // All games (gameId => game)
    mapping(uint256 => Game) private games;
    mapping(address => uint8) highestCombinations;


    uint256 public lastGameId;

    function showDealerCards(uint256 _gameId) external view returns (LibCard.Card[] memory) {
        return games[_gameId].dealerCards.revealedCards;
    }

    function showGameStats(uint256 _gameId) external view returns (uint8 turn, uint8 joined, uint256 pot, uint256 smallBlindAmount, uint256 currentBet, uint256 smallBlindPlayerId) {
        Game storage game = games[_gameId];
        return (game.turn, game.joined, game.pot, game.smallBlindAmount, game.currentBet, game.smallBlindPlayerId);
    }

    function showPlayerCardHash(uint256 _gameId, uint256 _playerId, uint256 _cardIndex) external view returns (bytes32) {
        return games[_gameId].players[_playerId].cards.at(_cardIndex);
    }

    // Logic

    // Owner
    function createGame(
        uint256 _smallBlindAmount
    ) public onlyOwner returns (uint256) {
        lastGameId++;

        Game storage game = games[lastGameId];
        game.smallBlindAmount = _smallBlindAmount;
        game.currentBet = 2 * _smallBlindAmount;

        emit GameCreated(lastGameId);
        return lastGameId;
    }

    // Players
    function joinGame(
        uint256 _gameId
    ) public payable {
        Game storage game = games[_gameId];
        // Check if has enough chips
        require(msg.value >= 2 * game.smallBlindAmount, "G10");
        // Check if game did not start yet
        require(game.status == GameStatus.NotStarted, "G1");
        // Check if there is a space
        require(game.joined < MAX_PLAYERS, "G2");
        // Check if did not join yet
        require(game.players[game.joined].player == address(0), "G3");
        // Check that user transferred required "Big blind" amount
        require(msg.value >= 2 * game.smallBlindAmount, "G5");
        game.pot = game.pot + msg.value;

        // Add player
        game.players[game.joined].player = msg.sender;
        game.players[game.joined].balance = msg.value;
        game.players[game.joined].bet = 0;
        game.players[game.joined].spent = 0;
        game.joined += 1;

        emit PlayerJoined(_gameId, msg.sender);
    }

    /// @notice abort a non-initialized game and allows the withdrawal of the bigBlindAmount by the respective owner
    function leaveGame(
        uint256 _gameId
    ) external {
        Game storage game = games[_gameId];
        // Check if game did not start yet
        require(game.status == GameStatus.NotStarted, "G1");

        uint256 _playerId = findPlayerId(_gameId, msg.sender);

        // Remove player
        game.players[_playerId].playerStatus = LibPlayer.PlayerStatus.INACTIVE;

        // Transfer required "Big blind" amount from contract to player
        payable(msg.sender).transfer(game.players[_playerId].balance);
        game.pot -= game.players[_playerId].balance;
        for (uint256 i = _playerId; i < game.joined - 1; i++) {
            game.players[i].player = game.players[i + 1].player;
            game.players[i].balance = game.players[i + 1].balance;
        }
        game.joined -= 1;

        emit PlayerLeft(_gameId, msg.sender);
    }

    function startGame(
        uint256 _gameId,
        bytes32[] memory _commitCards
    ) public onlyOwner {
        Game storage game = games[_gameId];
        require(game.joined < MIN_PLAYERS, "not enough players");
        // Check if game did not start yet
        require(game.status == GameStatus.NotStarted, "G1");
        // Check if provided cards length is valid:  hand + 2 * players
        require(_commitCards.length == 5 + 2 * game.joined, "G0");
        // Check if "Big Blind" player id is valid
        // require(_bigBlindPlayerId < game.players.length(), "G4");
        game.smallBlindPlayerId = uint8(lastGameId % game.joined);
        uint8 bigBlindPlayerId = (game.smallBlindPlayerId + 1) % game.joined;
        // taking small blind
        game.players[game.smallBlindPlayerId].balance -= game.smallBlindAmount;
        game.players[game.smallBlindPlayerId].bet = game.smallBlindAmount;
        game.players[game.smallBlindPlayerId].spent = game.smallBlindAmount;
        // taking big blind
        game.players[bigBlindPlayerId].balance -= game.smallBlindAmount * 2;
        game.players[bigBlindPlayerId].bet = game.smallBlindAmount * 2;
        game.players[bigBlindPlayerId].spent = game.smallBlindAmount * 2;

        game.turn = (bigBlindPlayerId + 1) % game.joined;
        game.currentBet = game.smallBlindAmount * 2;

        for (uint256 index = 0; index < _commitCards.length; index++) {
            /**
                Hand cards: index < 5
             */
            if (index < 5) {
                bool added = game.dealerCards.cards.add(_commitCards[index]);
                // ensures the card is unique
                require(added == true, "card not valid");
            } else {
                uint256 playerId = (index - 5) / 2;
                bool added = game.players[playerId].cards.add(_commitCards[index]);
                // ensures the card is unique
                require(added == true, "card not valid");
            }
        }

        for (uint256 i = 0; i < game.joined; i++) {
            game.players[i].playerStatus = LibPlayer.PlayerStatus.NOT_PLAYED;
        }

        game.round = 1;
        game.status = GameStatus.Started;
        emit GameStarted(_gameId);
    }

    function allPlayersMadeTurn(uint256 _gameId) private returns (bool) {
        Game storage game = games[_gameId];
        for (uint256 i = 0; i < game.joined; i++) {
            if (game.players[i].playerStatus == LibPlayer.PlayerStatus.NOT_PLAYED) {
                return false;
            }
        }
        return true;
    }

    function resetAllPlayersTurn(uint256 _gameId) private {
        Game storage game = games[_gameId];
        for (uint256 i = 0; i < game.joined; i++) {
            if (game.players[i].playerStatus == LibPlayer.PlayerStatus.PLAYED) {
                game.players[i].playerStatus = LibPlayer.PlayerStatus.NOT_PLAYED;
            }
        }
    }

    function startRoundPlayers(uint256 _gameId) private {
        Game storage game = games[_gameId];
        for (uint256 i = 0; i < game.joined; i++) {
            game.players[i].bet = 0;
            if (game.players[i].playerStatus == LibPlayer.PlayerStatus.PLAYED) {
                game.players[i].playerStatus = LibPlayer.PlayerStatus.NOT_PLAYED;
            }
        }
    }

    function makeCall(
        uint256 _gameId
    ) external {
        Game storage game = games[_gameId];
        uint256 playerId = findPlayerId(_gameId, msg.sender);
        require(game.turn != playerId, "wrong turn");
        require(game.players[playerId].playerStatus == LibPlayer.PlayerStatus.NOT_PLAYED, "already played");
        require(game.status == GameStatus.Started, "game is not active");
        require(game.round < 5, "game evaluation in progress");

        uint256 callAmount = game.currentBet - game.players[playerId].bet;
        if (callAmount >= game.players[playerId].balance) {
            uint256 transferAmount = game.players[playerId].balance;
            game.players[playerId].balance = 0;
            game.players[playerId].spent += transferAmount;
            game.players[playerId].bet = 0;
            game.players[playerId].playerStatus = LibPlayer.PlayerStatus.INACTIVE;
        } else {
            game.players[playerId].balance -= callAmount;
            game.players[playerId].spent += callAmount;
            game.players[playerId].bet = game.currentBet;
            game.players[playerId].playerStatus = LibPlayer.PlayerStatus.PLAYED;
        }

        evaluateRoundEnd(_gameId);
    }

    function kickPlayer(
        uint256 _gameId,
        address _playerAddress
    ) external onlyOwner {
        Game storage game = games[_gameId];
        uint256 playerId = findPlayerId(_gameId, _playerAddress);

        game.players[playerId].bet = 0;
        game.players[playerId].playerStatus = LibPlayer.PlayerStatus.LEFT;
        game.pot -= game.players[playerId].balance;
        payable(_playerAddress).transfer(game.players[playerId].balance);
        game.players[playerId].balance = 0;

        evaluateRoundEnd(_gameId);
    }

    function makeFold(
        uint256 _gameId
    ) external {
        Game storage game = games[_gameId];
        uint256 playerId = findPlayerId(_gameId, msg.sender);
        require(game.turn != playerId, "wrong turn");
        require(game.status == GameStatus.Started, "game is not active");

        game.players[playerId].bet = 0;
        game.players[playerId].playerStatus = LibPlayer.PlayerStatus.LEFT;
        game.pot -= game.players[playerId].balance;
        payable(msg.sender).transfer(game.players[playerId].balance);
        game.players[playerId].balance = 0;

        evaluateRoundEnd(_gameId);
    }

    function makeRaise(
        uint256 _gameId,
        uint256 _raiseAmount
    ) external {
        Game storage game = games[_gameId];
        uint256 playerId = findPlayerId(_gameId, msg.sender);
        require(game.turn != playerId, "wrong turn");
        require(game.players[playerId].playerStatus == LibPlayer.PlayerStatus.NOT_PLAYED, "already played");
        require(game.round < 5, "game evaluation in progress");
        require(game.status == GameStatus.Started, "game is not active");

        require(_raiseAmount > game.currentBet, "wrong amount");

        uint256 amountToPay = _raiseAmount - game.players[playerId].bet;
        require(amountToPay <= game.players[playerId].balance, "not enough chips");

        game.currentBet = _raiseAmount;
        resetAllPlayersTurn(_gameId);
        game.players[playerId].balance -= amountToPay;
        game.players[playerId].bet = _raiseAmount;
        game.players[playerId].spent += amountToPay;
        game.players[playerId].playerStatus = LibPlayer.PlayerStatus.PLAYED;

        evaluateRoundEnd(_gameId);
    }

    function evaluateRoundEnd(
        uint256 _gameId
    ) private {
        Game storage game = games[_gameId];
        if (allPlayersMadeTurn(_gameId)) {
            emit RoundEnd(_gameId, game.round);
            game.round += 1;
        } else {
            if (game.round < 5) {
                while (game.players[game.turn].playerStatus != LibPlayer.PlayerStatus.NOT_PLAYED) {
                    game.turn = (game.turn + 1) % game.joined;
                }
                emit PlayerTurn(_gameId, game.players[game.turn].player, false);
            } else if (game.round == 5) {
                while (game.players[game.turn].playerStatus != LibPlayer.PlayerStatus.NOT_PLAYED || game.players[game.turn].playerStatus != LibPlayer.PlayerStatus.INACTIVE) {
                    game.turn = (game.turn + 1) % game.joined;
                }
                emit PlayerTurn(_gameId, game.players[game.turn].player, true);
            } else {
                game.status = GameStatus.PendingPayoff;
                emit GamePendingPayoff(_gameId);
            }
        }
    }

    function revealPlayerCards(
        uint256 _gameId,
        LibCard.Card[] calldata _cards
    ) external {
        Game storage game = games[_gameId];
        uint256 playerId = findPlayerId(_gameId, msg.sender);
        require(game.turn != playerId, "wrong turn");
        require(game.players[playerId].playerStatus == LibPlayer.PlayerStatus.NOT_PLAYED || game.players[playerId].playerStatus == LibPlayer.PlayerStatus.INACTIVE, "already played");
        require(game.round == 5, "too early to reveal cards");
        require(_cards.length == 2, "wrong cards amount");
        require(game.status == GameStatus.Started, "game is not active");

        game.players[playerId].revealedCards.push(_cards[0]);
        game.players[playerId].revealedCards.push(_cards[1]);
        game.players[playerId].playerStatus = LibPlayer.PlayerStatus.INACTIVE;

        evaluateRoundEnd(_gameId);
    }

    /// @notice dealer initializes a new turn after all the players have made their move
    function toggleRound(uint256 _gameId, LibCard.Card[] calldata _cards) external onlyOwner {
        Game storage game = games[_gameId];
        require(game.round < 6, "no more rounds");

        /// 2nd turn/flop round: dealer reveals three cards
        if (game.round == 2) {
            require(_cards.length == 3, "wrong cards amount");
            game.dealerCards.revealedCards.push(_cards[0]);
            game.dealerCards.revealedCards.push(_cards[1]);
            game.dealerCards.revealedCards.push(_cards[2]);
        }
        /// 3rd turn/turn round: dealer reveals one card
        if (game.round == 3) {
            require(_cards.length == 1, "wrong cards amount");
            game.dealerCards.revealedCards.push(_cards[0]);
        }
        // 4th round/river round: dealer reveals one card
        if (game.round == 4) {
            require(_cards.length == 1, "wrong cards amount");
            game.dealerCards.revealedCards.push(_cards[0]);
        }

        startRoundPlayers(_gameId);
        emit PlayerTurn(_gameId, game.players[game.turn].player, game.round == 5);
    }


    /// @notice it is called at the end of the last turn. it reveals all the player's cards and forward the payoff accordingly
    /// @dev  there are internal checks to ensures the consistency of the hashes with the respective cards. Each player has their own salt which is known only to the dealer. The dealer has their own salt as well.
    /// @param _gameId uint256 id of the game being played
    /// @param _cardsSalts array including the salts of the dealer and the players. It must follow the following order
    /// _cardsSalts[0] the salt of the dealer
    ///_cardsSalts[k:n] the salts of the players
    function endGame(
        uint256 _gameId,
        bytes32[] calldata _cardsSalts
    ) external onlyOwner {
        Game storage game = games[_gameId];
        require(game.status == GameStatus.PendingPayoff, "wrong game state");
        require(_cardsSalts.length == game.joined + 1, "wrong salts amount");
        // check last player made their move (what if the last player folded tho?)
        require(game.players[game.joined - 1].playerStatus == LibPlayer.PlayerStatus.PLAYED, "final turn not completed");
        // dealer's cards validation
        for (uint k = 0; k < game.dealerCards.revealedCards.length; k++) {
            require(
                game.dealerCards.revealedCards[k].verifyCardHash(
                    _cardsSalts[0],
                    game.dealerCards.cards.at(k)
                ),
                "wrong dealer card verification"
            );
        }
        // players' cards validation
        for (uint256 y = 0; y < game.joined; y++) {
            if (game.players[y].playerStatus == LibPlayer.PlayerStatus.INACTIVE) {
                for (uint256 x = 0; x < game.players[y].cards.length(); x++) {
                    require(
                        game.players[y].revealedCards[x].verifyCardHash(
                            _cardsSalts[y + 1],
                            game.players[y].cards.at(x)
                        ),
                        "G7"
                    );
                }
            }
            // should add a refund mechanism by keeping track of balances if it fails (use try catch?)
            // check the most valuable combination (maybe compare it against a benchmark)
        }

        sendGamePrizes(_gameId);

        // if all checks have been successful, transition to payoff phase
        game.status = GameStatus.Ended;
        emit GameEnded(_gameId);
    }

    function sendGamePrizes(uint256 _gameId) private {
        Game storage game = games[_gameId];
        uint8 playersLeft = 0;
        // if one player left transfer all win to him
        address playerAddress = game.players[0].player;
        for (uint256 i = 0; i < game.joined; i++) {
            if (game.players[i].playerStatus == LibPlayer.PlayerStatus.INACTIVE) {
                playersLeft += 1;
                playerAddress = game.players[i].player;
            }
        }
        if (playersLeft == 1) {
            payable(playerAddress).transfer(game.pot);
            game.pot = 0;
        }
        // evaluating players rank
        uint256 minSplit = game.pot;
        for (uint256 i = 0; i < game.joined; i++) {
            if (game.players[i].playerStatus == LibPlayer.PlayerStatus.INACTIVE) {
                uint8 rank = evaluateRank(concatArrays(game.dealerCards.revealedCards, game.players[i].revealedCards));
                highestCombinations[game.players[i].player] = rank;
            }
        }
        // transfer wins based on participation
        while (minSplit != 0) {
            for (uint256 j = 0; j < game.joined; j++) {
                if (game.players[j].playerStatus == LibPlayer.PlayerStatus.INACTIVE && game.players[j].spent < minSplit) {
                    minSplit = game.players[j].spent;
                }
            }
            if (minSplit != 0) {
                uint256 win = 0;
                address[] memory players = new address[](game.joined); // upper bound = game.joined
                for (uint256 j = 0; j < game.joined; j++) {
                    if (game.players[j].spent < minSplit) {
                        win += game.players[j].spent;
                        game.pot -= game.players[j].spent;
                        game.players[j].spent = 0;
                        game.players[j].playerStatus = LibPlayer.PlayerStatus.LEFT;
                    } else if (game.players[j].spent == minSplit) {
                        win += game.players[j].spent;
                        game.pot -= game.players[j].spent;
                        game.players[j].spent = 0;
                        game.players[j].playerStatus = LibPlayer.PlayerStatus.LEFT;
                        players[players.length - 1] = game.players[j].player;
                    } else {
                        win += minSplit;
                        game.pot -= minSplit;
                        game.players[j].spent = game.players[j].spent - minSplit;
                        players[players.length - 1] = game.players[j].player;
                    }
                }
                
                address[] memory winners = new address[](game.joined); // upper bound = game.joined
                address[] memory empty;
                winners[0] = players[0];
                uint8 maxRank = highestCombinations[players[0]];
                for (uint256 z = 0; z < players.length; z++) {
                    if (highestCombinations[players[z]] > maxRank) {
                        maxRank = highestCombinations[players[z]];
                        winners = empty;
                        console.log(winners.length);
                        winners[winners.length - 1] = players[z];
                    } else if (highestCombinations[players[z]] == maxRank) {
                        winners[winners.length - 1] = players[z];
                    }
                }
                if (winners.length > 1) {
                    for (uint256 h = 0; h < winners.length; h++) {
                        payable(winners[h]).transfer(win % winners.length);
                    }
                } else {
                    payable(winners[0]).transfer(win);
                }
                minSplit = game.pot;
            }
        }
    }

    function concatArrays(LibCard.Card[] memory cards1, LibCard.Card[] memory cards2) private returns (LibCard.Card[] memory) {
        LibCard.Card[] memory returnArr = new LibCard.Card[](cards1.length + cards2.length);

        uint8 i = 0;
        for (; i < cards1.length; i++) {
            returnArr[i] = cards1[i];
        }
        for (uint8 j = 0; j < cards2.length; j++) {
            returnArr[i++] = cards2[j];
        }

        return returnArr;
    }

    function findPlayerId(
        uint256 _gameId,
        address _player
    ) private returns (uint256) {
        Game storage game = games[_gameId];
        // find a player
        for (uint256 i = 0; i < game.joined; i++) {
            if (game.players[i].player == _player) {
                return i;
            }
        }
        revert("player not found");
    }

    function evaluateRank(LibCard.Card[] memory _cards) internal pure returns (uint8) {
        return evaluateCombinationRank(_cards) * 10 + evaluateHighRank(_cards);
    }

    function evaluateCombinationRank(LibCard.Card[] memory _cards) private pure returns (uint8) {
        uint8[4] memory suits;
        uint8[13] memory ranks;
        for (uint8 i = 0; i < _cards.length; i++) {
            ranks[uint8(_cards[i].value)] += 1;
            suits[uint8(_cards[i].suit)] += 1;
        }
        bool isFlush = false;
        uint8 flushSuit = 0;
        bool isStraight = false;
        uint8 highStraight = 0;
        uint8 pairCount = 0;
        uint8 highPair = 0;
        uint8 threeCount = 0;
        uint8 highThree = 0;

        for (uint8 i = 0; i < 4; i++) {
            if (suits[i] == 5) {
                isFlush = true;
                flushSuit = i;
            }
        }
        for (uint8 i = 0; i < 9; i++) {
            if (ranks[i] > 0 && ranks[i + 1] > 0 && ranks[i + 2] > 0 && ranks[i + 3] > 0 && ranks[i + 4] > 0) {
                isStraight = true;
                highStraight = i + 4;
            }
        }
        if (isStraight == false && ranks[0] > 0 && ranks[1] > 0 && ranks[2] > 0 && ranks[3] > 0 && ranks[12] > 0) {
            isStraight = true;
            highStraight = 3;
        }
        if (isStraight && isFlush) {
            if (_cards.length == 5) {
                return uint8(Combinations.Straight_Flush) * 20 + highStraight;
            }
            // Don't know how to sort in solidity, need to check if there is royal flash
        }
        for (uint8 i = 0; i < 13; i++) {
            if (ranks[i] == 4) {
                return uint8(Combinations.Four) * 20 + i;
            }
            if (ranks[i] == 3) {
                threeCount += 1;
                highThree = i;
            }
        }
        if (threeCount == 2) {
            return uint8(Combinations.Full_House) * 20 + highThree;
        }
        for (uint8 i = 0; i < 13; i++) {
            if (ranks[i] == 2) {
                pairCount += 1;
                highPair = i;
            }
        }
        if (threeCount == 1 && pairCount > 0) {
            return uint8(Combinations.Full_House) * 20 + highThree;
        }
        if (isFlush) {
            return uint8(Combinations.Flush) * 20;
        }
        if (isStraight) {
            return uint8(Combinations.Straight) * 20 + highStraight;
        }
        if (threeCount == 1) {
            return uint8(Combinations.Three) * 20 + highThree;
        }
        if (pairCount > 1) {
            return uint8(Combinations.Too_Pair) * 20 + highPair;
        }
        if (pairCount == 1) {
            return uint8(Combinations.Pair) * 20 + highPair;
        }
        return 0;
    }

    function evaluateHighRank(LibCard.Card[] memory _cards) internal pure returns (uint8) {
        require(_cards.length >= 5, "not enough cards");
        uint8 rank = uint8(_cards[0].value);
        for (uint8 i = 1; i < _cards.length; i++) {
            if (rank < uint8(_cards[0].value)) {
                rank = uint8(_cards[0].value);
            }
        }
        return rank;
    }


}
