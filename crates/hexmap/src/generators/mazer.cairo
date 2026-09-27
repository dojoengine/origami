//! Maze generator: randomised backtracker over 6 directions (lot L5).
//!
//! The maze is a tree of open tiles grown from a random interior tile. A candidate `n`, neighbour
//! of the current tile `c`, is carved only if one mask test against the maze succeeds; the mask is
//! `2^c * K`, where `K` is a per-direction constant of the layout, so no neighbour is tested alone.
//!
//! Order 0: `n` is carved if `c` is its only open neighbour (and `n` itself is closed). Corridors
//! are one tile wide, walls one tile thick. Shown for a West step (`n = c + 1`), rotate for the
//! other directions:
//!
//! ```text
//!    0 0
//!   0 n c
//!    0 0
//! ```
//!
//! Order 1: additionally, no open tile lies at distance 2 of `n`, except the three tiles behind
//! `c` (`x`: the neighbours of `c` that are not neighbours of `n`). Two open tiles at distance 2
//! therefore always share an open neighbour: distinct corridors are separated by walls at least
//! two tiles thick and never run side by side.
//!
//! ```text
//!     0 0 0
//!    0 0 0 x
//!   0 0 n c x
//!    0 0 0 x
//!     0 0 0
//! ```
//!
//! Order 2 and above: rejected with `Mazer: order > 1 not supported`.
//!
//! Only the three forward neighbours of `c` are candidates: the two other neighbours of `c` touch
//! its parent, which is open. After a forward candidate is carved, the adjacent forward candidates
//! touch it and are skipped without a test. Every open tile has a single open path to every other
//! (the maze is a tree), so every open tile is reachable.

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::types::direction::{Direction, DirectionTrait};

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// 1/4 in the field.
const INV_4: felt252 = 0x60000000000000cc00000000000000000000000000000000000000000000001;

/// Errors module.
pub mod errors {
    pub const MAZER_INVALID_ORDER: felt252 = 'Mazer: order > 1 not supported';
}

/// Per-map constants of the carve test, computed once per generation.
#[derive(Copy, Drop)]
pub(crate) struct Carver {
    /// Last interior column, `W - 2`.
    pub right: felt252,
    /// Last interior row, `H - 2`.
    pub top: felt252,
    /// Order 1 rule.
    pub sparse: bool,
    /// 2^(W-1).
    pub up_even: felt252,
    /// 2^W.
    pub up_odd: felt252,
    /// 2^(W+1).
    pub up_odd_west: felt252,
    /// 2^-(W+1).
    pub down_even: felt252,
    /// 2^-W.
    pub down_odd: felt252,
    /// 2^-(W-1).
    pub down_odd_west: felt252,
    /// Closed neighbourhood of an even row tile, relative: `1 + sum of the 6 steps`.
    pub closed_even: felt252,
    /// Closed neighbourhood of an odd row tile, relative.
    pub closed_odd: felt252,
}

#[generate_trait]
pub(crate) impl CarverImpl of CarverTrait {
    /// Compute the carve constants of a map.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1
    /// # Returns
    /// * The carver
    /// # Panics
    /// * If the order is above 1
    #[inline]
    fn new(width: u8, height: u8, order: u8) -> Carver {
        assert(order <= 1, errors::MAZER_INVALID_ORDER);
        let up_odd = Bits::pow(width);
        let down_odd = Bits::inv(width);
        let up_even = up_odd * INV_2;
        let down_even = down_odd * INV_2;
        Carver {
            right: (width - 2).into(),
            top: (height - 2).into(),
            sparse: order == 1,
            up_even,
            up_odd,
            up_odd_west: up_odd + up_odd,
            down_even,
            down_odd,
            down_odd_west: down_odd + down_odd,
            closed_even: INV_2 + 3 + 3 * (up_even + down_even),
            closed_odd: INV_2 + 3 + 3 * (up_odd + down_odd),
        }
    }

