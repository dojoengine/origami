//! The examples of `README.md`, compiled against the public API.

use origami_random::deck::{Deck, DeckTrait};
use origami_random::dice::{Dice, DiceTrait};

#[test]
fn test_readme_dice() {
    // Create a new 6-sided dice with a seed
    let mut dice: Dice = DiceTrait::new(6, 'SEED');
    // Roll the dice
    let result = dice.roll();
    assert!(result >= 1 && result <= 6);
}

#[test]
fn test_readme_deck() {
    // Create a new deck with 52 cards and a seed
    let mut deck: Deck = DeckTrait::new('SEED', 52);
    // Draw a card from the deck
    let card = deck.draw();
    // Discard a card back into the deck
    deck.discard(card);
    // Withdraw a specific card from the deck
    deck.withdraw(10);
    assert!(deck.remaining == 51);
}

#[test]
fn test_readme_advanced() {
    // Spawn 1 to 6 mobs
    let mut dice = DiceTrait::new(6, 'SEED');
    let mut count = dice.roll();
    // Create a deck with the same number of cards as the number of mobs
    let mut deck = DeckTrait::new('SEED', count.into());
    // Draw each mob from the deck and create an array of mob ids
    let mut mob_ids: Array<u8> = array![];
    while count > 0 {
        let mob_id = deck.draw();
        mob_ids.append(mob_id);
        count -= 1;
    }
    assert!(mob_ids.len() >= 1);
}
