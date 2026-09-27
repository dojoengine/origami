//! Hexagonal directions, pointy-top, odd-r offset layout.
//!
//! Index convention (shared with `origami_map`): `i = y * width + x`, bit 0 is printed
//! bottom-right, `+1` is West and `+width` is North. Odd rows are drawn shifted half a tile
//! toward increasing `x` (to the left in the printout).
//!
//! | Direction | even row      | odd row       |
//! |-----------|---------------|---------------|
//! | East      | `i - 1`       | `i - 1`       |
//! | NorthEast | `i + W - 1`   | `i + W`       |
//! | NorthWest | `i + W`       | `i + W + 1`   |
//! | West      | `i + 1`       | `i + 1`       |
//! | SouthWest | `i - W`       | `i - W + 1`   |
//! | SouthEast | `i - W - 1`   | `i - W`       |

// Constants

/// Number of directions.
pub const DIRECTION_COUNT: u8 = 6;
/// Width in bits of a direction in a packed permutation.
pub const DIRECTION_SIZE: NonZero<u32> = 0x10;

/// Types.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Direction {
    East,
    NorthEast,
    NorthWest,
    West,
    SouthWest,
    SouthEast,
}

#[generate_trait]
pub impl DirectionImpl of DirectionTrait {
    /// Return the opposite direction.
    /// # Arguments
    /// * `self` - The direction
    /// # Returns
    /// * The opposite direction
    #[inline]
    fn opposite(self: Direction) -> Direction {
        match self {
            Direction::East => Direction::West,
            Direction::NorthEast => Direction::SouthWest,
            Direction::NorthWest => Direction::SouthEast,
            Direction::West => Direction::East,
            Direction::SouthWest => Direction::NorthEast,
            Direction::SouthEast => Direction::NorthWest,
        }
    }

    /// Return the neighbour index without any bound check.
    /// # Arguments
    /// * `self` - The direction
    /// * `position` - The current position, its neighbour must lie in the board
    /// * `width` - The width of the map
    /// * `odd` - Whether the position lies on an odd row
    /// # Returns
    /// * The neighbour position
    #[inline]
    fn next(self: Direction, position: u8, width: u8, odd: bool) -> u8 {
        match self {
            Direction::East => position - 1,
            Direction::NorthEast => if odd {
                position + width
            } else {
                position + width - 1
            },
            Direction::NorthWest => if odd {
                position + width + 1
            } else {
                position + width
            },
            Direction::West => position + 1,
            Direction::SouthWest => if odd {
                position + 1 - width
            } else {
                position - width
            },
            Direction::SouthEast => if odd {
                position - width
            } else {
                position - width - 1
            },
        }
    }

    /// Pop the next direction from a packed permutation (4 bits per direction, first in the
    /// lowest nibble), as returned by `Rng::shuffle6`.
    /// # Arguments
    /// * `directions` - The packed directions
    /// # Returns
    /// * The next direction
    /// # Effects
    /// * The packed directions are updated
    #[inline]
    fn pop_front(ref directions: u32) -> Direction {
        let (rest, index) = DivRem::div_rem(directions, DIRECTION_SIZE);
        directions = rest;
        match index {
            0 => Direction::East,
            1 => Direction::NorthEast,
            2 => Direction::NorthWest,
            3 => Direction::West,
            4 => Direction::SouthWest,
            _ => Direction::SouthEast,
        }
    }
}

pub impl DirectionIntoU8 of Into<Direction, u8> {
    #[inline]
    fn into(self: Direction) -> u8 {
        match self {
            Direction::East => 0,
            Direction::NorthEast => 1,
            Direction::NorthWest => 2,
            Direction::West => 3,
            Direction::SouthWest => 4,
            Direction::SouthEast => 5,
        }
    }
}

pub impl U8TryIntoDirection of TryInto<u8, Direction> {
    #[inline]
    fn try_into(self: u8) -> Option<Direction> {
        match self {
            0 => Some(Direction::East),
            1 => Some(Direction::NorthEast),
            2 => Some(Direction::NorthWest),
            3 => Some(Direction::West),
            4 => Some(Direction::SouthWest),
            5 => Some(Direction::SouthEast),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Direction, DirectionTrait};

    const WIDTH: u8 = 7;

    #[test]
    fn test_direction_opposite() {
        let mut index: u8 = 0;
        while index != 6 {
            let direction: Direction = index.try_into().unwrap();
            assert!(direction.opposite().opposite() == direction);
            assert!(direction.opposite() != direction);
            let opposite: u8 = direction.opposite().into();
            assert!(opposite == (index + 3) % 6);
            index += 1;
        }
    }

    #[test]
    fn test_direction_round_trip() {
        let mut index: u8 = 0;
        while index != 6 {
            let direction: Direction = index.try_into().unwrap();
            let back: u8 = direction.into();
            assert!(back == index);
            index += 1;
        }
        let none: Option<Direction> = 6_u8.try_into();
        assert!(none.is_none());
    }

    #[test]
    fn test_direction_next_even_row() {
        // (3, 2) = 17
        let position = 2 * WIDTH + 3;
        assert!(Direction::East.next(position, WIDTH, false) == 2 * WIDTH + 2);
        assert!(Direction::West.next(position, WIDTH, false) == 2 * WIDTH + 4);
        assert!(Direction::NorthEast.next(position, WIDTH, false) == 3 * WIDTH + 2);
        assert!(Direction::NorthWest.next(position, WIDTH, false) == 3 * WIDTH + 3);
        assert!(Direction::SouthEast.next(position, WIDTH, false) == 1 * WIDTH + 2);
        assert!(Direction::SouthWest.next(position, WIDTH, false) == 1 * WIDTH + 3);
    }

    #[test]
    fn test_direction_next_odd_row() {
        // (3, 3) = 24
        let position = 3 * WIDTH + 3;
        assert!(Direction::East.next(position, WIDTH, true) == 3 * WIDTH + 2);
        assert!(Direction::West.next(position, WIDTH, true) == 3 * WIDTH + 4);
        assert!(Direction::NorthEast.next(position, WIDTH, true) == 4 * WIDTH + 3);
        assert!(Direction::NorthWest.next(position, WIDTH, true) == 4 * WIDTH + 4);
        assert!(Direction::SouthEast.next(position, WIDTH, true) == 2 * WIDTH + 3);
        assert!(Direction::SouthWest.next(position, WIDTH, true) == 2 * WIDTH + 4);
    }

    #[test]
    fn test_direction_next_opposite_round_trip() {
        let mut index: u8 = 0;
        while index != 6 {
            let direction: Direction = index.try_into().unwrap();
            // Even row start, the neighbour of a vertical move lies on an odd row
            let position = 2 * WIDTH + 3;
            let vertical = index == 1 || index == 2 || index == 4 || index == 5;
            let next = direction.next(position, WIDTH, false);
            assert!(direction.opposite().next(next, WIDTH, vertical) == position);
            index += 1;
        }
    }

    #[test]
    fn test_direction_pop_front() {
        let mut directions: u32 = 0x501234;
        assert!(DirectionTrait::pop_front(ref directions) == Direction::SouthWest);
        assert!(DirectionTrait::pop_front(ref directions) == Direction::West);
        assert!(DirectionTrait::pop_front(ref directions) == Direction::NorthWest);
        assert!(DirectionTrait::pop_front(ref directions) == Direction::NorthEast);
        assert!(DirectionTrait::pop_front(ref directions) == Direction::East);
        assert!(DirectionTrait::pop_front(ref directions) == Direction::SouthEast);
        assert!(directions == 0);
    }
}
