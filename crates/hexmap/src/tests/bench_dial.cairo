//! Gas benchmarks of lot L3, weighted Dial: one `#[test]` per fixture and algorithm, each with an
//! `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! Correctness oracle: a scalar Dijkstra (`dijkstra`), test-only. The losing formulations live
//! here too.

// Core imports

use core::dict::Felt252Dict;

// Internal imports

use origami_hexmap::finders::dial::Dial;
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::helpers::rng::RngTrait;
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::Variants;
use origami_hexmap::types::direction::{Direction, DirectionTrait};

// Constants

/// 2^-128 in the field.
const INV_2_128: felt252 = 0x800000000000010fffffffffffffffff7ffffffffffffef0000000000000001;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Repetitions of the microbenchmarks.
const REPS: u8 = 100;

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
    let (_, _, pairs_low) = Bits::bitwise(frontier.low, double.low);
    let (_, _, pairs_high) = Bits::bitwise(frontier.high, double.high);
    let (even_low, _, _) = Bits::bitwise(pairs_low, layout.even.low);
    let (even_high, _, _) = Bits::bitwise(pairs_high, layout.even.high);
    let pairs_even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
    let pairs_odd: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128 - pairs_even;
    let up: u256 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd).into();
    let down: u256 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd).into();
    let east: u256 = (felt * INV_2).into();
    let (_, _, low) = Bits::bitwise(pairs_low, east.low);
    let (_, _, low) = Bits::bitwise(low, up.low);
    let (_, _, low) = Bits::bitwise(low, down.low);
    let (low, _, _) = Bits::bitwise(low, unvisited.low);
    let (_, _, high) = Bits::bitwise(pairs_high, east.high);
    let (_, _, high) = Bits::bitwise(high, up.high);
    let (_, _, high) = Bits::bitwise(high, down.high);
    let (high, _, _) = Bits::bitwise(high, unvisited.high);
    u256 { low, high }
}

/// Set intersection, one builtin application per limb.
#[inline(always)]
pub fn and(lhs: u256, rhs: u256) -> u256 {
    let (low, _, _) = Bits::bitwise(lhs.low, rhs.low);
    let (high, _, _) = Bits::bitwise(lhs.high, rhs.high);
    u256 { low, high }
}

// Microbenchmarks (17x14, per op = (test - loop) / 100)

#[test]
#[available_gas(l2_gas: 153000)]
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
#[available_gas(l2_gas: 2371000)]
fn bench_dial_micro_expand_corelib() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14_COST_2.into();
    let unvisited: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (Variants::expand_felt(@layout, frontier) & unvisited).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2344000)]
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
#[available_gas(l2_gas: 448000)]
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
#[available_gas(l2_gas: 333000)]
fn bench_dial_micro_and_limb() {
    let lhs: u256 = CAVE_17X14_COST_2.into();
    let rhs: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (low, _, _) = Bits::bitwise(lhs.low, rhs.low);
        acc += low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 204000)]
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
#[available_gas(l2_gas: 340000)]
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

// Variant harness: the library search on `u256` (interior endpoints, reachable target), one
// building block changed per variant. `search_winner` is the harness copy of the library.

/// Cost classes, as in the library.
#[derive(Copy, Drop)]
pub struct HarnessClasses {
    pub two: u256,
    pub three: u256,
    pub four: u256,
    pub any: u256,
    pub odd: u256,
    pub upper: u256,
    pub has_two: bool,
    pub has_three: bool,
    pub has_four: bool,
}

/// Inputs of the forward loops.
#[derive(Copy, Drop)]
pub struct Setup {
    pub layout: Layout,
    pub unvisited: u256,
    pub arrivals: u256,
    pub target: u256,
    pub classes: HarnessClasses,
    pub to: u8,
    pub to_bit: felt252,
    pub to_odd: bool,
    pub weighted: bool,
}

/// Partition by class, the highest class wins.
pub fn harness_classes(open: u256, costs: Span<felt252>) -> HarnessClasses {
    let count = costs.len();
    let zero: u256 = 0;
    let mut rest = open;
    let four = if count == 3 {
        let four = and(rest, (*costs[2]).into());
        rest = rest - four;
        four
    } else {
        zero
    };
    let three = if count >= 2 {
        let three = and(rest, (*costs[1]).into());
        rest = rest - three;
        three
    } else {
        zero
    };
    let two = if count >= 1 {
        and(rest, (*costs[0]).into())
    } else {
        zero
    };
    let (f2, f3, f4) = (Bits::to_felt(two), Bits::to_felt(three), Bits::to_felt(four));
    HarnessClasses {
        two,
        three,
        four,
        any: (f2 + f3 + f4).into(),
        odd: (f2 + f4).into(),
        upper: (f3 + f4).into(),
        has_two: f2 != 0,
        has_three: f3 != 0,
        has_four: f4 != 0,
    }
}

