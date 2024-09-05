//! Spread objects into a map.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::helpers::asserter::{Asserter, MAX_SIZE};

// Constants

const MULTIPLIER: u256 = 10000;

/// Errors module.
pub mod errors {
    pub const SPREADER_INVALID_DIMENSION: felt252 = 'Spreader: invalid dimension';
    pub const SPREADER_NOT_ENOUGH_PLACE: felt252 = 'Spreader: not enough place';
}

/// Implementation of the `SpreaderTrait` trait.
#[generate_trait]
pub impl Spreader of SpreaderTrait {
    /// Spread objects into a map.
    /// # Arguments
    /// * `grid` - The grid where to spread the objects
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `count` - The number of objects to spread
    /// * `seed` - The seed to spread the objects
    /// # Returns
    /// * The grid with the objects spread
    #[inline]
    fn generate(grid: felt252, width: u8, height: u8, count: u8, mut seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Check] Ensure there is enough space for the objects
        let total = Bitmap::popcount(grid);
        assert(count <= total, errors::SPREADER_NOT_ENOUGH_PLACE);
        // [Effect] Deposite objects uniformly
        let start = Bitmap::least_significant_bit(grid);
        let merge = Self::iter(grid, start, total, count, seed);
        let objects: u256 = grid.into() ^ merge.into();
        objects.try_into().unwrap()
    }

    /// Recursive function to spread objects into the grid.
    /// # Arguments
    /// * `grid` - The grid where to spread the objects
    /// * `index` - The current index
    /// * `total` - The total number of objects
    /// * `count` - The number of objects to spread
    /// * `seed` - The seed to spread the objects
    /// # Returns
    /// * The original grid with the objects spread set to 0
    #[inline]
    fn iter(mut grid: felt252, index: u8, total: u8, mut count: u8, seed: felt252) -> felt252 {
        // [Checl] Stop if all objects are placed
        if count == 0 || index >= total {
            return grid;
        };
        // [Check] Skip if the position is already occupied
        let seed = Seeder::shuffle(seed, seed);
        if Bitmap::get(grid, index) == 0 {
            return Self::iter(grid, index + 1, total, count, seed);
        };
        // [Compute] Uniform random number between 0 and MULTIPLIER
        let random = seed.into() % MULTIPLIER;
        let probability: u256 = count.into() * MULTIPLIER / (total - index).into();
        // [Check] Probability of being an object
        if random <= probability {
            // [Compute] Update grid
            count -= 1;
            // [Effect] Set bit to 0
            grid = Bitmap::unset(grid, index);
        };
        Self::iter(grid, index + 1, total, count, seed)
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Spreader;

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_spreader_generate() {
        // 000000000000100000
        // 000010100000000000
        // 000010000100000000
        // 000000101000000000
        // 011001000000100000
        // 000000100001000000
        // 000100000000001100
        // 000000100000000000
        // 010000110000100011
        // 000000000000000010
        // 010000010000111000
        // 000001000010000000
        // 001000000000000000
        // 001000000100100000
        let width = 18;
        let height = 14;
        let grid: felt252 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        let room = Spreader::generate(grid, width, height, 35, SEED);
        assert_eq!(room, 0x802800084000A006408008401003008004308C0002410E01080200008120);
    }
}

