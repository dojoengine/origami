//! Random walk algorithm to generate a grid.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::mazer::Mazer;
use origami_map::helpers::asserter::Asserter;
use origami_map::types::direction::{Direction, DirectionTrait};

// Constants

const DIRECTION_SIZE: u32 = 0x10;

/// Implementation of the `WalkerTrait` trait.
#[generate_trait]
pub impl Walker of WalkerTrait {
    /// Generate a random walk.
    /// # Arguments
    /// * `width` - The width of the walk
    /// * `height` - The height of the walk
    /// * `steps` - The number of steps to walk
    /// * `seed` - The seed to generate the walk
    /// # Returns
    /// * The generated walk
    #[inline]
    fn generate(width: u8, height: u8, steps: u16, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Effect] Add start position
        // [Compute] Engage the random walk
        let start = Seeder::random_position(width, height, seed);
        let mut grid = 0;
        Self::iter(width, height, start, steps, ref grid, seed);
        grid
    }

    /// Recursive function to generate the random walk.
    /// # Arguments
    /// * `width` - The width of the walk
    /// * `height` - The height of the walk
    /// * `start` - The starting position
    /// * `steps` - The number of steps to walk
    /// * `grid` - The original grid
    /// * `seed` - The seed to generate the walk
    /// # Returns
    /// * The original grid with the walk
    #[inline]
    fn iter(width: u8, height: u8, start: u8, mut steps: u16, ref grid: felt252, seed: felt252) {
        // [Check] Stop if the recursion runs out of steps
        if steps == 0 {
            return;
        }
        steps -= 1;
        // [Effect] Set the position
        grid = Bitmap::set(grid, start);
        // [Compute] Generate shuffled neighbors
        let seed = Seeder::shuffle(seed, seed);
        let mut directions = DirectionTrait::compute_shuffled_directions(seed);
        // [Assess] Direction 1
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(grid, width, height, start, direction) {
            let start = Mazer::next(width, start, direction);
            return Self::iter(width, height, start, steps, ref grid, seed);
        }
        // [Assess] Direction 2
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(grid, width, height, start, direction) {
            let start = Mazer::next(width, start, direction);
            return Self::iter(width, height, start, steps, ref grid, seed);
        }
        // [Assess] Direction 3
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(grid, width, height, start, direction) {
            let start = Mazer::next(width, start, direction);
            return Self::iter(width, height, start, steps, ref grid, seed);
        }
        // [Assess] Direction 4
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(grid, width, height, start, direction) {
            let start = Mazer::next(width, start, direction);
            return Self::iter(width, height, start, steps, ref grid, seed);
        };
    }

    /// Check if the position can be visited in the specified direction.
    /// # Arguments
    /// * `grid` - The grid
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `position` - The current position
    /// * `direction` - The direction to check
    /// # Returns
    /// * Whether the position can be visited
    #[inline]
    fn check(grid: felt252, width: u8, height: u8, position: u8, direction: Direction) -> bool {
        let (x, y) = (position % width, position / width);
        match direction {
            Direction::North => (y < height - 2) && (x != 0) && (x != width - 1),
            Direction::East => (x < width - 2) && (y != 0) && (y != height - 1),
            Direction::South => (y > 1) && (x != 0) && (x != width - 1),
            Direction::West => (x > 1) && (y != 0) && (y != height - 1),
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Walker;

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_walker_generate() {
        // 000000000000000000
        // 000111111100000000
        // 001111111000000000
        // 001111101100000000
        // 000111111100000000
        // 000011110001001000
        // 000111110001111100
        // 001111111111111110
        // 000111101110111110
        // 000011111111111110
        // 000111111111111110
        // 000001111111111110
        // 000000111111111110
        // 000000000000000000
        let width = 18;
        let height = 14;
        let steps: u16 = 500;
        let walk: felt252 = Walker::generate(width, height, steps, SEED);
        assert_eq!(walk, 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000);
    }
}