    /// Field multiplier of one step: `2^n = 2^c * step`.
    /// # Arguments
    /// * `self` - The carver
    /// * `direction` - The direction
    /// * `odd` - Whether the current row is odd
    /// # Returns
    /// * The multiplier
    #[inline]
    fn step(self: @Carver, direction: Direction, odd: bool) -> felt252 {
        match direction {
            Direction::East => INV_2,
            Direction::NorthEast => if odd {
                *self.up_odd
            } else {
                *self.up_even
            },
            Direction::NorthWest => if odd {
                *self.up_odd_west
            } else {
                *self.up_odd
            },
            Direction::West => 2,
            Direction::SouthWest => if odd {
                *self.down_odd_west
            } else {
                *self.down_odd
            },
            Direction::SouthEast => if odd {
                *self.down_odd
            } else {
                *self.down_even
            },
        }
    }

    /// Neighbour of an interior tile if it is an interior tile.
    /// # Arguments
    /// * `self` - The carver
    /// * `direction` - The direction
    /// * `x` - The column of an interior tile
    /// * `y` - The row of an interior tile
    /// * `odd` - Whether the row is odd
    /// # Returns
    /// * The step multiplier, the column, the row and the row parity of the neighbour, `None` if
    /// it is not interior
    #[inline]
    fn locate(
        self: @Carver, direction: Direction, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        let carver = *self;
        match direction {
            Direction::East => if x == 1 {
                None
            } else {
                Some((INV_2, x - 1, y, odd))
            },
            Direction::NorthEast => if y == carver.top {
                None
            } else if odd {
                Some((carver.up_odd, x, y + 1, false))
            } else if x == 1 {
                None
            } else {
                Some((carver.up_even, x - 1, y + 1, true))
            },
            Direction::NorthWest => if y == carver.top {
                None
            } else if !odd {
                Some((carver.up_odd, x, y + 1, true))
            } else if x == carver.right {
                None
            } else {
                Some((carver.up_odd_west, x + 1, y + 1, false))
            },
            Direction::West => if x == carver.right {
                None
            } else {
                Some((2, x + 1, y, odd))
            },
            Direction::SouthWest => if y == 1 {
                None
            } else if !odd {
                Some((carver.down_odd, x, y - 1, true))
            } else if x == carver.right {
                None
            } else {
                Some((carver.down_odd_west, x + 1, y - 1, false))
            },
            Direction::SouthEast => if y == 1 {
                None
            } else if odd {
                Some((carver.down_odd, x, y - 1, false))
            } else if x == 1 {
                None
            } else {
                Some((carver.down_even, x - 1, y - 1, true))
            },
        }
    }

    /// Carve test mask relative to the current tile `c`, without `c`: the candidate, its
    /// neighbours and, for order 1, its ball of radius 2 minus the three tiles behind `c`.
    /// # Arguments
    /// * `self` - The carver
    /// * `direction` - The direction of the candidate
    /// * `odd` - Whether the row of `c` is odd
    /// * `step` - The step multiplier of `direction`
    /// * `y` - The row of the candidate, an interior tile
    /// * `nodd` - Whether the row of the candidate is odd
    /// # Returns
    /// * The mask, to multiply by `2^c`
    #[inline]
    fn mask(
        self: @Carver, direction: Direction, odd: bool, step: felt252, y: felt252, nodd: bool,
    ) -> felt252 {
        if !*self.sparse {
            return self.closed_mask(step, nodd);
        }
        let cone = self.step(direction.left(), odd) + step + self.step(direction.right(), odd);
        self.sparse_mask(odd, step, y, nodd, cone)
    }

    /// Order 0 mask: closed neighbourhood of the candidate minus `c`.
    /// # Arguments
    /// * `self` - The carver
    /// * `step` - The step multiplier from `c` to the candidate
    /// * `nodd` - Whether the row of the candidate is odd
    /// # Returns
    /// * The mask, to multiply by `2^c`
    #[inline]
    fn closed_mask(self: @Carver, step: felt252, nodd: bool) -> felt252 {
        let closed = if nodd {
            *self.closed_odd
        } else {
            *self.closed_even
        };
        step * closed - 1
    }