/// Library setup for interior endpoints.
pub fn setup(
    grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
) -> Setup {
    let open: u256 = grid.into();
    let layout = LayoutTrait::new(width, height);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    let from_bit = Bits::pow(from);
    let to_bit = Bits::pow(to);
    let unvisited: u256 = (Bits::to_felt(and(open, interior)) - from_bit).into();
    let arrivals = expand_triple(@layout, from_bit.into(), unvisited);
    Setup {
        layout,
        unvisited,
        arrivals,
        target: to_bit.into(),
        classes: harness_classes(open, costs),
        to,
        to_bit,
        to_odd: (to / width) % 2 == 1,
        weighted: costs.len() != 0,
    }
}

/// Whether the target limb meets a set.
#[inline(always)]
fn hits(value: u256, target: u256) -> bool {
    let (hit, _, _) = if target.low != 0 {
        Bits::bitwise(value.low, target.low)
    } else {
        Bits::bitwise(value.high, target.high)
    };
    hit != 0
}

/// Library forward loop: felt bucket ring in locals, AND with the unvisited set in the dilation,
/// then one AND per class.
pub fn forward_winner(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![0];
    let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
        0, 0, 0, 0,
    );
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(arrivals, setup.target) {
            break;
        }
        let mut ones = Bits::to_felt(arrivals);
        if classes.has_two {
            let two = Bits::to_felt(and(arrivals, classes.two));
            ones -= two;
            second += two;
        }
        if classes.has_three {
            let three = Bits::to_felt(and(arrivals, classes.three));
            ones -= three;
            third += three;
        }
        if classes.has_four {
            let four = Bits::to_felt(and(arrivals, classes.four));
            ones -= four;
            fourth += four;
        }
        first += ones;
        let frontier = loop {
            let frontier = first;
            first = second;
            second = third;
            third = fourth;
            fourth = 0;
            time += 1;
            if frontier != 0 || first + second + third == 0 {
                break frontier;
            }
        };
        assert!(frontier != 0);
        while layers.len() != time {
            layers.append(0);
        }
        let set: u256 = frontier.into();
        layers.append(set);
        arrivals = expand_felt(@setup.layout, set, frontier, unvisited);
        unvisited =
            u256 { low: unvisited.low - arrivals.low, high: unvisited.high - arrivals.high };
    }
    (layers, time)
}

/// Library dilation with the frontier felt given.
#[inline(always)]
pub fn expand_felt(layout: @Layout, frontier: u256, felt: felt252, unvisited: u256) -> u256 {
    let layout = *layout;
    let double: u256 = (felt + felt).into();
    let (_, _, pairs_low) = Bits::bitwise(frontier.low, double.low);
    let (_, _, pairs_high) = Bits::bitwise(frontier.high, double.high);
    let (even_low, _, _) = Bits::bitwise(pairs_low, layout.even.low);
    let (even_high, _, _) = Bits::bitwise(pairs_high, layout.even.high);
    let pairs_even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
    let pairs_odd: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128 - pairs_even;
    let up: u256 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd).into();
    let down: u256 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd).into();
    let east: u256 = (felt * INV_2).into();
    let (_, _, low) = Bits::bitwise(pairs_low, east.low);
    let (_, _, low) = Bits::bitwise(low, up.low);
    let (_, _, low) = Bits::bitwise(low, down.low);
    let (low, _, _) = Bits::bitwise(low, unvisited.low);
    let (_, _, high) = Bits::bitwise(pairs_high, east.high);
    let (_, _, high) = Bits::bitwise(high, up.high);
    let (_, _, high) = Bits::bitwise(high, down.high);
    let (high, _, _) = Bits::bitwise(high, unvisited.high);
    u256 { low, high }
}

/// Library unit-cost loop: no buckets.
pub fn forward_unit(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let mut layers: Array<u256> = array![0];
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(arrivals, setup.target) {
            break;
        }
        assert!(arrivals != 0);
        time += 1;
        layers.append(arrivals);
        arrivals = expand_felt(@setup.layout, arrivals, Bits::to_felt(arrivals), unvisited);
        unvisited =
            u256 { low: unvisited.low - arrivals.low, high: unvisited.high - arrivals.high };
    }
    (layers, time)
}

/// Variant: bucket ring as an `Array<felt252>` rebuilt every time step.
pub fn forward_array_ring(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![0];
    let mut ring: Array<felt252> = array![0, 0, 0, 0];
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(arrivals, setup.target) {
            break;
        }
        let mut ones = Bits::to_felt(arrivals);
        let mut adds: Array<felt252> = array![];
        let two = if classes.has_two {
            Bits::to_felt(and(arrivals, classes.two))
        } else {
            0
        };
        let three = if classes.has_three {
            Bits::to_felt(and(arrivals, classes.three))
        } else {
            0
        };
        let four = if classes.has_four {
            Bits::to_felt(and(arrivals, classes.four))
        } else {
            0
        };
        ones -= two + three + four;
        adds.append(ones);
        adds.append(two);
        adds.append(three);
        adds.append(four);
        let mut next: Array<felt252> = array![];
        let mut index = 0;
        while index != 4 {
            next.append(*ring[index] + *adds[index]);
            index += 1;
        }
        ring = next;
        let frontier = loop {
            let mut span = ring.span();
            let frontier = *span.pop_front().unwrap();
            let mut rest: Array<felt252> = array![];
            let mut sum = 0;
            while let Option::Some(value) = span.pop_front() {
                rest.append(*value);
                sum += *value;
            }
            rest.append(0);
            ring = rest;
            time += 1;
            if frontier != 0 || sum == 0 {
                break frontier;
            }
        };
        assert!(frontier != 0);
        while layers.len() != time {
            layers.append(0);
        }
        let set: u256 = frontier.into();
        layers.append(set);
        arrivals = expand_felt(@setup.layout, set, frontier, unvisited);
        unvisited =
            u256 { low: unvisited.low - arrivals.low, high: unvisited.high - arrivals.high };
    }
    (layers, time)
}

