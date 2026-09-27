//! Gas benchmarks of lot L8, facade end-to-end: one `#[test]` per fixture and algorithm, each with
//! an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! `bench_map_<function>` calls the facade and `bench_map_direct_<function>` the library function
//! it forwards to, on the same inputs: the difference is the facade overhead.
//! `bench_map_scenario_*`
//! run the end-to-end scenario `new_cave` + `keep_component` + `open_with_corridor` +
//! `compute_distribution(10)` + `search_path`, one test per prefix: the cost of a step is the
//! difference between two consecutive prefixes.

// Core imports

#[feature("bounded-int-utils")]
use core::internal::bounded_int::{
    BoundedInt, ConstrainHelper, MulHelper, SubHelper, constrain, mul, sub,
};

// Internal imports

use origami_hexmap::finders::bfs::Bfs;
use origami_hexmap::finders::dial::Dial;
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::generators::digger::Digger;
use origami_hexmap::generators::mazer::Mazer;
use origami_hexmap::generators::spreader::Spreader;
use origami_hexmap::generators::walker::Walker;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::geometry::Geometry;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::map::{HexMap, HexMapTrait};
use origami_hexmap::tests::bench_dial::{CAVE_17X14_COST_2, CAVE_17X14_COST_3};
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::types::direction::Direction;

// Constants

const SEED: felt252 = 'SEED';

/// Repetitions of the query benchmarks.
const REPS: u8 = 100;

// Scenario 17x14: seed, a tile of the main cave, the corridor entrance and the path target.
const LARGE_SEED: felt252 = 'SEED';
const LARGE_KEEP: u8 = 113;
const LARGE_ENTRANCE: u8 = 8;
const LARGE_TARGET: u8 = 202;

// Scenario 7x7.
const SMALL_SEED: felt252 = 'ORIGAMI';
const SMALL_KEEP: u8 = 24;
const SMALL_ENTRANCE: u8 = 27;
const SMALL_TARGET: u8 = 8;

/// Entrance of the corridor tests, on the bottom edge of `CAVE_17X14`.
const CORRIDOR_ENTRANCE: u8 = 8;
/// Entrance of the maze tests.
const MAZE_ENTRANCE: u8 = 8;

/// A map on a fixture.
fn cave() -> HexMap {
    HexMapTrait::new(CAVE_17X14, 17, 14, SEED)
}

// Constructors

#[test]
#[available_gas(l2_gas: 20000)]
fn bench_map_new_empty() {
    let map = HexMapTrait::new_empty(17, 14, SEED);
    assert!(map.grid == EMPTY_17X14);
}

#[test]
#[available_gas(l2_gas: 20000)]
fn bench_map_direct_new_empty() {
    Asserter::assert_valid_dimension(17, 14);
    let grid = LayoutTrait::interior(17, 14);
    assert!(grid == EMPTY_17X14);
}

#[test]
#[available_gas(l2_gas: 3018000)]
fn bench_map_new_maze() {
    HexMapTrait::new_maze(17, 14, 0, SEED);
}

#[test]
#[available_gas(l2_gas: 3018000)]
fn bench_map_direct_new_maze() {
    Mazer::generate(17, 14, 0, SEED);
}

#[test]
#[available_gas(l2_gas: 153000)]
fn bench_map_new_cave() {
    HexMapTrait::new_cave(17, 14, 3, SEED);
}

#[test]
#[available_gas(l2_gas: 153000)]
fn bench_map_direct_new_cave() {
    Caver::generate(17, 14, 3, SEED);
}

#[test]
#[available_gas(l2_gas: 1050000)]
fn bench_map_new_random_walk() {
    HexMapTrait::new_random_walk(17, 14, 200, SEED);
}

#[test]
#[available_gas(l2_gas: 1050000)]
fn bench_map_direct_new_random_walk() {
    Walker::generate(17, 14, 200, SEED);
}

#[test]
#[available_gas(l2_gas: 133000)]
fn bench_map_new_hexagon() {
    HexMapTrait::new_hexagon(6, SEED);
}

