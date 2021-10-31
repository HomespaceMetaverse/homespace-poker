//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

library LibCard {
    // Values of Cards
	enum CardValue { Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King, Ace }
	// Suits of Cards
	enum CardSuit { Clubs, Diamonds, Hearts, Spades }

    // Card structure
    struct Card {
        CardValue value;
        CardSuit suit;
    }

    // Calculates hash of the Card with provided salt
    function getHash(Card memory _self, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                _self.value,
                _self.suit,
                _salt
            )
        );
    }

    // Verifies that Card hash with provided salt is valid
    function verifyCardHash(Card memory _self, bytes32 _salt, bytes32 _hash) internal pure returns (bool) {
        return getHash(_self, _salt) == _hash;
    }
}

// SAVE ALL THE DIFFERENT COMBINATIONS OF VALUABLE HANDS
