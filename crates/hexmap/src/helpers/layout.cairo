//! Board layout: masks, neighbour expansion and coordinates.
//!
//! Pointy-top, odd-r offset, row-major: `i = y * width + x`, see `types::direction`.
//!
//! Border invariant: a bitmap that is expanded only holds interior tiles
//! (`1 <= x <= W - 2`, `1 <= y <= H - 2`) and `W * H <= 251`. Then every neighbour shift is an
//! exact field multiplication (no wrap-around, no dropped bit, no overflow) and only the set
//! operations need the bitwise builtin.

// Core imports

use core::felt252_div;

// Internal imports

use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::types::direction::Direction;

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

/// Per-map constants of the neighbour expansion, computed once per call.
#[derive(Copy, Drop)]
pub struct Layout {
    pub width: u8,
    pub height: u8,
    /// Bits of the even rows.
    pub even: u256,
    /// 2^(W-1): up shift of the even rows.
    pub up_even: felt252,
    /// 2^W: up shift of the odd rows.
    pub up_odd: felt252,
    /// 2^-(W+1): down shift of the even rows.
    pub down_even: felt252,
    /// 2^-W: down shift of the odd rows.
    pub down_odd: felt252,
}

#[generate_trait]
pub impl LayoutImpl of LayoutTrait {
    /// Compute the layout constants of a map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The layout
    #[inline]
    fn new(width: u8, height: u8) -> Layout {
        let up_odd = Bits::pow(width);
        let down_odd = Bits::inv(width);
        Layout {
            width,
            height,
            even: Self::even(width, height).into(),
            up_even: up_odd * INV_2,
            up_odd,
            down_even: down_odd * INV_2,
            down_odd,
        }
    }

    /// Bits of the whole board, `2^(W*H) - 1`.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The board mask
    #[inline]
    fn board(width: u8, height: u8) -> felt252 {
        Bits::pow(width * height) - 1
    }

    /// Bits of the even rows, `ROW * (2^(2W * ceil(H/2)) - 1) / (2^(2W) - 1)`.
    /// The field division is exact because the divisor divides the numerator.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The even rows mask
    #[inline]
    fn even(width: u8, height: u8) -> felt252 {
        let row = Bits::pow(width);
        let size = width * height;
        // [Compute] 2^(2W * ceil(H/2)), may exceed the field: exact anyway, the quotient fits
        let top = if height % 2 == 0 {
            Bits::pow(size)
        } else {
            Bits::pow(size) * row
        };
        let pair = row * row - 1;
        felt252_div((row - 1) * (top - 1), pair.try_into().unwrap())
    }

    /// Bits of the interior, `(2^(W-1) - 2) * 2^W * (2^(W*(H-2)) - 1) / (2^W - 1)`.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The interior mask
    #[inline]
    fn interior(width: u8, height: u8) -> felt252 {
        let row = Bits::pow(width);
        let inner = row * INV_2 - 2;
        let rows = Bits::pow(width * (height - 2)) - 1;
        felt252_div(inner * row * rows, (row - 1).try_into().unwrap())
    }

    /// Bits of the hexagon of radius `radius` centred in its `(2R+3) x (2R+3)` board, whose
    /// outer ring is left as wall. With `W * H <= 251`, the largest radius is 6 (15x15).
    /// # Arguments
    /// * `radius` - The radius of the hexagon
    /// # Returns
    /// * The hexagon mask
    fn hexagon(radius: u8) -> felt252 {
        let width = 2 * radius + 3;
        let center = radius + 1;
        let half = center / 2;
        let mut mask: felt252 = 0;
        let mut y: u8 = 1;
        while y != width - 1 {
            // [Compute] Row extent: x_min = cx - R + max(0, cy - y) + y/2 - cy/2
            let (start, length) = if y < center {
                (1 + center - y + y / 2 - half, 2 * radius + 1 - (center - y))
            } else {
                (1 + y / 2 - half, 2 * radius + 1 - (y - center))
            };
            mask += (Bits::pow(length) - 1) * Bits::pow(y * width + start);
            y += 1;
        }
        mask
    }

