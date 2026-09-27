//! Weighted bit-parallel Dial search with cost classes (lot L3).
//!
//! Entering a tile costs 1, 2, 3 or 4. The costs are given as class bitmaps: `costs[k]` holds
//! the tiles of cost `k + 2`; a tile in several classes takes the highest one.
//!
//! Time-expanded layers, no heap: bucket `t` holds the tiles whose cheapest arrival time is `t`.
//! Because the cost is paid on entering a tile, the first neighbour of a tile to settle gives its
//! final arrival time: a tile is scheduled once, in the bucket `t + cost`, and leaves the
//! unvisited set at that moment. Settling bucket `t` is one dilation (`Layout::expand`), one AND
//! with the unvisited set and one AND per cost class. The buckets form a ring of 4 locals.
//!
//! Edge endpoints: the layer loop only expands interior tiles (border invariant). An edge start
//! is seeded with its open neighbours, an edge target is scheduled like any tile and never
//! expanded, and paths never cross another edge tile.

// Core imports

use core::integer::Bitwise;

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::types::direction::Direction;

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Largest number of cost classes.
const MAX_CLASSES: u32 = 3;

/// Errors module.
pub mod errors {
    pub const DIAL_TOO_MANY_COSTS: felt252 = 'Dial: too many costs';
    pub const DIAL_POSITION_NOT_WALKABLE: felt252 = 'Dial: position not walkable';
}

/// AND, XOR and OR of two limbs in a single application of the bitwise builtin, see
/// `generators::caver`.
extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

/// Walkable tiles of each cost class, disjoint (the highest class wins).
#[derive(Copy, Drop)]
struct Classes {
    /// Tiles of cost 2.
    two: u256,
    /// Tiles of cost 3.
    three: u256,
    /// Tiles of cost 4.
    four: u256,
    /// Tiles of cost 2 or 4: bit 0 of `cost - 1`.
    low: u256,
    /// Tiles of cost 3 or 4: bit 1 of `cost - 1`.
    high: u256,
}

/// The 4 pending buckets, `first` is the next time step.
#[derive(Copy, Drop)]
struct Buckets {
    first: u256,
    second: u256,
    third: u256,
    fourth: u256,
}

#[generate_trait]
pub impl Dial of DialTrait {
    /// Search the cheapest path between two tiles, entry costs in `{1, 2, 3, 4}`.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// * `costs` - `costs[k]` is the bitmap of the tiles of cost `k + 2`, at most 3 items,
    /// the other walkable tiles cost 1; a tile in several bitmaps takes the highest cost
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    fn search(
        grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
    ) -> Span<u8> {
        // [Check] Inputs
        Asserter::assert_valid_dimension(width, height);
        Asserter::assert_inside(width, height, from);
        Asserter::assert_inside(width, height, to);
        assert(costs.len() <= MAX_CLASSES, errors::DIAL_TOO_MANY_COSTS);
        let open: u256 = grid.into();
        assert(Bits::get(open, from), errors::DIAL_POSITION_NOT_WALKABLE);
        assert(Bits::get(open, to), errors::DIAL_POSITION_NOT_WALKABLE);
        if from == to {
            return array![].span();
        }
        // [Compute] Constants, classes and unvisited set
        let layout = LayoutTrait::new(width, height);
        let interior = LayoutTrait::interior(width, height);
        let classes = DialInternal::classes(open, costs);
        let (from_y, from_x) = DivRem::div_rem(from, width.try_into().unwrap());
        let (to_y, to_x) = DivRem::div_rem(to, width.try_into().unwrap());
        let from_edge = Asserter::is_edge(width, height, from_x, from_y);
        let to_edge = Asserter::is_edge(width, height, to_x, to_y);
        let from_bit = Bits::pow(from);
        let to_bit = Bits::pow(to);
        let mut unvisited = Bits::to_felt(DialInternal::and(open, interior.into()));
        if !from_edge {
            unvisited -= from_bit;
        }
        if to_edge {
            unvisited += to_bit;
        }
        let unvisited: u256 = unvisited.into();
        // [Compute] First arrivals: dilation of an interior start, open neighbours of an edge one
        let arrivals = if from_edge {
            let (seeds, adjacent) = DialInternal::seeds(width, height, from, to, unvisited);
            if adjacent {
                return array![to].span();
            }
            seeds
        } else {
            DialInternal::and(layout.expand(from_bit.into()), unvisited)
        };
        // [Compute] Forward search
        let target: u256 = to_bit.into();
        let (layers, time) =
            match DialInternal::forward(
                @layout, classes, from_bit.into(), unvisited, arrivals, target,
            ) {
            Option::Some(result) => result,
            Option::None => { return array![].span(); },
        };
        // [Return] Backtrack from the target
        DialInternal::backtrack(
            @layout, classes, layers.span(), width, height, to, to_bit, to_y, to_edge, time,
        )
    }

