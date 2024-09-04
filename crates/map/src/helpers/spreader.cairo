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
    #[inline]
    fn generate(grid: felt252, width: u8, height: u8, count: u8, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Check] Ensure there is enough space for the objects
        let mut total = width * height;
        // [Info] Remove one since felt252 cannot handle 2^253 - 1
        if total == MAX_SIZE {
            total -= 1;
        };
        assert(count <= total, errors::SPREADER_NOT_ENOUGH_PLACE);
        // [Effect] Deposite objects uniformly
        Self::iter(grid, 0, total, count, seed)
    }

    #[inline]
    fn iter(mut grid: felt252, index: u8, total: u8, mut count: u8, mut seed: felt252) -> felt252 {
        // [Checl] Stop if all objects are placed
        if count == 0 || index >= total {
            return grid;
        };
        // [Check] Skip if the position is already occupied
        seed = Seeder::reseed(seed, seed);
        if Bitmap::get(grid, index) == 1 {
            return Self::iter(grid, index + 1, total, count, seed);
        };
        // [Compute] Uniform random number between 0 and MULTIPLIER
        let random = seed.into() % MULTIPLIER;
        let probability: u256 = count.into() * MULTIPLIER / (total - index).into();
        // [Check] Probability of being an object
        if random <= probability {
            // [Compute] Update grid
            count -= 1;
            grid = Bitmap::set(grid, index);
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
        let room = Spreader::generate(0, width, height, 35, SEED);
        assert_eq!(room, 0x802800084000A006408008401003008004308C0002410E01080200008120);
    }
}

