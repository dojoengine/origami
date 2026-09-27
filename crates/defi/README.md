# Gradual Dutch Auctions (GDA)

## Introduction

Gradual Dutch Auctions (GDA) enable efficient sales of assets without relying on liquid markets. GDAs offer a novel solution for selling both non-fungible tokens (NFTs) and fungible tokens through discrete and continuous mechanisms.

## Discrete GDA

### Motivation

Discrete GDAs are perfect for selling NFTs in integer quantities. They offer an efficient way to conduct bulk purchases through a sequence of Dutch auctions.

### Mechanism

The process involves holding virtual Dutch auctions for each token, allowing for efficient clearing of batches. Price decay is exponential, controlled by a decay constant, and the starting price increases by a fixed scale factor.

### Calculating Batch Purchase Prices

Calculations can be made efficiently for purchasing a batch of auctions, following a given price function.

## Continuous GDA

### Motivation

Continuous GDAs offer a mechanism for selling fungible tokens, allowing for constant rate emissions over time.

### Mechanism

The process works by incrementally making more assets available for sale, splitting sales into an infinite sequence of auctions. Various price functions, including exponential decay, can be applied.

### Calculating Purchase Prices

It's possible to compute the purchase price for any quantity of tokens gas-efficiently, using specific mathematical expressions.

## Installation

Add the crate from the [scarbs.xyz](https://scarbs.xyz) registry, with the `fixed` package that provides its `Fixed` type:

```sh
scarb add origami_defi@1.8.0
scarb add fixed@0.4.0
```

Values are signed Q32.32 fixed-point numbers (`fixed::Fixed`): the range is `[-2^31, 2^31)` and the resolution is `2^-32`. Only the inputs and the result have to fit: the intermediate products are kept wide. The remaining domain limits are documented on each function (`# Domain`).

## How to Use

### Discrete Gradual Dutch Auction

The `DiscreteGDA` structure represents a Gradual Dutch Auction using discrete time steps. Here's how you can use it:

#### Creating a Discrete GDA

```rust
let gda = DiscreteGDA {
    sold: FixedTrait::from_int(0),
    initial_price: FixedTrait::from_int(100),
    scale_factor: FixedTrait::from_ratio(11, 10), // 1.1
    decay_constant: FixedTrait::from_ratio(1, 2), // 0.5
};
```

#### Calculating the Purchase Price

You can calculate the purchase price for a specific quantity at a given time using the `purchase_price` method.

```rust
let time_since_start = FixedTrait::from_int(2); // 2 days since the start
let quantity = FixedTrait::from_int(5); // Quantity to purchase
let price = gda.purchase_price(time_since_start, quantity);
```

### Continuous Gradual Dutch Auction

The `ContinuousGDA` structure represents a Gradual Dutch Auction using continuous time steps.

#### Creating a Continuous GDA

```rust
let gda = ContinuousGDA {
    initial_price: FixedTrait::from_int(1000),
    emission_rate: ONE,
    decay_constant: FixedTrait::from_ratio(1, 2),
};
```

#### Calculating the Purchase Price

Just like with the discrete version, you can calculate the purchase price for a specific quantity at a given time using the `purchase_price` method.

```rust
let time_since_last = FixedTrait::from_int(1); // 1 day since the last purchase
let quantity = FixedTrait::from_int(3); // Quantity to purchase
let price = gda.purchase_price(time_since_last, quantity);
```

---

These examples demonstrate how to create instances of the `DiscreteGDA` and `ContinuousGDA` structures, and how to utilize their `purchase_price` methods to calculate the price for purchasing specific quantities at given times.

You'll need the `fixed` package in your project to build the `Fixed` values: `use fixed::{FixedTrait, ONE};`.

## Conclusion

GDAs present a powerful tool for selling both fungible and non-fungible tokens in various contexts. They offer efficient, flexible solutions for asset sales, opening doors to innovative applications beyond traditional markets.

# Variable Rate GDAs (VRGDAs)

## Overview

Variable Rate GDAs ([VRGDAs](https://www.paradigm.xyz/2022/08/vrgda)) enable the selling of tokens according to a custom schedule, raising or lowering prices based on the sales pace. VRGDA is a generalization of the GDA mechanism.

## How to Use

### Linear Variable Rate Gradual Dutch Auction (LinearVRGDA)

The `LinearVRGDA` struct represents a linear auction where the price decays based on the target price, decay constant, and per-time-unit rate.

#### Creating a LinearVRGDA instance

```rust
let auction = LinearVRGDA {
    target_price: FixedTrait::from_ratio(6942, 100), // 69.42
    decay_constant: FixedTrait::from_ratio(31, 100), // 0.31
    target_units_per_time: FixedTrait::from_int(2),
};
```

#### Calculating Target Sale Time

```rust
let target_sale_time = auction.get_target_sale_time(sold_quantity);
```

#### Calculating VRGDA Price

```rust
let price = auction.get_vrgda_price(time_since_start, sold_quantity);
```

### Logistic Variable Rate Gradual Dutch Auction (LogisticVRGDA)

The `LogisticVRGDA` struct represents an auction where the price decays according to a logistic function, based on the target price, decay constant, max sellable quantity, and time scale.

#### Creating a LogisticVRGDA instance

```rust
let auction = LogisticVRGDA {
    target_price: FixedTrait::from_ratio(6942, 100), // 69.42
    decay_constant: FixedTrait::from_ratio(31, 100), // 0.31
    max_sellable: FixedTrait::from_int(6392),
    time_scale: FixedTrait::from_ratio(23, 10000), // 0.0023
};
```

#### Calculating Target Sale Time

```rust
let target_sale_time = auction.get_target_sale_time(sold_quantity);
```

#### Calculating VRGDA Price

```rust
let price = auction.get_vrgda_price(time_since_start, sold_quantity);
```

Make sure to import the required dependencies at the beginning of your Cairo file:

```rust
use fixed::{Fixed, FixedTrait};
```

These examples show you how to create instances of both `LinearVRGDA` and `LogisticVRGDA` and how to use their methods to calculate the target sale time and VRGDA price.

## Conclusion

VRGDAs offer a flexible way to issue NFTs on nearly any schedule, enabling seamless purchases at any time.
