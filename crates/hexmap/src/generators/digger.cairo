//! Digger: open a corridor or a maze from an edge tile (lot L5).
//!
//! The entrance, an edge tile that is not a corner, is opened, then the digger steps to one of its
//! interior neighbours (an open one if any, otherwise drawn at random when there are two or three)
//! and grows a maze from there with the carve rule of `Mazer` (same orders, same pictures), tested
//! against the tiles it opened itself. As soon as a dug tile touches an open tile of the original
//! grid, the dug tiles are connected to it:
//! * `corridor` stops everything: the result is a single winding corridor, with the dead ends of
//!   the backtracking, from the entrance to the open area;
//! * `maze` merges the original grid into its own tiles and goes on growing, so the rest of the
//!   maze also respects the carve rule around the original open tiles.
//! If the grid has no open tile in reach, both dig a full maze. The result is the original grid
//! with the dug tiles opened.

// Internal imports

use origami_hexmap::generators::mazer::{
    Carver, CarverTrait, EastHeading, Heading, NorthEastHeading, NorthWestHeading, SouthEastHeading,
    SouthWestHeading, WestHeading,
};
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::types::direction::Direction;

// Constants

/// Number of orders of the three forward directions.
const ORDER_COUNT: NonZero<u128> = 6;

/// Constants of a dig: carve constants, original grid and mode.
#[derive(Copy, Drop)]
pub struct Dig {
    pub carver: Carver,
    /// The original grid.
    pub grid: u256,
    /// Stop at the first open tile (corridor) or merge the grid and go on (maze).
    pub corridor: bool,
}

#[generate_trait]
pub impl Digger of DiggerTrait {
    /// Dig a maze from an edge tile.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `seed` - The seed
    /// # Returns
    /// * The grid with the maze
    fn maze(width: u8, height: u8, order: u8, start: u8, grid: felt252, seed: felt252) -> felt252 {
        Self::dig(width, height, order, start, grid, seed, false)
    }

    /// Dig a corridor from an edge tile until it reaches an open tile.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the corridor, 0 or 1
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `seed` - The seed
    /// # Returns
    /// * The grid with the corridor
    fn corridor(
        width: u8, height: u8, order: u8, start: u8, grid: felt252, seed: felt252,
    ) -> felt252 {
        Self::dig(width, height, order, start, grid, seed, true)
    }

    /// Dig from an edge tile.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order, 0 or 1
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `seed` - The seed
    /// * `corridor` - Stop at the first open tile, otherwise merge and go on
    /// # Returns
    /// * The grid with the dug tiles
    /// # Panics
    /// * If the dimensions are invalid, the order is above 1, or the start is not an edge tile
    /// or is a corner
    fn dig(
        width: u8, height: u8, order: u8, start: u8, grid: felt252, seed: felt252, corridor: bool,
    ) -> felt252 {
        // [Check] Dimensions, order and entrance
        Asserter::assert_valid_dimension(width, height);
        let carver = CarverTrait::new(width, height, order);
        Asserter::assert_inside(width, height, start);
        Asserter::assert_not_corner(width, height, start);
        Asserter::assert_on_edge(width, height, start);
        // [Compute] Step to an interior neighbour of the entrance
        let grid: u256 = grid.into();
        let mut rng = RngTrait::new(seed);
        let direction = Self::inward(width, height, start, grid, ref rng);
        let first = LayoutTrait::neighbor(width, height, start, direction).unwrap();
        let entrance = Bits::pow(start);
        let power = Bits::pow(first);
        let bit: u256 = power.into();
        let mut maze: u256 = (entrance + power).into();
        // [Check] Already open: the entrance is connected
        if grid & bit != 0 {
            return Bits::to_felt(maze | grid);
        }
        // [Effect] Contact of the first tile with the grid: stop, or merge and go on
        let layout = LayoutTrait::new(width, height);
        let around: u256 = (layout.neighbour_mask(first) - entrance).into();
        let mut stop = grid & around != 0;
        if stop {
            if corridor {
                return Bits::to_felt(maze | grid);
            }
            maze = maze | grid;
        }
        // [Effect] Grow from the first tile
        let (x, y) = LayoutTrait::coords(width, first);
        let dig = BoxTrait::new(Dig { carver, grid, corridor });
        Self::iter(
            dig, ref maze, ref rng, ref stop, power, x.into(), y.into(), y % 2 == 1, direction,
        );
        // [Return] Original grid with the dug tiles
        Bits::to_felt(maze | grid)
    }