/// Variant: bucket ring as a fixed-size array `[felt252; 4]`, destructured and rebuilt.
pub fn forward_fixed_ring(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![0];
    let mut ring: [felt252; 4] = [0, 0, 0, 0];
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(arrivals, setup.target) {
            break;
        }
        let mut ones = Bits::to_felt(arrivals);
        let two = if classes.has_two {
            Bits::to_felt(and(arrivals, classes.two))
        } else {
            0
        };
        let three = if classes.has_three {
            Bits::to_felt(and(arrivals, classes.three))
        } else {
            0
        };
        let four = if classes.has_four {
            Bits::to_felt(and(arrivals, classes.four))
        } else {
            0
        };
        ones -= two + three + four;
        let [a, b, c, d] = ring;
        ring = [a + ones, b + two, c + three, d + four];
        let frontier = loop {
            let [a, b, c, d] = ring;
            ring = [b, c, d, 0];
            time += 1;
            if a != 0 || b + c + d == 0 {
                break a;
            }
        };
        assert!(frontier != 0);
        while layers.len() != time {
            layers.append(0);
        }
        let set: u256 = frontier.into();
        layers.append(set);
        arrivals = expand_felt(@setup.layout, set, frontier, unvisited);
        unvisited =
            u256 { low: unvisited.low - arrivals.low, high: unvisited.high - arrivals.high };
    }
    (layers, time)
}

/// Variant: unvisited set partitioned by class once (`U_k`), one AND per class with the
/// dilation and removal by subtraction from each part.
pub fn forward_partition(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![0];
    let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
        0, 0, 0, 0,
    );
    let unvisited = setup.unvisited - setup.arrivals;
    let mut u2 = and(unvisited, classes.two);
    let mut u3 = and(unvisited, classes.three);
    let mut u4 = and(unvisited, classes.four);
    let mut u1 = unvisited - u2 - u3 - u4;
    let arrivals = setup.arrivals;
    // First arrivals, split once
    let mut n2 = and(arrivals, classes.two);
    let mut n3 = and(arrivals, classes.three);
    let mut n4 = and(arrivals, classes.four);
    let mut n1 = arrivals - n2 - n3 - n4;
    let mut probe = arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(probe, setup.target) {
            break;
        }
        first += Bits::to_felt(n1);
        second += Bits::to_felt(n2);
        third += Bits::to_felt(n3);
        fourth += Bits::to_felt(n4);
        let frontier = loop {
            let frontier = first;
            first = second;
            second = third;
            third = fourth;
            fourth = 0;
            time += 1;
            if frontier != 0 || first + second + third == 0 {
                break frontier;
            }
        };
        assert!(frontier != 0);
        while layers.len() != time {
            layers.append(0);
        }
        let set: u256 = frontier.into();
        layers.append(set);
        let all: u256 = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        let dilation = expand_felt(@setup.layout, set, frontier, all);
        probe = dilation;
        n1 = and(dilation, u1);
        u1 = u1 - n1;
        if classes.has_two {
            n2 = and(dilation, u2);
            u2 = u2 - n2;
        }
        if classes.has_three {
            n3 = and(dilation, u3);
            u3 = u3 - n3;
        }
        if classes.has_four {
            n4 = and(dilation, u4);
            u4 = u4 - n4;
        }
    }
    (layers, time)
}

/// Variant: corelib operators (`Layout::expand`, `u256` `&`, `-`).
pub fn forward_corelib(setup: @Setup) -> (Array<u256>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![0];
    let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
        0, 0, 0, 0,
    );
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if arrivals & setup.target != 0 {
            break;
        }
        let mut ones = Bits::to_felt(arrivals);
        if classes.has_two {
            let two = Bits::to_felt(arrivals & classes.two);
            ones -= two;
            second += two;
        }
        if classes.has_three {
            let three = Bits::to_felt(arrivals & classes.three);
            ones -= three;
            third += three;
        }
        if classes.has_four {
            let four = Bits::to_felt(arrivals & classes.four);
            ones -= four;
            fourth += four;
        }
        first += ones;
        let frontier = loop {
            let frontier = first;
            first = second;
            second = third;
            third = fourth;
            fourth = 0;
            time += 1;
            if frontier != 0 || first + second + third == 0 {
                break frontier;
            }
        };
        assert!(frontier != 0);
        while layers.len() != time {
            layers.append(0);
        }
        let set: u256 = frontier.into();
        layers.append(set);
        arrivals = Variants::expand_felt(@setup.layout, set) & unvisited;
        unvisited = unvisited - arrivals;
    }
    (layers, time)
}