    /// Order 1 mask: ball of radius 2 around the candidate minus `c` and the three tiles behind
    /// it.
    /// # Arguments
    /// * `self` - The carver
    /// * `odd` - Whether the row of `c` is odd
    /// * `step` - The step multiplier from `c` to the candidate
    /// * `y` - The row of the candidate, an interior tile
    /// * `nodd` - Whether the row of the candidate is odd
    /// * `cone` - The sum of the step multipliers of the three forward directions
    /// # Returns
    /// * The mask, to multiply by `2^c`
    #[inline]
    fn sparse_mask(
        self: @Carver, odd: bool, step: felt252, y: felt252, nodd: bool, cone: felt252,
    ) -> felt252 {
        let carver = *self;
        // [Compute] Rows -1..+1 of the ball: 5 tiles, then twice 4 tiles
        let quad = if nodd {
            carver.up_even + carver.down_even
        } else {
            (carver.up_even + carver.down_even) * INV_2
        };
        let mut ball = INV_4 * 31 + 15 * quad;
        // [Compute] Rows +2 and -2 when they lie in the board
        if y != carver.top {
            ball += 7 * carver.up_odd * carver.up_even;
        }
        if y != 1 {
            ball += 7 * carver.down_odd * carver.down_even;
        }
        // [Return] `c` and the tiles behind it: its closed neighbourhood minus the forward cone
        let closed = if odd {
            carver.closed_odd
        } else {
            carver.closed_even
        };
        step * ball - closed + cone
    }

    /// Carve the candidate if the test passes.
    /// # Arguments
    /// * `self` - The carver
    /// * `maze` - The open tiles
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    /// * `direction` - The direction of the candidate
    /// # Returns
    /// * The candidate power, column, row and parity if it was carved
    /// # Effects
    /// * The candidate is added to the maze
    #[inline]
    fn carve(
        self: @Carver,
        ref maze: u256,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        // [Check] Interior candidate
        let (step, nx, ny, nodd) = self.locate(direction, x, y, odd)?;
        // [Check] Carve rule, one mask test
        let mask: u256 = (power * self.mask(direction, odd, step, ny, nodd)).into();
        if maze.low & mask.low != 0 || maze.high & mask.high != 0 {
            return None;
        }
        // [Effect] Open the candidate, disjoint from the maze
        let next = power * step;
        let bit: u256 = next.into();
        maze = u256 { low: maze.low + bit.low, high: maze.high + bit.high };
        Some((next, nx, ny, nodd))
    }
}

/// Turns of a direction.
#[generate_trait]
pub(crate) impl TurnImpl of TurnTrait {
    /// The direction turned by 60 degrees clockwise (seen from above, `x` toward the West).
    #[inline]
    fn left(self: Direction) -> Direction {
        match self {
            Direction::East => Direction::SouthEast,
            Direction::NorthEast => Direction::East,
            Direction::NorthWest => Direction::NorthEast,
            Direction::West => Direction::NorthWest,
            Direction::SouthWest => Direction::West,
            Direction::SouthEast => Direction::SouthWest,
        }
    }

    /// The direction turned by 60 degrees the other way.
    #[inline]
    fn right(self: Direction) -> Direction {
        match self {
            Direction::East => Direction::NorthEast,
            Direction::NorthEast => Direction::NorthWest,
            Direction::NorthWest => Direction::West,
            Direction::West => Direction::SouthWest,
            Direction::SouthWest => Direction::SouthEast,
            Direction::SouthEast => Direction::East,
        }
    }
}

/// A direction known at compile time: the carve code is specialised per direction, so the
/// direction dispatch happens once per carved tile instead of once per candidate.
pub(crate) trait Heading {
    /// The direction.
    fn direction() -> Direction;
    /// Neighbour of an interior tile if it is an interior tile, see `CarverTrait::locate`.
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)>;
    /// Sum of the step multipliers of the three forward directions (order 1 only).
    fn cone(carver: @Carver, odd: bool) -> felt252;
}

