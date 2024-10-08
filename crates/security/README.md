# Security

The Origami Security crate is a library that provides security-related primitives for Dojo-based games. It offers implementations of common security patterns and utilities to enhance the safety and integrity of game development on the Dojo framework.

## Overview

The Security crate focuses on providing fundamental security mechanisms that are essential for game development. Its primary scope includes:

- Commitment schemes

The crate is designed to work seamlessly with the Dojo engine and other Origami crates.

## Features

### Commitment schemes

A Commitment is a cryptographic primitive that allows you to commit to a chosen value while keeping it hidden, with the ability to reveal it later. This is useful in scenarios where you want to make a binding commitment to a value, meaning that once a commitment is made, it cannot be changed or altered.

Features of the Commitment implementation include:

- Creation of new commitments
- Committing to a hash value
- Revealing and verifying committed values

## Installation

To add the Origami Security crate as a dependency in your project, you need to modify your Scarb.toml file. Add the following to your [dependencies] section:

```toml
[dependencies]
origami_security = { git = "https://github.com/dojoengine/origami" }
```

Make sure you have dojo installed and configured in your project.

## How to use it?

Here are some examples of how to use the Security crate:

### Commit/Reveal

```rust
use origami_security::commitment::{Commitment, CommitmentTrait};

// Create a new commitment
let mut commitment = CommitmentTrait::new();

// Commit to a value (in this case, a string)
let value = 'secret';
let mut serialized = array![];
value.serialize(ref serialized);
let hash = poseidon_hash_span(serialized.span());
commitment.commit(hash);

// Later, reveal and verify the commitment
let is_valid = commitment.reveal('secret');
assert(is_valid, 'Invalid reveal for commitment');
```

Remember to import the necessary traits and types when using the Security crate in your project.
