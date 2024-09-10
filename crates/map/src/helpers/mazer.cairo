//! Prim's algorithm to generate Maze.
//! See also https://en.wikipedia.org/wiki/Prim%27s_algorithm

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::asserter::Asserter;
use origami_map::types::direction::{Direction, DirectionTrait};

/// Implementation of the `MazerTrait` trait.
#[generate_trait]
pub impl Mazer of MazerTrait {
    /// Generate a maze.
    /// # Arguments
    /// * `width` - The width of the maze
    /// * `height` - The height of the maze
    /// * `seed` - The seed to generate the maze
    /// # Returns
    /// * The generated maze
    #[inline]
    fn generate(width: u8, height: u8, mut seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Compute] Generate the maze
        let start = Seeder::random_position(width, height, seed);
        let mut grid = 0;
        let mut maze = 0;
        Self::iter(width, height, start, ref grid, ref maze, ref seed);
        // [Return] The maze
        maze
    }

    /// Recursive function to generate the maze on an existing grid allowing a single contact point.
    /// # Arguments
    /// * `width` - The width of the maze
    /// * `height` - The height of the maze
    /// * `start` - The starting position
    /// * `grid` - The original grid
    /// * `maze` - The generated maze
    /// * `seed` - The seed to generate the maze
    #[inline]
    fn iter(
        width: u8, height: u8, start: u8, ref grid: felt252, ref maze: felt252, ref seed: felt252
    ) {
        // [Check] Stop criteria, the position collides with the original grid
        if Bitmap::get(grid, start) == 1 {
            // [Effect] Merge the maze with the grid
            let merge: u256 = grid.into() | maze.into();
            maze = merge.try_into().unwrap();
            return;
        }
        // [Effect] Set the position
        maze = Bitmap::set(maze, start);
        // [Compute] Generate shuffled neighbors
        seed = Seeder::shuffle(seed, seed);
        let mut directions = DirectionTrait::compute_shuffled_directions(seed);
        // [Assess] Direction 1
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, start, direction) {
            let next = Self::next(width, start, direction);
            Self::iter(width, height, next, ref grid, ref maze, ref seed);
        }
        // [Assess] Direction 2
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, start, direction) {
            let next = Self::next(width, start, direction);
            Self::iter(width, height, next, ref grid, ref maze, ref seed);
        }
        // [Assess] Direction 3
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, start, direction) {
            let next = Self::next(width, start, direction);
            Self::iter(width, height, next, ref grid, ref maze, ref seed);
        }
        // [Assess] Direction 4
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, start, direction) {
            let next = Self::next(width, start, direction);
            Self::iter(width, height, next, ref grid, ref maze, ref seed);
        };
    }

    /// Check if the position can be visited in the specified direction.
    /// # Arguments
    /// * `maze` - The maze
    /// * `width` - The width of the maze
    /// * `height` - The height of the maze
    /// * `position` - The current position
    /// * `direction` - The direction to check
    /// # Returns
    /// * Whether the position can be visited in the specified direction
    #[inline]
    fn check(maze: felt252, width: u8, height: u8, position: u8, direction: Direction) -> bool {
        let (x, y) = (position % width, position / width);
        match direction {
            Direction::North => (y <= height - 3)
                && (x != 0)
                && (x != width - 1)
                && (Bitmap::get(maze, position + 2 * width) == 0)
                && (Bitmap::get(maze, position + width + 1) == 0)
                && (Bitmap::get(maze, position + width - 1) == 0),
            Direction::East => (x <= width - 3)
                && (y != 0)
                && (y != height - 1)
                && (Bitmap::get(maze, position + 2) == 0)
                && (Bitmap::get(maze, position + width + 1) == 0)
                && (Bitmap::get(maze, position - width + 1) == 0),
            Direction::South => (y >= 2)
                && (x != 0)
                && (x != width - 1)
                && (Bitmap::get(maze, position - 2 * width) == 0)
                && (Bitmap::get(maze, position - width + 1) == 0)
                && (Bitmap::get(maze, position - width - 1) == 0),
            Direction::West => (x >= 2)
                && (y != 0)
                && (y != height - 1)
                && (Bitmap::get(maze, position - 2) == 0)
                && (Bitmap::get(maze, position + width - 1) == 0)
                && (Bitmap::get(maze, position - width - 1) == 0),
            _ => false,
        }
    }

    /// Get the next position in the specified direction.
    /// # Arguments
    /// * `width` - The width of the maze
    /// * `position` - The current position
    /// * `direction` - The direction to move
    /// # Returns
    /// * The next position in the specified direction
    #[inline]
    fn next(width: u8, position: u8, direction: Direction) -> u8 {
        let new_position = match direction {
            Direction::North => { position + width },
            Direction::East => { position + 1 },
            Direction::South => { position - width },
            Direction::West => { position - 1 },
            _ => { position },
        };
        new_position
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Mazer;

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_mazer_generate() {
        // 000000000000000000
        // 010111011111111010
        // 011010110010001110
        // 001111011011110010
        // 011001001101010100
        // 010001111010011110
        // 011010000011101010
        // 001110111101010110
        // 010101100111011100
        // 010111011101101010
        // 011000101011011110
        // 001111110110010100
        // 011010011101110110
        // 000000000000000000
        let width = 18;
        let height = 14;
        let maze: felt252 = Mazer::generate(width, height, SEED);
        assert_eq!(maze, 0x177FA6B238F6F264D511E9E683A8EF5656771776A62B78FD9469DD80000);
    }
}