#[test]
#[available_gas(l2_gas: 133000)]
fn bench_map_direct_new_hexagon() {
    Asserter::assert_valid_dimension(15, 15);
    LayoutTrait::hexagon(6);
}

// Openings

#[test]
#[available_gas(l2_gas: 67000)]
fn bench_map_open_with_corridor() {
    let mut map = cave();
    map.open_with_corridor(CORRIDOR_ENTRANCE, 0);
}

#[test]
#[available_gas(l2_gas: 67000)]
fn bench_map_direct_open_with_corridor() {
    Digger::corridor(17, 14, 0, CORRIDOR_ENTRANCE, CAVE_17X14, SEED);
}

#[test]
#[available_gas(l2_gas: 65000)]
fn bench_map_open_with_maze() {
    let mut map = cave();
    map.open_with_maze(MAZE_ENTRANCE, 0);
}

#[test]
#[available_gas(l2_gas: 65000)]
fn bench_map_direct_open_with_maze() {
    Digger::maze(17, 14, 0, MAZE_ENTRANCE, CAVE_17X14, SEED);
}

// Connectivity: the facade uses `Bfs::reachable` for its edge semantics (open edge tiles next to
// the component are kept); `Caver::keep_component` floods the interior only, without the checks

#[test]
#[available_gas(l2_gas: 583000)]
fn bench_map_keep_component() {
    let mut map = cave();
    map.keep_component(CAVE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 583000)]
fn bench_map_direct_keep_component() {
    Bfs::reachable(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 561000)]
fn bench_map_variant_keep_component_caver() {
    Caver::keep_component(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 108000)]
fn bench_map_keep_component_7x7() {
    let mut map = HexMapTrait::new(CAVE_7X7, 7, 7, SEED);
    map.keep_component(CAVE_7X7_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 101000)]
fn bench_map_variant_keep_component_caver_7x7() {
    Caver::keep_component(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 1211000)]
fn bench_map_keep_component_maze() {
    let mut map = HexMapTrait::new(MAZE_17X14, 17, 14, SEED);
    map.keep_component(MAZE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 1167000)]
fn bench_map_variant_keep_component_caver_maze() {
    Caver::keep_component(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
}

// Distribution

#[test]
#[available_gas(l2_gas: 203000)]
fn bench_map_compute_distribution() {
    cave().compute_distribution(10, SEED);
}

#[test]
#[available_gas(l2_gas: 203000)]
fn bench_map_direct_compute_distribution() {
    Spreader::generate(CAVE_17X14, 17, 14, 10, SEED);
}

// Finders

#[test]
#[available_gas(l2_gas: 742000)]
fn bench_map_search_path() {
    let path = cave().search_path(CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 742000)]
fn bench_map_direct_search_path() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1500000)]
fn bench_map_search_path_weighted() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    cave().search_path_weighted(CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 1500000)]
fn bench_map_direct_search_path_weighted() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
}

#[test]
#[available_gas(l2_gas: 275000)]
fn bench_map_field_of_movement() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    cave().field_of_movement(CAVE_17X14_FAR_FROM, 6, costs);
}

#[test]
#[available_gas(l2_gas: 275000)]
fn bench_map_direct_field_of_movement() {
    let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
    Dial::field_of_movement(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 6, costs);
}

