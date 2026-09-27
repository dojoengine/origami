//! Hex geometry: axial coordinates and grid distance.
//!
//! Odd-r offset to axial: `q = x - floor(y / 2)`, `r = y`. The distance is
//! `max(|dq|, |dr|, |dq + dr|)`: exact on an obstacle-free board, admissible and consistent as a
//! unit-cost heuristic.

// Internal imports

use origami_hexmap::helpers::layout::LayoutTrait;

#[generate_trait]
pub impl Geometry of GeometryTrait {
    /// Axial coordinates of a position.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `position` - The position
    /// # Returns
    /// * The axial coordinates `(q, r)`
    #[inline]
    fn to_axial(width: u8, position: u8) -> (i16, i16) {
        let (x, y) = LayoutTrait::coords(width, position);
        let q: i16 = x.into() - (y / 2).into();
        (q, y.into())
    }

    /// Grid distance between two positions.
    /// Measured cheaper than a single division by `2W` per position (see `GAS.md`).
    /// # Arguments
    /// * `width` - The width of the map
    /// * `from` - The first position
    /// * `to` - The second position
    /// # Returns
    /// * The number of steps between both positions on an empty board
    #[inline]
    fn distance(width: u8, from: u8, to: u8) -> u8 {
        let (x_from, y_from) = LayoutTrait::coords(width, from);
        let (x_to, y_to) = LayoutTrait::coords(width, to);
        // [Compute] dq = (x2 - x1) - (y2/2 - y1/2), without negative intermediates
        let lhs = x_to + y_from / 2;
        let rhs = x_from + y_to / 2;
        let (dq, dq_negative) = if lhs >= rhs {
            (lhs - rhs, false)
        } else {
            (rhs - lhs, true)
        };
        let (dr, dr_negative) = if y_to >= y_from {
            (y_to - y_from, false)
        } else {
            (y_from - y_to, true)
        };
        // [Return] Same signs: |dq| + |dr|, opposite signs: max(|dq|, |dr|)
        if dq_negative == dr_negative {
            dq + dr
        } else if dq > dr {
            dq
        } else {
            dr
        }
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Geometry;

    #[test]
    fn test_geometry_to_axial() {
        // (x, y) = (3, 5) on width 7: q = 3 - 2 = 1
        let (q, r) = Geometry::to_axial(7, 5 * 7 + 3);
        assert!(q == 1);
        assert!(r == 5);
        // (0, 4): q = -2
        let (q, r) = Geometry::to_axial(7, 4 * 7);
        assert!(q == -2);
        assert!(r == 4);
    }

    #[test]
    fn test_geometry_distance_design_checks() {
        // (x, 0) -> (x - 1, 1) is 1 step
        assert!(Geometry::distance(7, 3, 7 + 2) == 1);
        // (0, 0) -> (0, 2) is 2 steps
        assert!(Geometry::distance(7, 0, 14) == 2);
        // Symmetric and zero on the diagonal
        assert!(Geometry::distance(7, 7 + 2, 3) == 1);
        assert!(Geometry::distance(7, 24, 24) == 0);
        // Same row
        assert!(Geometry::distance(7, 7, 13) == 6);
    }
}
