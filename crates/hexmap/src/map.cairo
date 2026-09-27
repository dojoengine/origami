//! HexMap struct and generation methods.
//!
//! The facade mirrors `origami_map::map::MapTrait` name for name, plus the hex additions. Every
//! method forwards to one library call (see `tests/bench_map.cairo` for the facade overhead).

// Internal imports

use origami_hexmap::finders::bfs::{Bfs, BfsInternal};
use origami_hexmap::finders::dial::Dial;
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::generators::digger::Digger;
use origami_hexmap::generators::mazer::Mazer;
use origami_hexmap::generators::spreader::Spreader;
use origami_hexmap::generators::walker::Walker;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::geometry::Geometry;
use origami_hexmap::helpers::layout::{DilationTrait, LayoutTrait};
use origami_hexmap::types::direction::Direction;

// Constants

/// Largest board of the single-limb path, as in `finders::bfs`.
const SMALL_SIZE: u8 = 128;

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
    #[inline]
    fn new(grid: felt252, width: u8, height: u8, seed: felt252) -> HexMap {
        HexMap { width, height, grid, seed }
    }

    /// Create an empty map: every interior tile is walkable.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    /// # Panics
    /// * If the dimensions are invalid
    #[inline]
    fn new_empty(width: u8, height: u8, seed: felt252) -> HexMap {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Return] Interior mask
        HexMap { width, height, grid: LayoutTrait::interior(width, height), seed }
    }

    /// Create a map with a maze.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1, the higher the less dense
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    /// # Panics
    /// * If the dimensions are invalid or the order is above 1
    #[inline]
    fn new_maze(width: u8, height: u8, order: u8, seed: felt252) -> HexMap {
        let grid = Mazer::generate(width, height, order, seed);
        HexMap { width, height, grid, seed }
    }

    /// Create a map with a cave.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The number of generations of the automaton, 3 is a good default
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    /// # Panics
    /// * If the dimensions are invalid
    #[inline]
    fn new_cave(width: u8, height: u8, order: u8, seed: felt252) -> HexMap {
        let grid = Caver::generate(width, height, order, seed);
        HexMap { width, height, grid, seed }
    }

    /// Create a map with a random walk.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `steps` - The number of steps
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    /// # Panics
    /// * If the dimensions are invalid
    #[inline]
    fn new_random_walk(width: u8, height: u8, steps: u16, seed: felt252) -> HexMap {
        let grid = Walker::generate(width, height, steps, seed);
        HexMap { width, height, grid, seed }
    }

    /// Create an empty hexagon of radius `radius` in its `(2R+3) x (2R+3)` rectangle.
    /// # Arguments
    /// * `radius` - The radius, at most 6
    /// * `seed` - The seed of the map
    /// # Returns
    /// * The generated map
    /// # Panics
    /// * If the radius is above 6
    #[inline]
    fn new_hexagon(radius: u8, seed: felt252) -> HexMap {
        // [Check] The rectangle fits in 251 bits
        let width = 2 * radius + 3;
        Asserter::assert_valid_dimension(width, width);
        // [Return] Hexagon mask
        HexMap { width, height: width, grid: LayoutTrait::hexagon(radius), seed }
    }

    /// Open the map with a corridor from an edge tile, until it touches an open tile.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The edge tile, not a corner
    /// * `order` - The order of the corridor, 0 or 1
    /// # Effects
    /// * The grid is updated
    /// # Panics
    /// * If the order is above 1, or the position is not an edge tile or is a corner
    #[inline]
    fn open_with_corridor(ref self: HexMap, position: u8, order: u8) {
        self
            .grid =
                Digger::corridor(self.width, self.height, order, position, self.grid, self.seed);
    }

    /// Open the map with a maze from an edge tile, merged with the open tiles it touches.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The edge tile, not a corner
    /// * `order` - The order of the maze, 0 or 1
    /// # Effects
    /// * The grid is updated
    /// # Panics
    /// * If the order is above 1, or the position is not an edge tile or is a corner
    #[inline]
    fn open_with_maze(ref self: HexMap, position: u8, order: u8) {
        self.grid = Digger::maze(self.width, self.height, order, position, self.grid, self.seed);
    }

    /// Keep only the walkable tiles reachable from a position (flood fill).
    /// # Arguments
    /// * `self` - The map
    /// * `position` - A walkable position
    /// # Effects
    /// * The grid is updated
    /// # Panics
    /// * If the position is outside the board or not walkable
    #[inline]
    fn keep_component(ref self: HexMap, position: u8) {
        self.grid = Bfs::reachable(self.grid, self.width, self.height, position);
    }

    /// Pick `count` walkable tiles uniformly.
    /// # Arguments
    /// * `self` - The map
    /// * `count` - The number of tiles to pick
    /// * `seed` - The seed of the draw
    /// # Returns
    /// * The bitmap of the picked tiles
    /// # Panics
    /// * If `count` exceeds the number of walkable tiles
    #[inline]
    fn compute_distribution(self: HexMap, count: u8, seed: felt252) -> felt252 {
        Spreader::generate(self.grid, self.width, self.height, count, seed)
    }

    /// Search the shortest path between two tiles (bit-parallel BFS).
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    /// # Panics
    /// * If an endpoint is outside the board or not walkable
    #[inline]
    fn search_path(self: HexMap, from: u8, to: u8) -> Span<u8> {
        Bfs::search(self.grid, self.width, self.height, from, to)
    }

    /// Search the cheapest path between two tiles (bit-parallel Dial).
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// * `costs` - `costs[k]` is the bitmap of the tiles of cost `k + 2`, at most 3 items, the
    /// other walkable tiles cost 1; a tile in several bitmaps takes the highest cost
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    /// # Panics
    /// * If there are more than 3 cost classes, or an endpoint is outside the board or not
    /// walkable
    #[inline]
    fn search_path_weighted(self: HexMap, from: u8, to: u8, costs: Span<felt252>) -> Span<u8> {
        Dial::search(self.grid, self.width, self.height, from, to, costs)
    }

    /// Every tile reachable from a position with a total entry cost of at most `budget`.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `budget` - The movement budget
    /// * `costs` - The cost classes, as in `search_path_weighted`
    /// # Returns
    /// * The bitmap of the reachable tiles, `from` included
    /// # Panics
    /// * If there are more than 3 cost classes, or `from` is outside the board or not walkable
    #[inline]
    fn field_of_movement(self: HexMap, from: u8, budget: u8, costs: Span<felt252>) -> felt252 {
        Dial::field_of_movement(self.grid, self.width, self.height, from, budget, costs)
    }

    /// Length of the shortest path between two tiles, walls included.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The number of steps, `None` if unreachable
    /// # Panics
    /// * If an endpoint is outside the board or not walkable
    #[inline]
    fn distance_to(self: HexMap, from: u8, to: u8) -> Option<u8> {
        Bfs::distance(self.grid, self.width, self.height, from, to)
    }

    /// Grid distance between two positions, ignoring walls.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The first position
    /// * `to` - The second position
    /// # Returns
    /// * The distance
    #[inline]
    fn hex_distance(self: HexMap, from: u8, to: u8) -> u8 {
        Geometry::distance(self.width, from, to)
    }

    /// Every tile reachable from a position.
    /// # Arguments
    /// * `self` - The map
    /// * `from` - The starting position
    /// # Returns
    /// * The bitmap of the reachable tiles, `from` included
    /// # Panics
    /// * If `from` is outside the board or not walkable
    #[inline]
    fn reachable(self: HexMap, from: u8) -> felt252 {
        Bfs::reachable(self.grid, self.width, self.height, from)
    }

    /// Every tile reachable within `range` steps of a position.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The centre position
    /// * `range` - The number of steps
    /// # Returns
    /// * The bitmap of the tiles in range, `position` included
    /// # Panics
    /// * If `position` is outside the board or not walkable
    #[inline]
    fn range(self: HexMap, position: u8, range: u8) -> felt252 {
        Bfs::tiles_within_range(self.grid, self.width, self.height, position, range)
    }

    /// Every tile at exactly `radius` steps of a position, `range(radius)` minus
    /// `range(radius - 1)`, in one flood: the flood of `radius - 2` layers returns the balls of
    /// radius `radius - 1` and `radius - 2`, one dilation of the first gives the ring, and the open
    /// edge tiles next to the first but not to the second are the edge tiles of the ring.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The centre position
    /// * `radius` - The number of steps
    /// # Returns
    /// * The bitmap of the ring, `position` alone for radius 0
    /// # Panics
    /// * If `position` is outside the board or not walkable
    fn ring(self: HexMap, position: u8, radius: u8) -> felt252 {
        // [Check] Dimensions and position
        let (grid, width, height) = (self.grid, self.width, self.height);
        let open: u256 = BfsInternal::check_one(grid, width, height, position);
        let power = Bits::pow(position);
        if radius == 0 {
            return power;
        }
        // [Compute] Constants and centre
        let (step, back, free) = BfsInternal::constants(open, width, height);
        let centre = BfsInternal::endpoint(@back, height, position);
        if !centre.interior {
            // [Return] An open edge centre: the inner ball is a subset of the outer one
            let outer = Bfs::tiles_within_range(grid, width, height, position, radius);
            return outer - Bfs::tiles_within_range(grid, width, height, position, radius - 1);
        }
        if radius == 1 {
            return Bits::to_felt(Bits::and(centre.around.into(), open));
        }
        // [Compute] Balls of radius `radius - 1` and `radius - 2`
        let first = Bits::and((centre.around + power).into(), free);
        let edges = grid - Bits::to_felt(free);
        if width * height <= SMALL_SIZE {
            let (ball, inner) = BfsInternal::flood_small(@step, first.low, free.low, radius - 2);
            let inner = if radius == 2 {
                power
            } else {
                inner
            };
            // [Compute] Interior tiles of the ring
            let near = step.expand_small(ball.try_into().unwrap());
            let ring: felt252 = (near & free.low).into() - ball;
            if edges == 0 {
                return ring;
            }
            // [Return] Plus the edge tiles next to the ball but not to the inner ball
            let edges: u128 = edges.try_into().unwrap();
            let far = step.expand_small(inner.try_into().unwrap());
            return ring + (near & edges).into() - (far & edges).into();
        }
        let (ball, inner) = BfsInternal::flood(@step, first, free, radius - 2);
        let inner = if radius == 2 {
            power
        } else {
            inner
        };
        // [Compute] Interior tiles of the ring
        let wide: u256 = ball.into();
        let (low, high) = step.dilate(wide.low, wide.high, ball);
        let near = u256 { low, high };
        let ring = Bits::to_felt(Bits::and(near, free)) - ball;
        if edges == 0 {
            return ring;
        }
        // [Return] Plus the edge tiles next to the ball but not to the inner ball
        let edges: u256 = edges.into();
        let wide: u256 = inner.into();
        let (low, high) = step.dilate(wide.low, wide.high, inner);
        let far = u256 { low, high };
        ring + Bits::to_felt(Bits::and(near, edges)) - Bits::to_felt(Bits::and(far, edges))
    }

    /// Neighbour of a position, `None` outside the board.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The position
    /// * `direction` - The direction
    /// # Returns
    /// * The neighbour position
    #[inline]
    fn neighbor(self: HexMap, position: u8, direction: Direction) -> Option<u8> {
        LayoutTrait::neighbor(self.width, self.height, position, direction)
    }

    /// Whether a position is walkable.
    /// # Arguments
    /// * `self` - The map
    /// * `position` - The position, at most 251
    /// # Returns
    /// * `true` if the tile is walkable
    #[inline]
    fn is_walkable(self: HexMap, position: u8) -> bool {
        Bits::get(self.grid.into(), position)
    }
}

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::finders::bfs::Bfs;
    use origami_hexmap::finders::dial::Dial;
    use origami_hexmap::generators::caver::Caver;
    use origami_hexmap::generators::digger::Digger;
    use origami_hexmap::generators::mazer::Mazer;
    use origami_hexmap::generators::spreader::Spreader;
    use origami_hexmap::generators::walker::Walker;
    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::geometry::Geometry;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::tests::bench_dial::{CAVE_17X14_COST_2, CAVE_17X14_COST_3};
    use origami_hexmap::tests::fixtures::*;
    use origami_hexmap::types::direction::Direction;

    // Local imports

    use super::{HexMap, HexMapTrait};

    // Constants

    const SEED: felt252 = 'SEED';

    /// A map on the cave fixture.
    fn cave() -> HexMap {
        HexMapTrait::new(CAVE_17X14, 17, 14, SEED)
    }

    /// Every ring up to `max` equals `range(r) - range(r - 1)`.
    fn check_rings(map: HexMap, position: u8, max: u8) {
        assert!(map.ring(position, 0) == Bits::pow(position));
        let mut radius: u8 = 1;
        while radius != max {
            let expected = map.range(position, radius) - map.range(position, radius - 1);
            assert!(map.ring(position, radius) == expected);
            radius += 1;
        }
    }

    #[test]
    fn test_map_new() {
        let map = HexMapTrait::new(CAVE_17X14, 17, 14, SEED);
        assert!(map.width == 17);
        assert!(map.height == 14);
        assert!(map.grid == CAVE_17X14);
        assert!(map.seed == SEED);
    }

    #[test]
    fn test_map_new_empty() {
        assert!(HexMapTrait::new_empty(17, 14, SEED).grid == EMPTY_17X14);
        assert!(HexMapTrait::new_empty(7, 7, SEED).grid == EMPTY_7X7);
        assert!(HexMapTrait::new_empty(3, 3, SEED).grid == Bits::pow(4));
    }

    #[test]
    fn test_map_new_generators() {
        assert!(HexMapTrait::new_maze(17, 14, 0, SEED).grid == Mazer::generate(17, 14, 0, SEED));
        assert!(HexMapTrait::new_maze(19, 13, 1, SEED).grid == Mazer::generate(19, 13, 1, SEED));
        assert!(HexMapTrait::new_cave(17, 14, 3, SEED).grid == Caver::generate(17, 14, 3, SEED));
        let map = HexMapTrait::new_random_walk(7, 7, 50, SEED);
        assert!(map.grid == Walker::generate(7, 7, 50, SEED));
        assert!(map.width == 7 && map.height == 7 && map.seed == SEED);
    }

    #[test]
    fn test_map_new_hexagon() {
        //  0 0 0 0 0 0 0
        // 0 0 1 1 1 0 0
        //  0 1 1 1 1 0 0
        // 0 1 1 1 1 1 0
        //  0 1 1 1 1 0 0
        // 0 0 1 1 1 0 0
        //  0 0 0 0 0 0 0
        let map = HexMapTrait::new_hexagon(2, SEED);
        assert!(map.width == 7 && map.height == 7);
        assert!(map.grid == 0xe3c7cf0e00);
        let map = HexMapTrait::new_hexagon(6, SEED);
        assert!(map.width == 15 && map.height == 15);
        assert!(map.grid == LayoutTrait::hexagon(6));
        // Every tile of the hexagon is within `radius` of the centre
        assert!(map.range(112, 6) == map.grid);
    }

    #[test]
    fn test_map_open() {
        let mut map = cave();
        map.open_with_corridor(8, 0);
        assert!(map.grid == Digger::corridor(17, 14, 0, 8, CAVE_17X14, SEED));
        let mut map = HexMapTrait::new_empty(17, 14, SEED);
        map.open_with_maze(8, 1);
        assert!(map.grid == Digger::maze(17, 14, 1, 8, EMPTY_17X14, SEED));
    }

    #[test]
    fn test_map_keep_component() {
        let mut map = HexMapTrait::new(UNREACHABLE_17X14, 17, 14, SEED);
        map.keep_component(UNREACHABLE_17X14_FAR_FROM);
        let expected = Caver::keep_component(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM);
        assert!(map.grid == expected);
        assert!(map.grid != UNREACHABLE_17X14);
        assert!(!map.is_walkable(UNREACHABLE_17X14_FAR_TO));
        let mut map = HexMapTrait::new(CAVE_7X7, 7, 7, SEED);
        map.keep_component(CAVE_7X7_FAR_FROM);
        assert!(map.grid == Caver::keep_component(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM));
    }

    #[test]
    fn test_map_compute_distribution() {
        let objects = cave().compute_distribution(10, SEED);
        assert!(objects == Spreader::generate(CAVE_17X14, 17, 14, 10, SEED));
        assert!(Bits::popcount(objects.into()) == 10);
    }

    #[test]
    fn test_map_finders() {
        let map = cave();
        let (from, to) = (CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
        let path = map.search_path(from, to);
        assert!(path == Bfs::search(CAVE_17X14, 17, 14, from, to));
        assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
        assert!(map.distance_to(from, to) == Some(24));
        assert!(map.hex_distance(from, to) == Geometry::distance(17, from, to));
        let costs = array![CAVE_17X14_COST_2, CAVE_17X14_COST_3].span();
        let weighted = map.search_path_weighted(from, to, costs);
        assert!(weighted == Dial::search(CAVE_17X14, 17, 14, from, to, costs));
        let field = map.field_of_movement(from, 6, costs);
        assert!(field == Dial::field_of_movement(CAVE_17X14, 17, 14, from, 6, costs));
        assert!(map.reachable(from) == Bfs::reachable(CAVE_17X14, 17, 14, from));
        assert!(map.range(from, 4) == Bfs::tiles_within_range(CAVE_17X14, 17, 14, from, 4));
    }

    #[test]
    fn test_map_distance_unreachable() {
        let map = HexMapTrait::new(UNREACHABLE_17X14, 17, 14, SEED);
        let distance = map.distance_to(UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO);
        assert!(distance.is_none());
        assert!(map.search_path(UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO).len() == 0);
    }

    #[test]
    fn test_map_ring_fused() {
        // No open edge tile, both limbs and single limb
        check_rings(cave(), CAVE_17X14_FAR_FROM, 30);
        check_rings(HexMapTrait::new(MAZE_17X14, 17, 14, SEED), MAZE_17X14_FAR_FROM, 60);
        check_rings(HexMapTrait::new(CAVE_7X7, 7, 7, SEED), CAVE_7X7_FAR_FROM, 8);
        check_rings(HexMapTrait::new(MAZE_7X7, 7, 7, SEED), MAZE_7X7_FAR_FROM, 16);
    }

    #[test]
    fn test_map_ring_open_edge() {
        // Open edge tiles: one flood from the interior, two `range` calls from the entrance
        let mut map = cave();
        map.open_with_corridor(8, 0);
        check_rings(map, CAVE_17X14_FAR_FROM, 30);
        check_rings(map, 8, 30);
        let mut map = HexMapTrait::new(CAVE_7X7, 7, 7, SEED);
        map.open_with_corridor(3, 0);
        check_rings(map, CAVE_7X7_FAR_FROM, 8);
        check_rings(map, 3, 8);
    }

    #[test]
    fn test_map_ring_values() {
        //  0 0 0 0 0 0 0
        // 0 0 1 1 1 0 0
        //  0 1 0 0 1 0 0
        // 0 1 0 0 0 1 0
        //  0 1 0 0 1 0 0
        // 0 0 1 1 1 0 0
        //  0 0 0 0 0 0 0
        let map = HexMapTrait::new_empty(7, 7, SEED);
        assert!(map.ring(24, 2) == 0xe244490e00);
        assert!(Bits::popcount(map.ring(24, 1).into()) == 6);
        // The corners of the rectangle are at distance 3, nothing beyond
        assert!(map.ring(24, 3) == EMPTY_7X7 - LayoutTrait::hexagon(2));
        assert!(map.ring(24, 4) == 0);
    }

    #[test]
    fn test_map_neighbor() {
        let map = cave();
        assert!(map.neighbor(0, Direction::East).is_none());
        assert!(map.neighbor(0, Direction::West) == Some(1));
        assert!(
            map
                .neighbor(
                    20, Direction::NorthEast,
                ) == LayoutTrait::neighbor(17, 14, 20, Direction::NorthEast),
        );
        assert!(map.neighbor(237, Direction::NorthWest).is_none());
    }

    #[test]
    fn test_map_is_walkable() {
        let map = cave();
        assert!(map.is_walkable(CAVE_17X14_FAR_FROM));
        assert!(map.is_walkable(CAVE_17X14_FAR_TO));
        assert!(!map.is_walkable(0));
        assert!(!map.is_walkable(237));
    }

    #[test]
    fn test_map_scenario_17x14() {
        // Cave, component of 113, corridor from 8, 10 objects, path from 8 to 202:
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 E 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 * 1 1 1 1 0 1 1 1 1 0 0 0 0 0 0
        // 0 0 * 1 1 1 1 1 1 1 1 0 0 0 0 0 0
        //  0 0 * 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 1 * 1 1 1 1 1 0 0 0 0 0 0 0 0
        //  0 1 1 * 1 1 1 1 1 1 0 0 0 0 0 0 0
        // 0 0 1 1 * * * * * 1 1 0 0 0 0 0 0
        //  0 1 1 1 0 0 0 0 * 0 0 0 0 0 0 0 0
        // 0 1 1 1 0 0 0 0 0 * 0 0 0 0 0 0 0
        //  0 1 1 1 0 0 0 0 0 * 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 * 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 S 0 0 0 0 0 0 0 0
        let mut map = HexMapTrait::new_cave(17, 14, 3, SEED);
        map.keep_component(113);
        map.open_with_corridor(8, 0);
        assert!(map.grid == 0x400070003ef00ff807f003f803fe00ff80e10070403820001000100);
        let objects = map.compute_distribution(10, SEED);
        assert!(objects == 0x20000280000000000240000c00000010002800000000000);
        let path = map.search_path(8, 202);
        assert!(path.len() == 15);
        assert!(map.distance_to(8, 202) == Some(15));
    }

    #[test]
    fn test_map_scenario_7x7() {
        //  0 0 0 0 0 0 0
        // 0 0 0 1 1 0 0
        //  0 0 1 1 1 0 0
        // S * * * * 1 0
        //  0 0 0 0 * 1 0
        // 0 0 0 0 0 E 0
        //  0 0 0 0 0 0 0
        let mut map = HexMapTrait::new_cave(7, 7, 3, 'ORIGAMI');
        map.keep_component(24);
        map.open_with_corridor(27, 0);
        assert!(map.grid == 0x61cfc18100);
        // The open entrance is walkable: it can receive an object
        let objects = map.compute_distribution(10, 'ORIGAMI');
        assert!(objects == 0x6149c10100);
        assert!(map.search_path(27, 8).len() == 6);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_map_new_empty_revert_invalid_dimension() {
        HexMapTrait::new_empty(16, 16, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_map_new_hexagon_revert_radius() {
        HexMapTrait::new_hexagon(7, SEED);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_map_keep_component_revert_wall() {
        let mut map = cave();
        map.keep_component(0);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_map_ring_revert_wall() {
        cave().ring(0, 2);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not inside')]
    fn test_map_ring_revert_outside() {
        cave().ring(238, 2);
    }

    #[test]
    #[should_panic(expected: 'Dial: too many costs')]
    fn test_map_search_path_weighted_revert_costs() {
        let costs = array![0, 0, 0, 0].span();
        cave().search_path_weighted(CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position is a corner')]
    fn test_map_open_with_corridor_revert_corner() {
        let mut map = cave();
        map.open_with_corridor(0, 0);
    }
}