    /// Direction from the entrance to one of its interior neighbours: the first open one if any,
    /// otherwise drawn uniformly.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `rng` - The generator
    /// # Returns
    /// * The direction
    fn inward(width: u8, height: u8, start: u8, grid: u256, ref rng: Rng) -> Direction {
        let (x, y) = LayoutTrait::coords(width, start);
        let odd = y % 2 == 1;
        // [Compute] Interior neighbours, the first one always exists
        let mut directions: Array<Direction> = array![];
        if x == 0 {
            directions.append(Direction::West);
            if odd && y + 2 < height {
                directions.append(Direction::NorthWest);
            }
            if odd && y > 1 {
                directions.append(Direction::SouthWest);
            }
        } else if x == width - 1 {
            directions.append(Direction::East);
            if !odd && y + 2 < height {
                directions.append(Direction::NorthEast);
            }
            if !odd && y > 1 {
                directions.append(Direction::SouthEast);
            }
        } else if y == 0 {
            directions.append(Direction::NorthWest);
            if x > 1 {
                directions.append(Direction::NorthEast);
            }
        } else if odd {
            directions.append(Direction::SouthEast);
            if x + 2 < width {
                directions.append(Direction::SouthWest);
            }
        } else {
            directions.append(Direction::SouthWest);
            if x > 1 {
                directions.append(Direction::SouthEast);
            }
        }
        // [Return] An open one, otherwise uniform among them
        let mut candidates = directions.span();
        while let Option::Some(direction) = candidates.pop_front() {
            let next = LayoutTrait::neighbor(width, height, start, *direction).unwrap();
            if Bits::get(grid, next) {
                return *direction;
            }
        }
        let count: u8 = directions.len().try_into().unwrap();
        let index = if count == 1 {
            0
        } else {
            rng.next_below(count)
        };
        *directions.at(index.into())
    }

    /// Carve the candidate and, if carved, its subtree; stop or merge on contact with an open tile.
    /// # Arguments
    /// * `dig` - The dig constants
    /// * `maze` - The dug tiles
    /// * `rng` - The generator
    /// * `stop` - Corridor: an open tile was reached; maze: the grid was merged
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    /// # Returns
    /// * Whether the candidate was opened
    #[inline]
    fn visit<impl H: Heading>(
        dig: Box<Dig>,
        ref maze: u256,
        ref rng: Rng,
        ref stop: bool,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
    ) -> bool {
        let constants = dig.as_snapshot().unbox();
        if stop && *constants.corridor {
            return false;
        }
        let carver = constants.carver;
        // [Check] Interior candidate
        let (step, nx, ny, nodd) = match H::locate(carver, x, y, odd) {
            Some(located) => located,
            None => { return false; },
        };
        // [Check] Carve rule against the dug tiles, one mask test
        let mask = if *carver.sparse {
            carver.sparse_mask(odd, step, ny, nodd, H::cone(carver, odd))
        } else {
            carver.closed_mask(step, nodd)
        };
        let mask: u256 = (power * mask).into();
        if maze.low & mask.low != 0 || maze.high & mask.high != 0 {
            return false;
        }
        let next = power * step;
        let bit: u256 = next.into();
        // [Effect] Contact with an open tile of the original grid: open the candidate, then stop
        // or merge the grid and go on
        if !stop {
            let grid = *constants.grid;
            let around = if *carver.sparse {
                (power * carver.closed_mask(step, nodd)).into()
            } else {
                mask
            };
            if grid.low & around.low != 0 || grid.high & around.high != 0 {
                stop = true;
                maze = maze | bit;
                if *constants.corridor {
                    return true;
                }
                maze = maze | grid;
                Self::iter(dig, ref maze, ref rng, ref stop, next, nx, ny, nodd, H::direction());
                return true;
            }
        }
        // [Effect] Open the candidate and grow from it
        maze = u256 { low: maze.low + bit.low, high: maze.high + bit.high };
        Self::iter(dig, ref maze, ref rng, ref stop, next, nx, ny, nodd, H::direction());
        true
    }

