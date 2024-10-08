//! Brogue's algorithm customized to generate Cave.
//! See also https://www.rockpapershotgun.com/how-do-roguelikes-generate-levels

// Internal imports

use origami_map::helpers::power::TwoPower;
use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::asserter::Asserter;

// Constants

const WALL_TO_FLOOR_THRESHOLD: u8 = 4;
const FLOOR_TO_WALL_THRESHOLD: u8 = 3;

/// Implementation of the `CaverTrait` trait.
#[generate_trait]
pub impl Caver of CaverTrait {
    /// Generate a cave.
    /// # Arguments
    /// * `width` - The width of the cave
    /// * `height` - The height of the cave
    /// * `order` - The order of the cave, which is the number of smoothing iterations
    /// * `seed` - The seed to generate the cave
    /// # Returns
    /// * The generated cave
    #[inline]
    fn generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Effect] Remove leading bits
        let size = width * height;
        let default: u256 = seed.into() / TwoPower::pow(252 - size);
        let mut grid: felt252 = default.try_into().unwrap();
        Self::iter(width, height, size, order.into(), ref grid);
        // [Return] Cave
        grid
    }

    /// Recursive function to generate the cave.
    /// # Arguments
    /// * `width` - The width of the cave
    /// * `height` - The height of the cave
    /// * `size` - The size of the cave
    /// * `order` - The order of the cave
    /// * `grid` - The grid of the cave to update
    #[inline]
    fn iter(width: u8, height: u8, size: u8, order: u16, ref grid: felt252) {
        // [Check] Stop if the loop count is zero
        let mut index: u16 = size.into() * order - 1;
        while index != 0 {
            Self::assess(width, height, (index % size.into()).try_into().unwrap(), size, ref grid);
            index -= 1;
        };
    }

    /// Assess the grid at the specified index.
    /// # Arguments
    /// * `width` - The width of the cave
    /// * `height` - The height of the cave
    /// * `index` - The index of the grid to assess
    /// * `size` - The size of the cave
    /// * `grid` - The grid of the cave to update
    #[inline]
    fn assess(width: u8, height: u8, index: u8, size: u8, ref grid: felt252) {
        let is_wall = Bitmap::get(grid, index) == 0;
        let (x, y) = (index % width, index / width);
        let is_edge = Asserter::is_edge(width, height, x, y) && index < size;
        let floor_count = Self::count_direct_floor(width, height, x, y, grid)
            + Self::count_indirect_floor(width, height, x, y, grid);
        if is_wall && floor_count > WALL_TO_FLOOR_THRESHOLD && !is_edge {
            // [Effect] Convert wall into floor if surrounded by more than X floors
            grid = Bitmap::set(grid, index);
        } else if !is_wall && (floor_count < FLOOR_TO_WALL_THRESHOLD || is_edge) {
            // [Effect] Convert floor into wall if surrounded by less than Y floors
            grid = Bitmap::unset(grid, index);
        }
    }

    /// Count the number of direct floor neighbors (adjacent).
    /// # Arguments
    /// * `width` - The width of the cave
    /// * `height` - The height of the cave
    /// * `x` - The x-coordinate of the grid
    /// * `y` - The y-coordinate of the grid
    /// * `grid` - The grid of the cave
    /// # Returns
    /// * The number of direct floor neighbors
    #[inline]
    fn count_direct_floor(width: u8, height: u8, x: u8, y: u8, grid: felt252) -> u8 {
        // [Compute] Neighbors
        let mut floor_count: u8 = 0;
        // [Compute] North
        if y < height - 1 {
            let index = (y + 1) * width + x;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] East
        if x < width - 1 {
            let index = y * width + x + 1;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] South
        if y > 0 {
            let index = (y - 1) * width + x;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] West
        if x > 0 {
            let index = y * width + x - 1;
            floor_count += Bitmap::get(grid, index);
        };
        floor_count
    }

    /// Count the number of indirect floor neighbors (diagnoal).
    /// # Arguments
    /// * `width` - The width of the cave
    /// * `height` - The height of the cave
    /// * `x` - The x-coordinate of the grid
    /// * `y` - The y-coordinate of the grid
    /// * `grid` - The grid of the cave
    /// # Returns
    /// * The number of indirect floor neighbors
    #[inline]
    fn count_indirect_floor(width: u8, height: u8, x: u8, y: u8, grid: felt252) -> u8 {
        // [Compute] Neighbors
        let mut floor_count: u8 = 0;
        // [Compute] North West
        if y < height - 1 && x > 0 {
            let index = (y + 1) * width + x - 1;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] North East
        if y < height - 1 && x < width - 1 {
            let index = (y + 1) * width + x + 1;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] South East
        if y > 0 && x < width - 1 {
            let index = (y - 1) * width + x + 1;
            floor_count += Bitmap::get(grid, index);
        };
        // [Compute] South West
        if y > 0 && x > 0 {
            let index = (y - 1) * width + x - 1;
            floor_count += Bitmap::get(grid, index);
        };
        floor_count
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Caver, Seeder};

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_caver_generate() {
        // Order 0
        // 011011110001110110
        // 100011100010001110
        // 110000111001111100
        // 101111110101111110
        // 000010010001111001
        // 100001111011001110
        // 100111001101100110
        // 100010010110001000
        // 011111001110110110
        // 100001000111110000
        // 111010111100010100
        // 110001110000110111
        // 001000010000000100
        // 000110010110101010
        // Order 1
        // 000000000000000000
        // 000000000000001100
        // 000000111001111100
        // 000001111001111110
        // 000000111001111110
        // 000001111111111110
        // 000011111111111110
        // 000111111111111110
        // 000111111111111110
        // 000011111111111100
        // 010011111100111110
        // 000001111000111110
        // 000000111000011100
        // 000000000000000000
        // Order 2
        // 000000000000000000
        // 000000000000001100
        // 000000111001111100
        // 000001111001111110
        // 000001111111111110
        // 000001111111111110
        // 000011111111111110
        // 000111111111111110
        // 000111111111111110
        // 000011111111111110
        // 000011111101111110
        // 000001111000111110
        // 000000111000011100
        // 000000000000000000
        // Order 3
        // 000000000000000000
        // 000000000000001100
        // 000000111001111100
        // 000001111111111110
        // 000001111111111110
        // 000001111111111110
        // 000011111111111110
        // 000111111111111110
        // 000111111111111110
        // 000011111111111110
        // 000011111111111110
        // 000001111100111110
        // 000000111000011100
        // 000000000000000000
        let width = 18;
        let height = 14;
        let order = 2;
        let seed: felt252 = Seeder::shuffle(SEED, SEED);
        let cave = Caver::generate(width, height, order, seed);
        assert_eq!(cave, 0xC039F01E7E07FF81FFE0FFF87FFE1FFF83FFE0FDF81E3E038700000);
    }

    #[test]
    fn test_caver_new_seed_generate() {
        // Order 0
        // 011011111001101111
        // 010111100100000110
        // 100111101011010100
        // 001000100010010101
        // 001110001011110010
        // 000000011110011011
        // 111010010011001000
        // 001100000000100001
        // 101111111101010011
        // 011111010000010101
        // 001100101001101001
        // 000101011110101000
        // 101101001100101010
        // 100000100110110110
        // Order 1
        // 000000000000000000
        // 000111100000000000
        // 000111100000000000
        // 001111100000000000
        // 001110001111110000
        // 000100011111111000
        // 001110000011111000
        // 001111000001110000
        // 001111111000110010
        // 011111110000110000
        // 001111111001111000
        // 001111111111111000
        // 001111111111111110
        // 000000000000000000
        // Order 2
        // 000000000000000000
        // 000111100000000000
        // 000111100000000000
        // 001111100000000000
        // 001111001111110000
        // 001110001111111000
        // 001110000011111000
        // 001111000001110000
        // 001111110000110000
        // 011111110000110000
        // 001111111001111000
        // 001111111111111100
        // 001111111111111100
        // 000000000000000000
        // Order 3
        // 000000000000000000
        // 000111100000000000
        // 000111100000000000
        // 001111100000000000
        // 001111001111110000
        // 001110001111111000
        // 001110000011111000
        // 001111000001110000
        // 001111110000110000
        // 011111110000110000
        // 001111111001111000
        // 001111111111111100
        // 001111111111111100
        // 000000000000000000
        // Order 10
        // 000000000000000000
        // 001111111100000000
        // 001111111110000000
        // 001111111111110000
        // 001111111111110000
        // 001111111111111000
        // 001111111111111000
        // 001111111001110000
        // 001111110000110000
        // 011111110000110000
        // 001111111001111000
        // 001111111111111100
        // 001111111111111100
        // 000000000000000000
        // Order 20
        // 000000000000000000
        // 001111111100001110
        // 001111111110011110
        // 001111111111111110
        // 001111111111111110
        // 001111111111111110
        // 001111111111111000
        // 001111111001110000
        // 001111110000110000
        // 011111110000110000
        // 001111111001111000
        // 001111111111111100
        // 001111111111111100
        // 000000000000000000
        let width = 18;
        let height = 14;
        let order = 2;
        let seed: felt252 = Seeder::shuffle(SEED + SEED, SEED + SEED);
        let cave = Caver::generate(width, height, order, seed);
        assert_eq!(cave, 0x78001E000F80038FC0E3F8383E0F0703F0C1FC303F9E0FFFC3FFF00000);
    }
}
