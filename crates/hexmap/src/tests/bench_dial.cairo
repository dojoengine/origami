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
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::helpers::rng::RngTrait;
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::Variants;
use origami_hexmap::types::direction::Direction;

// Constants

/// Distance of an unreachable tile.
pub const UNREACHABLE: u32 = 0xffffffff;

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
}