    /// Grow from a dug tile, depth first, see `MazerTrait::iter`.
    /// # Arguments
    /// * `dig` - The dig constants
    /// * `maze` - The dug tiles
    /// * `rng` - The generator
    /// * `stop` - Corridor: an open tile was reached; maze: the grid was merged
    /// * `power` - `2^c`
    /// * `x` - The column of `c`
    /// * `y` - The row of `c`
    /// * `odd` - Whether the row of `c` is odd
    /// * `forward` - The direction of the step that reached `c`
    fn iter(
        dig: Box<Dig>,
        ref maze: u256,
        ref rng: Rng,
        ref stop: bool,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        forward: Direction,
    ) {
        match forward {
            Direction::East => Self::branch::<
                SouthEastHeading, EastHeading, NorthEastHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
            Direction::NorthEast => Self::branch::<
                EastHeading, NorthEastHeading, NorthWestHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
            Direction::NorthWest => Self::branch::<
                NorthEastHeading, NorthWestHeading, WestHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
            Direction::West => Self::branch::<
                NorthWestHeading, WestHeading, SouthWestHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
            Direction::SouthWest => Self::branch::<
                WestHeading, SouthWestHeading, SouthEastHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
            Direction::SouthEast => Self::branch::<
                SouthWestHeading, SouthEastHeading, EastHeading,
            >(dig, ref maze, ref rng, ref stop, power, x, y, odd),
        }
    }

    /// Try the three forward candidates in one of the 6 orders, see `MazerTrait::branch`.
    #[inline]
    fn branch<impl L: Heading, impl F: Heading, impl R: Heading>(
        dig: Box<Dig>,
        ref maze: u256,
        ref rng: Rng,
        ref stop: bool,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
    ) {
        match rng.draw(ORDER_COUNT) {
            0 => {
                // [Effect] L, F, R
                if Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd)
                    || !Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
            1 => {
                // [Effect] L, R, F
                if Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                } else if !Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
            2 => {
                // [Effect] F, L, R
                if !Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                    Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
            3 => {
                // [Effect] F, R, L
                if !Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                    Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
            4 => {
                // [Effect] R, L, F
                if Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                } else if !Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
            _ => {
                // [Effect] R, F, L
                if Self::visit::<R>(dig, ref maze, ref rng, ref stop, power, x, y, odd)
                    || !Self::visit::<F>(dig, ref maze, ref rng, ref stop, power, x, y, odd) {
                    Self::visit::<L>(dig, ref maze, ref rng, ref stop, power, x, y, odd);
                }
            },
        }
    }
}

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::tests::fixtures::CAVE_17X14;

    // Local imports

    use super::Digger;

    // Constants

    const SEED: felt252 = 'SEED';
    /// Tile (3, 0) of 17x14, bottom edge.
    const START: u8 = 3;
    /// Tile (16, 8) of 17x14, West edge (x = 0 is printed on the right).
    const START_WEST: u8 = 152;
    /// A 3x2 room in the middle of 17x14: tiles x = 7..9 of rows 6 and 7.
    const ROOM: felt252 = 0x1c000e000000000000000000000000000;

    /// Flood fill of the open interior tiles from the lowest one, built on `Layout::expand`.
    fn is_connected(grid: felt252, width: u8, height: u8) -> bool {
        let layout = LayoutTrait::new(width, height);
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let grid: u256 = grid.into() & interior;
        if grid == 0 {
            return true;
        }
        let mut reached = grid & (~grid + 1);
        loop {
            let next = layout.expand(reached) & grid;
            if next == reached {
                break;
            }
            reached = next;
        }
        reached == grid
    }

    /// Check a dug grid: it keeps the original grid, opens the entrance, opens a connected set
    /// of interior tiles plus the entrance, and the entrance touches it.
    fn check(result: felt252, grid: felt252, width: u8, height: u8, start: u8) {
        let board: u256 = LayoutTrait::board(width, height).into();
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let result_u256: u256 = result.into();
        let grid_u256: u256 = grid.into();
        let entrance: u256 = Bits::pow(start).into();
        assert!(result_u256 & grid_u256 == grid_u256);
        assert!(result_u256 & ~board == 0);
        // [Check] Only the entrance is dug outside the interior
        assert!((result_u256 & ~grid_u256) & ~interior == entrance);
        assert!(is_connected(result, width, height));
        // [Check] The entrance touches an open interior tile
        let (x, y) = LayoutTrait::coords(width, start);
        let mut touches = false;
        let mut directions = array![
            super::Direction::East, super::Direction::NorthEast, super::Direction::NorthWest,
            super::Direction::West, super::Direction::SouthWest, super::Direction::SouthEast,
        ]
            .span();
        while let Option::Some(direction) = directions.pop_front() {
            if let Option::Some(next) = LayoutTrait::neighbor(width, height, start, *direction) {
                if Bits::get(interior & result_u256, next) {
                    touches = true;
                }
            }
        }
        assert!(touches, "entrance ({}, {}) is closed off", x, y);
    }

    #[test]
    fn test_digger_corridor() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 1 1 1 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 1 1 1 1 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0
        let result = Digger::corridor(17, 14, 0, START, ROOM, SEED);
        assert!(result == 0x1c000f000060001800020001000080008);
        check(result, ROOM, 17, 14, START);
    }

