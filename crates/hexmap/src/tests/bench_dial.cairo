//! Gas benchmarks of lot L3, weighted Dial: one `#[test]` per fixture and algorithm, each with an
//! `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! Correctness oracle: a scalar Dijkstra (`dijkstra`), test-only. The losing formulations live
//! here too.

// Core imports

use core::dict::Felt252Dict;
use core::integer::Bitwise;

// Internal imports

use origami_hexmap::finders::dial::Dial;
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::helpers::rng::RngTrait;
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::Variants;
use origami_hexmap::types::direction::Direction;

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Repetitions of the microbenchmarks.
const REPS: u8 = 100;

/// AND, XOR and OR of two limbs in one builtin application, see `generators::caver`.
extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

/// Distance of an unreachable tile.
pub const UNREACHABLE: u32 = 0xffffffff;

// Cost maps of the benchmarks (generated offline, endpoints of the far pairs excluded).

/// EMPTY_17X14: 2 classes over 30 % of the floor (35 tiles cost 2, 18 cost 3); with `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (21, 18 and 14 tiles).
pub const EMPTY_17X14_COST_2: felt252 = 0x48000000005184004970051110b010190401408122000020280000;
pub const EMPTY_17X14_COST_3: felt252 = 0x8005003708000000000888000000000020030040800080000000;
pub const EMPTY_17X14_CLASS_2: felt252 = 0x40000000001084000010051110a000110001408120000020080000;
pub const EMPTY_17X14_CLASS_4: felt252 = 0x80000000041000049600000001010080400000002000000200000;
/// CAVE_17X14: 2 classes over 30 % of the floor (25 tiles cost 2, 13 cost 3); with `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (15, 13 and 10 tiles).
pub const CAVE_17X14_COST_2: felt252 = 0x44002200043402000b4003041000000000104018082400001000000;
pub const CAVE_17X14_COST_3: felt252 = 0x1080011400000040000000180000080000008200100000000800000;
pub const CAVE_17X14_CLASS_2: felt252 = 0x400220004240200084001000000000000000018002400001000000;
pub const CAVE_17X14_CLASS_4: felt252 = 0x4000000000100000030002041000000000104000080000000000000;
/// MAZE_17X14: 2 classes over 30 % of the floor (18 tiles cost 2, 9 cost 3); with `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (10, 9 and 8 tiles).
pub const MAZE_17X14_COST_2: felt252 = 0x4008000000c0000000080040002000002004006041000a002300000;
pub const MAZE_17X14_COST_3: felt252 = 0x200020008000000010080000000000004001000000420000000000;
pub const MAZE_17X14_CLASS_2: felt252 = 0x4008000000c00000000000400020000020040020000000002000000;
pub const MAZE_17X14_CLASS_4: felt252 = 0x80000000000000000004041000a000300000;
/// SERPENTINE_17X14: 2 classes over 30 % of the floor (18 tiles cost 2, 9 cost 3); with `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (11, 9 and 7 tiles).
pub const SERPENTINE_17X14_COST_2: felt252 = 0x148200000612080004010000000440000000000000888300000;
pub const SERPENTINE_17X14_COST_3: felt252 = 0x20000000000000000004000004200000002100000006800000;
pub const SERPENTINE_17X14_CLASS_2: felt252 = 0x100200000210080000010000000400000000000000888100000;
pub const SERPENTINE_17X14_CLASS_4: felt252 = 0x48000000402000004000000000040000000000000000200000;
/// UNREACHABLE_17X14: 2 classes over 30 % of the floor (32 tiles cost 2, 17 cost 3); with
/// `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (19, 17 and 13 tiles).
pub const UNREACHABLE_17X14_COST_2: felt252 =
    0x100404300d940184000580c4004800000000c000220802141100000;
pub const UNREACHABLE_17X14_COST_3: felt252 =
    0x20044000014000040412000000100a000000a000004800080000;
pub const UNREACHABLE_17X14_CLASS_2: felt252 = 0x42005940104000480840008000000000000200800101100000;
pub const UNREACHABLE_17X14_CLASS_4: felt252 =
    0x100400100800008000010040004000000000c000020002040000000;