pub(crate) impl EastHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::East
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if x == 1 {
            None
        } else {
            Some((INV_2, x - 1, y, odd))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        carver.step(Direction::SouthEast, odd) + INV_2 + carver.step(Direction::NorthEast, odd)
    }
}

pub(crate) impl NorthEastHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::NorthEast
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if y == *carver.top {
            None
        } else if odd {
            Some((*carver.up_odd, x, y + 1, false))
        } else if x == 1 {
            None
        } else {
            Some((*carver.up_even, x - 1, y + 1, true))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        INV_2 + carver.step(Direction::NorthEast, odd) + carver.step(Direction::NorthWest, odd)
    }
}

pub(crate) impl NorthWestHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::NorthWest
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if y == *carver.top {
            None
        } else if !odd {
            Some((*carver.up_odd, x, y + 1, true))
        } else if x == *carver.right {
            None
        } else {
            Some((*carver.up_odd_west, x + 1, y + 1, false))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        carver.step(Direction::NorthEast, odd) + carver.step(Direction::NorthWest, odd) + 2
    }
}

pub(crate) impl WestHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::West
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if x == *carver.right {
            None
        } else {
            Some((2, x + 1, y, odd))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        carver.step(Direction::NorthWest, odd) + 2 + carver.step(Direction::SouthWest, odd)
    }
}

pub(crate) impl SouthWestHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::SouthWest
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if y == 1 {
            None
        } else if !odd {
            Some((*carver.down_odd, x, y - 1, true))
        } else if x == *carver.right {
            None
        } else {
            Some((*carver.down_odd_west, x + 1, y - 1, false))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        2 + carver.step(Direction::SouthWest, odd) + carver.step(Direction::SouthEast, odd)
    }
}

pub(crate) impl SouthEastHeading of Heading {
    #[inline]
    fn direction() -> Direction {
        Direction::SouthEast
    }

    #[inline]
    fn locate(
        carver: @Carver, x: felt252, y: felt252, odd: bool,
    ) -> Option<(felt252, felt252, felt252, bool)> {
        if y == 1 {
            None
        } else if odd {
            Some((*carver.down_odd, x, y - 1, false))
        } else if x == 1 {
            None
        } else {
            Some((*carver.down_even, x - 1, y - 1, true))
        }
    }

    #[inline]
    fn cone(carver: @Carver, odd: bool) -> felt252 {
        carver.step(Direction::SouthWest, odd) + carver.step(Direction::SouthEast, odd) + INV_2
    }
}

#[generate_trait]
pub impl Mazer of MazerTrait {
    /// Generate a maze.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1, the higher the less dense
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    /// # Panics
    /// * If the dimensions are invalid or the order is above 1
    fn generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
        // [Check] Dimensions and order, once
        Asserter::assert_valid_dimension(width, height);
        let carver = BoxTrait::new(CarverTrait::new(width, height, order));
        // [Compute] Random interior root
        let mut rng = RngTrait::new(seed);
        let x = rng.next_below(width - 2) + 1;
        let y = rng.next_below(height - 2) + 1;
        let power = Bits::pow(y * width + x);
        let odd = y % 2 == 1;
        let mut maze: u256 = power.into();
        // [Effect] The root has no parent: try the 6 directions in random order
        let (x, y) = (x.into(), y.into());
        let mut directions = rng.shuffle6();
        let mut count: u8 = 6;
        while count != 0 {
            match DirectionTrait::pop_front(ref directions) {
                Direction::East => MazerInternal::visit::<
                    EastHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
                Direction::NorthEast => MazerInternal::visit::<
                    NorthEastHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
                Direction::NorthWest => MazerInternal::visit::<
                    NorthWestHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
                Direction::West => MazerInternal::visit::<
                    WestHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
                Direction::SouthWest => MazerInternal::visit::<
                    SouthWestHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
                Direction::SouthEast => MazerInternal::visit::<
                    SouthEastHeading,
                >(carver, ref maze, ref rng, power, x, y, odd),
            }
            count -= 1;
        }
        // [Return] Maze
        Bits::to_felt(maze)
    }
}