#[test]
#[available_gas(l2_gas: 527000)]
fn bench_map_distance_to() {
    let distance = cave().distance_to(CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(distance == Some(24));
}

#[test]
#[available_gas(l2_gas: 527000)]
fn bench_map_direct_distance_to() {
    let distance = Bfs::distance(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(distance == Some(24));
}

#[test]
#[available_gas(l2_gas: 583000)]
fn bench_map_reachable() {
    cave().reachable(CAVE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 583000)]
fn bench_map_direct_reachable() {
    Bfs::reachable(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM);
}

#[test]
#[available_gas(l2_gas: 109000)]
fn bench_map_range() {
    cave().range(CAVE_17X14_FAR_FROM, 4);
}

#[test]
#[available_gas(l2_gas: 109000)]
fn bench_map_direct_range() {
    Bfs::tiles_within_range(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 4);
}

#[test]
#[available_gas(l2_gas: 105000)]
fn bench_map_ring() {
    cave().ring(CAVE_17X14_FAR_FROM, 4);
}

/// Loser: two `range` calls (the facade falls back to it on grids with open edge tiles).
#[test]
#[available_gas(l2_gas: 186000)]
fn bench_map_variant_ring_two_ranges() {
    let outer = Bfs::tiles_within_range(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 4);
    let inner = Bfs::tiles_within_range(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 3);
    assert!(outer != inner);
}

#[test]
#[available_gas(l2_gas: 49000)]
fn bench_map_ring_7x7() {
    HexMapTrait::new(CAVE_7X7, 7, 7, SEED).ring(CAVE_7X7_FAR_FROM, 2);
}

#[test]
#[available_gas(l2_gas: 84000)]
fn bench_map_variant_ring_two_ranges_7x7() {
    let outer = Bfs::tiles_within_range(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, 2);
    let inner = Bfs::tiles_within_range(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, 1);
    assert!(outer != inner);
}

/// Fallback path: the same cave with an open edge tile.
#[test]
#[available_gas(l2_gas: 177000)]
fn bench_map_ring_open_edge() {
    let mut map = cave();
    map.open_with_corridor(CORRIDOR_ENTRANCE, 0);
    map.ring(CAVE_17X14_FAR_FROM, 4);
}

/// Same grid, two `range` calls without the facade prologue: the cost of the fallback test.
#[test]
#[available_gas(l2_gas: 283000)]
fn bench_map_variant_ring_two_ranges_open_edge() {
    let mut map = cave();
    map.open_with_corridor(CORRIDOR_ENTRANCE, 0);
    let outer = Bfs::tiles_within_range(map.grid, 17, 14, CAVE_17X14_FAR_FROM, 4);
    let inner = Bfs::tiles_within_range(map.grid, 17, 14, CAVE_17X14_FAR_FROM, 3);
    assert!(outer != inner);
}

// Queries

/// Loop baseline of the query benchmarks: 100 iterations, see `GAS.md`.
#[test]
#[available_gas(l2_gas: 150000)]
fn bench_map_loop_baseline() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 1241000)]
fn bench_map_hex_distance() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += map.hex_distance(n, 237 - n).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1143000)]
fn bench_map_direct_hex_distance() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Geometry::distance(17, n, 237 - n).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 880000)]
fn bench_map_neighbor() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if let Some(next) = map.neighbor(n + 20, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 821000)]
fn bench_map_direct_neighbor() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if let Some(next) = LayoutTrait::neighbor(17, 14, n + 20, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 892000)]
fn bench_map_is_walkable() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if map.is_walkable(n + n) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 893000)]
fn bench_map_direct_is_walkable() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if Bits::get(CAVE_17X14.into(), n + n) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

// Scenario 17x14, one test per prefix

#[test]
#[available_gas(l2_gas: 153000)]
fn bench_map_scenario_17x14_1_cave() {
    HexMapTrait::new_cave(17, 14, 3, LARGE_SEED);
}

#[test]
#[available_gas(l2_gas: 351000)]
fn bench_map_scenario_17x14_2_keep() {
    let mut map = HexMapTrait::new_cave(17, 14, 3, LARGE_SEED);
    map.keep_component(LARGE_KEEP);
}

#[test]
#[available_gas(l2_gas: 523000)]
fn bench_map_scenario_17x14_3_corridor() {
    let mut map = HexMapTrait::new_cave(17, 14, 3, LARGE_SEED);
    map.keep_component(LARGE_KEEP);
    map.open_with_corridor(LARGE_ENTRANCE, 0);
}

#[test]
#[available_gas(l2_gas: 721000)]
fn bench_map_scenario_17x14_4_distribution() {
    let mut map = HexMapTrait::new_cave(17, 14, 3, LARGE_SEED);
    map.keep_component(LARGE_KEEP);
    map.open_with_corridor(LARGE_ENTRANCE, 0);
    map.compute_distribution(10, LARGE_SEED);
}