/// CAVE_7X7: 2 classes over 30 % of the floor (4 tiles cost 2, 2 cost 3); with `_CLASS_2`
/// and `_CLASS_4` instead of `_COST_2`: 3 classes (2, 2 and 2 tiles).
pub const CAVE_7X7_COST_2: felt252 = 0x281000800;
pub const CAVE_7X7_COST_3: felt252 = 0x30000;
pub const CAVE_7X7_CLASS_2: felt252 = 0x80000800;
pub const CAVE_7X7_CLASS_4: felt252 = 0x201000000;

// Oracle

/// The 6 directions, fixed order.
pub fn directions() -> Span<Direction> {
    array![
        Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
        Direction::SouthWest, Direction::SouthEast,
    ]
        .span()
}

/// Entry cost of a tile: 1, or `k + 2` for the highest class `k` holding it.
pub fn tile_cost(costs: Span<felt252>, position: u8) -> u32 {
    let mut cost: u32 = 1;
    let mut index: u32 = 0;
    while index != costs.len() {
        if Bits::get((*costs[index]).into(), position) {
            cost = index + 2;
        }
        index += 1;
    }
    cost
}

/// Whether a tile lies on the outer ring.
pub fn is_edge(width: u8, height: u8, position: u8) -> bool {
    let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
    Asserter::is_edge(width, height, x, y)
}

/// Whether two tiles are neighbours.
pub fn adjacent(width: u8, height: u8, lhs: u8, rhs: u8) -> bool {
    for direction in directions() {
        if LayoutTrait::neighbor(width, height, lhs, *direction) == Option::Some(rhs) {
            return true;
        }
    }
    false
}

/// Scalar Dijkstra (linear scan of an open list, lazy deletion): cheapest entry cost of every
/// tile of the board from `from`, `UNREACHABLE` if none. Edge tiles other than `from` are
/// reached but never expanded.
pub fn dijkstra(grid: felt252, width: u8, height: u8, from: u8, costs: Span<felt252>) -> Span<u32> {
    let open: u256 = grid.into();
    let size = width * height;
    // Stored as distance + 1, 0 is unknown
    let mut dist: Felt252Dict<u32> = Default::default();
    dist.insert(from.into(), 1);
    let mut settled: u256 = 0;
    let mut queue: Array<(u8, u32)> = array![(from, 0)];
    while queue.len() != 0 {
        // Pop the cheapest entry
        let items = queue.span();
        let mut best: u32 = 0;
        let mut index: u32 = 1;
        while index != items.len() {
            let (_, lhs) = *items[index];
            let (_, rhs) = *items[best];
            if lhs < rhs {
                best = index;
            }
            index += 1;
        }
        let (position, distance) = *items[best];
        let mut rest: Array<(u8, u32)> = array![];
        let mut index: u32 = 0;
        while index != items.len() {
            if index != best {
                rest.append(*items[index]);
            }
            index += 1;
        }
        queue = rest;
        if Bits::get(settled, position) {
            continue;
        }
        settled = settled | Bits::pow(position).into();
        if position != from && is_edge(width, height, position) {
            continue;
        }
        for direction in directions() {
            if let Option::Some(next) = LayoutTrait::neighbor(width, height, position, *direction) {
                if Bits::get(open, next) && !Bits::get(settled, next) {
                    let candidate = distance + tile_cost(costs, next);
                    let known = dist.get(next.into());
                    if known == 0 || candidate + 1 < known {
                        dist.insert(next.into(), candidate + 1);
                        queue.append((next, candidate));
                    }
                }
            }
        }
    }
    let mut result: Array<u32> = array![];
    let mut position: u8 = 0;
    while position != size {
        let value = dist.get(position.into());
        result.append(if value == 0 {
            UNREACHABLE
        } else {
            value - 1
        });
        position += 1;
    }
    result.span()
}

