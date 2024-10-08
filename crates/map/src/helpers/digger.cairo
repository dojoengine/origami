//! Digger to generate entries.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::caver::Caver;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::mazer::Mazer;
use origami_map::helpers::asserter::Asserter;
use origami_map::types::direction::{Direction, DirectionTrait};

/// Implementation of the `DiggerTrait` trait.
#[generate_trait]
pub impl Digger of DiggerTrait {
    /// Dig a maze from the edge to the grid with a single contact point.
    /// # Arguments
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `order` - The order of the maze, it must be 0 or 1, the higher the order the less dense
    /// the maze will be
    /// * `start` - The starting position
    /// * `grid` - The original grid
    /// * `seed` - The seed to generate the maze
    /// # Returns
    /// * The grid with the maze to the exit
    #[inline]
    fn maze(
        width: u8, height: u8, order: u8, start: u8, mut grid: felt252, mut seed: felt252
    ) -> felt252 {
        // [Check] Position is not a corner and is on an edge
        Asserter::assert_not_corner(width, height, start);
        Asserter::assert_on_edge(width, height, start);
        // [Effect] Dig the edge and compute the next position
        let (x, y) = (start % width, start / width);
        let next: u8 = if x == 0 {
            Mazer::next(width, start, Direction::East)
        } else if x == width - 1 {
            Mazer::next(width, start, Direction::West)
        } else if y == 0 {
            Mazer::next(width, start, Direction::North)
        } else {
            Mazer::next(width, start, Direction::South)
        };
        // [Compute] Generate the maze from the exit to the grid
        let mut maze = Bitmap::set(0, start);
        Mazer::iter(width, height, order, next, ref grid, ref maze, ref seed);
        // [Return] The original grid with the maze to the exit
        let grid: u256 = grid.into() | maze.into();
        grid.try_into().unwrap()
    }

    /// Dig a corridor from the edge to the grid with a single contact point.
    /// # Arguments
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `order` - The order of the corridor, it must be 0 or 1, the higher the order the less
    /// dense the correlated maze will be
    /// * `start` - The starting position
    /// * `grid` - The original grid
    /// * `seed` - The seed to generate the maze
    /// # Returns
    /// * The grid with the maze to the exit
    #[inline]
    fn corridor(
        width: u8, height: u8, order: u8, start: u8, grid: felt252, mut seed: felt252
    ) -> felt252 {
        // [Check] Position is not a corner and is on an edge
        Asserter::assert_not_corner(width, height, start);
        Asserter::assert_on_edge(width, height, start);
        // [Effect] Dig the edge and compute the next position
        let (x, y) = (start % width, start / width);
        let next: u8 = if x == 0 {
            Mazer::next(width, start, Direction::East)
        } else if x == width - 1 {
            Mazer::next(width, start, Direction::West)
        } else if y == 0 {
            Mazer::next(width, start, Direction::North)
        } else {
            Mazer::next(width, start, Direction::South)
        };
        // [Compute] Generate the maze from the exit to the grid
        let mut maze = Bitmap::set(0, start);
        let mut stop = false;
        Self::iter(width, height, order, next, grid, ref stop, ref maze, ref seed);
        // [Return] The original grid with the maze to the exit
        let grid: u256 = grid.into() | maze.into();
        grid.try_into().unwrap()
    }

    /// Recursive function to generate the corridor on an existing grid.
    /// # Arguments
    /// * `width` - The width of the corridor
    /// * `height` - The height of the corridor
    /// * `order` - The order of the corridor, it must be 0 or 1, the higher the order the less
    /// dense the correlated maze will be
    /// * `start` - The starting position
    /// * `grid` - The original grid
    /// * `stop` - The stop criteria
    /// * `maze` - The generated corridor
    /// * `seed` - The seed to generate the corridor
    #[inline]
    fn iter(
        width: u8,
        height: u8,
        order: u8,
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
        seed = Seeder::shuffle(seed, seed);
        let mut directions = DirectionTrait::compute_shuffled_directions(seed);
        // [Assess] Direction 1
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, order, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, order, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 2
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, order, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, order, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 3
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, order, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, order, next, grid, ref stop, ref maze, ref seed);
        }
        // [Assess] Direction 4
        let direction: Direction = DirectionTrait::pop_front(ref directions);
        if Self::check(maze, width, height, order, start, direction, stop) {
            let next = Mazer::next(width, start, direction);
            Self::iter(width, height, order, next, grid, ref stop, ref maze, ref seed);
        };
    }

    /// Check if the position can be visited in the specified direction.
    /// # Arguments
    /// * `maze` - The maze
    /// * `width` - The width of the maze
    /// * `height` - The height of the maze
    /// * `order` - The order of the corridor, it must be 0 or 1, the higher the order the less
    /// dense the correlated maze will be
    /// * `position` - The current position
    /// * `direction` - The direction to check
    /// * `stop` - The stop criteria
    /// # Returns
    /// * Whether the position can be visited in the specified direction
    #[inline]
    fn check(
        grid: felt252,
        width: u8,
        height: u8,
        order: u8,
        position: u8,
        direction: Direction,
        stop: bool
    ) -> bool {
        !stop && Mazer::check(grid, width, height, order, position, direction)
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
        // Input
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 <-- Start
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // Output
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 1 1 1
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 1 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 1 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 1 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 1 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let width = 18;
        let height = 14;
        let order = 0;
        let mut grid = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let walk: felt252 = Digger::corridor(width, height, order, 216, grid, SEED);
        assert_eq!(walk, 0x7F073F810FB061FC083C4A1F1F8FFFE1EEF83FFE1FFF81FFE03FF80000);
    }

    #[test]
    fn test_digger_dig_maze_order_0() {
        // Input
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 <-- Start
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // Output
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 1 1 1 0 1 1 1
        // 0 0 1 1 1 1 1 1 1 0 1 1 0 0 0 1 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 1 0 0 0 1 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 1 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 1 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let width = 18;
        let height = 14;
        let order = 0;
        let mut grid = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let walk: felt252 = Digger::maze(width, height, order, 216, grid, SEED);
        assert_eq!(walk, 0x7F773FB10FB7E1FC883C4A1F1F8FFFE1EEF83FFE1FFF81FFE03FF80000);
    }

    #[test]
    fn test_digger_dig_maze_order_1() {
        // Input
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 <-- Start
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // Output
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 1 1 1 0 1 1 1
        // 0 0 1 1 1 1 1 1 1 0 0 1 0 0 0 1 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 1 0
        // 0 0 0 0 1 1 1 1 0 0 0 1 0 0 1 0 1 0
        // 0 0 0 1 1 1 1 1 0 0 0 1 1 1 1 1 1 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let width = 18;
        let height = 14;
        let order = 1;
        let mut grid = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let walk: felt252 = Digger::maze(width, height, order, 216, grid, SEED);
        assert_eq!(walk, 0x7F773F910FB7E1FC083C4A1F1F8FFFE1EEF83FFE1FFF81FFE03FF80000);
    }
}