#[test]
#[available_gas(l2_gas: 1222000)]
fn bench_map_scenario_17x14_5_total() {
    let mut map = HexMapTrait::new_cave(17, 14, 3, LARGE_SEED);
    map.keep_component(LARGE_KEEP);
    map.open_with_corridor(LARGE_ENTRANCE, 0);
    map.compute_distribution(10, LARGE_SEED);
    let path = map.search_path(LARGE_ENTRANCE, LARGE_TARGET);
    assert!(path.len() != 0);
}

// Scenario 7x7

#[test]
#[available_gas(l2_gas: 88000)]
fn bench_map_scenario_7x7_1_cave() {
    HexMapTrait::new_cave(7, 7, 3, SMALL_SEED);
}

#[test]
#[available_gas(l2_gas: 149000)]
fn bench_map_scenario_7x7_2_keep() {
    let mut map = HexMapTrait::new_cave(7, 7, 3, SMALL_SEED);
    map.keep_component(SMALL_KEEP);
}

#[test]
#[available_gas(l2_gas: 200000)]
fn bench_map_scenario_7x7_3_corridor() {
    let mut map = HexMapTrait::new_cave(7, 7, 3, SMALL_SEED);
    map.keep_component(SMALL_KEEP);
    map.open_with_corridor(SMALL_ENTRANCE, 0);
}

#[test]
#[available_gas(l2_gas: 325000)]
fn bench_map_scenario_7x7_4_distribution() {
    let mut map = HexMapTrait::new_cave(7, 7, 3, SMALL_SEED);
    map.keep_component(SMALL_KEEP);
    map.open_with_corridor(SMALL_ENTRANCE, 0);
    map.compute_distribution(10, SMALL_SEED);
}

#[test]
#[available_gas(l2_gas: 510000)]
fn bench_map_scenario_7x7_5_total() {
    let mut map = HexMapTrait::new_cave(7, 7, 3, SMALL_SEED);
    map.keep_component(SMALL_KEEP);
    map.open_with_corridor(SMALL_ENTRANCE, 0);
    map.compute_distribution(10, SMALL_SEED);
    let path = map.search_path(SMALL_ENTRANCE, SMALL_TARGET);
    assert!(path.len() != 0);
}

// Audit A4: bound checks of `neighbor`, `is_walkable` and `hex_distance`. The library uses the
// `bounded_int` form of `map.cairo` (`bench_map_neighbor`, `bench_map_is_walkable`,
// `bench_map_hex_distance`); the losers below are test-only, see `GAS.md`, F1.

/// `W * H` as a bounded integer.
impl SizeMul of MulHelper<u8, u8> {
    type Result = BoundedInt<0, 65025>;
}

/// `position - W * H`.
impl PositionSub of SubHelper<u8, BoundedInt<0, 65025>> {
    type Result = BoundedInt<-65025, 255>;
}

/// Sign of `position - W * H`.
impl PositionConstrain of ConstrainHelper<BoundedInt<-65025, 255>, 0> {
    type LowT = BoundedInt<-65025, -1>;
    type HighT = BoundedInt<0, 255>;
}

/// Inside test: `u16` product and comparison.
#[inline(always)]
fn inside_u16(width: u8, height: u8, position: u8) -> bool {
    let size: u16 = width.into() * height.into();
    position.into() < size
}

/// Inside test: `u8` product (panics on dimensions above 255 tiles).
#[inline(always)]
fn inside_u8(width: u8, height: u8, position: u8) -> bool {
    position < width * height
}