/// Check a path returned by `search` against the oracle distance of the target.
pub fn check_path(
    grid: felt252,
    width: u8,
    height: u8,
    from: u8,
    to: u8,
    costs: Span<felt252>,
    path: Span<u8>,
    expected: u32,
) {
    if expected == UNREACHABLE || from == to {
        assert!(path.len() == 0, "path must be empty");
        return;
    }
    let open: u256 = grid.into();
    assert!(path.len() != 0, "path must not be empty");
    assert!(*path[0] == to, "path must start at the target");
    let mut total: u32 = 0;
    let mut index: u32 = 0;
    while index != path.len() {
        let position = *path[index];
        assert!(Bits::get(open, position), "path tile must be walkable");
        if index != 0 {
            assert!(!is_edge(width, height, position), "path crosses an edge tile");
        }
        let previous = if index + 1 == path.len() {
            from
        } else {
            *path[index + 1]
        };
        assert!(adjacent(width, height, position, previous), "path tiles must be adjacent");
        total += tile_cost(costs, position);
        index += 1;
    }
    assert!(total == expected, "path cost {} != oracle {}", total, expected);
}

/// Oracle field of movement: tiles of distance at most `budget`.
pub fn field_oracle(distances: Span<u32>, budget: u8) -> felt252 {
    let mut field: felt252 = 0;
    let mut position: u8 = 0;
    let budget: u32 = budget.into();
    while position.into() != distances.len() {
        if *distances[position.into()] <= budget {
            field += Bits::pow(position);
        }
        position += 1;
    }
    field
}

/// Pseudo-random cost classes over a grid: `count` classes, each about 12.5 % of the tiles.
pub fn random_costs(
    grid: felt252, width: u8, height: u8, seed: felt252, count: u32,
) -> Span<felt252> {
    let board: u256 = LayoutTrait::board(width, height).into();
    let r1: u256 = Bits::to_felt(RngTrait::mix(seed, 1).into() & board).into();
    let r2: u256 = Bits::to_felt(RngTrait::mix(seed, 2).into() & board).into();
    let r3: u256 = Bits::to_felt(RngTrait::mix(seed, 3).into() & board).into();
    let r4: u256 = Bits::to_felt(RngTrait::mix(seed, 4).into() & board).into();
    let grid: u256 = grid.into();
    let mut costs: Array<felt252> = array![];
    if count >= 1 {
        costs.append(Bits::to_felt(grid & r1 & r2 & r3));
    }
    if count >= 2 {
        costs.append(Bits::to_felt(grid & r1 & r2 & ~r3));
    }
    if count >= 3 {
        // Overlaps the first two: the highest class wins
        costs.append(Bits::to_felt(grid & r4 & r1 & ~r2));
    }
    costs.span()
}

/// Check `search` against the oracle from one start to every `stride`-th walkable tile, and
/// `field_of_movement` for a few budgets.
pub fn check_all(grid: felt252, width: u8, height: u8, from: u8, costs: Span<felt252>, stride: u8) {
    let distances = dijkstra(grid, width, height, from, costs);
    let open: u256 = grid.into();
    let size = width * height;
    let mut to: u8 = 0;
    let mut skip: u8 = 0;
    while to != size {
        if Bits::get(open, to) {
            if skip == 0 {
                let path = Dial::search(grid, width, height, from, to, costs);
                check_path(grid, width, height, from, to, costs, path, *distances[to.into()]);
                skip = stride;
            }
            skip -= 1;
        }
        to += 1;
    }
    for budget in array![0_u8, 1, 2, 3, 5, 8, 13].span() {
        let field = Dial::field_of_movement(grid, width, height, from, *budget, costs);
        assert!(field == field_oracle(distances, *budget), "field of movement {}", *budget);
    }
}

/// Unit costs: path length equal to the scalar BFS of `tests/variants.cairo`.
pub fn check_unit(grid: felt252, width: u8, height: u8, from: u8, to: u8, distance: u32) {
    let path = Dial::search(grid, width, height, from, to, array![].span());
    assert!(path.len() == distance, "unit path {} != bfs {}", path.len(), distance);
    assert!(Variants::bfs_distance(grid, width, height, from, to) == distance);
    let expected = if distance == 0 {
        UNREACHABLE
    } else {
        distance
    };
    check_path(grid, width, height, from, to, array![].span(), path, expected);
}

// Harness: copies of the library building blocks, for the microbenchmarks and the variants