#[generate_trait]
pub(crate) impl MazerInternal of MazerInternalTrait {
    /// Carve the candidate and, if carved, its subtree.
    /// # Arguments
    /// * `carver` - The carve constants
    /// * `maze` - The open tiles
    /// * `rng` - The generator
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    /// # Returns
    /// * Whether the candidate was carved
    #[inline]
    fn visit<impl H: Heading>(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
    ) -> bool {
        let constants = carver.as_snapshot().unbox();
        // [Check] Interior candidate
        let (step, nx, ny, nodd) = match H::locate(constants, x, y, odd) {
            Some(located) => located,
            None => { return false; },
        };
        // [Check] Carve rule, one mask test
        let mask = if *constants.sparse {
            constants.sparse_mask(odd, step, ny, nodd, H::cone(constants, odd))
        } else {
            constants.closed_mask(step, nodd)
        };
        let mask: u256 = (power * mask).into();
        if maze.low & mask.low != 0 || maze.high & mask.high != 0 {
            return false;
        }
        // [Effect] Open the candidate, disjoint from the maze, and grow from it
        let next = power * step;
        let bit: u256 = next.into();
        maze = u256 { low: maze.low + bit.low, high: maze.high + bit.high };
        Self::iter(carver, ref maze, ref rng, next, nx, ny, nodd, H::direction());
        true
    }

    /// Grow the maze from a carved tile, depth first.
    /// # Arguments
    /// * `carver` - The carve constants
    /// * `maze` - The open tiles
    /// * `rng` - The generator
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    /// * `forward` - The direction of the step that reached `c`
    fn iter(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        forward: Direction,
    ) {
        match forward {
            Direction::East => Self::branch::<
                SouthEastHeading, EastHeading, NorthEastHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
            Direction::NorthEast => Self::branch::<
                EastHeading, NorthEastHeading, NorthWestHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
            Direction::NorthWest => Self::branch::<
                NorthEastHeading, NorthWestHeading, WestHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
            Direction::West => Self::branch::<
                NorthWestHeading, WestHeading, SouthWestHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
            Direction::SouthWest => Self::branch::<
                WestHeading, SouthWestHeading, SouthEastHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
            Direction::SouthEast => Self::branch::<
                SouthWestHeading, SouthEastHeading, EastHeading,
            >(carver, ref maze, ref rng, power, x, y, odd),
        }
    }

