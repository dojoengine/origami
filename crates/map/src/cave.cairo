//! Cave generation methods.

// Internal imports

use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::power::TwoPower;
use origami_map::helpers::seeder::Seeder;
use origami_map::types::direction::Direction;

// Constants

const MAX_SIZE: u8 = 252;

/// Cave struct.
#[derive(Destruct)]
pub struct Cave {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
}

/// Errors module.
pub mod errors {
    pub const CAVE_INVALID_EXIT: felt252 = 'Cave: invalid exit';
    pub const CAVE_INVALID_DIMENSION: felt252 = 'Cave: invalid dimension';
}

/// Implementation of the `CaveTrait` trait for the `Cave` struct.
#[generate_trait]
pub impl CaveImpl of CaveTrait {
    #[inline(always)]
    fn new(width: u8, height: u8, count: u8, seed: felt252) -> Cave {
        // [Check] Valid dimensions
        let size = width * height;
        assert(width * height <= MAX_SIZE, errors::CAVE_INVALID_DIMENSION);
        // [Effect] Deposite objects uniformly
        let seed = Seeder::reseed(seed, seed);
        let default: u256 = seed.into() / TwoPower::power(252 - size);
        let mut cave = Cave { width, height, grid: default.try_into().unwrap() };
        Self::generate(ref cave, count.into());
        // [Return] Cave
        cave
    }

    #[inline]
    fn is_edge(ref self: Cave, x: u8, y: u8) -> bool {
        let width: u8 = self.width;
        let height: u8 = self.height;
        x == 0 || y == 0 || x == width - 1 || y == height - 1
    }

    #[inline]
    fn add(ref self: Cave, position: u8) {
        // [Check] Exit is not a corner and on edge
        self.assert_not_corner(position);
        self.assert_on_edge(position);
        // [Effect] Dig until it reaches the cave
        let (x, y) = (position % self.width, position / self.width);
        let direction: Direction = if x == 0 {
            Direction::East
        } else if x == self.width - 1 {
            Direction::West
        } else if y == 0 {
            Direction::North
        } else {
            Direction::South
        };
        Self::dig(ref self, position, direction);
    }

    #[inline]
    fn next(ref self: Cave, position: u8, direction: Direction) -> u8 {
        let width = self.width;
        match direction {
            Direction::North => position + width,
            Direction::East => position + 1,
            Direction::South => position - width,
            Direction::West => position - 1,
            _ => position,
        }
    }

    #[inline]
    fn dig(ref self: Cave, position: u8, direction: Direction) {
        self.grid = Bitmap::set(self.grid, position);
        let (x, y) = (position % self.width, position / self.width);
        let next = self.next(position, direction);
        if Bitmap::get(self.grid, next) == 0 && self.count_direct_floor(x, y) < 2 {
            Self::dig(ref self, next, direction);
        }
    }

    #[inline]
    fn generate(ref self: Cave, count: u16) {
        // [Check] Stop if the loop count is zero
        let size: u16 = (self.width * self.height).into();
        let mut index: u16 = (size - 1) * count;
        while index != 0 {
            self.assess((index % size).try_into().unwrap(), size.try_into().unwrap());
            index -= 1;
        };
    }

    #[inline]
    fn assess(ref self: Cave, index: u8, size: u8) {
        let is_wall = Bitmap::get(self.grid, index) == 0;
        let (x, y) = (index % self.width, index / self.width);
        let is_edge = self.is_edge(x, y) && index < size;
        let floor_count = self.count_direct_floor(x, y) + self.count_indirect_floor(x, y);
        if is_wall && floor_count > 4 && !is_edge {
            // [Effect] Convert wall into floor if surrounded by more than 4 floors
            self.grid = Bitmap::set(self.grid, index);
        } else if !is_wall && (floor_count < 3 || is_edge) {
            // [Effect] Convert floor into wall if surrounded by less than 3 floors
            self.grid = Bitmap::unset(self.grid, index);
        }
    }

    #[inline]
    fn count_direct_floor(ref self: Cave, x: u8, y: u8) -> u8 {
        // [Compute] Neighbors
        let mut floor_count: u8 = 0;
        // [Compute] North
        if y < self.height - 1 {
            let index = (y + 1) * self.width + x;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] East
        if x < self.width - 1 {
            let index = y * self.width + x + 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] South
        if y > 0 {
            let index = (y - 1) * self.width + x;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] West
        if x > 0 {
            let index = y * self.width + x - 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        floor_count
    }

    #[inline]
    fn count_indirect_floor(ref self: Cave, x: u8, y: u8) -> u8 {
        // [Compute] Neighbors
        let mut floor_count: u8 = 0;
        // [Compute] North West
        if y < self.height - 1 && x > 0 {
            let index = (y + 1) * self.width + x - 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] North East
        if y < self.height - 1 && x < self.width - 1 {
            let index = (y + 1) * self.width + x + 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] South East
        if y > 0 && x < self.width - 1 {
            let index = (y - 1) * self.width + x + 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        // [Compute] South West
        if y > 0 && x > 0 {
            let index = (y - 1) * self.width + x - 1;
            floor_count += Bitmap::get(self.grid, index);
        };
        floor_count
    }
}


#[generate_trait]
impl CaveAssert of AssertTrait {
    #[inline]
    fn assert_on_edge(ref self: Cave, position: u8) {
        let (x, y) = (position % self.width, position / self.width);
        assert(
            x == 0 || x == self.width - 1 || y == 0 || y == self.height - 1,
            errors::CAVE_INVALID_EXIT
        );
    }

    #[inline]
    fn assert_not_corner(ref self: Cave, position: u8) {
        let (x, y) = (position % self.width, position / self.width);
        assert(x != 0 || y != 0, errors::CAVE_INVALID_EXIT);
        assert(x != self.width - 1 || y != 0, errors::CAVE_INVALID_EXIT);
        assert(x != 0 || y != self.height - 1, errors::CAVE_INVALID_EXIT);
        assert(x != self.width - 1 || y != self.height - 1, errors::CAVE_INVALID_EXIT);
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Cave, CaveTrait};

    // Constants

    const SEED: felt252 = 'SEED';

    #[test]
    fn test_cave_new_generation() {
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
        let cave = CaveTrait::new(width, height, order, SEED);
        assert_eq!(cave.grid, 0xC039F01E7E07FF81FFE0FFF87FFE1FFF83FFE0FDF81E3E038700000);
    }

    #[test]
    fn test_cave_new_seed_generation() {
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
        let cave = CaveTrait::new(width, height, order, SEED + SEED);
        assert_eq!(cave.grid, 0x78001E000F80038FC0E3F8383E0F0703F0C1FC303F9E0FFFC3FFF00000);
    }

    #[test]
    fn test_cave_add() {
        // 000000000000000000
        // 000000000000001100
        // 000000111001111100
        // 000001111001111110
        // 000001111111111110
        // 000001111111111110
        // 000011111111111110
        // 000111111111111110
        // 111111111111111110
        // 000011111111111110
        // 000011111101111110
        // 000001111000111110
        // 000000111000011100
        // 000000000000000000
        let width = 18;
        let height = 14;
        let order = 2;
        let mut cave = CaveTrait::new(width, height, order, SEED);
        cave.add(107);
        assert_eq!(cave.grid, 0xC039F01E7E07FF81FFE0FFF87FFEFFFF83FFE0FDF81E3E038700000);
    }
}