    /// Every tile reachable from a position with a total entry cost of at most `budget`, the
    /// position included (`hexx`'s `field_of_movement`).
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `budget` - The movement budget
    /// * `costs` - The cost classes, as in `search`
    /// # Returns
    /// * The bitmap of the reachable tiles
    fn field_of_movement(
        grid: felt252, width: u8, height: u8, from: u8, budget: u8, costs: Span<felt252>,
    ) -> felt252 {
        // [Check] Inputs
        Asserter::assert_valid_dimension(width, height);
        Asserter::assert_inside(width, height, from);
        assert(costs.len() <= MAX_CLASSES, errors::DIAL_TOO_MANY_COSTS);
        let open: u256 = grid.into();
        assert(Bits::get(open, from), errors::DIAL_POSITION_NOT_WALKABLE);
        let from_bit = Bits::pow(from);
        if budget == 0 {
            return from_bit;
        }
        // [Compute] Constants, classes and unvisited set; open edge tiles are only endpoints
        let layout = LayoutTrait::new(width, height);
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let classes = DialInternal::classes(open, costs);
        let (from_y, from_x) = DivRem::div_rem(from, width.try_into().unwrap());
        let from_edge = Asserter::is_edge(width, height, from_x, from_y);
        let inside = DialInternal::and(open, interior);
        let edges = inside != open;
        let unvisited: u256 = if edges {
            (grid - from_bit).into()
        } else if from_edge {
            inside
        } else {
            (Bits::to_felt(inside) - from_bit).into()
        };
        let arrivals = if from_edge {
            let (seeds, _) = DialInternal::seeds(width, height, from, from, unvisited);
            seeds
        } else {
            DialInternal::and(layout.expand(from_bit.into()), unvisited)
        };
        // [Return] Settled tiles up to the budget
        DialInternal::field(
            @layout, classes, interior, edges, from_bit, budget, unvisited, arrivals,
        )
    }
}

#[generate_trait]
impl DialInternal of DialInternalTrait {
    /// Set intersection, one builtin application per limb.
    #[inline(always)]
    fn and(lhs: u256, rhs: u256) -> u256 {
        let (low, _, _) = bitwise(lhs.low, rhs.low);
        let (high, _, _) = bitwise(lhs.high, rhs.high);
        u256 { low, high }
    }

    /// Set difference when `rhs` is a subset of `lhs`.
    #[inline(always)]
    fn sub(lhs: u256, rhs: u256) -> u256 {
        u256 { low: lhs.low - rhs.low, high: lhs.high - rhs.high }
    }

    /// Set union when `lhs` and `rhs` are disjoint.
    #[inline(always)]
    fn add(lhs: u256, rhs: u256) -> u256 {
        u256 { low: lhs.low + rhs.low, high: lhs.high + rhs.high }
    }

    /// Whether a set is empty.
    #[inline(always)]
    fn is_empty(value: u256) -> bool {
        value.low == 0 && value.high == 0
    }