/// Variant: only the non-empty layers are stored, with their times.
pub fn forward_sparse(setup: @Setup) -> (Array<u256>, Array<u32>, u32) {
    let setup = *setup;
    let classes = setup.classes;
    let mut layers: Array<u256> = array![];
    let mut times: Array<u32> = array![];
    let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
        0, 0, 0, 0,
    );
    let mut unvisited = setup.unvisited - setup.arrivals;
    let mut arrivals = setup.arrivals;
    let mut time: u32 = 0;
    loop {
        if hits(arrivals, setup.target) {
            break;
        }
        let mut ones = Bits::to_felt(arrivals);
        if classes.has_two {
            let two = Bits::to_felt(and(arrivals, classes.two));
            ones -= two;
            second += two;
        }
        if classes.has_three {
            let three = Bits::to_felt(and(arrivals, classes.three));
            ones -= three;
            third += three;
        }
        if classes.has_four {
            let four = Bits::to_felt(and(arrivals, classes.four));
            ones -= four;
            fourth += four;
        }
        first += ones;
        let frontier = loop {
            let frontier = first;
            first = second;
            second = third;
            third = fourth;
            fourth = 0;
            time += 1;
            if frontier != 0 || first + second + third == 0 {
                break frontier;
            }
        };
        assert!(frontier != 0);
        let set: u256 = frontier.into();
        layers.append(set);
        times.append(time);
        arrivals = expand_felt(@setup.layout, set, frontier, unvisited);
        unvisited =
            u256 { low: unvisited.low - arrivals.low, high: unvisited.high - arrivals.high };
    }
    (layers, times, time)
}

/// Cost of a tile from its limb, as in the library.
#[inline(always)]
fn harness_cost(classes: @HarnessClasses, bit: u128, high: bool) -> u32 {
    let classes = *classes;
    let (any, upper, odd) = if high {
        (classes.any.high, classes.upper.high, classes.odd.high)
    } else {
        (classes.any.low, classes.upper.low, classes.odd.low)
    };
    let (hit, _, _) = Bits::bitwise(bit, any);
    if hit == 0 {
        return 1;
    }
    if !classes.has_three && !classes.has_four {
        return 2;
    }
    let (hit, _, _) = Bits::bitwise(bit, upper);
    if hit == 0 {
        return 2;
    }
    if !classes.has_four {
        return 3;
    }
    let (hit, _, _) = Bits::bitwise(bit, odd);
    if hit == 0 {
        3
    } else {
        4
    }
}

/// Cost of a tile from its felt bit.
fn harness_cost_of(classes: @HarnessClasses, bit: felt252) -> u32 {
    let value: u256 = bit.into();
    if value.low != 0 {
        harness_cost(classes, value.low, false)
    } else {
        harness_cost(classes, value.high, true)
    }
}

/// One backtracking step of the library: the lowest neighbour of `position` in `layer`.
/// Returns the neighbour, its bit, its limb and its parity.
#[inline(always)]
fn step_mask(
    layout: @Layout, layer: u256, position: u8, bit: felt252, odd: bool,
) -> (u8, felt252, u128, bool, bool) {
    let layout = *layout;
    let width = layout.width;
    let mask = if odd {
        bit * (INV_2 + 2 + 3 * (layout.up_odd + layout.down_odd))
    } else {
        bit * (INV_2 + 2 + 3 * (layout.up_even + layout.down_even))
    };
    let (hits, high) = if position < 127 - width {
        let (hits, _, _) = Bits::bitwise(mask.try_into().unwrap(), layer.low);
        (hits, false)
    } else if position >= 129 + width {
        let (hits, _, _) = Bits::bitwise((mask * INV_2_128).try_into().unwrap(), layer.high);
        (hits, true)
    } else {
        let mask: u256 = mask.into();
        let (hits, _, _) = Bits::bitwise(mask.low, layer.low);
        if hits != 0 {
            (hits, false)
        } else {
            let (hits, _, _) = Bits::bitwise(mask.high, layer.high);
            (hits, true)
        }
    };
    let (rest, _, _) = Bits::bitwise(hits, hits - 1);
    let lowest = hits - rest;
    let next_bit: felt252 = if high {
        lowest.into() * TWO_POW_128
    } else {
        lowest.into()
    };
    let (down, up) = if odd {
        (layout.down_odd, layout.up_odd)
    } else {
        (layout.down_even, layout.up_even)
    };
    let south = bit * down;
    let (next, flip) = if next_bit == south {
        (position - if odd {
            width
        } else {
            width + 1
        }, true)
    } else if next_bit == south + south {
        (if odd {
            position + 1 - width
        } else {
            position - width
        }, true)
    } else if next_bit == bit * INV_2 {
        (position - 1, false)
    } else if next_bit == bit + bit {
        (position + 1, false)
    } else if next_bit == bit * up {
        (position + if odd {
            width
        } else {
            width - 1
        }, true)
    } else {
        (position + if odd {
            width + 1
        } else {
            width
        }, true)
    };
    (next, next_bit, lowest, high, odd != flip)
}

