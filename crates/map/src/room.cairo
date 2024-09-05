//! Room struct and generation methods.

// Internal imports

use origami_map::helpers::power::TwoPower;
use origami_map::helpers::mazer::Mazer;
use origami_map::helpers::asserter::Asserter;
use origami_map::helpers::walker::Walker;
use origami_map::helpers::caver::Caver;
use origami_map::helpers::digger::Digger;
use origami_map::helpers::spreader::Spreader;

/// Types.
#[derive(Copy, Drop)]
pub struct Room {
    pub width: u8,
    pub height: u8,
    pub grid: felt252,
    pub seed: felt252,
}

/// Implementation of the `RoomTrait` trait for the `Room` struct.
#[generate_trait]
pub impl RoomImpl of RoomTrait {
    #[inline]
    fn new_empty(width: u8, height: u8, seed: felt252) -> Room {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Effect] Generate room according to the method
        let grid = Private::empty(width, height);
        // [Effect] Create room
        Room { width, height, grid, seed }
    }

    #[inline]
    fn new_maze(width: u8, height: u8, seed: felt252) -> Room {
        let grid = Mazer::generate(width, height, seed);
        Room { width, height, grid, seed }
    }

    #[inline]
    fn new_cave(width: u8, height: u8, order: u8, seed: felt252) -> Room {
        let grid = Caver::generate(width, height, order, seed);
        Room { width, height, grid, seed }
    }

    #[inline]
    fn new_random_walk(width: u8, height: u8, steps: u16, seed: felt252) -> Room {
        let grid = Walker::generate(width, height, steps, seed);
        Room { width, height, grid, seed }
    }

    #[inline]
    fn open_with_corridor(ref self: Room, position: u8) {
        // [Effect] Add a corridor to open the room
        self.grid = Digger::corridor(self.width, self.height, position, self.grid, self.seed);
    }

    #[inline]
    fn open_with_maze(ref self: Room, position: u8) {
        // [Effect] Add a maze to open the room
        self.grid = Digger::maze(self.width, self.height, position, self.grid, self.seed);
    }

    #[inline]
    fn compute_distribution(ref self: Room, count: u8, seed: felt252) -> felt252 {
        Spreader::generate(self.grid, self.width, self.height, count, seed)
    }
}

#[generate_trait]
impl Private of PrivateTrait {
    #[inline]
    fn empty(width: u8, height: u8) -> felt252 {
        // [Effect] Generate empty room
        let offset: u256 = TwoPower::power(width);
        let row: felt252 = ((offset - 1) / 2).try_into().unwrap() - 1; // Remove head and tail bits
        let offset: felt252 = offset.try_into().unwrap();
        let mut index = height - 2;
        let mut default: felt252 = 0;
        loop {
            if index == 0 {
                break;
            };
            default += row;
            default *= offset;
            index -= 1;
        };
        default
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Room, RoomTrait};
    use origami_map::helpers::seeder::Seeder;

    // Constants

    const SEED: felt252 = 'S33D';

    #[test]
    fn test_room_new() {
        // 000000000000000000
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 011111111111111110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let mut room: Room = RoomTrait::new_empty(width, height, SEED);
        room.open_with_corridor(1);
        assert_eq!(room.grid, 0x1FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF9FFFE7FFF80002);
    }

    #[test]
    fn test_room_maze() {
        // 000000000000000000
        // 010111011111110110
        // 011101101000011100
        // 001011011011101010
        // 001100110010011110
        // 011011100111101010
        // 010110011101011010
        // 011011101011010110
        // 001000110110011010
        // 001111011010110110
        // 011001110011000100
        // 010110101101011100
        // 011101111011110110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let mut room: Room = RoomTrait::new_maze(width, height, SEED);
        room.open_with_corridor(1);
        assert_eq!(room.grid, 0x177F676870B6EA33279B9EA59D69BAD623668F6B6673116B5C77BD80002);
    }

    #[test]
    fn test_room_cave() {
        // 000000000000000000
        // 001100001100000000
        // 011111001100000000
        // 011111000110000110
        // 011111100111000110
        // 011111100011000000
        // 011111100000000000
        // 011111110000000000
        // 011111111100000000
        // 011111111111000000
        // 011111111111100110
        // 001111111111111110
        // 001111111111111110
        // 000000000000000010
        let width = 18;
        let height = 14;
        let order = 3;
        let seed: felt252 = Seeder::reseed(SEED, SEED);
        let mut room: Room = RoomTrait::new_cave(width, height, order, seed);
        room.open_with_corridor(1);
        assert_eq!(room.grid, 0xC3007CC01F1867E719F8C07E001FC007FC01FFC07FF98FFFE3FFF80002);
    }

    #[test]
    fn test_room_random_walk() {
        // 010000000000000000
        // 010000000011000000
        // 011000000111001100
        // 001101000111111110
        // 011011100011111110
        // 001111111111111110
        // 011010011111111110
        // 001010011101111110
        // 011011111111111110
        // 010011111111111110
        // 010011111111111110
        // 011011111111100000
        // 001101111111100000
        // 000000000000000000
        let width = 18;
        let height = 14;
        let steps: u16 = 2 * width.into() * height.into();
        let mut room: Room = RoomTrait::new_random_walk(width, height, steps, SEED);
        room.open_with_maze(250);
        assert_eq!(room.grid, 0x4000100C060730D1FE6E3F8FFFE69FF8A77E6FFF93FFE4FFF9BFE037F800000);
    }
}
