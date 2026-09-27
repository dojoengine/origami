//! Map assert helper functions.

// Constants

/// Largest board, in bits: the border invariant needs every bitmap below 2^251.
pub const MAX_SIZE: u16 = 251;

/// Errors module.
pub mod errors {
    pub const ASSERTER_INVALID_DIMENSION: felt252 = 'Asserter: invalid dimension';
    pub const ASSERTER_POSITION_IS_CORNER: felt252 = 'Asserter: position is a corner';
    pub const ASSERTER_POSITION_NOT_EDGE: felt252 = 'Asserter: position not an edge';
    pub const ASSERTER_POSITION_NOT_INSIDE: felt252 = 'Asserter: position not inside';
}

#[generate_trait]
pub impl Asserter of AssertTrait {
    /// Check if the position is on the edge of the map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `x` - The x coordinate of the position
    /// * `y` - The y coordinate of the position
    /// # Returns
    /// * `true` if the position is on the edge of the map, `false` otherwise
    #[inline]
    fn is_edge(width: u8, height: u8, x: u8, y: u8) -> bool {
        x == 0 || y == 0 || x == width - 1 || y == height - 1
    }

    /// Check if the position is a corner of the map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `x` - The x coordinate of the position
    /// * `y` - The y coordinate of the position
    /// # Returns
    /// * `true` if the position is a corner of the map, `false` otherwise
    #[inline]
    fn is_corner(width: u8, height: u8, x: u8, y: u8) -> bool {
        (x == 0 || x == width - 1) && (y == 0 || y == height - 1)
    }

    /// Assert that the dimensions are valid: `W, H >= 3` and `W * H <= 251`.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Panics
    /// * If the dimensions are invalid
    #[inline]
    fn assert_valid_dimension(width: u8, height: u8) {
        assert(width > 2, errors::ASSERTER_INVALID_DIMENSION);
        assert(height > 2, errors::ASSERTER_INVALID_DIMENSION);
        let size: u16 = width.into() * height.into();
        assert(size <= MAX_SIZE, errors::ASSERTER_INVALID_DIMENSION);
    }

    /// Assert that the position is on the edge of the map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The position to check
    /// # Panics
    /// * If the position is not on the edge of the map
    #[inline]
    fn assert_on_edge(width: u8, height: u8, position: u8) {
        let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
        assert(Self::is_edge(width, height, x, y), errors::ASSERTER_POSITION_NOT_EDGE);
    }

    /// Assert that the position is not a corner of the map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The position to check
    /// # Panics
    /// * If the position is a corner of the map
    #[inline]
    fn assert_not_corner(width: u8, height: u8, position: u8) {
        let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
        assert(!Self::is_corner(width, height, x, y), errors::ASSERTER_POSITION_IS_CORNER);
    }

    /// Assert that the position lies in the board.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The position to check
    /// # Panics
    /// * If the position is outside the board
    #[inline]
    fn assert_inside(width: u8, height: u8, position: u8) {
        let size: u16 = width.into() * height.into();
        assert(position.into() < size, errors::ASSERTER_POSITION_NOT_INSIDE);
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Asserter;

    #[test]
    fn test_asserter_valid_dimensions() {
        Asserter::assert_valid_dimension(3, 3);
        Asserter::assert_valid_dimension(17, 14);
        Asserter::assert_valid_dimension(19, 13);
        Asserter::assert_valid_dimension(83, 3);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_asserter_revert_too_large() {
        // 252 bits: one too many
        Asserter::assert_valid_dimension(18, 14);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_asserter_revert_u8_overflow() {
        // 16 * 16 = 256 overflows u8, the dimension error must still be raised
        Asserter::assert_valid_dimension(16, 16);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_asserter_revert_too_small() {
        Asserter::assert_valid_dimension(2, 20);
    }

    #[test]
    fn test_asserter_edges_and_corners() {
        assert!(Asserter::is_edge(7, 7, 0, 3));
        assert!(Asserter::is_edge(7, 7, 3, 6));
        assert!(!Asserter::is_edge(7, 7, 3, 3));
        assert!(Asserter::is_corner(7, 7, 6, 6));
        assert!(Asserter::is_corner(7, 7, 0, 6));
        assert!(!Asserter::is_corner(7, 7, 0, 3));
        Asserter::assert_on_edge(7, 7, 3);
        Asserter::assert_not_corner(7, 7, 3);
        Asserter::assert_inside(7, 7, 48);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not an edge')]
    fn test_asserter_revert_not_edge() {
        Asserter::assert_on_edge(7, 7, 24);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position is a corner')]
    fn test_asserter_revert_corner() {
        Asserter::assert_not_corner(7, 7, 6);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not inside')]
    fn test_asserter_revert_outside() {
        Asserter::assert_inside(7, 7, 49);
    }
}