/// Library backtracking (interior target).
pub fn backtrack_winner(setup: @Setup, layers: Span<u256>, time: u32) -> Span<u8> {
    let setup = *setup;
    let mut path: Array<u8> = array![setup.to];
    if time == 0 {
        return path.span();
    }
    let (mut position, mut bit, mut odd) = (setup.to, setup.to_bit, setup.to_odd);
    let (mut time, mut cost) = if setup.weighted {
        let cost = harness_cost_of(@setup.classes, bit);
        (time + cost, cost)
    } else {
        (time + 1, 1)
    };
    loop {
        let previous = time - cost;
        if previous == 0 {
            break;
        }
        let (next, next_bit, lowest, high, next_odd) = step_mask(
            @setup.layout, *layers[previous], position, bit, odd,
        );
        path.append(next);
        if setup.weighted {
            cost = harness_cost(@setup.classes, lowest, high);
        }
        position = next;
        bit = next_bit;
        odd = next_odd;
        time = previous;
    }
    path.span()
}

/// Cost of a tile by bit tests of the class planes.
fn bit_cost(classes: @HarnessClasses, weighted: bool, position: u8) -> u32 {
    let classes = *classes;
    if !weighted || !Bits::get(classes.any, position) {
        1
    } else if !Bits::get(classes.upper, position) {
        2
    } else if !Bits::get(classes.odd, position) {
        3
    } else {
        4
    }
}

/// Variant: backtracking by single-bit tests of the 6 neighbours in a fixed direction order,
/// the cost by bit tests of the class planes.
pub fn backtrack_bits(setup: @Setup, layers: Span<u256>, time: u32) -> Span<u8> {
    let setup = *setup;
    let width = setup.layout.width;
    let mut path: Array<u8> = array![setup.to];
    if time == 0 {
        return path.span();
    }
    let (mut position, mut odd) = (setup.to, setup.to_odd);
    let classes = setup.classes;
    let mut cost = bit_cost(@classes, setup.weighted, position);
    let mut time = time + cost;
    let directions = directions();
    loop {
        let previous = time - cost;
        if previous == 0 {
            break;
        }
        let layer = *layers[previous];
        let mut next: u8 = 0;
        for direction in directions {
            let candidate = (*direction).next(position, width, odd);
            if Bits::get(layer, candidate) {
                next = candidate;
                break;
            }
        }
        // A vertical move flips the row parity
        if next + 1 != position && next != position + 1 {
            odd = !odd;
        }
        path.append(next);
        position = next;
        cost = bit_cost(@classes, setup.weighted, position);
        time = previous;
    }
    path.span()
}

/// Variant: backtracking through the sparse layers, `pop_back` until the wanted time.
pub fn backtrack_sparse(
    setup: @Setup, layers: Span<u256>, times: Span<u32>, time: u32,
) -> Span<u8> {
    let setup = *setup;
    let mut layers = layers;
    let mut times = times;
    let mut path: Array<u8> = array![setup.to];
    if time == 0 {
        return path.span();
    }
    let (mut position, mut bit, mut odd) = (setup.to, setup.to_bit, setup.to_odd);
    let (mut time, mut cost) = if setup.weighted {
        let cost = harness_cost_of(@setup.classes, bit);
        (time + cost, cost)
    } else {
        (time + 1, 1)
    };
    loop {
        let previous = time - cost;
        if previous == 0 {
            break;
        }
        let layer = loop {
            let layer = *layers.pop_back().unwrap();
            if *times.pop_back().unwrap() == previous {
                break layer;
            }
        };
        let (next, next_bit, lowest, high, next_odd) = step_mask(
            @setup.layout, layer, position, bit, odd,
        );
        path.append(next);
        if setup.weighted {
            cost = harness_cost(@setup.classes, lowest, high);
        }
        position = next;
        bit = next_bit;
        odd = next_odd;
        time = previous;
    }
    path.span()
}

/// Harness copy of the library search on `u256`.
pub fn search_winner(
    grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
) -> Span<u8> {
    let setup = setup(grid, width, height, from, to, costs);
    let (layers, time) = forward_winner(@setup);
    backtrack_winner(@setup, layers.span(), time)
}

// Baseline: scalar Dijkstra with a binary heap in a dictionary

/// Binary min-heap of `key = distance * 256 + position` in a dictionary (index -> key).
#[derive(Destruct)]
pub struct Heap {
    pub items: Felt252Dict<u64>,
    pub size: felt252,
}

#[generate_trait]
pub impl HeapImpl of HeapTrait {
    fn new() -> Heap {
        Heap { items: Default::default(), size: 0 }
    }

    fn push(ref self: Heap, key: u64) {
        let mut index = self.size;
        self.size += 1;
        // Sift up
        while index != 0 {
            let index_u: u32 = index.try_into().unwrap();
            let parent: felt252 = ((index_u - 1) / 2).into();
            let above = self.items.get(parent);
            if above <= key {
                break;
            }
            self.items.insert(index, above);
            index = parent;
        }
        self.items.insert(index, key);
    }