/// Library dilation intersected with a set (bitwise triple per limb).
#[inline(always)]
pub fn expand_triple(layout: @Layout, frontier: u256, unvisited: u256) -> u256 {
    let layout = *layout;
    let felt = Bits::to_felt(frontier);
    let double: u256 = (felt + felt).into();
    let (_, _, pairs_low) = bitwise(frontier.low, double.low);
    let (_, _, pairs_high) = bitwise(frontier.high, double.high);
    let (even_low, _, _) = bitwise(pairs_low, layout.even.low);
    let (even_high, _, _) = bitwise(pairs_high, layout.even.high);
    let pairs_even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
    let pairs_odd: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128 - pairs_even;
    let up: u256 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd).into();
    let down: u256 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd).into();
    let east: u256 = (felt * INV_2).into();
    let (_, _, low) = bitwise(pairs_low, east.low);
    let (_, _, low) = bitwise(low, up.low);
    let (_, _, low) = bitwise(low, down.low);
    let (low, _, _) = bitwise(low, unvisited.low);
    let (_, _, high) = bitwise(pairs_high, east.high);
    let (_, _, high) = bitwise(high, up.high);
    let (_, _, high) = bitwise(high, down.high);
    let (high, _, _) = bitwise(high, unvisited.high);
    u256 { low, high }
}

/// Set intersection, one builtin application per limb.
#[inline(always)]
pub fn and(lhs: u256, rhs: u256) -> u256 {
    let (low, _, _) = bitwise(lhs.low, rhs.low);
    let (high, _, _) = bitwise(lhs.high, rhs.high);
    u256 { low, high }
}

// Microbenchmarks (17x14, per op = (test - loop) / 100)

