//! Prim's algorithm to generate Maze.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::mazer::Mazer;
use origami_map::helpers::asserter::Asserter;

// Constants

const DIRECTION_SIZE: u32 = 0x10;

/// Implementation of the `MazerTrait` trait.
#[generate_trait]
pub impl Walker of MazerTrait {
    #[inline]
    fn generate(width: u8, height: u8, mut steps: u16, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Effect] Add start position
        let start = Seeder::random_position(width, height, seed);
        let mut grid = Bitmap::set(0, start);
        // [Compute] Engage the random walk
        let mut seed = Seeder::reseed(seed, seed);
        Self::iter(width, height, start, ref steps, ref grid, ref seed);
        grid
    }

    #[inline]
    fn iter(
        width: u8, height: u8, start: u8, ref steps: u16, ref grid: felt252, ref seed: felt252
    ) {
        // [Check] Stop if the recursion runs out of steps
        if steps == 0 {
            return;
        }
        steps -= 1;
        // [Compute] Generate shuffled neighbors
        let mut directions = Mazer::compute_shuffled_directions(seed);
        // [Assess] Direction 1
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(grid, width, height, start, direction) {
            // [Compute] Add neighbor
            let start = Mazer::next(width, start, direction);
            grid = Bitmap::set(grid, start);
            seed = Seeder::reseed(seed, seed);
            return Self::iter(width, height, start, ref steps, ref grid, ref seed);
        }
        // [Assess] Direction 2
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(grid, width, height, start, direction) {
            // [Compute] Add neighbor
            let start = Mazer::next(width, start, direction);
            grid = Bitmap::set(grid, start);
            seed = Seeder::reseed(seed, seed);
            return Self::iter(width, height, start, ref steps, ref grid, ref seed);
        }
        // [Assess] Direction 3
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(grid, width, height, start, direction) {
            // [Compute] Add neighbor
            let start = Mazer::next(width, start, direction);
            grid = Bitmap::set(grid, start);
            seed = Seeder::reseed(seed, seed);
            return Self::iter(width, height, start, ref steps, ref grid, ref seed);
        }
        // [Assess] Direction 4
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(grid, width, height, start, direction) {
            // [Compute] Add neighbor
            let start = Mazer::next(width, start, direction);
            grid = Bitmap::set(grid, start);
            seed = Seeder::reseed(seed, seed);
            return Self::iter(width, height, start, ref steps, ref grid, ref seed);
        };
    }

    #[inline]
    fn check(grid: felt252, width: u8, height: u8, position: u8, direction: u8) -> bool {
        let (x, y) = (position % width, position / width);
        match direction {
            0 => (y < height - 2) && (x != 0) && (x != width - 1),
            1 => (x < width - 2) && (y != 0) && (y != height - 1),
            2 => (y > 1) && (x != 0) && (x != width - 1),
            _ => (x > 1) && (y != 0) && (y != height - 1),
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