    fn pop(ref self: Heap) -> u64 {
        let top = self.items.get(0);
        self.size -= 1;
        let last = self.items.get(self.size);
        let size: u32 = self.size.try_into().unwrap();
        let mut index: u32 = 0;
        // Sift down
        loop {
            let left = 2 * index + 1;
            if left >= size {
                break;
            }
            let mut child = left;
            let mut value = self.items.get(left.into());
            if left + 1 < size {
                let right = self.items.get((left + 1).into());
                if right < value {
                    child = left + 1;
                    value = right;
                }
            }
            if last <= value {
                break;
            }
            self.items.insert(index.into(), value);
            index = child;
        }
        self.items.insert(index.into(), last);
        top
    }
}

/// Scalar Dijkstra: heap of (distance, position), bitmap of settled tiles, parents in a
/// dictionary, early exit at the target. Interior endpoints.
pub fn dijkstra_heap(
    grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
) -> Span<u8> {
    let interior: u256 = LayoutTrait::interior(width, height).into();
    let open: u256 = grid.into() & interior;
    let classes = harness_classes(open, costs);
    let mut dist: Felt252Dict<u32> = Default::default();
    let mut parent: Felt252Dict<u8> = Default::default();
    let mut settled: felt252 = 0;
    let mut heap = HeapTrait::new();
    heap.push(from.into());
    dist.insert(from.into(), 1);
    let directions = directions();
    let found = loop {
        if heap.size == 0 {
            break false;
        }
        let key = heap.pop();
        let (distance, position) = DivRem::div_rem(key, 256);
        let position: u8 = position.try_into().unwrap();
        let bit = Bits::pow(position);
        if Bits::get(settled.into(), position) {
            continue;
        }
        settled += bit;
        if position == to {
            break true;
        }
        let odd = (position / width) % 2 == 1;
        for direction in directions {
            let next = (*direction).next(position, width, odd);
            if Bits::get(open, next) {
                let cost = harness_cost_of(@classes, Bits::pow(next));
                let candidate: u32 = distance.try_into().unwrap() + cost;
                let known = dist.get(next.into());
                if known == 0 || candidate + 1 < known {
                    dist.insert(next.into(), candidate + 1);
                    parent.insert(next.into(), position);
                    heap.push(candidate.into() * 256 + next.into());
                }
            }
        }
    };
    let mut path: Array<u8> = array![];
    if !found {
        return path.span();
    }
    let mut position = to;
    while position != from {
        path.append(position);
        position = parent.get(position.into());
    }
    path.span()
}

// Benchmarks: variants (CAVE 17x14 far pair, 2 classes, unless stated)

#[test]
#[available_gas(l2_gas: 1608000)]
fn bench_dial_variant_winner_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let path = search_winner(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 2171000)]
fn bench_dial_variant_array_ring_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_array_ring(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1587000)]
fn bench_dial_variant_fixed_ring_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_fixed_ring(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1851000)]
fn bench_dial_variant_partition_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_partition(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1661000)]
fn bench_dial_variant_corelib_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_corelib(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1599000)]
fn bench_dial_variant_sparse_layers_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, times, time) = forward_sparse(@setup);
    let path = backtrack_sparse(@setup, layers.span(), times.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 2260000)]
fn bench_dial_variant_bit_tests_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_winner(@setup);
    let path = backtrack_bits(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1083000)]
fn bench_dial_variant_forward_only_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (_, time) = forward_winner(@setup);
    assert!(time != 0);
}

#[test]
#[available_gas(l2_gas: 86000)]
fn bench_dial_variant_setup_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    assert!(setup.to != 0);
}

#[test]
#[available_gas(l2_gas: 1132000)]
fn bench_dial_variant_unit_winner_17x14() {
    let costs = array![].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_unit(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 1419000)]
fn bench_dial_variant_unit_buckets_17x14() {
    let costs = array![].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_winner(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 493000)]
fn bench_dial_variant_u256_7x7() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    let path = search_winner(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, costs);
    assert!(path.len() != 0);
}

#[test]
#[available_gas(l2_gas: 27198000)]
fn bench_dial_variant_dijkstra_heap_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let path = dijkstra_heap(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    assert!(path.len() == 24);
}

#[test]
#[available_gas(l2_gas: 39593000)]
fn bench_dial_variant_dijkstra_heap_empty_17x14() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    let path = dijkstra_heap(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, costs);
    assert!(path.len() != 0);
}

#[test]
#[available_gas(l2_gas: 14137000)]
fn bench_dial_variant_dijkstra_heap_maze_17x14() {
    let costs = array![MAZE_17X14_COST_2, MAZE_17X14_COST_3].span();
    let path = dijkstra_heap(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, costs);
    assert!(path.len() != 0);
}

#[test]
#[available_gas(l2_gas: 4110000)]
fn bench_dial_variant_dijkstra_heap_7x7() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    let path = dijkstra_heap(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, costs);
    assert!(path.len() != 0);
}

#[test]
#[available_gas(l2_gas: 2096000)]
fn bench_dial_variant_backtrack_twice_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_winner(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    let again = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == again.len());
}

#[test]
#[available_gas(l2_gas: 1591000)]
fn bench_dial_variant_backtrack_once_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_winner(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == path.len());
}

#[test]
#[available_gas(l2_gas: 1159000)]
fn bench_dial_micro_step_mask() {
    let layout = LayoutTrait::new(17, 14);
    let layer: u256 = CAVE_17X14.into();
    let bit = Bits::pow(100);
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (next, _, _, _, _) = step_mask(@layout, layer, 100, bit, false);
        acc += next.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1266000)]