#[test]
#[available_gas(l2_gas: 1000000)]
fn bench_dial_micro_loop() {
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += frontier.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_expand_corelib() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14_COST_2.into();
    let unvisited: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (layout.expand(frontier) & unvisited).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_expand_triple() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14_COST_2.into();
    let unvisited: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += expand_triple(@layout, frontier, unvisited).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_and_triple() {
    let lhs: u256 = CAVE_17X14_COST_2.into();
    let rhs: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += and(lhs, rhs).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_and_limb() {
    let lhs: u256 = CAVE_17X14_COST_2.into();
    let rhs: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (low, _, _) = bitwise(lhs.low, rhs.low);
        acc += low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_limb_sub() {
    let lhs: u256 = CAVE_17X14.into();
    let rhs: u256 = CAVE_17X14_COST_2.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (lhs.low - rhs.low).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 10000000)]
fn bench_dial_micro_felt_to_u256() {
    let value: felt252 = CAVE_17X14;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let wide: u256 = (value + n.into()).into();
        acc += wide.low.into();
    }
    assert!(acc != 0);
}

// Benchmarks: library

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_baseline_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    assert!(CAVE_17X14 != 0 && costs.len() == 2);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_empty_17x14() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_maze_17x14() {
    let costs = array![MAZE_17X14_COST_2, MAZE_17X14_COST_3].span();
    Dial::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_serpentine_17x14() {
    let costs = array![SERPENTINE_17X14_COST_2, SERPENTINE_17X14_COST_3].span();
    Dial::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO, costs,
    );
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_unreachable_17x14() {
    let costs = array![UNREACHABLE_17X14_COST_2, UNREACHABLE_17X14_COST_3].span();
    Dial::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO, costs,
    );
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_7x7() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    Dial::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_17x14_near() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_empty_17x14_classes_0() {
    Dial::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_17x14_classes_0() {
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_maze_17x14_classes_0() {
    Dial::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_serpentine_17x14_classes_0() {
    Dial::search(
        SERPENTINE_17X14,
        17,
        14,
        SERPENTINE_17X14_FAR_FROM,
        SERPENTINE_17X14_FAR_TO,
        array![].span(),
    );
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_7x7_classes_0() {
    Dial::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_17x14_classes_1() {
    let costs = array![CAVE_17X14_COST_2 + CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_cave_17x14_classes_3() {
    let costs = array![CAVE_17X14_CLASS_2, CAVE_17X14_COST_3, CAVE_17X14_CLASS_4].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_field_empty_17x14_budget_4() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 4, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_field_empty_17x14_budget_12() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 12, costs);
}

#[test]
#[available_gas(l2_gas: 100000000)]
fn bench_dial_field_cave_17x14_budget_8() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::field_of_movement(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 8, costs);
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::*;

    #[test]
    fn test_dial_unit_equals_bfs_17x14() {
        check_unit(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO, 3);
        check_unit(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, 19);
        check_unit(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO, 3);
        check_unit(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, 24);
        check_unit(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO, 3);
        check_unit(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, 53);
        check_unit(
            SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO, 3,
        );
        check_unit(
            SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO, 90,
        );
        check_unit(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO, 0,
        );
        check_unit(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO, 0,
        );
    }

    #[test]
    fn test_dial_unit_equals_bfs_7x7() {
        check_unit(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO, 3);
        check_unit(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO, 6);
        check_unit(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, 6);
        check_unit(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO, 13);
        check_unit(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO, 14);
        check_unit(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO, 0);
    }

    /// Oracle checks with 0 to 3 random cost classes.
    fn check_fixture(grid: felt252, width: u8, height: u8, from: u8, seed: felt252, stride: u8) {
        let mut count: u32 = 0;
        while count != 4 {
            let costs = random_costs(grid, width, height, seed + count.into(), count);
            check_all(grid, width, height, from, costs, stride);
            count += 1;
        }
    }

    #[test]
    fn test_dial_oracle_empty_17x14() {
        check_fixture(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, 0, 11);
    }

    #[test]
    fn test_dial_oracle_cave_17x14() {
        check_fixture(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 10, 11);
    }

    #[test]
    fn test_dial_oracle_maze_17x14() {
        check_fixture(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, 20, 7);
    }

    #[test]
    fn test_dial_oracle_serpentine_17x14() {
        check_fixture(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, 30, 11);
    }

    #[test]
    fn test_dial_oracle_unreachable_17x14() {
        check_fixture(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, 40, 11);
    }

    #[test]
    fn test_dial_oracle_fixtures_7x7() {
        let fixtures = array![
            (EMPTY_7X7, EMPTY_7X7_FAR_FROM), (CAVE_7X7, CAVE_7X7_FAR_FROM),
            (MAZE_7X7, MAZE_7X7_FAR_FROM), (SERPENTINE_7X7, SERPENTINE_7X7_FAR_FROM),
            (UNREACHABLE_7X7, UNREACHABLE_7X7_FAR_FROM),
        ];
        let mut seed: felt252 = 100;
        for (grid, from) in fixtures.span() {
            let mut count: u32 = 0;
            while count != 4 {
                let costs = random_costs(*grid, 7, 7, seed, count);
                check_all(*grid, 7, 7, *from, costs, 1);
                seed += 1;
                count += 1;
            }
        }
    }
    /// Open edge tiles: corner 0, 5, adjacent pair 10 and 11, 102 (x = 0), 135 (x = 16), 229
    /// (top row).
    fn edges_17x14() -> Span<u8> {
        array![0, 5, 10, 11, 102, 135, 229].span()
    }

    fn with_edges(grid: felt252, edges: Span<u8>) -> felt252 {
        let mut grid = grid;
        for edge in edges {
            grid += Bits::pow(*edge);
        }
        grid
    }

    #[test]
    fn test_dial_oracle_edges_17x14() {
        let edges = edges_17x14();
        let grid = with_edges(EMPTY_17X14, edges);
        let mut seed: felt252 = 50;
        for from in edges {
            let costs = random_costs(grid, 17, 14, seed, 2);
            check_all(grid, 17, 14, *from, costs, 13);
            // Edge to edge, every pair
            let distances = dijkstra(grid, 17, 14, *from, costs);
            for to in edges {
                let path = Dial::search(grid, 17, 14, *from, *to, costs);
                check_path(grid, 17, 14, *from, *to, costs, path, *distances[(*to).into()]);
            }
            seed += 1;
        }
    }

    #[test]
    fn test_dial_oracle_edges_interior_start_17x14() {
        let grid = with_edges(CAVE_17X14, edges_17x14());
        let costs = random_costs(grid, 17, 14, 60, 3);
        check_all(grid, 17, 14, CAVE_17X14_FAR_FROM, costs, 1);
    }

    #[test]
    fn test_dial_oracle_edges_7x7() {
        // Corner 0, 3, pair 21 and 27 (x = 0 and x = 6), 45 (top)
        let edges = array![0, 3, 21, 27, 45].span();
        let grid = with_edges(EMPTY_7X7, edges);
        let mut seed: felt252 = 70;
        for from in edges {
            let mut count: u32 = 0;
            while count != 4 {
                let costs = random_costs(grid, 7, 7, seed, count);
                check_all(grid, 7, 7, *from, costs, 1);
                seed += 1;
                count += 1;
            }
        }
    }

    #[test]
    fn test_dial_oracle_3x3() {
        // Single interior tile 4 and its open edge neighbours
        let grid: felt252 = 0x1ff - 1 - 0x100;
        let mut count: u32 = 0;
        while count != 4 {
            let costs = random_costs(grid, 3, 3, count.into(), count);
            let mut from: u8 = 1;
            while from != 8 {
                check_all(grid, 3, 3, from, costs, 1);
                from += 1;
            }
            count += 1;
        }
    }

    #[test]
    fn test_dial_oracle_caves_19x13() {
        let mut seed: felt252 = 0;
        while seed != 4 {
            let grid = Caver::generate(19, 13, 3, seed);
            let open: u256 = grid.into();
            let mut from: u8 = 100;
            while !Bits::get(open, from) {
                from += 1;
            }
            let costs = random_costs(grid, 19, 13, seed, (seed + 1).try_into().unwrap() % 4);
            check_all(grid, 19, 13, from, costs, 13);
            seed += 1;
        }
    }

    #[test]
    fn test_dial_oracle_caves_17x14() {
        let mut seed: felt252 = 10;
        while seed != 14 {
            let grid = Caver::generate(17, 14, 3, seed);
            let open: u256 = grid.into();
            let mut from: u8 = 40;
            while !Bits::get(open, from) {
                from += 1;
            }
            let costs = random_costs(grid, 17, 14, seed, 3);
            check_all(grid, 17, 14, from, costs, 13);
            seed += 1;
        }
    }

    /// Oracle check of the benchmark inputs, and their statistics (path length, cost).
    #[test]
    fn test_dial_bench_inputs() {
        let inputs = array![
            (
                EMPTY_17X14,
                EMPTY_17X14_FAR_FROM,
                EMPTY_17X14_FAR_TO,
                EMPTY_17X14_COST_2,
                EMPTY_17X14_COST_3,
            ),
            (
                CAVE_17X14,
                CAVE_17X14_FAR_FROM,
                CAVE_17X14_FAR_TO,
                CAVE_17X14_COST_2,
                CAVE_17X14_COST_3,
            ),
            (
                MAZE_17X14,
                MAZE_17X14_FAR_FROM,
                MAZE_17X14_FAR_TO,
                MAZE_17X14_COST_2,
                MAZE_17X14_COST_3,
            ),
            (
                SERPENTINE_17X14,
                SERPENTINE_17X14_FAR_FROM,
                SERPENTINE_17X14_FAR_TO,
                SERPENTINE_17X14_COST_2,
                SERPENTINE_17X14_COST_3,
            ),
            (
                UNREACHABLE_17X14,
                UNREACHABLE_17X14_FAR_FROM,
                UNREACHABLE_17X14_FAR_TO,
                UNREACHABLE_17X14_COST_2,
                UNREACHABLE_17X14_COST_3,
            ),
            (
                CAVE_17X14,
                CAVE_17X14_NEAR_FROM,
                CAVE_17X14_NEAR_TO,
                CAVE_17X14_COST_2,
                CAVE_17X14_COST_3,
            ),
        ];
        for (grid, from, to, two, three) in inputs.span() {
            let classes = array![
                array![].span(), array![*two + *three].span(), array![*two, *three].span(),
            ];
            for costs in classes.span() {
                let distances = dijkstra(*grid, 17, 14, *from, *costs);
                let path = Dial::search(*grid, 17, 14, *from, *to, *costs);
                let expected = *distances[(*to).into()];
                check_path(*grid, 17, 14, *from, *to, *costs, path, expected);
                println!(
                    "{} -> {}: {} classes, cost {}, {} tiles",
                    from,
                    to,
                    costs.len(),
                    expected,
                    path.len(),
                );
            }
        }
    }
}
