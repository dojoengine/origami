//! Gas benchmarks of lot L8, facade end-to-end: one `#[test]` per fixture and algorithm, each with
//! an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! `bench_map_<function>` calls the facade and `bench_map_direct_<function>` the library function
//! it forwards to, on the same inputs: the difference is the facade overhead.
//! `bench_map_scenario_*`
//! run the end-to-end scenario `new_cave` + `keep_component` + `open_with_corridor` +
//! `compute_distribution(10)` + `search_path`, one test per prefix: the cost of a step is the
//! difference between two consecutive prefixes.

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

// Connectivity: the facade uses `Bfs::reachable`, `Caver::keep_component` is the loser

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
#[available_gas(l2_gas: 610000)]
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
#[available_gas(l2_gas: 177000)]
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
#[available_gas(l2_gas: 1306000)]
fn bench_map_variant_keep_component_caver_maze() {
    Caver::keep_component(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
}

// Distribution

#[test]
#[available_gas(l2_gas: 218000)]
fn bench_map_compute_distribution() {
    cave().compute_distribution(10, SEED);
}

#[test]
#[available_gas(l2_gas: 218000)]
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
#[available_gas(l2_gas: 1143000)]
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
#[available_gas(l2_gas: 821000)]
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
#[available_gas(l2_gas: 837000)]
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