fn bench_dial_micro_step_mask_north_west() {
    // 100 lies on the odd row 5: its North-West neighbour is 100 + 17 + 1
    let layout = LayoutTrait::new(17, 14);
    let layer: u256 = Bits::pow(118).into();
    let bit = Bits::pow(100);
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (next, _, _, _, _) = step_mask(@layout, layer, 100, bit, true);
        acc += next.into();
    }
    assert!(acc == 11800);
}

#[test]
#[available_gas(l2_gas: 699000)]
fn bench_dial_micro_cost() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let classes = harness_classes(CAVE_17X14.into(), costs);
    let mut acc: u32 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += harness_cost(@classes, 0x100000, false);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 139000)]
fn bench_dial_micro_span_at() {
    let layers = array![1_u256, 2, 3, 4, 5, 6, 7, 8, 9, 10].span();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (*layers[5]).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 377000)]
fn bench_dial_micro_lowest() {
    let hits: u128 = 0x1100;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (rest, _, _) = Bits::bitwise(hits, hits - 1);
        acc += (hits - rest).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 205000)]
fn bench_dial_micro_felt_eq() {
    let bit = Bits::pow(100);
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if bit * INV_2 == acc {
            acc += 2;
        }
        acc += 1;
    }
    assert!(acc != 0);
}

// Benchmarks: library

#[test]
#[available_gas(l2_gas: 15000)]
fn bench_dial_baseline_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    assert!(CAVE_17X14 != 0 && costs.len() == 2);
}

#[test]
#[available_gas(l2_gas: 1245000)]
fn bench_dial_empty_17x14() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 1500000)]
fn bench_dial_cave_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 3534000)]
fn bench_dial_maze_17x14() {
    let costs = array![MAZE_17X14_COST_2, MAZE_17X14_COST_3].span();
    Dial::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 5350000)]
fn bench_dial_serpentine_17x14() {
    let costs = array![SERPENTINE_17X14_COST_2, SERPENTINE_17X14_COST_3].span();
    Dial::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO, costs,
    );
}

#[test]
#[available_gas(l2_gas: 716000)]
fn bench_dial_unreachable_17x14() {
    let costs = array![UNREACHABLE_17X14_COST_2, UNREACHABLE_17X14_COST_3].span();
    Dial::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO, costs,
    );
}

#[test]
#[available_gas(l2_gas: 314000)]
fn bench_dial_cave_7x7() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    Dial::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 305000)]
fn bench_dial_cave_17x14_near() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 802000)]
fn bench_dial_empty_17x14_classes_0() {
    Dial::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 986000)]
fn bench_dial_cave_17x14_classes_0() {
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 2106000)]
fn bench_dial_maze_17x14_classes_0() {
    Dial::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 3459000)]
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
#[available_gas(l2_gas: 185000)]
fn bench_dial_cave_7x7_classes_0() {
    Dial::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, array![].span());
}

#[test]
#[available_gas(l2_gas: 1464000)]
fn bench_dial_cave_17x14_classes_1() {
    let costs = array![CAVE_17X14_COST_2 + CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 1538000)]
fn bench_dial_cave_17x14_classes_3() {
    let costs = array![CAVE_17X14_CLASS_2, CAVE_17X14_COST_3, CAVE_17X14_CLASS_4].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 134000)]
fn bench_dial_field_empty_17x14_budget_2() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 2, costs);
}

#[test]
#[available_gas(l2_gas: 365000)]
fn bench_dial_field_empty_17x14_budget_8() {
    let costs = array![EMPTY_17X14_COST_2, EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 8, costs);
}

#[test]
#[available_gas(l2_gas: 353000)]
fn bench_dial_field_cave_17x14_budget_8() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::field_of_movement(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 8, costs);
}

#[test]
#[available_gas(l2_gas: 90000)]
fn bench_dial_field_empty_17x14_classes_0_budget_2() {
    let costs = array![].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 2, costs);
}

#[test]
#[available_gas(l2_gas: 262000)]
fn bench_dial_field_empty_17x14_classes_0_budget_8() {
    let costs = array![].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 8, costs);
}

#[test]
#[available_gas(l2_gas: 125000)]
fn bench_dial_field_empty_17x14_classes_1_budget_2() {
    let costs = array![EMPTY_17X14_COST_2 + EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 2, costs);
}

#[test]
#[available_gas(l2_gas: 349000)]
fn bench_dial_field_empty_17x14_classes_1_budget_8() {
    let costs = array![EMPTY_17X14_COST_2 + EMPTY_17X14_COST_3].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 8, costs);
}

#[test]
#[available_gas(l2_gas: 142000)]
fn bench_dial_field_empty_17x14_classes_3_budget_2() {
    let costs = array![EMPTY_17X14_CLASS_2, EMPTY_17X14_COST_3, EMPTY_17X14_CLASS_4].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 2, costs);
}

#[test]
#[available_gas(l2_gas: 381000)]
fn bench_dial_field_empty_17x14_classes_3_budget_8() {
    let costs = array![EMPTY_17X14_CLASS_2, EMPTY_17X14_COST_3, EMPTY_17X14_CLASS_4].span();
    Dial::field_of_movement(EMPTY_17X14, 17, 14, 110, 8, costs);
}

