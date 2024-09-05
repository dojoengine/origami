//! Digger to generate entries.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::caver::Caver;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::mazer::{Mazer, DIRECTION_SIZE};
use origami_map::helpers::asserter::Asserter;

/// Implementation of the `DiggerTrait` trait.
#[generate_trait]
pub impl Digger of DiggerTrait {
    #[inline]
    fn maze(width: u8, height: u8, start: u8, mut grid: felt252, mut seed: felt252) -> felt252 {
        // [Check] Position is not a corner and is on an edge
        Asserter::assert_not_corner(width, height, start);
        Asserter::assert_on_edge(width, height, start);
        // [Effect] Dig the edge and compute the next position
        let (x, y) = (start % width, start / width);
        let next: u8 = if x == 0 {
            Mazer::next(width, start, 1)
        } else if x == width - 1 {
            Mazer::next(width, start, 3)
        } else if y == 0 {
            Mazer::next(width, start, 0)
        } else {
            Mazer::next(width, start, 2)
        };
        // [Compute] Generate the maze from the exit to the grid
        let mut maze = Bitmap::set(0, start);
        Mazer::iter(width, height, next, ref grid, ref maze, ref seed);
        // [Return] The original grid with the maze to the exit
        let grid: u256 = grid.into() | maze.into();
        grid.try_into().unwrap()
    }

    #[inline]
    fn corridor(width: u8, height: u8, start: u8, grid: felt252, mut seed: felt252) -> felt252 {
        // [Check] Position is not a corner and is on an edge
        Asserter::assert_not_corner(width, height, start);
        Asserter::assert_on_edge(width, height, start);
        // [Effect] Dig the edge and compute the next position
        let (x, y) = (start % width, start / width);
        let next: u8 = if x == 0 {
            Mazer::next(width, start, 1)
        } else if x == width - 1 {
            Mazer::next(width, start, 3)
        } else if y == 0 {
            Mazer::next(width, start, 0)
        } else {
            Mazer::next(width, start, 2)
        };
        // [Compute] Generate the maze from the exit to the grid
        let mut maze = Bitmap::set(0, start);
        let mut stop = false;
        Self::iter(width, height, next, grid, ref stop, ref maze, ref seed);
        // [Return] The original grid with the maze to the exit
        let grid: u256 = grid.into() | maze.into();
        grid.try_into().unwrap()
    }

    #[inline]
    fn iter(
        width: u8,
        height: u8,
        start: u8,
        grid: felt252,
        ref stop: bool,
        ref maze: felt252,
        ref seed: felt252
    ) {
        // [Check] Stop criteria, the position collides with the grid
        if Bitmap::get(grid, start) == 1 {
            stop = true;
            return;
        }
        // [Effect] Set the position
        maze = Bitmap::set(maze, start);
        // [Compute] Generate shuffled neighbors
        seed = Seeder::reseed(seed, seed);
        let mut directions = Mazer::compute_shuffled_directions(seed);
        // [Assess] Direction 1
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(maze, width, height, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 2
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(maze, width, height, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 3
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(maze, width, height, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 4
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if Self::check(maze, width, height, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, next, grid, ref stop, ref maze, ref seed);
        };
    }

    #[inline]
    fn check(
        grid: felt252, width: u8, height: u8, position: u8, direction: u8, stop: bool
    ) -> bool {
        !stop && Mazer::check(grid, width, height, position, direction)
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Digger;

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_digger_dig_corridor() {
        // Input grid
        // 000000000000000000
        // 000111111100000000 <-- Start
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
        // Output grid
        // 000000000000000000
        // 000111111100000111
        // 001111111000000100
        // 001111101100000110
        // 000111111100000010
        // 000011110001001010
        // 000111110001111110
        // 001111111111111110
        // 000111101110111110
        // 000011111111111110
        // 000111111111111110
        // 000001111111111110
        // 000000111111111110
        // 000000000000000000
        let width = 18;
        let height = 14;
        let mut grid = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let walk: felt252 = Digger::corridor(width, height, 216, grid, SEED);
        assert_eq!(walk, 0x7F073F810FB061FC083C4A1F1F8FFFE1EEF83FFE1FFF81FFE03FF80000);
    }

    #[test]
    fn test_digger_dig_maze() {
        // Input grid
        // 000000000000000000
        // 000111111100000000 <-- Start
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
        // Output grid
        // 000000000000000000
        // 000111111101110111
        // 001111111011000100
        // 001111101101111110
        // 000111111100100010
        // 000011110001001010
        // 000111110001111110
        // 001111111111111110
        // 000111101110111110
        // 000011111111111110
        // 000111111111111110
        // 000001111111111110
        // 000000111111111110
        // 000000000000000000
        let width = 18;
        let height = 14;
        let mut grid = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let walk: felt252 = Digger::maze(width, height, 216, grid, SEED);
        assert_eq!(walk, 0x7F773FB10FB7E1FC883C4A1F1F8FFFE1EEF83FFE1FFF81FFE03FF80000);
    }
}
