# Hexmap

The Origami Hexmap crate provides hexagonal tile maps for Dojo-based games: generation,
pathfinding and range queries on bitmaps packed in a single `felt252`.

> Status: foundation. The primitives (layout, bits, geometry, random pool) are implemented and
> benchmarked; finders, generators and the `HexMap` facade are stubs that panic with
> `unimplemented` until their lots land.

## Conventions

- **Pointy-top, odd-r offset, row-major**: tile `(x, y)` is bit `i = y * W + x`, `1` is walkable.
  Bit 0 is printed bottom-right, `+1` is West and `+W` is North, like `origami_map`. Odd rows are
  shifted half a tile toward increasing `x`.
- **Neighbours** (`p` = row parity):

  | Direction | even row    | odd row     |
  |-----------|-------------|-------------|
  | East      | `i - 1`     | `i - 1`     |
  | NorthEast | `i + W - 1` | `i + W`     |
  | NorthWest | `i + W`     | `i + W + 1` |
  | West      | `i + 1`     | `i + 1`     |
  | SouthWest | `i - W`     | `i - W + 1` |
  | SouthEast | `i - W - 1` | `i - W`     |

- **Limits**: `W, H >= 3` and `W * H <= 251`, for example 17x14, 16x15, 19x13 or 25x10. The outer
  ring is wall for every bit-parallel operation (border invariant). Under this invariant, every
  neighbour shift is an exact field multiplication.
- **Flat-top** maps need no code: a flat-top odd-q map with `C` columns and `R` rows is the
  pointy-top map with `W = R`, `H = C`, tile `(col, row)` at index `col * W + row`.
- **Hexagons** of radius `R <= 6` fit in a `(2R + 3) x (2R + 3)` rectangle
  (`LayoutTrait::hexagon`).
- **Distance**: `q = x - floor(y / 2)`, `r = y`, `d = max(|dq|, |dr|, |dq + dr|)`.

## Gas

Every benchmark carries an `#[available_gas(l2_gas: N)]` budget. See [GAS.md](./GAS.md) for the
measurements and for the procedure to record budgets.

## Tests

```sh
scarb test -p origami_hexmap   # runs snforge
```