#[test]
#[available_gas(l2_gas: 48000)]
fn bench_dial_field_empty_7x7_classes_0_budget_1() {
    let costs = array![].span();
    Dial::field_of_movement(EMPTY_7X7, 7, 7, 8, 1, costs);
}

#[test]
#[available_gas(l2_gas: 88000)]
fn bench_dial_field_empty_7x7_classes_0_budget_4() {
    let costs = array![].span();
    Dial::field_of_movement(EMPTY_7X7, 7, 7, 8, 4, costs);
}

#[test]
#[available_gas(l2_gas: 69000)]
fn bench_dial_field_empty_7x7_classes_2_budget_1() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    Dial::field_of_movement(EMPTY_7X7, 7, 7, 8, 1, costs);
}

#[test]
#[available_gas(l2_gas: 138000)]
fn bench_dial_field_empty_7x7_classes_2_budget_4() {
    let costs = array![CAVE_7X7_COST_2, CAVE_7X7_COST_3].span();
    Dial::field_of_movement(EMPTY_7X7, 7, 7, 8, 4, costs);
}

#[test]
#[available_gas(l2_gas: 1588000)]
fn bench_dial_variant_unit_backtrack_twice_17x14() {
    let costs = array![].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_unit(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    let again = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == again.len());
}

#[test]
#[available_gas(l2_gas: 1132000)]
fn bench_dial_variant_unit_backtrack_once_17x14() {
    let costs = array![].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_unit(@setup);
    let path = backtrack_winner(@setup, layers.span(), time);
    assert!(path.len() == path.len());
}

#[test]
#[available_gas(l2_gas: 3433000)]
fn bench_dial_variant_bit_tests_twice_17x14() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    let setup = setup(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    let (layers, time) = forward_winner(@setup);
    let path = backtrack_bits(@setup, layers.span(), time);
    let again = backtrack_bits(@setup, layers.span(), time);
    assert!(path.len() == again.len());
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

    /// Every variant returns a path of the oracle cost, with 0 to 3 classes (the third class
    /// overlaps the first: the highest class wins).
    fn check_variants(grid: felt252, from: u8, to: u8, two: felt252, three: felt252) {
        let classes = array![
            array![].span(), array![two + three].span(), array![two, three].span(),
            array![two, three, two].span(),
        ];
        for costs in classes.span() {
            let costs = *costs;
            let expected = *dijkstra(grid, 17, 14, from, costs)[to.into()];
            let setup = setup(grid, 17, 14, from, to, costs);
            let mut paths: Array<Span<u8>> = array![];
            paths.append(search_winner(grid, 17, 14, from, to, costs));
            let (layers, time) = forward_array_ring(@setup);
            paths.append(backtrack_winner(@setup, layers.span(), time));
            let (layers, time) = forward_fixed_ring(@setup);
            paths.append(backtrack_winner(@setup, layers.span(), time));
            let (layers, time) = forward_partition(@setup);
            paths.append(backtrack_winner(@setup, layers.span(), time));
            let (layers, time) = forward_corelib(@setup);
            paths.append(backtrack_winner(@setup, layers.span(), time));
            let (layers, times, time) = forward_sparse(@setup);
            paths.append(backtrack_sparse(@setup, layers.span(), times.span(), time));
            let (layers, time) = forward_winner(@setup);
            paths.append(backtrack_bits(@setup, layers.span(), time));
            paths.append(dijkstra_heap(grid, 17, 14, from, to, costs));
            if costs.len() == 0 {
                let (layers, time) = forward_unit(@setup);
                paths.append(backtrack_winner(@setup, layers.span(), time));
            }
            for path in paths.span() {
                check_path(grid, 17, 14, from, to, costs, *path, expected);
            }
            // The harness copy of the winner returns the library path
            assert!(*paths[0] == Dial::search(grid, 17, 14, from, to, costs));
        }
    }

    #[test]
    fn test_dial_variants_empty_17x14() {
        check_variants(
            EMPTY_17X14,
            EMPTY_17X14_FAR_FROM,
            EMPTY_17X14_FAR_TO,
            EMPTY_17X14_COST_2,
            EMPTY_17X14_COST_3,
        );
    }

    #[test]
    fn test_dial_variants_cave_17x14() {
        check_variants(
            CAVE_17X14,
            CAVE_17X14_FAR_FROM,
            CAVE_17X14_FAR_TO,
            CAVE_17X14_COST_2,
            CAVE_17X14_COST_3,
        );
        check_variants(
            CAVE_17X14,
            CAVE_17X14_NEAR_FROM,
            CAVE_17X14_NEAR_TO,
            CAVE_17X14_COST_2,
            CAVE_17X14_COST_3,
        );
    }

    #[test]
    fn test_dial_variants_maze_17x14() {
        check_variants(
            MAZE_17X14,
            MAZE_17X14_FAR_FROM,
            MAZE_17X14_FAR_TO,
            MAZE_17X14_COST_2,
            MAZE_17X14_COST_3,
        );
    }
}