    /// Partition the walkable tiles by cost class, the highest class wins.
    /// # Arguments
    /// * `open` - The walkable tiles
    /// * `costs` - The class bitmaps, at most 3
    /// # Returns
    /// * The disjoint classes
    #[inline]
    fn classes(open: u256, costs: Span<felt252>) -> Classes {
        let zero: u256 = 0;
        let count = costs.len();
        if count == 0 {
            return Classes { two: zero, three: zero, four: zero, low: zero, high: zero };
        }
        let mut rest = open;
        let four = if count == 3 {
            let four = Self::and(rest, (*costs[2]).into());
            rest = Self::sub(rest, four);
            four
        } else {
            zero
        };
        let three = if count >= 2 {
            let three = Self::and(rest, (*costs[1]).into());
            rest = Self::sub(rest, three);
            three
        } else {
            zero
        };
        let two = Self::and(rest, (*costs[0]).into());
        Classes { two, three, four, low: Self::add(two, four), high: Self::add(three, four) }
    }

    /// Open neighbours of an edge start (scalar, at most 3 in the board).
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The start, an edge tile
    /// * `to` - The target
    /// * `unvisited` - The tiles a path may enter
    /// # Returns
    /// * The neighbours in `unvisited` and whether `to` is a neighbour
    fn seeds(width: u8, height: u8, from: u8, to: u8, unvisited: u256) -> (u256, bool) {
        let mut seeds: felt252 = 0;
        let mut adjacent = false;
        for direction in array![
            Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
            Direction::SouthWest, Direction::SouthEast,
        ]
            .span() {
            if let Option::Some(next) = LayoutTrait::neighbor(width, height, from, *direction) {
                if next == to {
                    adjacent = true;
                } else if Bits::get(unvisited, next) {
                    seeds += Bits::pow(next);
                }
            }
        }
        (seeds.into(), adjacent)
    }

    /// Schedule new arrivals in the buckets of their arrival time.
    /// # Arguments
    /// * `classes` - The cost classes
    /// * `buckets` - The pending buckets, `first` is the next time step
    /// * `arrivals` - The tiles entered from the frontier just settled
    #[inline(always)]
    fn schedule(classes: @Classes, ref buckets: Buckets, arrivals: u256) {
        let classes = *classes;
        let mut ones = arrivals;
        if !Self::is_empty(classes.two) {
            let two = Self::and(arrivals, classes.two);
            ones = Self::sub(ones, two);
            buckets.second = Self::add(buckets.second, two);
        }
        if !Self::is_empty(classes.three) {
            let three = Self::and(arrivals, classes.three);
            ones = Self::sub(ones, three);
            buckets.third = Self::add(buckets.third, three);
        }
        if !Self::is_empty(classes.four) {
            let four = Self::and(arrivals, classes.four);
            ones = Self::sub(ones, four);
            buckets.fourth = Self::add(buckets.fourth, four);
        }
        buckets.first = Self::add(buckets.first, ones);
    }

    /// Pop the next non-empty bucket.
    /// # Arguments
    /// * `buckets` - The pending buckets
    /// * `time` - The current time, advanced to the popped bucket
    /// # Returns
    /// * The popped frontier, empty when every bucket is empty
    #[inline(always)]
    fn pop(ref buckets: Buckets, ref time: u32) -> u256 {
        loop {
            let frontier = buckets.first;
            buckets =
                Buckets {
                    first: buckets.second, second: buckets.third, third: buckets.fourth, fourth: 0,
                };
            time += 1;
            if !Self::is_empty(frontier) {
                break frontier;
            }
            if Self::is_empty(buckets.first)
                && Self::is_empty(buckets.second)
                && Self::is_empty(buckets.third) {
                break frontier;
            }
        }
    }

