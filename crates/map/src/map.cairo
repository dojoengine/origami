//! Map struct and generation methods.

// Internal imports

use origami_map::helpers::power::TwoPower;
use origami_map::helpers::mazer::Mazer;
use origami_map::helpers::asserter::Asserter;
use origami_map::helpers::walker::Walker;
use origami_map::helpers::caver::Caver;
use origami_map::helpers::digger::Digger;
use origami_map::helpers::spreader::Spreader;
use origami_map::helpers::astar::Astar;

/// Types.
#[derive(Copy, Drop)]
pub struct Map {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
    pub seed: felt252,
}

/// Implementation of the `MapTrait` trait for the `Map` struct.
#[generate_trait]
pub impl MapImpl of MapTrait {
    /// Create a map.
    /// # Arguments
    /// * `grid` - The grid of the map
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed to generate the map
    /// # Returns
    /// * The corresponding map
    #[inline]
    fn new(grid: felt252, width: u8, height: u8, seed: felt252) -> Map {
        Map { width, height, grid, seed }
    }

    /// Create an empty map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed to generate the map
    /// # Returns
    /// * The generated map
    #[inline]
    fn new_empty(width: u8, height: u8, seed: felt252) -> Map {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Effect] Generate map according to the method
        let grid = Private::empty(width, height);
        // [Effect] Create map
        Map { width, height, grid, seed }
    }

    /// Create a map with a maze.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, it must be 0 or 1, the higher the order the less dense
    /// the maze will be
    /// * `seed` - The seed to generate the map
    /// # Returns
    /// * The generated map
    #[inline]
    fn new_maze(width: u8, height: u8, order: u8, seed: felt252) -> Map {
        let grid = Mazer::generate(width, height, order, seed);
        Map { width, height, grid, seed }
    }

    /// Create a map with a cave.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the cave, the higher the order the more contiguous the cave will be
    /// but also more expensive to generate
    /// * `seed` - The seed to generate the map
    /// # Returns
    /// * The generated map
    #[inline]
    fn new_cave(width: u8, height: u8, order: u8, seed: felt252) -> Map {
        let grid = Caver::generate(width, height, order, seed);
        Map { width, height, grid, seed }
    }

    /// Create a map with a random walk.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `steps` - The number of steps to walk
    /// * `seed` - The seed to generate the map
    /// # Returns
    /// * The generated map
    #[inline]
    fn new_random_walk(width: u8, height: u8, steps: u16, seed: felt252) -> Map {
        let grid = Walker::generate(width, height, steps, seed);
        Map { width, height, grid, seed }
    }

    /// Open the map with a corridor.
    /// # Arguments
    /// * `position` - The position of the corridor
    /// * `order` - The order of the corridor, it must be 0 or 1, the higher the order the less
    /// dense the correlated maze will be
    /// # Returns
    /// * The map with the corridor
    #[inline]
    fn open_with_corridor(ref self: Map, position: u8, order: u8) {
        // [Effect] Add a corridor to open the map
        self
            .grid =
                Digger::corridor(self.width, self.height, order, position, self.grid, self.seed);
    }

    /// Open the map with a maze.
    /// # Arguments
    /// * `position` - The position of the maze
    /// * `order` - The order of the maze, it must be 0 or 1, the higher the order the less dense
    /// the maze will be
    /// # Returns
    /// * The map with the maze
    #[inline]
    fn open_with_maze(ref self: Map, position: u8, order: u8) {
        // [Effect] Add a maze to open the map
        self.grid = Digger::maze(self.width, self.height, order, position, self.grid, self.seed);
    }

    /// Compute a distribution of objects in the map.
    /// # Arguments
    /// * `count` - The number of objects to distribute
    /// # Returns
    /// * The distribution of objects
    #[inline]
    fn compute_distribution(self: Map, count: u8, seed: felt252) -> felt252 {
        Spreader::generate(self.grid, self.width, self.height, count, seed)
    }

    /// Search a path in the map.
    /// # Arguments
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (incl.) to the start (excl.)
    /// * If the path is empty, the target is not reachable
    #[inline]
    fn search_path(self: Map, from: u8, to: u8) -> Span<u8> {
        Astar::search(self.grid, self.width, self.height, from, to)
    }
}

#[generate_trait]
impl Private of PrivateTrait {
    /// Generate an empty map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The generated empty map
    #[inline]
    fn empty(width: u8, height: u8) -> felt252 {
        // [Effect] Generate empty map
        let offset: u256 = TwoPower::pow(width);
        let row: felt252 = ((offset - 1) / 2).try_into().unwrap() - 1; // Remove head and tail bits
        let offset: felt252 = offset.try_into().unwrap();
        let mut index = height - 2;
        let mut default: felt252 = 0;
        loop {
            if index == 0 {
                break;
            };
            default += row;
            default *= offset;
            index -= 1;
        };
        default
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Map, MapTrait};
    use origami_map::helpers::seeder::Seeder;

