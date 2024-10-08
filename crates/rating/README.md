# Rating

The Origami Rating crate is a library that provides rating-related algorithms for Dojo-based games. It offers efficient implementations of rating systems commonly used in game development and competitive matchmaking.

## Overview

The Rating crate focuses on providing rating algorithms that are essential for game development, particularly for competitive games. Its primary scope includes:

- Elo rating system implementation

The crate is designed to work seamlessly with the Dojo engine and other Origami crates.

## Features

### Elo Rating System

- Calculate rating changes based on game outcomes
- Support for different K-factors
- Handling of wins, losses, and draws

## Installation

To add the Origami Rating crate as a dependency in your project, you need to modify your Scarb.toml file. Add the following to your [dependencies] section:

```toml
[dependencies]
origami_rating = { git = "https://github.com/dojoengine/origami" }
```

Make sure you have dojo installed and configured in your project.

## How to use it?

Here are some examples of how to use the Rating crate:

### Elo rating system

This example demonstrates how to calculate and apply a rating change using the Elo system. The rating_change function takes the current ratings of both players, the game outcome, and the K-factor as inputs. It returns the magnitude of the rating change and a boolean indicating whether the change is negative.

```rust
use origami_rating::elo::EloTrait;

// Calculate rating change for player A
let (change, is_negative) = EloTrait::rating_change(
    1200_u64,  // Player A's current rating
    1400_u64,  // Player B's current rating
    100_u16,   // Outcome (100 = win, 50 = draw, 0 = loss)
    20_u8      // K-factor
);

// Apply the rating change
let new_rating_a = if is_negative {
    1200 - change
} else {
    1200 + change
};

println!("Player A's new rating: {}", new_rating_a);
```

Remember to import the necessary traits and types when using the Rating crate in your project.