    /// Settle buckets until the target is scheduled.
    /// # Arguments
    /// * `layout` - The layout
    /// * `classes` - The cost classes
    /// * `start` - The start bit, layer 0
    /// * `unvisited` - The tiles not yet scheduled, `arrivals` included
    /// * `arrivals` - The tiles entered from the start
    /// * `target` - The target bit
    /// # Returns
    /// * The settled layers and the time of the layer that reaches the target, `None` if
    /// unreachable
    fn forward(
        layout: @Layout,
        classes: Classes,
        start: u256,
        unvisited: u256,
        arrivals: u256,
        target: u256,
    ) -> Option<(Array<u256>, u32)> {
        let mut layers: Array<u256> = array![start];
        let mut buckets = Buckets { first: 0, second: 0, third: 0, fourth: 0 };
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let (target_limb, target_high) = if target.low != 0 {
            (target.low, false)
        } else {
            (target.high, true)
        };
        let found = loop {
            // [Check] Target scheduled: its arrival time is final
            let limb = if target_high {
                arrivals.high
            } else {
                arrivals.low
            };
            let (hit, _, _) = bitwise(limb, target_limb);
            if hit != 0 {
                break true;
            }
            // [Effect] Schedule the arrivals, settle the next bucket
            Self::schedule(@classes, ref buckets, arrivals);
            let frontier = Self::pop(ref buckets, ref time);
            if Self::is_empty(frontier) {
                break false;
            }
            // [Effect] Empty time steps keep their index
            while layers.len() != time {
                layers.append(0);
            }
            layers.append(frontier);
            arrivals = Self::and(layout.expand(frontier), unvisited);
            unvisited = Self::sub(unvisited, arrivals);
        };
        if found {
            Option::Some((layers, time))
        } else {
            Option::None
        }
    }

    /// Settle buckets up to the budget.
    /// # Arguments
    /// * `layout` - The layout
    /// * `classes` - The cost classes
    /// * `interior` - The interior mask
    /// * `edges` - Whether `unvisited` holds edge tiles, which are never expanded
    /// * `start` - The start bit
    /// * `budget` - The movement budget, at least 1
    /// * `unvisited` - The tiles not yet scheduled, `arrivals` included
    /// * `arrivals` - The tiles entered from the start
    /// # Returns
    /// * The settled tiles
    fn field(
        layout: @Layout,
        classes: Classes,
        interior: u256,
        edges: bool,
        start: felt252,
        budget: u8,
        unvisited: u256,
        arrivals: u256,
    ) -> felt252 {
        let mut buckets = Buckets { first: 0, second: 0, third: 0, fourth: 0 };
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let budget: u32 = budget.into();
        let mut field = start;
        loop {
            Self::schedule(@classes, ref buckets, arrivals);
            let frontier = Self::pop(ref buckets, ref time);
            if time > budget || Self::is_empty(frontier) {
                break field;
            }
            field += Bits::to_felt(frontier);
            if time == budget {
                break field;
            }
            let frontier = if edges {
                Self::and(frontier, interior)
            } else {
                frontier
            };
            arrivals = Self::and(layout.expand(frontier), unvisited);
            unvisited = Self::sub(unvisited, arrivals);
        }
    }

    /// Cost of a tile given its one-hot limb.
    #[inline(always)]
    fn cost(classes: @Classes, bit: u128, high: bool) -> u32 {
        let classes = *classes;
        let (low_plane, high_plane) = if high {
            (classes.low.high, classes.high.high)
        } else {
            (classes.low.low, classes.high.low)
        };
        let (low, _, _) = bitwise(bit, low_plane);
        let (high, _, _) = bitwise(bit, high_plane);
        let mut cost = 1;
        if low != 0 {
            cost += 1;
        }
        if high != 0 {
            cost += 2;
        }
        cost
    }