    // Constants

    const SEED: felt252 = 'S33D';

    #[test]
    fn test_map_new() {
        let width = 18;
        let height = 14;
        let grid = 0x1FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF80002;
        let map: Map = MapTrait::new(grid, width, height, SEED);
        assert_eq!(map.width, width);
        assert_eq!(map.height, height);
        assert_eq!(map.grid, grid);
        assert_eq!(map.seed, SEED);
    }

    #[test]
    fn test_map_new_empty() {
        // 000000000000000000
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let order = 0;
        let mut map: Map = MapTrait::new_empty(width, height, SEED);
        map.open_with_corridor(1, order);
        assert_eq!(map.grid, 0x1FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF80002);
    }

    #[test]
    fn test_map_maze() {
        // 000000000000000000
        // 010111011111110110
        // 011101101000011100
        // 001011011011101010
        // 001100110010011110
        // 011011100111101010
        // 010110011101011010
        // 011011101011010110
        // 001000110110011010
        // 001111011010110110
        // 011001110011000100
        // 010110101101011100
        // 011101111011110110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let order = 0;
        let mut map: Map = MapTrait::new_maze(width, height, order, SEED);
        map.open_with_corridor(1, order);
        assert_eq!(map.grid, 0x177F676870B6EA33279B9EA59D69BAD623668F6B6673116B5C77BD80002);
    }

    #[test]
    fn test_map_cave() {
        // 000000000000000000
        // 001100001100000000
        // 011111001100000000
        // 011111000110000110
        // 011111100111000110
        // 011111100011000000
        // 011111100000000000
        // 011111110000000000
        // 011111111100000000
        // 011111111111000000
        // 011111111111100110
        // 001111111111111110
        // 001111111111111110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let cave_order = 3;
        let corridor_order = 0;
        let seed: felt252 = Seeder::shuffle(SEED, SEED);
        let mut map: Map = MapTrait::new_cave(width, height, cave_order, seed);
        map.open_with_corridor(1, corridor_order);
        assert_eq!(map.grid, 0xC3007CC01F1867E719F8C07E001FC007FC01FFC07FF98FFFE3FFF80002);
    }

    #[test]
    fn test_map_random_walk() {
        // 010000000000000000
        // 010000000011000000
        // 011000000111001100
        // 001101000111111110
        // 011011100011111110
        // 001111111111111110
        // 011010011111111110
        // 001010011101111110
        // 011011111111111110
        // 010011111111111110
        // 010011111111111110
        // 011011111111100000
        // 001101111111100000
        // 000000000000000000
        let width = 18;
        let height = 14;
        let steps: u16 = 2 * width.into() * height.into();
        let order = 0;
        let mut map: Map = MapTrait::new_random_walk(width, height, steps, SEED);
        map.open_with_maze(250, order);
        assert_eq!(map.grid, 0x4000100C060730D1FE6E3F8FFFE69FF8A77E6FFF93FFE4FFF9BFE037F800000);
    }

    #[test]
    fn test_map_compute_distribution() {
        // 000000000000000000
        // 000000000011000000
        // 000000000111001100
        // 000001000111111110
        // 000011100011111110
        // 000011111111111110
        // 000010011111111110
        // 000010011101111110
        // 000011111111111110
        // 000011111111111110
        // 000011111111111110
        // 000011111111100000
        // 000001111111100000
        // 000000000000000000
        // Output:
        // 000000000000000000
        // 000000000000000000
        // 000000000000000000
        // 000000000000001000
        // 000000100001000000
        // 000010000000001000
        // 000000000000000000
        // 000000000000000000
        // 000000000001001000
        // 000000000100000000
        // 000000000000000000
        // 000000010000100000
        // 000000000000000000
        // 000000000000000000
        let width = 18;
        let height = 14;
        let steps: u16 = 2 * width.into() * height.into();
        let mut map: Map = MapTrait::new_random_walk(width, height, steps, SEED);
        let distribution = map.compute_distribution(10, SEED);
        assert_eq!(distribution, 0x8021002008000000000001200100000000420000000000);
    }

    #[test]
    fn test_map_search_path() {
        // 000000000000000000
        // 000000000011000000
        // 000000000111001100
        // 000001000111111110
        // 000011100011111110
        // 000011111111111110
        // 0000100111x─┐11110
        // 000010011101│11110
        // 000011111111│11110
        // 000011111111│11110
        // 000011111111│11110
        // 000011111111│00000
        // 000001111111x00000
        // 000000000000000000
        let width = 18;
        let height = 14;
        let steps: u16 = 2 * width.into() * height.into();
        let mut map: Map = MapTrait::new_random_walk(width, height, steps, SEED);
        let path = map.search_path(23, 133);
        assert_eq!(path, array![133, 132, 131, 113, 95, 77, 59, 41].span());
    }
}