    #[test]
    fn test_digger_corridor_order_1() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  1 0 0 1 1 1 1 0 0 0 0 0 0 0 0 0 0
        // 0 1 1 1 0 0 0 1 1 1 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 1 1 1 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let result = Digger::corridor(17, 14, 1, START_WEST, ROOM, SEED);
        assert!(result == 0x13c0071c000e000000000000000000000000000);
        check(result, ROOM, 17, 14, START_WEST);
    }

    #[test]
    fn test_digger_corridor_open_neighbour() {
        // The entrance steps into the cave at once: only the entrance is dug
        let result = Digger::corridor(17, 14, 0, START_WEST, CAVE_17X14, SEED);
        assert!(result == CAVE_17X14 + Bits::pow(START_WEST));
        check(result, CAVE_17X14, 17, 14, START_WEST);
    }

    #[test]
    fn test_digger_maze_order_0() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 1 0 1 1 1 1 1 1 1 1 0 0 1 1 0 0
        // 0 0 1 1 0 0 0 0 0 0 0 1 1 0 0 1 0
        //  0 1 0 1 1 0 0 1 1 1 0 0 1 1 0 1 0
        // 0 1 0 0 0 0 1 1 0 0 1 0 1 0 1 1 0
        //  0 1 1 0 0 1 0 0 0 0 1 0 1 0 0 1 0
        // 0 1 0 1 0 1 0 1 1 1 0 1 0 0 1 1 0
        //  0 1 0 1 1 0 0 1 1 1 1 0 0 1 0 1 0
        // 0 1 0 1 0 0 1 0 0 0 0 1 1 0 0 1 0
        //  0 0 1 0 1 0 1 1 0 1 0 0 1 1 0 1 0
        // 0 1 1 0 0 1 1 0 0 1 0 1 1 0 1 0 0
        //  0 0 1 1 1 0 1 0 1 0 1 0 1 0 1 1 0
        // 0 1 1 0 0 1 0 1 1 0 1 0 1 0 1 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0
        let result = Digger::maze(17, 14, 0, START, ROOM, SEED);
        assert!(result == 0xbfcc30192ce690cacc85255d32cf294864569a665a1d55996a80008);
        check(result, ROOM, 17, 14, START);
    }

    #[test]
    fn test_digger_maze_order_1() {
        // The corridor reaches the room in a straight line, which leaves no branch to grow
        let result = Digger::maze(17, 14, 1, START_WEST, ROOM, SEED);
        assert!(result == 0x13c0071c000e000000000000000000000000000);
        check(result, ROOM, 17, 14, START_WEST);
    }

    #[test]
    fn test_digger_every_edge() {
        // Every non-corner edge tile of 7x7 and 3x3, both modes, both orders, empty grid
        let mut order: u8 = 0;
        while order != 2 {
            let mut start: u8 = 0;
            while start != 49 {
                let (x, y) = LayoutTrait::coords(7, start);
                let edge = x == 0 || y == 0 || x == 6 || y == 6;
                let corner = (x == 0 || x == 6) && (y == 0 || y == 6);
                if edge && !corner {
                    // Nothing to reach: both modes dig the same full maze
                    let corridor = Digger::corridor(7, 7, order, start, 0, SEED);
                    check(corridor, 0, 7, 7, start);
                    assert!(corridor == Digger::maze(7, 7, order, start, 0, SEED));
                }
                start += 1;
            }
            let mut starts = array![1_u8, 3, 5, 7].span();
            while let Option::Some(start) = starts.pop_front() {
                let corridor = Digger::corridor(3, 3, order, *start, 0, SEED);
                check(corridor, 0, 3, 3, *start);
                assert!(corridor == Bits::pow(*start) + Bits::pow(4));
            }
            order += 1;
        }
    }

    #[test]
    #[should_panic(expected: 'Asserter: position is a corner')]
    fn test_digger_revert_corner() {
        Digger::corridor(17, 14, 0, 0, CAVE_17X14, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not an edge')]
    fn test_digger_revert_not_edge() {
        Digger::maze(17, 14, 0, 18, CAVE_17X14, SEED);
    }

    #[test]
    #[should_panic(expected: 'Mazer: order > 1 not supported')]
    fn test_digger_revert_order() {
        Digger::maze(17, 14, 2, START, CAVE_17X14, SEED);
    }
}