    /// Walk back from the target through the layers: the predecessor of a tile of arrival time
    /// `d` and cost `c` is a neighbour settled at `d - c`.
    /// # Arguments
    /// * `layout` - The layout
    /// * `classes` - The cost classes
    /// * `layers` - The settled layers, index = time
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `to` - The target
    /// * `to_bit` - `2^to`
    /// * `to_y` - The row of the target
    /// * `to_edge` - Whether the target is an edge tile
    /// * `time` - The time of the layer that reaches the target
    /// # Returns
    /// * The path from the target (included) to the start (excluded)
    fn backtrack(
        layout: @Layout,
        classes: Classes,
        layers: Span<u256>,
        width: u8,
        height: u8,
        to: u8,
        to_bit: felt252,
        to_y: u8,
        to_edge: bool,
        time: u32,
    ) -> Span<u8> {
        let mut path: Array<u8> = array![to];
        if time == 0 {
            return path.span();
        }
        // [Compute] First tile: an edge target has no exact neighbour mask, scan its neighbours
        let (mut position, mut bit, mut odd) = if to_edge {
            let layer = *layers[time];
            let mut found: u8 = 0;
            for direction in array![
                Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
                Direction::SouthWest, Direction::SouthEast,
            ]
                .span() {
                if let Option::Some(next) = LayoutTrait::neighbor(width, height, to, *direction) {
                    if Bits::get(layer, next) {
                        found = next;
                        break;
                    }
                }
            }
            path.append(found);
            let (y, _) = DivRem::div_rem(found, width.try_into().unwrap());
            (found, Bits::pow(found), y % 2 == 1)
        } else {
            (to, to_bit, to_y % 2 == 1)
        };
        // [Compute] Arrival time of the current tile
        let mut time = time;
        if !to_edge {
            // The target's own cost is subtracted in the loop
            let target: u256 = to_bit.into();
            time +=
                if target.low != 0 {
                    Self::cost(@classes, target.low, false)
                } else {
                    Self::cost(@classes, target.high, true)
                };
        }
        let (mut current, mut current_high) = {
            let value: u256 = bit.into();
            if value.low != 0 {
                (value.low, false)
            } else {
                (value.high, true)
            }
        };
        let layout = *layout;
        loop {
            let previous = time - Self::cost(@classes, current, current_high);
            if previous == 0 {
                break;
            }
            // [Compute] Neighbours settled at `previous`, keep the lowest bit
            let mask = if odd {
                bit * (INV_2 + 2 + 3 * (layout.up_odd + layout.down_odd))
            } else {
                bit * (INV_2 + 2 + 3 * (layout.up_even + layout.down_even))
            };
            let hits = Self::and(mask.into(), *layers[previous]);
            let (limb, high) = if hits.low != 0 {
                (hits.low, false)
            } else {
                (hits.high, true)
            };
            let (rest, _, _) = bitwise(limb, limb - 1);
            let lowest = limb - rest;
            let next_bit: felt252 = if high {
                lowest.into() * TWO_POW_128
            } else {
                lowest.into()
            };
            // [Compute] Direction of the neighbour, lowest offsets first
            let (down, up) = if odd {
                (layout.down_odd, layout.up_odd)
            } else {
                (layout.down_even, layout.up_even)
            };
            let south = bit * down;
            if next_bit == south {
                position -= if odd {
                    width
                } else {
                    width + 1
                };
                odd = !odd;
            } else if next_bit == south + south {
                position = if odd {
                    position + 1 - width
                } else {
                    position - width
                };
                odd = !odd;
            } else if next_bit == bit * INV_2 {
                position -= 1;
            } else if next_bit == bit + bit {
                position += 1;
            } else if next_bit == bit * up {
                position += if odd {
                    width
                } else {
                    width - 1
                };
                odd = !odd;
            } else {
                position += if odd {
                    width + 1
                } else {
                    width
                };
                odd = !odd;
            }
            path.append(position);
            bit = next_bit;
            current = lowest;
            current_high = high;
            time = previous;
        }
        path.span()
    }
}
