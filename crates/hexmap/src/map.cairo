//! HexMap struct and generation methods (lot L8).

// Internal imports

use origami_hexmap::types::direction::Direction;

/// Types.
#[derive(Copy, Drop, Serde)]
pub struct HexMap {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
    pub seed: felt252,
}

/// Implementation of the `HexMapTrait` trait for the `HexMap` struct.
#[generate_trait]
pub impl HexMapImpl of HexMapTrait {
    /// Create a map.
    /// # Arguments
    /// * `grid` - The grid of the map, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The corresponding map
    fn new(grid: felt252, width: u8, height: u8, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Create an empty map: every interior tile is walkable.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    fn new_empty(width: u8, height: u8, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Create a map with a maze.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1, the higher the less dense
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    fn new_maze(width: u8, height: u8, order: u8, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Create a map with a cave.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The number of generations
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    fn new_cave(width: u8, height: u8, order: u8, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Create a map with a random walk.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `steps` - The number of steps
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    fn new_random_walk(width: u8, height: u8, steps: u16, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Create an empty hexagon of radius `radius` in its `(2R+3) x (2R+3)` rectangle.
    /// # Arguments
    /// * `radius` - The radius, at most 6
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    fn new_hexagon(radius: u8, seed: felt252) -> HexMap {
        panic!("unimplemented")
    }

    /// Open the map with a corridor from an edge tile.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The edge tile, not a corner
    /// * `order` - The order of the corridor, 0 or 1
    /// # Effects
    /// * The grid is updated
    fn open_with_corridor(ref self: HexMap, position: u8, order: u8) {
        panic!("unimplemented")
    }

    /// Open the map with a maze from an edge tile.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The edge tile, not a corner
    /// * `order` - The order of the maze, 0 or 1
    /// # Effects
    /// * The grid is updated
    fn open_with_maze(ref self: HexMap, position: u8, order: u8) {
        panic!("unimplemented")
    }

    /// Pick `count` walkable tiles uniformly.
    /// # Arguments
    /// * `self` - The map
    /// * `count` - The number of tiles to pick
    /// * `seed` - The seed of the draw
    /// # Returns
    /// * The bitmap of the picked tiles
    fn compute_distribution(self: HexMap, count: u8, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }

    /// Search the shortest path between two tiles (bit-parallel BFS).
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    fn search_path(self: HexMap, from: u8, to: u8) -> Span<u8> {
        panic!("unimplemented")
    }

    /// Search the cheapest path between two tiles (bit-parallel Dial).
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// * `costs` - `costs[k]` is the bitmap of the tiles of cost `k + 2`, at most 3 items
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    fn search_path_weighted(self: HexMap, from: u8, to: u8, costs: Span<felt252>) -> Span<u8> {
        panic!("unimplemented")
    }

    /// Every tile reachable from a position.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// # Returns
    /// * The bitmap of the reachable tiles
    fn reachable(self: HexMap, from: u8) -> felt252 {
        panic!("unimplemented")
    }

    /// Every walkable tile reachable within `range` steps of a position.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The centre position
    /// * `range` - The number of steps
    /// # Returns
    /// * The bitmap of the tiles in range
    fn tiles_within_range(self: HexMap, position: u8, range: u8) -> felt252 {
        panic!("unimplemented")
    }

    /// Grid distance between two positions, ignoring walls.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The first position
    /// * `to` - The second position
    /// # Returns
    /// * The distance
    fn distance(self: HexMap, from: u8, to: u8) -> u8 {
        panic!("unimplemented")
    }

    /// Neighbour of a position, `None` outside the board.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The position
    /// * `direction` - The direction
    /// # Returns
    /// * The neighbour position
    fn neighbor(self: HexMap, position: u8, direction: Direction) -> Option<u8> {
        panic!("unimplemented")
    }
}