/// `LayoutTrait::neighbor` with the row test `y >= H` after its division.
fn neighbor_row(width: u8, height: u8, position: u8, direction: Direction) -> Option<u8> {
    let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
    if y >= height {
        return None;
    }
    let odd = y % 2 == 1;
    match direction {
        Direction::East => if x == 0 {
            None
        } else {
            Some(position - 1)
        },
        Direction::West => if x == width - 1 {
            None
        } else {
            Some(position + 1)
        },
        Direction::NorthEast => if y == height - 1 {
            None
        } else if odd {
            Some(position + width)
        } else if x == 0 {
            None
        } else {
            Some(position + width - 1)
        },
        Direction::NorthWest => if y == height - 1 {
            None
        } else if !odd {
            Some(position + width)
        } else if x == width - 1 {
            None
        } else {
            Some(position + width + 1)
        },
        Direction::SouthEast => if y == 0 {
            None
        } else if odd {
            Some(position - width)
        } else if x == 0 {
            None
        } else {
            Some(position - width - 1)
        },
        Direction::SouthWest => if y == 0 {
            None
        } else if !odd {
            Some(position - width)
        } else if x == width - 1 {
            None
        } else {
            Some(position + 1 - width)
        },
    }
}

#[test]
#[available_gas(l2_gas: 901000)]
fn bench_map_variant_neighbor_u16() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let position = n + 20;
        if !inside_u16(map.width, map.height, position) {
            continue;
        }
        if let Some(next) =
            LayoutTrait::neighbor(map.width, map.height, position, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 901000)]
fn bench_map_variant_neighbor_u8() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let position = n + 20;
        if !inside_u8(map.width, map.height, position) {
            continue;
        }
        if let Some(next) =
            LayoutTrait::neighbor(map.width, map.height, position, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 890000)]
fn bench_map_variant_neighbor_row() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if let Some(next) = neighbor_row(map.width, map.height, n + 20, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 907000)]
fn bench_map_variant_is_walkable_u16() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let position = n + n;
        if inside_u16(map.width, map.height, position) && Bits::get(map.grid.into(), position) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 907000)]
fn bench_map_variant_is_walkable_u8() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let position = n + n;
        if inside_u8(map.width, map.height, position) && Bits::get(map.grid.into(), position) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1282000)]
fn bench_map_variant_hex_distance_u16() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (from, to) = (n, 237 - n);
        let size: u16 = map.width.into() * map.height.into();
        assert(from.into() < size && to.into() < size, 'Asserter: position not inside');
        acc += Geometry::distance(map.width, from, to).into();
    }
    assert!(acc != 0);
}

/// `Geometry::distance` with the row tests `y < H` after its divisions.
fn distance_rows(width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (x_from, y_from) = LayoutTrait::coords(width, from);
    let (x_to, y_to) = LayoutTrait::coords(width, to);
    assert(y_from < height && y_to < height, 'Asserter: position not inside');
    let lhs = x_to + y_from / 2;
    let rhs = x_from + y_to / 2;
    let (dq, dq_negative) = if lhs >= rhs {
        (lhs - rhs, false)
    } else {
        (rhs - lhs, true)
    };
    let (dr, dr_negative) = if y_to >= y_from {
        (y_to - y_from, false)
    } else {
        (y_from - y_to, true)
    };
    if dq_negative == dr_negative {
        dq + dr
    } else if dq > dr {
        dq
    } else {
        dr
    }
}

#[test]
#[available_gas(l2_gas: 1445000)]
fn bench_map_variant_hex_distance_rows() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += distance_rows(map.width, map.height, n, 237 - n).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1345000)]
#[feature("bounded-int-utils")]
fn bench_map_variant_hex_distance_bounded_once() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (from, to) = (n, 237 - n);
        let size = mul::<_, _, SizeMul>(map.width, map.height);
        let from_ok =
            match constrain::<_, 0, PositionConstrain>(sub::<_, _, PositionSub>(from, size)) {
            Ok(_) => true,
            Err(_) => false,
        };
        let to_ok = match constrain::<_, 0, PositionConstrain>(sub::<_, _, PositionSub>(to, size)) {
            Ok(_) => true,
            Err(_) => false,
        };
        assert(from_ok && to_ok, 'Asserter: position not inside');
        acc += Geometry::distance(map.width, from, to).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1304000)]
fn bench_map_variant_hex_distance_max() {
    let map = cave();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (from, to) = (n, 237 - n);
        // One comparison: the larger endpoint
        let top = if from > to {
            from
        } else {
            to
        };
        Asserter::assert_inside(map.width, map.height, top);
        acc += Geometry::distance(map.width, from, to).into();
    }
    assert!(acc != 0);
}
