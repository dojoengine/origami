//! Maze struct and generation methods.

// Core imports

use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;

// Internal imports

use origami_map::helpers::powers::{TwoPower, TwoPowerTrait};

// Constants

const DIRECTION_SIZE: u32 = 0x10;

/// Maze struct.
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
        maze.grid = Self::set(0, start);
        // [Compute] Generate the maze
        Self::generate(ref maze, start);
        // [Return] Maze
        maze
    }

    #[inline]
    fn generate(ref maze: Maze, start: u8) {
        // [Compute] Generate shuffled neighbors
        let mut directions = Self::compute_shuffled_directions(maze.seed);
        // [Assess] Direction 1
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if maze.check_neighbor(start, direction) {
            // [Compute] Add neighbor
            let start = maze.add_neighbor(start, direction);
            maze.seed = Self::reseed(maze.seed);
            Self::generate(ref maze, start);
        }
        // [Assess] Direction 2
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if maze.check_neighbor(start, direction) {
            // [Compute] Add neighbor
            let start = maze.add_neighbor(start, direction);
            maze.seed = Self::reseed(maze.seed);
            Self::generate(ref maze, start);
        }
        // [Assess] Direction 3
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if maze.check_neighbor(start, direction) {
            // [Compute] Add neighbor
            let start = maze.add_neighbor(start, direction);
            maze.seed = Self::reseed(maze.seed);
            Self::generate(ref maze, start);
        }
        // [Assess] Direction 4
        let direction: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        if maze.check_neighbor(start, direction) {
            // [Compute] Add neighbor
            let start = maze.add_neighbor(start, direction);
            maze.seed = Self::reseed(maze.seed);
            Self::generate(ref maze, start);
        }
    }

    #[inline]
    fn add_exit(ref self: Maze, exit: u8) {
        // [Check] Exit is not a corner and on edge
        self.assert_not_corner(exit);
        self.assert_on_edge(exit);
        // [Effect] Add exit at position
        self.grid = Self::set(self.grid, exit);
        // [Effect] Check the next position inside the maze to ensure the exit is reachable
        let (x, y) = (exit % self.width, exit / self.width);
        if x == 0 {
            let position = exit + 1;
            if Self::get(self.grid, position) == 0 {
                self.grid = Self::set(self.grid, position);
            }
        } else if x == self.width - 1 {
            let position = exit - 1;
            if Self::get(self.grid, position) == 0 {
                self.grid = Self::set(self.grid, position);
            }
        } else if y == 0 {
            let position = exit + self.width;
            if Self::get(self.grid, position) == 0 {
                self.grid = Self::set(self.grid, position);
            }
        } else if y == self.height - 1 {
            let position = exit - self.width;
            if Self::get(self.grid, position) == 0 {
                self.grid = Self::set(self.grid, position);
            }
        }
    }

    #[inline]
    fn check_neighbor(ref self: Maze, position: u8, direction: u8) -> bool {
        let (x, y) = (position % self.width, position / self.width);
        match direction {
            0 => (y <= self.height - 4)
                && (x != 0)
                && (x != self.width - 1)
                && (y != self.height - 1)
                && (Self::get(self.grid, position + 2 * self.width) == 0),
            1 => (x <= self.width - 4)
                && (y != 0)
                && (y != self.height - 1)
                && (x != self.width - 1)
                && (Self::get(self.grid, position + 2) == 0),
            2 => (y >= 3)
                && (x != 0)
                && (x != self.width - 1)
                && (y != 0)
                && (Self::get(self.grid, position - 2 * self.width) == 0),
            _ => (x >= 3)
                && (y != 0)
                && (y != self.height - 1)
                && (x != 0)
                && (Self::get(self.grid, position - 2) == 0),
        }
    }

    #[inline]
    fn add_neighbor(ref self: Maze, position: u8, direction: u8) -> u8 {
        let (x, y) = (position % self.width, position / self.width);
        let edge = x == 0 || y == 0 || x == self.width - 1 || y == self.height - 1;
        match direction {
            0 => {
                let mut new_position = position + self.width;
                self.grid = Self::set(self.grid, new_position);
                if !edge {
                    new_position = position + 2 * self.width;
                    self.grid = Self::set(self.grid, new_position);
                }
                new_position
            },
            1 => {
                let mut new_position = position + 1;
                self.grid = Self::set(self.grid, new_position);
                if !edge {
                    new_position = position + 2;
                    self.grid = Self::set(self.grid, new_position);
                }
                new_position
            },
            2 => {
                let mut new_position = position - self.width;
                self.grid = Self::set(self.grid, new_position);
                if !edge {
                    new_position = position - 2 * self.width;
                    self.grid = Self::set(self.grid, new_position);
                }
                new_position
            },
            _ => {
                let mut new_position = position - 1;
                self.grid = Self::set(self.grid, new_position);
                if !edge {
                    new_position = position - 2;
                    self.grid = Self::set(self.grid, new_position);
                }
                new_position
            },
        }
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

    #[inline]
    fn get(value: felt252, index: u8) -> u8 {
        let value: u256 = value.into();
        let offset: u256 = TwoPower::power(index);
        (value / offset % 2).try_into().unwrap()
    }

    #[inline]
    fn set(value: felt252, index: u8) -> felt252 {
        // [Info] Unsafe since the value at index is expected to be null
        let value: u256 = value.into();
        let offset: u256 = TwoPower::power(index);
        (value + offset).try_into().unwrap()
    }

    #[inline]
    fn reseed(seed: felt252) -> felt252 {
        let mut state = PoseidonTrait::new();
        state = state.update(seed);
        state.finalize()
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
    fn test_maze_new_seed() {
        // 000000000000000
        // 010111110111110
        // 010101010000010
        // 011101010111110
        // 000001010100010
        // 011111011101010
        // 010000000001010
        // 010111111111110
        // 010000000001000
        // 011111111101110
        // 010000000100000
        // 011111110111110
        // 000000010000010
        // 011111111111010
        // 000000000000010
        let width = 15;
        let height = 15;
        let start_index: u8 = 1;
        let mut maze: Maze = MazeTrait::new(width, height, start_index, SEED);
        assert_eq!(maze.grid, 0x17df2a82757c0a89f75200a5ffc8021ff720207f7c0209ffd0002);
    }

    #[test]
    fn test_maze_add_exit() {
        // 001000000000000
        // 011111110111110
        // 010101010000010
        // 011101010111110
        // 000001010100010
        // 011111011101010
        // 010000000001010
        // 010111111111110
        // 010000000001000
        // 011111111101110
        // 010000000100000
        // 011111110111110
        // 000000010000010
        // 011111111111010
        // 000000000000010
        let width = 15;
        let height = 15;
        let start_index: u8 = 1;
        let mut maze: Maze = MazeTrait::new(width, height, start_index, SEED);
        maze.add_exit(222);
        assert_eq!(maze.grid, 0x4001fdf2a82757c0a89f75200a5ffc8021ff720207f7c0209ffd0002);
    }

    #[test]
    fn test_maze_add_exit_twice() {
        // 001000000000000
        // 111111110111110
        // 010101010000010
        // 011101010111110
        // 000001010100010
        // 011111011101010
        // 010000000001010
        // 010111111111110
        // 010000000001000
        // 011111111101110
        // 010000000100000
        // 011111110111110
        // 000000010000010
        // 011111111111010
        // 000000000000010
        let width = 15;
        let height = 15;
        let start_index: u8 = 1;
        let mut maze: Maze = MazeTrait::new(width, height, start_index, SEED);
        maze.add_exit(222);
        maze.add_exit(209);
        assert_eq!(maze.grid, 0x4003fdf2a82757c0a89f75200a5ffc8021ff720207f7c0209ffd0002);
    }
}
