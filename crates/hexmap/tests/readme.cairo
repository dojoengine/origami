//! The examples of `README.md`, compiled against the public API (integration test: the
//! `pub(crate)` internals are out of reach here, as for a dependent package).

use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::{Direction, HexMap, HexMapTrait, U252Trait, u252};

const SEED: felt252 = 'SEED';

/// The README map: a 17x14 cave kept connected to 113 and opened from the edge tile 8.
fn opened() -> HexMap {
    let mut map = HexMapTrait::new_cave(17, 14, 3, SEED);
    map.keep_component(113);
    map.open_with_corridor(8, 0);
    map
}

#[test]
fn test_readme_create() {
    let seed = SEED;
    let grid = HexMapTrait::new_cave(17, 14, 3, seed).grid;
    // From an existing grid (no check)
    let map = HexMapTrait::new(grid, 17, 14, seed);
    assert!(map.grid == grid);
    // Every interior tile walkable
    let map = HexMapTrait::new_empty(17, 14, seed);
    assert!(map.grid == LayoutTrait::interior(17, 14));
    // A maze, order 0 (dense) or 1 (sparse, walls at least 2 thick)
    let map = HexMapTrait::new_maze(17, 14, 0, seed);
    assert!(map.grid != 0);
    // A cave: cellular automaton B4/S2, `order` generations, 3 is a good default
    let map = HexMapTrait::new_cave(17, 14, 3, seed);
    assert!(map.grid == grid);
    // A random walk of `steps` steps from a random interior tile
    let map = HexMapTrait::new_random_walk(17, 14, 500, seed);
    assert!(map.grid != 0);
    // A hexagon of radius 4 in a 11x11 board
    let map = HexMapTrait::new_hexagon(4, seed);
    assert!(map.width == 11 && map.height == 11);
}

#[test]
fn test_readme_open() {
    let seed = SEED;
    let mut map = HexMapTrait::new_cave(17, 14, 3, seed);
    // Keep the cave connected to tile 113 (flood fill)
    map.keep_component(113);
    let kept = map;
    // Dig a corridor from the edge tile 8 until it touches an open tile
    map.open_with_corridor(8, 0);
    assert!(map.is_walkable(8));
    // Or grow a maze from an edge tile, merged with the open tiles it touches
    let mut map = kept;
    map.open_with_maze(8, 0);
    assert!(map.is_walkable(8));
}

#[test]
fn test_readme_place_objects() {
    let map = opened();
    let seed = SEED;
    // 10 distinct walkable tiles, uniform, as a bitmap
    let objects: felt252 = map.compute_distribution(10, seed);
    let objects: u256 = objects.into();
    let grid: u256 = map.grid.into();
    assert!(objects & grid == objects);
}

#[test]
fn test_readme_find_paths() {
    let map = opened();
    let swamps = map.range(113, 2);
    let mountains = map.ring(113, 4);
    // Shortest path, from the target (included) to the start (excluded), empty if unreachable
    let path: Span<u8> = map.search_path(8, 202);
    assert!(path.len() == 15);
    // Number of steps only, `None` if unreachable
    let steps: Option<u8> = map.distance_to(8, 202);
    assert!(steps == Option::Some(15));
    // Distance on an empty board, walls ignored
    let d: u8 = map.hex_distance(8, 202);
    assert!(d <= 15);
    // Cheapest path with entry costs
    let costs = array![swamps, mountains].span();
    let path: Span<u8> = map.search_path_weighted(8, 202, costs);
    assert!(path.len() >= 15);
}

#[test]
fn test_readme_query_areas() {
    let map = opened();
    let costs = array![map.range(113, 2)].span();
    // Every tile reachable from 113
    let component: felt252 = map.reachable(113);
    assert!(component == map.grid);
    // Tiles within 4 steps (walls block), 113 included
    let area: felt252 = map.range(113, 4);
    // Tiles at exactly 4 steps
    let ring: felt252 = map.ring(113, 4);
    assert!(ring == area - map.range(113, 3));
    // Tiles reachable with a movement budget of 6 under the cost classes
    let moves: felt252 = map.field_of_movement(113, 6, costs);
    assert!(moves != 0);
    // Neighbour, `None` outside the board
    let next: Option<u8> = map.neighbor(113, Direction::NorthEast);
    // 113 is on an even row: NorthEast is `i + W - 1`
    assert!(next == Option::Some(113 + 17 - 1));
    let open: bool = map.is_walkable(113);
    assert!(open);
}

#[test]
#[should_panic(expected: 'Bfs: position not walkable')]
fn test_readme_endpoint_on_wall_panics() {
    let map = opened();
    // Tile 0 is a corner of the wall ring
    map.search_path(0, 202);
}

#[test]
fn test_readme_u252() {
    let map = opened();
    let seed = SEED;
    let objects: u252 = map.compute_distribution(10, seed).into(); // free
    let raw: felt252 = objects.into(); // free
    assert!(raw == map.compute_distribution(10, seed));
    assert!(objects.value() == raw);
}

#[test]
fn test_readme_migration() {
    // `Hex { col: 0, row: 0 }` of `origami_map::hex` on a 17x14 board
    let index = LayoutTrait::index(17, 0 + 1, 0 + 2);
    let layout = LayoutTrait::new(17, 14);
    let map = HexMapTrait::new_empty(17, 14, SEED);
    // Six neighbours, as a bitmap
    let neighbours: u256 = layout.neighbour_mask(index).into();
    let ring: u256 = map.ring(index, 1).into();
    let grid: u256 = map.grid.into();
    assert!(neighbours & grid == ring);
    // `hex.is_neighbor(other)`
    assert!(map.hex_distance(index, index + 1) == 1);
}
