//! Room generation methods.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;

// Constants

const MAX_SIZE: u8 = 252;
const MULTIPLIER: u256 = 10000;

/// Room struct.
#[derive(Destruct)]
pub struct Room {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
    pub seed: felt252,
}

/// Errors module.
pub mod errors {
    pub const ROOM_NOT_ENOUGH_PLACE: felt252 = 'Room: not enough place';
    pub const ROOM_INVALID_DIMENSION: felt252 = 'Room: invalid dimension';
}

/// Implementation of the `RoomTrait` trait for the `Room` struct.
#[generate_trait]
pub impl RoomImpl of RoomTrait {
    #[inline(always)]
    fn new(grid: felt252, width: u8, height: u8, count: u8, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        assert(width * height <= MAX_SIZE, errors::ROOM_INVALID_DIMENSION);
        // [Check] Ensure there is enough space for the objects
        let mut total = width * height;
        // [Info] Remove one since felt252 cannot handle 2^253 - 1
        if total == MAX_SIZE {
            total -= 1;
        };
        assert(count <= total, errors::ROOM_NOT_ENOUGH_PLACE);
        // [Effect] Deposite objects uniformly
        Self::generate(grid, 0, total, count, seed)
    }

    #[inline]
    fn generate(
        mut grid: felt252, index: u8, total: u8, mut count: u8, mut seed: felt252
    ) -> felt252 {
        // [Checl] Stop if all objects are placed
        if count == 0 || index >= total {
            return grid;
        };
        // [Check] Skip if the position is already occupied
        seed = Seeder::reseed(seed, seed);
        if Bitmap::get(grid, index) == 1 {
            return Self::generate(grid, index + 1, total, count, seed);
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
        Self::generate(grid, index + 1, total, count, seed)
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Room, RoomTrait};

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_room_new_generation() {
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
        let room = RoomTrait::new(0, width, height, 35, SEED);
        assert_eq!(room, 0x802800084000A006408008401003008004308C0002410E01080200008120);
    }
}
