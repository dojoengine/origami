# Hexmap

The Origami Hexmap crate provides hexagonal tile maps for Dojo-based games: generation,
pathfinding and range queries on bitmaps packed in a single `felt252`. It is the hexagonal sibling
of [`origami_map`](../map) and mirrors its `Map` API name for name.

Every operation is bit-parallel: a whole board is processed by a few field products and bitwise
operations per step, so a 17x14 cave, its entrance, 10 objects and a path cost about 1.14M gas,
more than 100 times less than the same scenario on `origami_map` (see [Gas](#gas)).

## Installation

```sh
scarb add origami_hexmap@1.8.0
```

Or from git, in your `[dependencies]`:

```toml
[dependencies]
origami_hexmap = { git = "https://github.com/dojoengine/origami", tag = "v1.8.0" }
```

## Conventions

### Index

Pointy-top tiles, odd-r offset, row-major: tile `(x, y)` is bit `i = y * W + x` of the grid, `1`
is walkable. Bit 0 is drawn bottom-right, `+1` is West and `+W` is North, like `origami_map`. Odd
rows are shifted half a tile toward increasing `x` (to the left in the drawings). A 5x5 board:

```text
  24  23  22  21  20      y = 4
19  18  17  16  15        y = 3
  14  13  12  11  10      y = 2
09  08  07  06  05        y = 1
  04  03  02  01  00      y = 0
```

This is `HexPrinter`'s layout: top row first, `x = 0` on the right, even rows indented.

### Directions

```text
      NorthWest   NorthEast
  West        tile        East
      SouthWest   SouthEast
```

| Direction | even row    | odd row     |
|-----------|-------------|-------------|
| East      | `i - 1`     | `i - 1`     |
| NorthEast | `i + W - 1` | `i + W`     |
| NorthWest | `i + W`     | `i + W + 1` |
| West      | `i + 1`     | `i + 1`     |
| SouthWest | `i - W`     | `i - W + 1` |
| SouthEast | `i - W - 1` | `i - W`     |

### Border ring and entrances

- **The outer ring is always wall** for the generators (border invariant). Under this invariant,
  every neighbour shift is an exact field multiplication, which is what makes the library cheap.
- **Open edge tiles are entrances.** `open_with_corridor` and `open_with_maze` open one edge tile
  (not a corner) and dig inward. A path may start or end on an open edge tile but never crosses
  one; `reachable`, `range`, `ring` and `field_of_movement` include the open edge tiles on which a
  path can end. `compute_distribution` treats them as any walkable tile.
- `HexMapTrait::new` accepts any grid, but the finders and generators assume the border ring is
  wall except for such entrances.

### Limits

- `W, H >= 3` and `W * H <= 251`, for example 17x14, 16x15, 19x13, 25x10 or 7x7. Boards of at most
  128 tiles run on a single `u128` limb, about a third cheaper per step.
- Positions are `u8`.
- **Hexagons** of radius `R <= 6` fit in a `(2R + 3) x (2R + 3)` rectangle (`new_hexagon`).
- **Flat-top** maps need no code: a flat-top odd-q map with `C` columns and `R` rows is the
  pointy-top map with `W = R`, `H = C`, tile `(col, row)` at index `col * W + row` (transpose).
- **Distance**: `q = x - floor(y / 2)`, `r = y`, `d = max(|dq|, |dr|, |dq + dr|)`.

## Usage

```rust
use origami_hexmap::{Direction, HexMap, HexMapTrait};
```

`HexMap { width, height, grid, seed }` is `Copy`, `Drop` and `Serde`; store `grid` as a `felt252`.
The names follow the Rust crate [`hexx`](https://docs.rs/hexx) where they apply (`distance_to`,
`range`, `ring`, `field_of_movement`, `neighbor`) to ease a later migration.

### Create a map

```rust
// From an existing grid (no check)
let map = HexMapTrait::new(grid, 17, 14, seed);
// Every interior tile walkable
let map = HexMapTrait::new_empty(17, 14, seed);
// A maze, order 0 (dense) or 1 (sparse, walls at least 2 thick)
let map = HexMapTrait::new_maze(17, 14, 0, seed);
// A cave: cellular automaton B4/S2, `order` generations, 3 is a good default
let map = HexMapTrait::new_cave(17, 14, 3, seed);
// A random walk of `steps` steps from a random interior tile
let map = HexMapTrait::new_random_walk(17, 14, 500, seed);
// A hexagon of radius 4 in a 11x11 board
let map = HexMapTrait::new_hexagon(4, seed);
```

### Open a map

```rust
let mut map = HexMapTrait::new_cave(17, 14, 3, seed);
// Keep the cave connected to tile 113 (flood fill)
map.keep_component(113);
// Dig a corridor from the edge tile 8 until it touches an open tile
map.open_with_corridor(8, 0);
// Or grow a maze from an edge tile, merged with the open tiles it touches
map.open_with_maze(8, 0);
```

The digger stops (corridor) or merges (maze) as soon as a dug tile touches an open tile: on hexes,
touching means connected.

### Place objects

```rust
// 10 distinct walkable tiles, uniform, as a bitmap
let objects: felt252 = map.compute_distribution(10, seed);
```

### Find paths

```rust
// Shortest path, from the target (included) to the start (excluded), empty if unreachable
let path: Span<u8> = map.search_path(8, 202);
// Number of steps only, `None` if unreachable
let steps: Option<u8> = map.distance_to(8, 202);
// Distance on an empty board, walls ignored
let d: u8 = map.hex_distance(8, 202);
// Cheapest path with entry costs
let costs = array![swamps, mountains].span();
let path: Span<u8> = map.search_path_weighted(8, 202, costs);
```

**Cost classes.** `costs[k]` is the bitmap of the tiles whose entry costs `k + 2`, with at most 3
classes; every other walkable tile costs 1. A tile in several bitmaps takes the highest cost. The
cost is paid on entering a tile, so the start is free. With `costs` empty, the weighted search is a
plain BFS.

### Query areas

```rust
// Every tile reachable from 113
let component: felt252 = map.reachable(113);
// Tiles within 4 steps (walls block), 113 included
let area: felt252 = map.range(113, 4);
// Tiles at exactly 4 steps
let ring: felt252 = map.ring(113, 4);
// Tiles reachable with a movement budget of 6 under the cost classes
let moves: felt252 = map.field_of_movement(113, 6, costs);
// Neighbour, `None` outside the board
let next: Option<u8> = map.neighbor(113, Direction::NorthEast);
let open: bool = map.is_walkable(113);
```

### Panics

| Message | When |
|---|---|
| `Asserter: invalid dimension` | `W < 3`, `H < 3` or `W * H > 251` (constructors, digger, finders, spreader); `new_hexagon` with a radius above 6 |
| `Asserter: position not inside` | a finder endpoint or a `ring` / `range` centre outside the board |
| `Asserter: position not an edge` | `open_with_*` from a tile that is not on the edge |
| `Asserter: position is a corner` | `open_with_*` from a corner |
| `Mazer: order > 1 not supported` | `new_maze` or `open_with_*` with an order above 1 |
| `Bfs: position not walkable` | `search_path`, `distance_to`, `reachable`, `range`, `ring` or `keep_component` from or to a wall |
| `Dial: position not walkable` | `search_path_weighted` or `field_of_movement` from or to a wall |
| `Dial: too many costs` | more than 3 cost classes |
| `Spreader: not enough place` | `compute_distribution` with more objects than walkable tiles |
| `Spreader: invalid grid` | `compute_distribution` on a grid with a walkable bit outside the board |

`search_path` returns an empty path when the target is unreachable and when `from == to`;
`distance_to` returns `None` and `Some(0)` respectively. `hex_distance`, `neighbor` and
`is_walkable` do not check their positions.

**Endpoints on walls panic.** This differs from `origami_map`, whose `search_path` returns an
empty path when the start or the target is a wall. In `origami_hexmap` an empty path only means
"unreachable" (or `from == to`); test `is_walkable` first if an endpoint may be a wall.

## Randomness and determinism

- **Deterministic.** A seed gives the same map, the same objects and the same walk for a given
  package version: the generators draw from a Poseidon stream of the seed only (no block data, no
  caller). Store the seed, not the grid, when the version is pinned.
- **Streams are part of the API from 1.8.0 on.** Each generator (`new_maze`, `new_cave`,
  `new_random_walk`, `open_with_corridor`, `open_with_maze`, `compute_distribution`) has a test
  pinning the exact grid of one seed; a change of those outputs is a breaking change.
- **Bias.** The internal `Rng` draws bounded integers from a 128-bit pool (one Poseidon
  permutation) refilled below 2^64: the draws of one pool are within `2^-56` of independent
  uniform draws for bounds up to 251 (`2^-54.5` for a shuffle of 6). `compute_distribution` is
  uniform over the `count`-subsets of the walkable tiles up to these sources (its Poseidon key
  words add `< 2^-51.3` per call, see `GAS.md`, L7).
- **Not a secret.** The seed decides everything: use a commit-reveal scheme or a VRF for the
  seed when players must not predict the map (see `origami_security`).

## Gas

Sierra gas measured by snforge 0.61.0 (scarb 2.19.4) in [`bench_map.cairo`](https://github.com/dojoengine/origami/blob/main/crates/hexmap/src/tests/bench_map.cairo),
each test including a ~14k test baseline. The facade adds no gas over the library call it forwards
to (identical or lower figures on every function). Details and the per-lot measurements:
[GAS.md](https://github.com/dojoengine/origami/blob/main/crates/hexmap/GAS.md) (in the repository,
not in the package).

| Function | Input | Gas |
|---|---|---:|
| `new_empty` | 17x14 | 18k |
| `new_maze` | 17x14, order 0 (90 tiles carved) | 2.90M |
| `new_cave` | 17x14, order 3 | 142k |
| `new_cave` | 7x7, order 3 | 81k |
| `new_random_walk` | 17x14, 200 steps | 969k (~4.8k per step) |
| `new_hexagon` | radius 6 | 126k |
| `open_with_corridor` | 17x14 cave, entrance 8 | 63k |
| `keep_component` / `reachable` | 17x14 cave / maze | 536k / 1.11M |
| `keep_component` / `reachable` | 7x7 cave | 98k |
| `compute_distribution` | 17x14 cave, 10 objects | 193k |
| `search_path` | 17x14 cave, 24 steps | 706k |
| `search_path` | 7x7, 6 steps | 132k |
| `distance_to` | 17x14 cave, 24 steps | 502k |
| `search_path_weighted` | 17x14 cave, 2 cost classes | 1.41M |
| `field_of_movement` | 17x14 cave, budget 6, 2 classes | 254k |
| `range` | 17x14 cave, radius 4 | 104k |
| `ring` | 17x14 cave, radius 4 | 100k |
| `ring` | 7x7 cave, radius 2 | 46k |
| `hex_distance` | per call | 9.5k |
| `neighbor` | per call | 6.4k |
| `is_walkable` | per call | 6.5k |

Rules of thumb: a BFS layer costs ~19k on a two-limb board and ~10k on a single-limb board, a
backtracking step ~8k; a weighted time step ~37k with 2 cost classes.

### End-to-end scenario

`new_cave(order 3)` + `keep_component` + `open_with_corridor` + `compute_distribution(10)` +
`search_path` from the entrance, against the same scenario on `origami_map` 18x14 (which has no
`keep_component`; cairo-test estimate).

| Step | hexmap 17x14 | hexmap 7x7 | origami_map 18x14 |
|---|---:|---:|---:|
| `new_cave` | 142k | 81k | 126.0M |
| `keep_component` | 182k | 55k | - |
| `open_with_corridor` | 161k | 48k | 60k |
| `compute_distribution(10)` | 177k | 111k | 8.96M |
| `search_path` | 476k (15 steps) | 177k (6 steps) | 10.77M (25 steps) |
| **Total** | **1.14M** | **471k** | **145.8M** |

## Bitmaps and `u252`

Grids and every bitmap in the API are `felt252`: free to store, to serialize and to pass around.
The crate also exports `u252`, an unsigned integer held in one `felt252` (every felt is a valid
`u252`, value set `[0, P - 1]`):

```rust
use origami_hexmap::{U252Trait, u252};

let objects: u252 = map.compute_distribution(10, seed).into(); // free
let raw: felt252 = objects.into(); // free
```

Use it for counters and stored values that are felts on the wire: conversions, `Serde`,
`StorePacking`, `==`, wrapping arithmetic and exact shifts cost nothing or less than `u256`.
Keep `u256` (or the felt bitmaps as they are) for set operations and comparisons: `&`, `|`, `^`,
`<` and checked `+` / `-` split the felt into two limbs first and cost 2x to 3x the `u256`
operation (checked add 4.2k vs 1.9k, `&` 6.1k vs 2.4k).

## Migration from `origami_map::hex`

`origami_map::hex::Hex { col, row }` is a coordinate pair without a board. In `origami_hexmap`, a
tile is an index on a board with a wall ring:

- `Hex { col, row }` becomes `LayoutTrait::index(W, col + 1, row + 2)`: one column and two rows of
  margin keep the wall ring and the row parity. Both crates shift odd rows toward increasing
  `col` / `x`, so the neighbour sets are the same.
- Direction names do not carry over: `origami_map::hex` labels the vertical neighbours differently
  on even and odd rows (`NorthEast` is `row - 1` on odd rows and `row + 1` on even rows). Convert
  positions, then use the direction table above.
- `hex.neighbors()` becomes six `neighbor` calls, or the bitmap `layout.neighbour_mask(index)`.
- `hex.tiles_within_range(range)` (an `Array<Hex>`, walls ignored) becomes `map.range(index, range)`
  (a bitmap, walls respected); on an empty board they hold the same tiles, as long as they stay
  inside the board.
- `hex.is_neighbor(other)` becomes `map.hex_distance(a, b) == 1`.

## Tests

```sh
scarb test -p origami_hexmap   # runs snforge
```