    /// Try the three forward candidates `L`, `F`, `R` in one of the 6 orders.
    /// Only the 3 forward neighbours are candidates: the two other neighbours touch the parent.
    /// Once a side candidate is carved, the middle one touches it and only the opposite side
    /// candidate remains; once the middle one is carved, both side ones touch it.
    /// # Arguments
    /// * `carver` - The carve constants
    /// * `maze` - The open tiles
    /// * `rng` - The generator
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    #[inline]
    fn branch<impl L: Heading, impl F: Heading, impl R: Heading>(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
    ) {
        match rng.draw6() {
            0 => {
                // [Effect] L, F, R
                if Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd)
                    || !Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
            1 => {
                // [Effect] L, R, F
                if Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd);
                } else if !Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
            2 => {
                // [Effect] F, L, R
                if !Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd);
                    Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
            3 => {
                // [Effect] F, R, L
                if !Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd);
                    Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
            4 => {
                // [Effect] R, L, F
                if Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd);
                } else if !Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
            _ => {
                // [Effect] R, F, L
                if Self::visit::<R>(carver, ref maze, ref rng, power, x, y, odd)
                    || !Self::visit::<F>(carver, ref maze, ref rng, power, x, y, odd) {
                    Self::visit::<L>(carver, ref maze, ref rng, power, x, y, odd);
                }
            },
        }
    }
}

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::geometry::Geometry;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::helpers::printer::HexPrinter;
    use origami_hexmap::types::direction::Direction;

    // Local imports

    use super::{CarverTrait, Mazer};

    // Constants

    const SEED: felt252 = 'SEED';

    /// Flood fill of the open tiles from the lowest one, built on `Layout::expand`.
    pub fn is_connected(grid: felt252, width: u8, height: u8) -> bool {
        let layout = LayoutTrait::new(width, height);
        let grid: u256 = grid.into();
        if grid == 0 {
            return true;
        }
        let lowest = grid & (~grid + 1);
        let mut reached = lowest;
        loop {
            let next = layout.expand(reached) & grid;
            if next == reached {
                break;
            }
            reached = next;
        }
        reached == grid
    }

    /// Check the invariants of a generated maze.
    fn check(grid: felt252, width: u8, height: u8) {
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let grid_u256: u256 = grid.into();
        assert!(grid_u256 != 0);
        assert!(grid_u256 & ~interior == 0);
        assert!(is_connected(grid, width, height));
    }

    /// Order 0 rule: every open tile touches exactly its tree neighbours, so the open tiles form
    /// a tree: `edges = tiles - 1`, counted from the neighbour masks.
    fn check_tree(grid: felt252, width: u8, height: u8) {
        let layout = LayoutTrait::new(width, height);
        let grid_u256: u256 = grid.into();
        let mut tiles: u32 = 0;
        let mut degrees: u32 = 0;
        let mut index: u8 = 0;
        while index != width * height {
            if Bits::get(grid_u256, index) {
                tiles += 1;
                let mask: u256 = layout.neighbour_mask(index).into();
                degrees += Bits::popcount(mask & grid_u256).into();
            }
            index += 1;
        }
        assert!(degrees == 2 * (tiles - 1));
    }

    /// Order 1 rule: two open tiles at distance 2 always share an open neighbour.
    fn check_sparse(grid: felt252, width: u8, height: u8) {
        let layout = LayoutTrait::new(width, height);
        let grid_u256: u256 = grid.into();
        let mut index: u8 = 0;
        while index != width * height {
            if Bits::get(grid_u256, index) {
                let tile: u256 = Bits::pow(index).into();
                let near = layout.expand(tile);
                let ring = (layout.expand(near & grid_u256) - near) & grid_u256;
                let far = (layout
                    .expand(layout.expand(tile) & LayoutTrait::interior(width, height).into())
                    - near)
                    & grid_u256;
                assert!(far == ring);
            }
            index += 1;
        }
    }

    #[test]
    fn test_mazer_generate_17x14_order_0() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 1 1 1 0 1 1 1 0 0 1 1 0 1 1 0
        // 0 1 1 0 0 1 0 0 0 1 1 0 0 1 1 0 0
        //  0 0 0 1 0 1 1 0 1 0 1 1 1 0 1 1 0
        // 0 0 1 1 0 1 0 1 1 0 0 0 0 0 1 0 0
        //  0 1 0 1 1 0 0 0 0 1 1 0 1 1 0 1 0
        // 0 1 0 0 0 0 0 1 1 1 0 1 0 0 1 1 0
        //  0 1 0 1 1 1 1 0 0 1 0 1 1 0 0 0 0
        // 0 0 1 1 0 0 0 0 0 0 0 1 0 0 1 1 0
        //  0 1 0 0 0 1 0 1 1 0 0 1 1 1 0 1 0
        // 0 1 0 0 1 1 0 0 0 1 0 0 0 0 0 1 0
        //  0 1 0 1 0 1 1 1 0 1 1 0 0 0 0 1 0
        // 0 0 1 1 0 1 0 0 1 0 0 1 1 1 1 1 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let maze = Mazer::generate(17, 14, 0, SEED);
        assert!(maze == 0x773664660b5d8d608b0da41d32f2c0c04c8b3a4c412bb08d27c0000);
        check(maze, 17, 14);
        check_tree(maze, 17, 14);
    }

    #[test]
    fn test_mazer_generate_17x14_order_1() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 0 0 0 0 0 0 0 0 0 0 0
        //  0 1 1 0 0 1 1 0 0 0 0 0 0 0 0 0 0
        // 0 1 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 1 1 0 0 0 0 0 0 1 0
        // 0 0 0 0 0 0 0 0 0 1 0 0 1 1 1 1 0
        //  0 0 0 0 0 0 0 0 0 1 1 1 0 0 0 1 0
        // 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
        //  0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 1 1 1 0 0 0 0 0 1 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 1 1 0 0 0 0 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let maze = Mazer::generate(17, 14, 1, SEED);
        assert!(maze == 0x1c003300104000302004f0038801003f00704000308007c0000);
        check(maze, 17, 14);
        check_tree(maze, 17, 14);
        check_sparse(maze, 17, 14);
    }

    #[test]
    fn test_mazer_generate_7x7() {
        //  0 0 0 0 0 0 0
        // 0 1 1 0 1 1 0
        //  0 0 1 1 0 1 0
        // 0 1 0 0 0 1 0
        //  0 1 0 1 1 0 0
        // 0 0 1 1 0 1 0
        //  0 0 0 0 0 0 0
        let maze = Mazer::generate(7, 7, 0, SEED);
        assert!(maze == 0x1b1a44b0d00);
        check_tree(maze, 7, 7);
        //  0 0 0 0 0 0 0
        // 0 1 1 0 0 0 0
        //  0 0 1 1 0 0 0
        // 0 0 0 0 1 1 0
        //  0 0 0 0 0 1 0
        // 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0
        let maze = Mazer::generate(7, 7, 1, SEED);
        assert!(maze == 0x18180c08000);
        check_sparse(maze, 7, 7);
    }

    #[test]
    fn test_mazer_generate_3x3() {
        //  0 0 0
        // 0 1 0
        //  0 0 0
        assert!(Mazer::generate(3, 3, 0, SEED) == 0x10);
        assert!(Mazer::generate(3, 3, 1, SEED) == 0x10);
    }

    #[test]
    fn test_mazer_generate_19x13() {
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 1 1 1 1 0 0 0 0 1 0 0 1 0 0 0 0 0 0
        //  0 0 0 0 1 0 0 0 1 0 0 0 1 1 1 0 0 1 0
        // 0 0 0 0 0 1 0 0 1 0 0 0 1 0 0 1 1 1 0
        //  0 0 0 0 0 1 1 1 0 0 0 1 0 0 0 0 0 0 0
        // 0 0 0 0 0 1 0 0 1 0 0 1 0 0 0 0 0 0 0
        //  0 0 0 1 1 0 0 0 1 1 1 0 0 0 0 0 0 1 0
        // 0 0 0 1 0 0 0 0 1 0 0 1 0 0 1 1 1 1 0
        //  0 0 1 0 0 0 0 0 0 0 0 1 1 1 0 0 0 1 0
        // 0 0 0 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
        //  0 0 1 0 0 1 1 1 0 0 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 0 0 0 0 1 1 1 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let maze = Mazer::generate(19, 13, 1, SEED);
        assert!(maze == 0x78480111c81227038800490031c08424f100e2101004e400438000000);
        check(maze, 19, 13);
        check_sparse(maze, 19, 13);
    }

    #[test]
    fn test_mazer_generate_dimensions() {
        let mut seed: felt252 = 0;
        while seed != 8 {
            let mut order = 0;
            while order != 2 {
                check(Mazer::generate(3, 3, order, seed), 3, 3);
                check(Mazer::generate(7, 7, order, seed), 7, 7);
                check(Mazer::generate(19, 13, order, seed), 19, 13);
                check(Mazer::generate(83, 3, order, seed), 83, 3);
                check(Mazer::generate(3, 83, order, seed), 3, 83);
                let maze = Mazer::generate(17, 14, order, seed);
                check(maze, 17, 14);
                check_tree(maze, 17, 14);
                if order == 1 {
                    check_sparse(maze, 17, 14);
                }
                order += 1;
            }
            seed += 1;
        }
    }

    /// Compare every carve mask with its definition, from `Geometry::distance`.
    fn check_masks(width: u8, height: u8, order: u8) {
        let carver = CarverTrait::new(width, height, order);
        let interior: u256 = LayoutTrait::interior(width, height).into();
        // Wrapped ring tiles may reach bit `W * H`, never further: the masks stay exact
        let board: u256 = (Bits::pow(width * height + 1) - 1).into();
        let radius: u8 = order + 1;
        let mut position: u8 = 0;
        while position != width * height {
            let (x, y) = LayoutTrait::coords(width, position);
            let odd = y % 2 == 1;
            // [Check] Rows next to the border and one middle row, to bound the test steps
            let sampled = y <= 2 || y >= height - 3 || y == height / 2;
            if sampled && Bits::get(interior, position) {
                let mut directions = array![
                    Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
                    Direction::SouthWest, Direction::SouthEast,
                ]
                    .span();
                while let Option::Some(direction) = directions.pop_front() {
                    let direction = *direction;
                    let neighbor = LayoutTrait::neighbor(width, height, position, direction)
                        .unwrap();
                    let (nx, ny) = LayoutTrait::coords(width, neighbor);
                    let interior_neighbor = nx != 0 && ny != 0 && nx != width
                        - 1 && ny != height
                        - 1;
                    match carver.locate(direction, x.into(), y.into(), odd) {
                        Some((
                            step, lx, ly, nodd,
                        )) => {
                            assert!(interior_neighbor);
                            assert!(lx == nx.into() && ly == ny.into() && nodd == (ny % 2 == 1));
                            let candidate = neighbor;
                            assert!(Bits::pow(position) * step == Bits::pow(candidate));
                            let mask: u256 = (Bits::pow(position)
                                * carver.mask(direction, odd, step, ly, nodd))
                                .into();
                            // [Check] Exact: no bit beyond the board
                            assert!(mask & ~board == 0);
                            // [Check] Interior tiles of the mask
                            let mut expected: u256 = 0;
                            let low = if candidate > 3 * width {
                                candidate - 3 * width
                            } else {
                                0
                            };
                            let reach: u16 = candidate.into() + 3 * width.into();
                            let high = if reach < (width * height).into() {
                                candidate + 3 * width
                            } else {
                                width * height
                            };
                            let mut tile: u8 = low;
                            while tile != high {
                                let near = Geometry::distance(width, candidate, tile) <= radius;
                                let behind = Geometry::distance(width, position, tile) == 1
                                    && Geometry::distance(width, candidate, tile) == 2;
                                if near && tile != position && !behind {
                                    expected = expected | Bits::pow(tile).into();
                                }
                                tile += 1;
                            }
                            assert!(mask & interior == expected & interior);
                        },
                        None => assert!(!interior_neighbor),
                    }
                }
            }
            position += 1;
        }
    }

    #[test]
    fn test_mazer_masks_order_0_7x7() {
        check_masks(7, 7, 0);
    }

    #[test]
    fn test_mazer_masks_order_0_17x14() {
        check_masks(17, 14, 0);
    }

    #[test]
    fn test_mazer_masks_order_1_7x7() {
        check_masks(7, 7, 1);
    }

    #[test]
    fn test_mazer_masks_order_1_17x14() {
        check_masks(17, 14, 1);
    }

    #[test]
    fn test_mazer_masks_order_1_19x13() {
        check_masks(19, 13, 1);
    }

    #[test]
    fn test_mazer_generate_deterministic() {
        assert!(Mazer::generate(17, 14, 0, SEED) == Mazer::generate(17, 14, 0, SEED));
        assert!(Mazer::generate(17, 14, 0, SEED) != Mazer::generate(17, 14, 0, SEED + 1));
    }

    #[test]
    #[should_panic(expected: 'Mazer: order > 1 not supported')]
    fn test_mazer_generate_revert_order() {
        Mazer::generate(17, 14, 2, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_mazer_generate_revert_dimension() {
        Mazer::generate(18, 14, 0, SEED);
    }
}
