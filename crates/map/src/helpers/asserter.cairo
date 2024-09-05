//! Map assert helper functions.

// Constants
pub const MAX_SIZE: u8 = 252;

/// Errors module.
pub mod errors {
    pub const ASSERTER_INVALID_DIMENSION: felt252 = 'Asserter: invalid dimension';
    pub const ASSERTER_POSITION_IS_CORNER: felt252 = 'Asserter: position is a corner';
    pub const ASSERTER_POSITION_NOT_EDGE: felt252 = 'Asserter: position not an edge';
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
        (x == 0 && y == 0)
            || (x == width - 1 && y == 0)
            || (x == 0 && y == height - 1)
            || (x == width - 1 && y == height - 1)
    }

    /// Assert that the dimensions are valid.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Panics
    /// * If the dimensions are invalid
    #[inline]
    fn assert_valid_dimension(width: u8, height: u8) {
        assert(width > 2, errors::ASSERTER_INVALID_DIMENSION);
        assert(height > 2, errors::ASSERTER_INVALID_DIMENSION);
        assert(width * height <= MAX_SIZE, errors::ASSERTER_INVALID_DIMENSION);
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
        let (x, y) = (position % width, position / width);
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
        let (x, y) = (position % width, position / width);
        assert(!Self::is_corner(width, height, x, y), errors::ASSERTER_POSITION_IS_CORNER);
    }
}
