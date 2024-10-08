# Random

The Origami Random crate is a library that provides pseudo-random generation functionality for Dojo-based games. It offers efficient implementations of random number generation and randomization techniques commonly used in game development.

## Overview

The Random crate focuses on providing random generation primitives that are essential for game development. Its primary scope includes:

- Dice rolling
- Card deck management and shuffling

The crate is designed to work seamlessly with the Dojo engine and other Origami crates.

## Features

### Dice Rolling

- Create dice with customizable face counts
- Generate random rolls based on a seed

### Card Deck Management

- Create decks with a specified number of cards
- Draw cards randomly from the deck
- Discard and withdraw cards from the deck
- Create decks from bitmaps for custom initial states

## Installation

To add the Origami Random crate as a dependency in your project, you need to modify your Scarb.toml file. Add the following to your [dependencies] section:

```toml
[dependencies]
origami_random = { git = "https://github.com/dojoengine/origami" }
```

Make sure you have dojo installed and configured in your project.

## How to use it?

Here are some examples of how to use the Random crate:

### Dice Rolling

To use the dice rolling feature:

```rust
use origami_random::dice::{Dice, DiceTrait};

// Create a new 6-sided dice with a seed
let mut dice = DiceTrait::new(6, 'SEED');

// Roll the dice
let result = dice.roll();
```

### Card Deck Management

To use the card deck management feature:

```rust
use origami_random::deck::{Deck, DeckTrait};

// Create a new deck with 52 cards and a seed
let mut deck = DeckTrait::new('SEED', 52);

// Draw a card from the deck
let card = deck.draw();

// Discard a card back into the deck
deck.discard(card);

// Withdraw a specific card from the deck
deck.withdraw(10);
```

### Advanced usage

Dice and Deck can be used to create more complex randomization mechanics in your game. For example, you can use Dice to determine the outcome of a skill check, or use a Deck to randomly sequence game events.

In the following example, we use the Dice to define the number of mobs to spawn and use the Deck to associate a specifc order to each mob.

```rust
use origami_random::dice::{Dice, DiceTrait};
use origami_random::deck::{Deck, DeckTrait};

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
```

Remember to import the necessary traits and types when using the Random crate in your project.