    /// Hex dilation: the frontier and all its neighbours (design section 2.2).
    /// 5 `u256` set operations, 3 felt-to-`u256` conversions, all shifts are field products.
    /// # Arguments
    /// * `self` - The layout
    /// * `frontier` - The frontier, interior tiles only (border invariant)
    /// # Returns
    /// * The frontier and its neighbours
    #[inline]
    fn expand(self: @Layout, frontier: u256) -> u256 {
        let layout = *self;
        // [Compute] Frontier and its West neighbours, then split by row parity
        let pairs = frontier | (frontier + frontier);
        let pairs_even = Bits::to_felt(pairs & layout.even);
        let pairs_felt = Bits::to_felt(pairs);
        let pairs_odd = pairs_felt - pairs_even;
        // [Compute] NE/NW and SE/SW, parities land on disjoint rows
        let up = pairs_even * layout.up_even + pairs_odd * layout.up_odd;
        let down = pairs_even * layout.down_even + pairs_odd * layout.down_odd;
        // [Compute] East neighbours
        let east = Bits::to_felt(frontier) * INV_2;
        // [Return] Union
        pairs | east.into() | up.into() | down.into()
    }

    /// Hex dilation for boards of at most 128 bits (`W * H <= 128`): the same formulation on a
    /// single `u128` limb, about a third cheaper than `expand` (see `GAS.md`).
    /// # Arguments
    /// * `self` - The layout
    /// * `frontier` - The frontier, interior tiles only (border invariant)
    /// # Returns
    /// * The frontier and its neighbours
    #[inline]
    fn expand_small(self: @Layout, frontier: u128) -> u128 {
        let layout = *self;
        let pairs = frontier | (frontier + frontier);
        let pairs_even: felt252 = (pairs & layout.even.low).into();
        let pairs_odd = pairs.into() - pairs_even;
        let up: u128 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd)
            .try_into()
            .unwrap();
        let down: u128 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd)
            .try_into()
            .unwrap();
        let east: u128 = (frontier.into() * INV_2).try_into().unwrap();
        pairs | east | up | down
    }

    /// The 6 neighbour bits of an interior position.
    /// `2^i * M_parity` with `M` the field sum of the 6 relative offsets, exact because every
    /// neighbour of an interior tile lies in the board.
    /// # Arguments
    /// * `self` - The layout
    /// * `position` - The position, an interior tile
    /// # Returns
    /// * The neighbour mask
    #[inline]
    fn neighbour_mask(self: @Layout, position: u8) -> felt252 {
        let layout = *self;
        let (_, odd) = Self::parity(layout.width, position);
        let offsets = if odd {
            // {-1, +1, +W, +W+1, -W, -W+1}
            INV_2 + 2 + 3 * (layout.up_odd + layout.down_odd)
        } else {
            // {-1, +1, +W-1, +W, -W-1, -W}
            INV_2 + 2 + 3 * (layout.up_even + layout.down_even)
        };
        Bits::pow(position) * offsets
    }

    /// Position of the coordinates.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `x` - The column
    /// * `y` - The row
    /// # Returns
    /// * The position
    #[inline]
    fn index(width: u8, x: u8, y: u8) -> u8 {
        y * width + x
    }

    /// Coordinates of a position.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `position` - The position
    /// # Returns
    /// * The column and the row
    #[inline]
    fn coords(width: u8, position: u8) -> (u8, u8) {
        let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
        (x, y)
    }

    /// Column and row parity of a position, one division by `2W`.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `position` - The position
    /// # Returns
    /// * The column and whether the row is odd
    #[inline]
    fn parity(width: u8, position: u8) -> (u8, bool) {
        let (_, rem) = DivRem::div_rem(position, (2 * width).try_into().unwrap());
        if rem < width {
            (rem, false)
        } else {
            (rem - width, true)
        }
    }

    /// Neighbour of a position, `None` if it falls outside the board.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The position
    /// * `direction` - The direction
    /// # Returns
    /// * The neighbour position if it lies in the board
    fn neighbor(width: u8, height: u8, position: u8, direction: Direction) -> Option<u8> {
        let (y, x) = DivRem::div_rem(position, width.try_into().unwrap());
        let odd = y % 2 == 1;
        match direction {
            Direction::East => if x == 0 {
                None
            } else {
                Some(position - 1)
            },
            Direction::West => if x == width - 1 {
                None
            } else {
                Some(position + 1)
            },
            Direction::NorthEast => if y == height - 1 {
                None
            } else if odd {
                Some(position + width)
            } else if x == 0 {
                None
            } else {
                Some(position + width - 1)
            },
            Direction::NorthWest => if y == height - 1 {
                None
            } else if !odd {
                Some(position + width)
            } else if x == width - 1 {
                None
            } else {
                Some(position + width + 1)
            },
            Direction::SouthEast => if y == 0 {
                None
            } else if odd {
                Some(position - width)
            } else if x == 0 {
                None
            } else {
                Some(position - width - 1)
            },
            Direction::SouthWest => if y == 0 {
                None
            } else if !odd {
                Some(position - width)
            } else if x == width - 1 {
                None
            } else {
                Some(position + 1 - width)
            },
        }
    }
}
