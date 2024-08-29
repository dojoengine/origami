//! Maze struct and generation methods.

// Core imports

use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;

// Constants

const DIRECTION_SIZE: u32 = 0x10;

/// Types.
#[derive(Destruct)]
pub struct Maze {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
    pub seed: felt252,
}

/// Errors module.
pub mod errors {
    pub const MAZE_INVALID_DIMENSION: felt252 = 'Maze: invalid dimension';
    pub const MAZE_INVALID_EXIT: felt252 = 'Maze: invalid exit';
    pub const MATH_INVALID_INPUT: felt252 = 'Math: invalid input';
    pub const MATH_INVALID_SIZE: felt252 = 'Math: invalid size';
}

/// Implementation of the `MazeTrait` trait for the `Maze` struct.
#[generate_trait]
pub impl MazeImpl of MazeTrait {
    #[inline(always)]
    fn new(width: u8, height: u8, start: u8, seed: felt252) -> Maze {
        // [Check] Valid dimensions
        assert(width * height <= 252, errors::MAZE_INVALID_DIMENSION);
        // [Check] Start is not a corner and is on an edge
        let mut maze = Maze { width, height, grid: 0, seed };
        maze.assert_not_corner(start);
        maze.assert_on_edge(start);
        // [Effect] Add start position
        maze.grid = Bitmap::set(0, start);
        let start = maze.start(start);
        // [Compute] Generate the maze
        Self::generate(ref maze, start);
        // [Return] Maze
        maze
    }

    #[inline]
    fn generate(ref self: Maze, start: u8) {
        // [Compute] Generate shuffled neighbors
        let mut directions = Self::compute_shuffled_directions(self.seed);
        // [Assess] Direction 1
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if self.check(start, direction) {
            // [Compute] Add neighbor
            let start = self.walk(start, direction);
            self.seed = Seeder::reseed(self.seed, self.seed);
            Self::generate(ref self, start);
        }
        // [Assess] Direction 2
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if self.check(start, direction) {
            // [Compute] Add neighbor
            let start = self.walk(start, direction);
            self.seed = Seeder::reseed(self.seed, self.seed);
            Self::generate(ref self, start);
        }
        // [Assess] Direction 3
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if self.check(start, direction) {
            // [Compute] Add neighbor
            let start = self.walk(start, direction);
            self.seed = Seeder::reseed(self.seed, self.seed);
            Self::generate(ref self, start);
        }
        // [Assess] Direction 4
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if self.check(start, direction) {
            // [Compute] Add neighbor
            let start = self.walk(start, direction);
            self.seed = Seeder::reseed(self.seed, self.seed);
            Self::generate(ref self, start);
        }
    }

    #[inline]
    fn add(ref self: Maze, exit: u8) {
        // [Check] Exit is not a corner and on edge
        self.assert_not_corner(exit);
        self.assert_on_edge(exit);
        // [Effect] Add exit at position
        self.grid = Bitmap::set(self.grid, exit);
        // [Effect] Check the next position inside the maze to ensure the exit is reachable
        let (x, y) = (exit % self.width, exit / self.width);
        if x == 0 {
            let position = exit + 1;
            if Bitmap::get(self.grid, position) == 0 {
                self.grid = Bitmap::set(self.grid, position);
            }
        } else if x == self.width - 1 {
            let position = exit - 1;
            if Bitmap::get(self.grid, position) == 0 {
                self.grid = Bitmap::set(self.grid, position);
            }
        } else if y == 0 {
            let position = exit + self.width;
            if Bitmap::get(self.grid, position) == 0 {
                self.grid = Bitmap::set(self.grid, position);
            }
        } else if y == self.height - 1 {
            let position = exit - self.width;
            if Bitmap::get(self.grid, position) == 0 {
                self.grid = Bitmap::set(self.grid, position);
            }
        }
    }

