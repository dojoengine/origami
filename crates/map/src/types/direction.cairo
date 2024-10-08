// Constants

pub const DIRECTION_SIZE: u32 = 0x10;

// Types.
#[derive(Drop, Copy, Serde)]
pub struct HexTile {
    pub col: u32,
    pub row: u32,
}

#[derive(Drop, Copy, Serde)]
pub enum Direction {
    None,
    NorthWest,
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
}

#[generate_trait]
pub impl DirectionImpl of DirectionTrait {
    /// Compute shuffled directions.
    /// # Arguments
    /// * `seed` - The seed to generate the shuffled directions
    /// # Returns
    /// * The shuffled directions
    #[inline]
    fn compute_shuffled_directions(seed: felt252) -> u32 {
        // [Compute] Random number
        let mut random: u32 = (seed.into() % 24_u256).try_into().unwrap();
        // [Return] Pickup a random permutation
        match random {
            0 => 0x2468,
            1 => 0x2486,
            2 => 0x2648,
            3 => 0x2684,
            4 => 0x2846,
            5 => 0x2864,
            6 => 0x4268,
            7 => 0x4286,
            8 => 0x4628,
            9 => 0x4682,
            10 => 0x4826,
            11 => 0x4862,
            12 => 0x6248,
            13 => 0x6284,
            14 => 0x6428,
            15 => 0x6482,
            16 => 0x6824,
            17 => 0x6842,
            18 => 0x8246,
            19 => 0x8264,
            20 => 0x8426,
            21 => 0x8462,
            22 => 0x8624,
            _ => 0x8642,
        }
    }

    /// Get the next direction from a packed directions.
    /// # Arguments
    /// * `directions` - The packed directions
    /// # Returns
    /// * The next direction
    /// # Effects
    /// * The packed directions is updated
    #[inline]
    fn pop_front(ref directions: u32) -> Direction {
        let direciton: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
        directions /= DIRECTION_SIZE;
        direciton.into()
    }

    /// Get the next direction from a given position and direction.
    /// # Arguments
    /// * `self` - The current direction
    /// * `position` - The current position
    /// * `width` - The width of the grid
    /// # Returns
    /// * The next position
    #[inline]
    fn next(self: Direction, position: u8, width: u8) -> u8 {
        match self {
            Direction::None => position,
            Direction::NorthWest => position + width + 1,
            Direction::North => position + width,
            Direction::NorthEast => position + width - 1,
            Direction::East => position - 1,
            Direction::SouthEast => position - width - 1,
            Direction::South => position - width,
            Direction::SouthWest => position - width + 1,
            Direction::West => position + 1,
        }
    }
}

pub impl DirectionIntoFelt252 of Into<Direction, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            Direction::None => 0,
            Direction::NorthWest => 1,
            Direction::North => 2,
            Direction::NorthEast => 3,
            Direction::East => 4,
            Direction::SouthEast => 5,
            Direction::South => 6,
            Direction::SouthWest => 7,
            Direction::West => 8,
        }
    }
}

pub impl DirectionFromU8 of Into<u8, Direction> {
    fn into(self: u8) -> Direction {
        match self {
            0 => Direction::None,
            1 => Direction::NorthWest,
            2 => Direction::North,
            3 => Direction::NorthEast,
            4 => Direction::East,
            5 => Direction::SouthEast,
            6 => Direction::South,
            7 => Direction::SouthWest,
            8 => Direction::West,
            _ => Direction::None,
        }
    }
}
