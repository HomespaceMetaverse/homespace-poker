import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers } from "hardhat";
import { HomeSpacePoker } from "../typechain";
import pokerDeck, { TDeck, TCard } from "../utils";

export const toBN = (value: string): BigNumber => {
  return parseUnits(value);
};

const {
  utils: { parseUnits },
} = ethers;

export const getCardHash = (card: TCard, salt: string): string => {
  const saltToBytes = ethers.utils.formatBytes32String(salt);
  return ethers.utils.solidityKeccak256(
    ["uint8", "uint8", "bytes32"],
    [card.value, card.suit, saltToBytes]
  );
};

const salts = {
  DEALER_SALT: "DEALER_SALT",
  PLAYER_ONE_SALT: "PLAYER_ONE_SALT",
  PLAYER_TWO_SALT: "PLAYER_TWO_SALT",
  PLAYER_THREE_SALT: "PLAYER_THREE_SALT",
};

type TGame = {
  gameId: number;
  expectedTurn: number;
  expectedJoined: number;
  expectedPot: BigNumber;
  expectedBigBlindAmount: BigNumber;
  expectedCurrentBet: BigNumber;
  expectedBigBlindPlayerId: BigNumber;
};

// smallblind is the first
describe("HomeSpacePoker", function () {
  let poker: HomeSpacePoker;
  const bigBlindAmount = parseUnits("1.0");
  const raiseAmount = bigBlindAmount.mul(2);

  let gameValues = {
    gameId: 0,
    expectedTurn: 0,
    expectedJoined: 0,
    expectedPot: toBN("0"),
    expectedBigBlindAmount: toBN("0"),
    expectedCurrentBet: toBN("0"),
    expectedBigBlindPlayerId: toBN("0"),
  };
  let dealerCardsHashes,
    playerOneCardsHashes,
    playerTwoCardsHashes,
    playerThreeCardsHashes,
    gameCardsHashes;
  let dealerDeck: TDeck,
    playerOneDeck: [TCard, TCard],
    playerTwoDeck: [TCard, TCard],
    playerThreeDeck: [TCard, TCard],
    gameCardsDeck: TDeck;

  const testGameStats = async (gameArgs: TGame): Promise<void> => {
    const stats = await poker.showGameStats(gameArgs.gameId);
    console.log(stats);
    expect(stats.turn, "wrong turn").to.be.eq(gameArgs.expectedTurn);
    expect(stats.joined, "wrong joined players number").to.be.eq(
      gameArgs.expectedJoined
    );
    expect(stats.pot, "wrong game pot").to.be.eq(gameArgs.expectedPot);
    expect(stats.bigBlindAmount, "wrong big-blind amount").to.be.eq(
      gameArgs.expectedBigBlindAmount
    );
    expect(stats.currentBet, "wrong currentBet amount").to.be.eq(
      gameArgs.expectedCurrentBet
    );
  };

  before(async () => {
    const HomeSpacePoker = await ethers.getContractFactory("HomeSpacePoker");
    poker = await HomeSpacePoker.deploy();
    await poker.deployed();
  });
  it("Should create the game", async function () {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    expect(await poker.REQUIRED_PLAYERS()).to.equal(3);
    expect(await poker.lastGameId()).to.equal(0);
    await poker.createGame(bigBlindAmount);

    expect(await poker.lastGameId()).to.equal(1);

    const dealerCards = await poker.showDealerCards(1);
    gameValues = {
      ...gameValues,
      gameId: 1,
      expectedBigBlindAmount: bigBlindAmount,
      expectedCurrentBet: bigBlindAmount,
    };
    await testGameStats(gameValues);
  });

  it("should allow up to 3 players to join the game", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    await poker.connect(player2).joinGame(1);
    gameValues = {
      ...gameValues,
      expectedJoined: 1,
    };
    await testGameStats(gameValues);
    await poker.connect(player3).joinGame(1, { value: bigBlindAmount });
    gameValues = {
      ...gameValues,
      expectedJoined: 2,
      expectedPot: bigBlindAmount,
    };
    await testGameStats(gameValues);
    await poker.connect(player4).joinGame(1);
    gameValues = {
      ...gameValues,
      expectedJoined: 3,
    };
    await testGameStats(gameValues);
  });

  it("should start the game successfully", async () => {
    const { joined } = await poker.showGameStats(1);
    const dealerCardsAmount = 5;
    const totalCards = dealerCardsAmount + joined * 2;
    dealerDeck = pokerDeck.slice(0, dealerCardsAmount);
    // @ts-ignore
    playerOneDeck = pokerDeck.slice(dealerCardsAmount, 7);
    // @ts-ignore
    playerTwoDeck = pokerDeck.slice(7, 9);
    // @ts-ignore
    playerThreeDeck = pokerDeck.slice(9, 11);
    dealerCardsHashes = dealerDeck.map((card) =>
      getCardHash(card, salts.DEALER_SALT)
    );
    playerOneCardsHashes = playerOneDeck.map((card) =>
      getCardHash(card, salts.PLAYER_ONE_SALT)
    );
    playerTwoCardsHashes = playerTwoDeck.map((card) =>
      getCardHash(card, salts.PLAYER_TWO_SALT)
    );
    playerThreeCardsHashes = playerThreeDeck.map((card) =>
      getCardHash(card, salts.PLAYER_THREE_SALT)
    );

    gameCardsDeck = dealerDeck
      .concat(playerOneDeck)
      .concat(playerTwoDeck)
      .concat(playerThreeDeck);
    gameCardsHashes = dealerCardsHashes
      .concat(playerOneCardsHashes)
      .concat(playerTwoCardsHashes)
      .concat(playerThreeCardsHashes);

    await poker.startGame(1, gameCardsHashes);
    gameValues = {
      ...gameValues,
      expectedTurn: 1,
    };
    await testGameStats(gameValues);
  });
  it("should not update the game if dealer calls toggleTurn before the completion of the turn", async () => {
    const myCard = {
      value: 1,
      suit: 2,
    };
    const cards = new Array(3).fill(myCard);
    await poker.toggleTurn(1, cards);
    const dealerCards = await poker.showDealerCards(1);
    await testGameStats(gameValues);
  });

  it("players play their 1st turn moves", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    await poker.connect(player2).dispatch(1, 0, 0);
    await poker.connect(player3).dispatch(1, 1, 2, { value: bigBlindAmount });
    await poker.connect(player4).dispatch(1, 2, 2, { value: bigBlindAmount });

    gameValues = {
      ...gameValues,
      expectedPot: gameValues.expectedPot.add(bigBlindAmount.mul(2)),
    };
    await testGameStats(gameValues);
  });

  it("dealer moves to 2nd round/flop round", async () => {
    await poker.toggleTurn(1, dealerDeck.slice(0, 3));
    const cards = await poker.showDealerCards(1);
    console.log("dealercards: ", cards);
    gameValues = {
      ...gameValues,
      expectedTurn: 2,
    };
    await testGameStats(gameValues);
  });

  it("players play their 2nd turn actions", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    await poker.connect(player3).dispatch(1, 1, 2, { value: bigBlindAmount });
    await poker.connect(player4).dispatch(1, 2, 2, { value: bigBlindAmount });
    gameValues = {
      ...gameValues,
      expectedPot: gameValues.expectedPot.add(bigBlindAmount.mul(2)),
    };
    await testGameStats(gameValues);
  });

  it("dealer moves the game to the 3rd turn", async () => {
    await poker.toggleTurn(1, [dealerDeck[3]]);
    const dealerCards = await poker.showDealerCards(1);
    gameValues = {
      ...gameValues,
      expectedTurn: 3,
    };
    await testGameStats(gameValues);
  });

  it("player play their 3rd turn actions", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    await poker.connect(player3).dispatch(1, 1, 1, { value: raiseAmount });
    await expect(
      poker.connect(player4).dispatch(1, 2, 2, { value: bigBlindAmount })
    ).to.be.revertedWith("wrong call amount");
    await poker.connect(player4).dispatch(1, 2, 2, { value: raiseAmount });

    gameValues = {
      ...gameValues,
      expectedPot: gameValues.expectedPot.add(raiseAmount.mul(2)),
      expectedCurrentBet: raiseAmount,
    };
    await testGameStats(gameValues);
  });

  it("dealer moves to the last turn", async () => {
    await poker.toggleTurn(1, [dealerDeck[4]]);
    const dealerCards = await poker.showDealerCards(1);
    // console.log("dealercards: ", dealerCards);
    gameValues = {
      ...gameValues,
      expectedTurn: 4,
    };
    await testGameStats(gameValues);
  });

  it("players do their actions for the last turn", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();

    await poker.connect(player3).dispatch(1, 1, 2, { value: raiseAmount });
    await poker.connect(player4).dispatch(1, 2, 2, { value: raiseAmount });
    gameValues = {
      ...gameValues,
      expectedPot: gameValues.expectedPot.add(raiseAmount.mul(2)),
    };
    await testGameStats(gameValues);
  });

  it("dealer ends the game", async () => {
    const [owner, player2, player3, player4] = await ethers.getSigners();
    const hexSalts = Object.values(salts).map((salt) =>
      ethers.utils.formatBytes32String(salt)
    );
    // @ts-ignore
    await poker.endGame(
      1,
      [playerOneDeck, playerTwoDeck, playerThreeDeck],
      // @ts-ignore
      hexSalts
    );
    // const dealerCards = await poker.showDealerCards(1);
    // console.log("dealercards: ", dealerCards);
    // const stats = await poker.showGameStats(1);
    // console.log(stats);
    // console.log(stats.pot.toString());
  });
});