    #[inline]
    fn check(ref self: Maze, position: u8, direction: u8) -> bool {
        let (x, y) = (position % self.width, position / self.width);
        match direction {
            0 => (y <= self.height - 3)
                && (x != 0)
                && (x != self.width - 1)
                && (Bitmap::get(self.grid, position + 2 * self.width) == 0)
                && (Bitmap::get(self.grid, position + self.width + 1) == 0)
                && (Bitmap::get(self.grid, position + self.width - 1) == 0),
            1 => (x <= self.width - 3)
                && (y != 0)
                && (y != self.height - 1)
                && (Bitmap::get(self.grid, position + 2) == 0)
                && (Bitmap::get(self.grid, position + self.width + 1) == 0)
                && (Bitmap::get(self.grid, position - self.width + 1) == 0),
            2 => (y >= 2)
                && (x != 0)
                && (x != self.width - 1)
                && (Bitmap::get(self.grid, position - 2 * self.width) == 0)
                && (Bitmap::get(self.grid, position - self.width + 1) == 0)
                && (Bitmap::get(self.grid, position - self.width - 1) == 0),
            _ => (x >= 2)
                && (y != 0)
                && (y != self.height - 1)
                && (Bitmap::get(self.grid, position - 2) == 0)
                && (Bitmap::get(self.grid, position + self.width - 1) == 0)
                && (Bitmap::get(self.grid, position - self.width - 1) == 0),
        }
    }

    #[inline]
    fn start(ref self: Maze, position: u8) -> u8 {
        let (x, y) = (position % self.width, position / self.width);
        let new_position = if y == 0 {
            position + self.width
        } else if x == 0 {
            position + 1
        } else if y == self.height - 1 {
            position - self.width
        } else {
            position - 1
        };
        self.grid = Bitmap::set(self.grid, new_position);
        new_position
    }

    #[inline]
    fn walk(ref self: Maze, position: u8, direction: u8) -> u8 {
        let width = self.width;
        let new_position = match direction {
            0 => { position + width },
            1 => { position + 1 },
            2 => { position - width },
            _ => { position - 1 },
        };
        self.grid = Bitmap::set(self.grid, new_position);
        new_position
    }

    #[inline]
    fn compute_shuffled_directions(seed: felt252) -> u32 {
        // [Compute] Random number
        let mut random: u32 = (seed.into() % 24_u256).try_into().unwrap();
        // [Return] Pickup a random permutation
        // [Info] 0:Top, 1:Right, 2:Bottom, 3:Left
        match random {
            0 => 0x0123,
            1 => 0x0132,
            2 => 0x0213,
            3 => 0x0231,
            4 => 0x0312,
            5 => 0x0321,
            6 => 0x1023,
            7 => 0x1032,
            8 => 0x1203,
            9 => 0x1230,
            10 => 0x1302,
            11 => 0x1320,
            12 => 0x2013,
            13 => 0x2031,
            14 => 0x2103,
            15 => 0x2130,
            16 => 0x2301,
            17 => 0x2310,
            18 => 0x3012,
            19 => 0x3021,
            20 => 0x3102,
            21 => 0x3120,
            22 => 0x3201,
            _ => 0x3210,
        }
    }
}

#[generate_trait]
impl MazeAssert of AssertTrait {
    #[inline]
    fn assert_on_edge(ref self: Maze, position: u8) {
        let (x, y) = (position % self.width, position / self.width);
        assert(
            x == 0 || x == self.width - 1 || y == 0 || y == self.height - 1,
            errors::MAZE_INVALID_EXIT
        );
    }

    #[inline]
    fn assert_not_corner(ref self: Maze, position: u8) {
        let (x, y) = (position % self.width, position / self.width);
        assert(x != 0 || y != 0, errors::MAZE_INVALID_EXIT);
        assert(x != self.width - 1 || y != 0, errors::MAZE_INVALID_EXIT);
        assert(x != 0 || y != self.height - 1, errors::MAZE_INVALID_EXIT);
        assert(x != self.width - 1 || y != self.height - 1, errors::MAZE_INVALID_EXIT);
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Maze, MazeTrait};

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_maze_new() {
        // 010000000000000000
        // 111011111101111110
        // 010110010011001010
        // 010101111110110110
        // 010110100101011100
        // 010011010111100010
        // 011101011000101110
        // 010101110110111010
        // 010110011101000110
        // 010011100111110100
        // 011100111001001110
        // 000101001011101000
        // 011111101110101110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let start_index: u8 = 1;
        let mut maze: Maze = MazeTrait::new(width, height, start_index, SEED);
        maze.add(250);
        maze.add(233);
        assert_eq!(maze.grid, 0x40003BF7E593295FB65A57135E2758B95DBA59D1939F47393852E87EEB80002);
    }
}
