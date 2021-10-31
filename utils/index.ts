export type TCard = {
  value: number;
  suit: number;
};
export type TDeck = TCard[];
const pokerDeck = Object.freeze([
  // clubs
  { value: 0, suit: 0 },
  { value: 1, suit: 0 },
  { value: 2, suit: 0 },
  { value: 3, suit: 0 },
  { value: 4, suit: 0 },
  { value: 5, suit: 0 },
  { value: 6, suit: 0 },
  { value: 7, suit: 0 },
  { value: 8, suit: 0 },
  { value: 9, suit: 0 },
  { value: 10, suit: 0 },
  { value: 11, suit: 0 },
  { value: 12, suit: 0 },
  // diamonds
  { value: 0, suit: 1 },
  { value: 1, suit: 1 },
  { value: 2, suit: 1 },
  { value: 3, suit: 1 },
  { value: 4, suit: 1 },
  { value: 5, suit: 1 },
  { value: 6, suit: 1 },
  { value: 7, suit: 1 },
  { value: 8, suit: 1 },
  { value: 9, suit: 1 },
  { value: 10, suit: 1 },
  { value: 11, suit: 1 },
  { value: 12, suit: 1 },
  // hearts
  { value: 0, suit: 2 },
  { value: 1, suit: 2 },
  { value: 2, suit: 2 },
  { value: 3, suit: 2 },
  { value: 4, suit: 2 },
  { value: 5, suit: 2 },
  { value: 6, suit: 2 },
  { value: 7, suit: 2 },
  { value: 8, suit: 2 },
  { value: 9, suit: 2 },
  { value: 10, suit: 2 },
  { value: 11, suit: 2 },
  { value: 12, suit: 2 },
  // spades
  { value: 0, suit: 3 },
  { value: 1, suit: 3 },
  { value: 2, suit: 3 },
  { value: 3, suit: 3 },
  { value: 4, suit: 3 },
  { value: 5, suit: 3 },
  { value: 6, suit: 3 },
  { value: 7, suit: 3 },
  { value: 8, suit: 3 },
  { value: 9, suit: 3 },
  { value: 10, suit: 3 },
  { value: 11, suit: 3 },
  { value: 12, suit: 3 },
]);

export default pokerDeck;
