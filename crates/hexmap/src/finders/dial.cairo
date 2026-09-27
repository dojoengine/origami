//! Weighted bit-parallel Dial search with cost classes (lot L3).
//!
//! Entering a tile costs 1, 2, 3 or 4. The costs are given as class bitmaps: `costs[k]` holds
//! the tiles of cost `k + 2`; a tile in several classes takes the highest one.
//!
//! Time-expanded layers, no heap: bucket `t` holds the tiles whose cheapest arrival time is `t`.
//! Because the cost is paid on entering a tile, the first neighbour of a tile to settle gives its
//! final arrival time: a tile is scheduled once, in the bucket `t + cost`, and leaves the
//! unvisited set at that moment. Settling bucket `t` is one dilation intersected with the
//! unvisited set, plus one AND per cost class. The buckets are a ring of 4 felt locals (the
//! scheduled sets are disjoint, so a union is an addition). Without costs, a unit-cost loop
//! skips the buckets. Boards of at most 128 bits run the same loops on a single `u128` limb.
//!
//! Backtracking: the predecessor of a tile of arrival time `d` and cost `c` is a neighbour
//! settled at `d - c`: the lowest bit of the neighbour mask intersected with that layer.
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
/// 2^-128 in the field.
const INV_2_128: felt252 = 0x800000000000010fffffffffffffffff7ffffffffffffef0000000000000001;
/// Largest number of cost classes.
const MAX_CLASSES: u32 = 3;
/// Largest board of the single-limb path.
const SMALL_SIZE: u8 = 128;

/// Errors module.
pub mod errors {
    pub const DIAL_TOO_MANY_COSTS: felt252 = 'Dial: too many costs';
    pub const DIAL_POSITION_NOT_WALKABLE: felt252 = 'Dial: position not walkable';
}

/// AND, XOR and OR of two limbs in a single application of the bitwise builtin, see
/// `generators::caver`.
extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

/// Walkable tiles of each cost class, disjoint (the highest class wins), and the planes of
/// `cost - 1` read by the backtracking.
#[derive(Copy, Drop)]
struct Classes<T> {
    /// Tiles of cost 2.
    two: T,
    /// Tiles of cost 3.
    three: T,
    /// Tiles of cost 4.
    four: T,
    /// Tiles of cost 2, 3 or 4.
    any: T,
    /// Tiles of cost 2 or 4.
    odd: T,
    /// Tiles of cost 3 or 4.
    upper: T,
    has_two: bool,
    has_three: bool,
    has_four: bool,
}

/// Constants of the backtracking.
#[derive(Copy, Drop)]
struct Walk {
    width: u8,
    /// Field sum of the neighbour offsets, even rows.
    mask_even: felt252,
    /// Field sum of the neighbour offsets, odd rows.
    mask_odd: felt252,
    down_even: felt252,
    down_odd: felt252,
    up_even: felt252,
    up_odd: felt252,
    /// Below this position every neighbour lies in the low limb.
    low_limit: u8,
    /// From this position every neighbour lies in the high limb.
    high_limit: u8,
}

/// Endpoints of a search.
#[derive(Copy, Drop)]
struct Ends {
    from: u8,
    to: u8,
    from_bit: felt252,
    to_bit: felt252,
    from_edge: bool,
    to_edge: bool,
    /// Whether the target lies on an odd row.
    to_odd: bool,
}

/// Bitmap operations of the loops: a `u256`, or a single `u128` for boards of at most 128 bits.
trait Set<T> {
    /// The bitmap of a felt below 2^251 (below 2^128 for `u128`).
    fn from_felt(value: felt252) -> T;
    /// The bitmap of a `u256` (its low limb for `u128`).
    fn from_wide(value: u256) -> T;
    fn to_felt(self: T) -> felt252;
    fn and(self: T, other: T) -> T;
    /// Set difference when `other` is a subset of `self`.
    fn sub(self: T, other: T) -> T;
    fn is_empty(self: T) -> bool;
    /// Whether the set meets the limb of a one-hot target.
    fn hits(self: T, target: T) -> bool;
    /// Limb `high` of the set.
    fn limb(self: T, high: bool) -> u128;
    /// Hex dilation (`Layout::expand`) intersected with `unvisited`.
    fn expand(layout: @Layout, frontier: T, felt: felt252, unvisited: T) -> T;
    /// The neighbours of an interior position in a layer, on the limb that holds them: the
    /// mask is `2^position` times the field sum of the neighbour offsets.
    fn neighbours(
        layer: T, mask: felt252, position: u8, low_limit: u8, high_limit: u8,
    ) -> (u128, bool);
}

impl WideSet of Set<u256> {
    #[inline(always)]
    fn from_felt(value: felt252) -> u256 {
        value.into()
    }

    #[inline(always)]
    fn from_wide(value: u256) -> u256 {
        value
    }

    #[inline(always)]
    fn to_felt(self: u256) -> felt252 {
        Bits::to_felt(self)
    }

    #[inline(always)]
    fn and(self: u256, other: u256) -> u256 {
        let (low, _, _) = bitwise(self.low, other.low);
        let (high, _, _) = bitwise(self.high, other.high);
        u256 { low, high }
    }

    #[inline(always)]
    fn sub(self: u256, other: u256) -> u256 {
        u256 { low: self.low - other.low, high: self.high - other.high }
    }

    #[inline(always)]
    fn is_empty(self: u256) -> bool {
        self.low == 0 && self.high == 0
    }

    #[inline(always)]
    fn hits(self: u256, target: u256) -> bool {
        let (hit, _, _) = if target.low != 0 {
            bitwise(self.low, target.low)
        } else {
            bitwise(self.high, target.high)
        };
        hit != 0
    }

    #[inline(always)]
    fn limb(self: u256, high: bool) -> u128 {
        if high {
            self.high
        } else {
            self.low
        }
    }

    /// The field shifts of `Layout::expand`, set operations on limbs (12 applications).
    #[inline(always)]
    fn expand(layout: @Layout, frontier: u256, felt: felt252, unvisited: u256) -> u256 {
        let layout = *layout;
        let double: u256 = (felt + felt).into();
        // [Compute] Frontier and its West neighbours, split by row parity
        let (_, _, pairs_low) = bitwise(frontier.low, double.low);
        let (_, _, pairs_high) = bitwise(frontier.high, double.high);
        let (even_low, _, _) = bitwise(pairs_low, layout.even.low);
        let (even_high, _, _) = bitwise(pairs_high, layout.even.high);
        let pairs_even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
        let pairs_odd: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128 - pairs_even;
        // [Compute] NE/NW, SE/SW and East neighbours
        let up: u256 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd).into();
        let down: u256 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd).into();
        let east: u256 = (felt * INV_2).into();
        // [Return] Union, intersected
        let (_, _, low) = bitwise(pairs_low, east.low);
        let (_, _, low) = bitwise(low, up.low);
        let (_, _, low) = bitwise(low, down.low);
        let (low, _, _) = bitwise(low, unvisited.low);
        let (_, _, high) = bitwise(pairs_high, east.high);
        let (_, _, high) = bitwise(high, up.high);
        let (_, _, high) = bitwise(high, down.high);
        let (high, _, _) = bitwise(high, unvisited.high);
        u256 { low, high }
    }

    #[inline(always)]
    fn neighbours(
        layer: u256, mask: felt252, position: u8, low_limit: u8, high_limit: u8,
    ) -> (u128, bool) {
        if position < low_limit {
            let (hits, _, _) = bitwise(mask.try_into().unwrap(), layer.low);
            (hits, false)
        } else if position >= high_limit {
            let (hits, _, _) = bitwise((mask * INV_2_128).try_into().unwrap(), layer.high);
            (hits, true)
        } else {
            // [Compute] The mask straddles the limbs
            let mask: u256 = mask.into();
            let (hits, _, _) = bitwise(mask.low, layer.low);
            if hits != 0 {
                (hits, false)
            } else {
                let (hits, _, _) = bitwise(mask.high, layer.high);
                (hits, true)
            }
        }
    }
}

impl SmallSet of Set<u128> {
    #[inline(always)]
    fn from_felt(value: felt252) -> u128 {
        value.try_into().unwrap()
    }

    #[inline(always)]
    fn from_wide(value: u256) -> u128 {
        value.low
    }

    #[inline(always)]
    fn to_felt(self: u128) -> felt252 {
        self.into()
    }

    #[inline(always)]
    fn and(self: u128, other: u128) -> u128 {
        let (value, _, _) = bitwise(self, other);
        value
    }

    #[inline(always)]
    fn sub(self: u128, other: u128) -> u128 {
        self - other
    }

    #[inline(always)]
    fn is_empty(self: u128) -> bool {
        self == 0
    }

    #[inline(always)]
    fn hits(self: u128, target: u128) -> bool {
        let (hit, _, _) = bitwise(self, target);
        hit != 0
    }

    #[inline(always)]
    fn limb(self: u128, high: bool) -> u128 {
        self
    }

    /// `Layout::expand_small` with the intersection (6 applications).
    #[inline(always)]
    fn expand(layout: @Layout, frontier: u128, felt: felt252, unvisited: u128) -> u128 {
        let layout = *layout;
        let double: u128 = (felt + felt).try_into().unwrap();
        let (_, _, pairs) = bitwise(frontier, double);
        let (pairs_even, _, _) = bitwise(pairs, layout.even.low);
        let pairs_even: felt252 = pairs_even.into();
        let pairs_odd = pairs.into() - pairs_even;
        let up: u128 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd)
            .try_into()
            .unwrap();
        let down: u128 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd)
            .try_into()
            .unwrap();
        let east: u128 = (felt * INV_2).try_into().unwrap();
        let (_, _, value) = bitwise(pairs, east);
        let (_, _, value) = bitwise(value, up);
        let (_, _, value) = bitwise(value, down);
        let (value, _, _) = bitwise(value, unvisited);
        value
    }

    #[inline(always)]
    fn neighbours(
        layer: u128, mask: felt252, position: u8, low_limit: u8, high_limit: u8,
    ) -> (u128, bool) {
        let (hits, _, _) = bitwise(mask.try_into().unwrap(), layer);
        (hits, false)
    }
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
        // [Compute] Endpoints and unvisited set: interior tiles, plus an edge target
        let layout = LayoutTrait::new(width, height);
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let (from_y, from_x) = DivRem::div_rem(from, width.try_into().unwrap());
        let (to_y, to_x) = DivRem::div_rem(to, width.try_into().unwrap());
        let ends = Ends {
            from,
            to,
            from_bit: Bits::pow(from),
            to_bit: Bits::pow(to),
            from_edge: Asserter::is_edge(width, height, from_x, from_y),
            to_edge: Asserter::is_edge(width, height, to_x, to_y),
            to_odd: to_y % 2 == 1,
        };
        let mut unvisited = Bits::to_felt(WideSet::and(open, interior));
        if !ends.from_edge {
            unvisited -= ends.from_bit;
        }
        if ends.to_edge {
            unvisited += ends.to_bit;
        }
        // [Return] Cheapest path
        if width * height <= SMALL_SIZE {
            DialInternal::solve::<u128>(@layout, height, open, costs, ends, unvisited)
        } else {
            DialInternal::solve::<u256>(@layout, height, open, costs, ends, unvisited)
        }
    }

    /// Every tile reachable from a position with a total entry cost of at most `budget`, the
    /// position included (`hexx`'s `field_of_movement`). Open edge tiles are reachable as
    /// endpoints but never crossed.
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
        // [Compute] Unvisited set, open edge tiles included
        let layout = LayoutTrait::new(width, height);
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let (from_y, from_x) = DivRem::div_rem(from, width.try_into().unwrap());
        let from_edge = Asserter::is_edge(width, height, from_x, from_y);
        let inside = WideSet::and(open, interior);
        let edges = inside != open;
        let unvisited = if edges {
            grid - from_bit
        } else if from_edge {
            Bits::to_felt(inside)
        } else {
            Bits::to_felt(inside) - from_bit
        };
        // [Return] Settled tiles up to the budget
        if width * height <= SMALL_SIZE {
            DialInternal::field::<
                u128,
            >(@layout, height, open, costs, interior, edges, from, from_edge, budget, unvisited)
        } else {
            DialInternal::field::<
                u256,
            >(@layout, height, open, costs, interior, edges, from, from_edge, budget, unvisited)
        }
    }
}

#[generate_trait]
impl DialInternal of DialInternalTrait {
    /// Partition the walkable tiles by cost class, the highest class wins.
    /// # Arguments
    /// * `open` - The walkable tiles
    /// * `costs` - The class bitmaps, 1 to 3
    /// # Returns
    /// * The disjoint classes
    #[inline]
    fn classes<T, +Set<T>, +Drop<T>>(open: u256, costs: Span<felt252>) -> Classes<T> {
        let count = costs.len();
        let zero: u256 = 0;
        let mut rest = open;
        let four = if count == 3 {
            let four = WideSet::and(rest, (*costs[2]).into());
            rest = WideSet::sub(rest, four);
            four
        } else {
            zero
        };
        let three = if count >= 2 {
            let three = WideSet::and(rest, (*costs[1]).into());
            rest = WideSet::sub(rest, three);
            three
        } else {
            zero
        };
        let two = WideSet::and(rest, (*costs[0]).into());
        let (two_felt, three_felt, four_felt) = (
            Bits::to_felt(two), Bits::to_felt(three), Bits::to_felt(four),
        );
        Classes {
            two: Set::from_wide(two),
            three: Set::from_wide(three),
            four: Set::from_wide(four),
            any: Set::from_felt(two_felt + three_felt + four_felt),
            odd: Set::from_felt(two_felt + four_felt),
            upper: Set::from_felt(three_felt + four_felt),
            has_two: two_felt != 0,
            has_three: three_felt != 0,
            has_four: four_felt != 0,
        }
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
    fn seeds(width: u8, height: u8, from: u8, to: u8, unvisited: felt252) -> (felt252, bool) {
        let unvisited: u256 = unvisited.into();
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
        (seeds, adjacent)
    }

    /// Cheapest path on one set representation.
    fn solve<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout,
        height: u8,
        open: u256,
        costs: Span<felt252>,
        ends: Ends,
        unvisited: felt252,
    ) -> Span<u8> {
        let unvisited: T = Set::from_felt(unvisited);
        // [Compute] First arrivals: dilation of an interior start, open neighbours of an edge one
        let arrivals: T = if ends.from_edge {
            let (seeds, adjacent) = Self::seeds(
                *layout.width, height, ends.from, ends.to, Set::to_felt(unvisited),
            );
            if adjacent {
                return array![ends.to].span();
            }
            Set::from_felt(seeds)
        } else {
            Set::expand(layout, Set::from_felt(ends.from_bit), ends.from_bit, unvisited)
        };
        let target: T = Set::from_felt(ends.to_bit);
        let walk = Self::walk(layout);
        // [Compute] Forward search, then backtrack from the target
        if costs.len() == 0 {
            return match Self::forward_unit(layout, unvisited, arrivals, target) {
                Option::Some((
                    layers, time,
                )) => {
                    let classes = Classes {
                        two: target,
                        three: target,
                        four: target,
                        any: target,
                        odd: target,
                        upper: target,
                        has_two: false,
                        has_three: false,
                        has_four: false,
                    };
                    Self::backtrack(walk, classes, false, layers.span(), height, ends, time)
                },
                Option::None => array![].span(),
            };
        }
        let classes: Classes<T> = Self::classes(open, costs);
        match Self::forward(layout, classes, unvisited, arrivals, target) {
            Option::Some((
                layers, time,
            )) => Self::backtrack(walk, classes, true, layers.span(), height, ends, time),
            Option::None => array![].span(),
        }
    }

    /// Field of movement on one set representation.
    fn field<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout,
        height: u8,
        open: u256,
        costs: Span<felt252>,
        interior: u256,
        edges: bool,
        from: u8,
        from_edge: bool,
        budget: u8,
        unvisited: felt252,
    ) -> felt252 {
        let start = Bits::pow(from);
        let arrivals = if from_edge {
            let (seeds, _) = Self::seeds(*layout.width, height, from, from, unvisited);
            seeds
        } else {
            let unvisited: T = Set::from_felt(unvisited);
            Set::to_felt(Set::expand(layout, Set::from_felt(start), start, unvisited))
        };
        let interior: T = Set::from_wide(interior);
        let unvisited: T = Set::from_felt(unvisited - arrivals);
        if costs.len() == 0 {
            return Self::field_unit(layout, interior, edges, start, budget, unvisited, arrivals);
        }
        let classes: Classes<T> = Self::classes(open, costs);
        Self::field_weighted(layout, classes, interior, edges, start, budget, unvisited, arrivals)
    }

    /// Settle buckets until the target is scheduled.
    /// # Arguments
    /// * `layout` - The layout
    /// * `classes` - The cost classes
    /// * `unvisited` - The tiles not yet scheduled, `arrivals` included
    /// * `arrivals` - The tiles entered from the start
    /// * `target` - The target bit
    /// # Returns
    /// * The settled layers (index = time, layer 0 left empty) and the time of the layer that
    /// schedules the target, `None` if unreachable
    fn forward<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout, classes: Classes<T>, unvisited: T, arrivals: T, target: T,
    ) -> Option<(Array<T>, u32)> {
        let empty: T = Set::from_felt(0);
        let mut layers: Array<T> = array![empty];
        let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
            0, 0, 0, 0,
        );
        let mut unvisited = Set::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let found = loop {
            // [Check] Target scheduled: its arrival time is final
            if Set::hits(arrivals, target) {
                break true;
            }
            // [Effect] Schedule the arrivals in the bucket of their cost
            let mut ones = Set::to_felt(arrivals);
            if classes.has_two {
                let two = Set::to_felt(Set::and(arrivals, classes.two));
                ones -= two;
                second += two;
            }
            if classes.has_three {
                let three = Set::to_felt(Set::and(arrivals, classes.three));
                ones -= three;
                third += three;
            }
            if classes.has_four {
                let four = Set::to_felt(Set::and(arrivals, classes.four));
                ones -= four;
                fourth += four;
            }
            first += ones;
            // [Effect] Pop the next non-empty bucket, the buckets are disjoint
            let frontier = loop {
                let frontier = first;
                first = second;
                second = third;
                third = fourth;
                fourth = 0;
                time += 1;
                if frontier != 0 || first + second + third == 0 {
                    break frontier;
                }
            };
            if frontier == 0 {
                break false;
            }
            // [Effect] Record the layer, empty time steps keep their index
            while layers.len() != time {
                layers.append(empty);
            }
            let set: T = Set::from_felt(frontier);
            layers.append(set);
            arrivals = Set::expand(layout, set, frontier, unvisited);
            unvisited = Set::sub(unvisited, arrivals);
        };
        if found {
            Option::Some((layers, time))
        } else {
            Option::None
        }
    }

    /// Unit costs: plain breadth-first layers, no buckets.
    /// # Returns
    /// * The layers (index = distance, layer 0 left empty) and the distance of the target minus
    /// one, `None` if unreachable
    fn forward_unit<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout, unvisited: T, arrivals: T, target: T,
    ) -> Option<(Array<T>, u32)> {
        let mut layers: Array<T> = array![Set::from_felt(0)];
        let mut unvisited = Set::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let found = loop {
            if Set::hits(arrivals, target) {
                break true;
            }
            if Set::is_empty(arrivals) {
                break false;
            }
            time += 1;
            layers.append(arrivals);
            arrivals = Set::expand(layout, arrivals, Set::to_felt(arrivals), unvisited);
            unvisited = Set::sub(unvisited, arrivals);
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
    /// * `unvisited` - The tiles not yet scheduled
    /// * `arrivals` - The tiles entered from the start
    /// # Returns
    /// * The settled tiles
    fn field_weighted<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout,
        classes: Classes<T>,
        interior: T,
        edges: bool,
        start: felt252,
        budget: u8,
        unvisited: T,
        arrivals: felt252,
    ) -> felt252 {
        let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
            0, 0, 0, 0,
        );
        let mut unvisited = unvisited;
        let mut arrivals: T = Set::from_felt(arrivals);
        let mut time: u8 = 0;
        let mut field = start;
        loop {
            let mut ones = Set::to_felt(arrivals);
            if classes.has_two {
                let two = Set::to_felt(Set::and(arrivals, classes.two));
                ones -= two;
                second += two;
            }
            if classes.has_three {
                let three = Set::to_felt(Set::and(arrivals, classes.three));
                ones -= three;
                third += three;
            }
            if classes.has_four {
                let four = Set::to_felt(Set::and(arrivals, classes.four));
                ones -= four;
                fourth += four;
            }
            first += ones;
            let frontier = loop {
                let frontier = first;
                first = second;
                second = third;
                third = fourth;
                fourth = 0;
                time += 1;
                if frontier != 0 || first + second + third == 0 || time == budget {
                    break frontier;
                }
            };
            field += frontier;
            if time == budget || frontier == 0 {
                break field;
            }
            let set: T = Set::from_felt(frontier);
            arrivals =
                if edges {
                    let inner = Set::and(set, interior);
                    Set::expand(layout, inner, Set::to_felt(inner), unvisited)
                } else {
                    Set::expand(layout, set, frontier, unvisited)
                };
            unvisited = Set::sub(unvisited, arrivals);
        }
    }

    /// Unit costs: plain breadth-first layers up to the budget.
    fn field_unit<T, +Set<T>, +Copy<T>, +Drop<T>>(
        layout: @Layout,
        interior: T,
        edges: bool,
        start: felt252,
        budget: u8,
        unvisited: T,
        arrivals: felt252,
    ) -> felt252 {
        let mut unvisited = unvisited;
        let mut felt = arrivals;
        let mut time: u8 = 0;
        let mut field = start;
        loop {
            field += felt;
            time += 1;
            if time == budget || felt == 0 {
                break field;
            }
            let set: T = Set::from_felt(felt);
            let arrivals = if edges {
                let inner = Set::and(set, interior);
                Set::expand(layout, inner, Set::to_felt(inner), unvisited)
            } else {
                Set::expand(layout, set, felt, unvisited)
            };
            unvisited = Set::sub(unvisited, arrivals);
            felt = Set::to_felt(arrivals);
        }
    }

    /// Constants of the backtracking.
    #[inline]
    fn walk(layout: @Layout) -> Walk {
        let layout = *layout;
        let width = layout.width;
        Walk {
            width,
            mask_even: INV_2 + 2 + 3 * (layout.up_even + layout.down_even),
            mask_odd: INV_2 + 2 + 3 * (layout.up_odd + layout.down_odd),
            down_even: layout.down_even,
            down_odd: layout.down_odd,
            up_even: layout.up_even,
            up_odd: layout.up_odd,
            low_limit: 127 - width,
            high_limit: 129 + width,
        }
    }

    /// Cost of a tile given its one-hot limb and the class planes on that limb: a single test
    /// for the tiles of cost 1.
    #[inline(always)]
    fn cost(bit: u128, any: u128, upper: u128, odd: u128, has_upper: bool, has_four: bool) -> u32 {
        let (hit, _, _) = bitwise(bit, any);
        if hit == 0 {
            return 1;
        }
        if !has_upper {
            return 2;
        }
        let (hit, _, _) = bitwise(bit, upper);
        if hit == 0 {
            return 2;
        }
        if !has_four {
            return 3;
        }
        let (hit, _, _) = bitwise(bit, odd);
        if hit == 0 {
            3
        } else {
            4
        }
    }

    /// Cost of a tile given its limb.
    #[inline]
    fn cost_limb<T, +Set<T>, +Copy<T>, +Drop<T>>(
        classes: @Classes<T>, bit: u128, high: bool,
    ) -> u32 {
        let classes = *classes;
        Self::cost(
            bit,
            Set::limb(classes.any, high),
            Set::limb(classes.upper, high),
            Set::limb(classes.odd, high),
            classes.has_three || classes.has_four,
            classes.has_four,
        )
    }

    /// Cost of a tile given its bit.
    #[inline]
    fn cost_of<T, +Set<T>, +Copy<T>, +Drop<T>>(classes: @Classes<T>, bit: felt252) -> u32 {
        let value: u256 = bit.into();
        if value.low != 0 {
            Self::cost_limb(classes, value.low, false)
        } else {
            Self::cost_limb(classes, value.high, true)
        }
    }

    /// Walk back from the target through the layers.
    /// # Arguments
    /// * `walk` - The backtracking constants
    /// * `classes` - The cost classes
    /// * `weighted` - Whether the costs are not all 1
    /// * `layers` - The settled layers, index = time
    /// * `height` - The height of the map
    /// * `ends` - The endpoints
    /// * `time` - The time of the layer that schedules the target
    /// # Returns
    /// * The path from the target (included) to the start (excluded)
    fn backtrack<T, +Set<T>, +Copy<T>, +Drop<T>>(
        walk: Walk,
        classes: Classes<T>,
        weighted: bool,
        layers: Span<T>,
        height: u8,
        ends: Ends,
        time: u32,
    ) -> Span<u8> {
        let mut path: Array<u8> = array![ends.to];
        if time == 0 {
            return path.span();
        }
        let width = walk.width;
        // [Compute] First tile: an edge target has no exact neighbour mask, scan its neighbours
        let (mut position, mut bit, mut odd, mut time) = if ends.to_edge {
            let layer: u256 = Set::to_felt(*layers[time]).into();
            let mut found: u8 = 0;
            for direction in array![
                Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
                Direction::SouthWest, Direction::SouthEast,
            ]
                .span() {
                if let Option::Some(next) =
                    LayoutTrait::neighbor(width, height, ends.to, *direction) {
                    if Bits::get(layer, next) {
                        found = next;
                        break;
                    }
                }
            }
            path.append(found);
            let (y, _) = DivRem::div_rem(found, width.try_into().unwrap());
            (found, Bits::pow(found), y % 2 == 1, time)
        } else {
            let arrival = if weighted {
                time + Self::cost_of(@classes, ends.to_bit)
            } else {
                time + 1
            };
            (ends.to, ends.to_bit, ends.to_odd, arrival)
        };
        let mut cost = if weighted {
            Self::cost_of(@classes, bit)
        } else {
            1
        };
        let has_upper = classes.has_three || classes.has_four;
        loop {
            let previous = time - cost;
            if previous == 0 {
                break;
            }
            // [Compute] Neighbours settled at `previous`, lowest hit
            let mask = if odd {
                bit * walk.mask_odd
            } else {
                bit * walk.mask_even
            };
            let (hits, high) = Set::neighbours(
                *layers[previous], mask, position, walk.low_limit, walk.high_limit,
            );
            let (rest, _, _) = bitwise(hits, hits - 1);
            let lowest = hits - rest;
            let next_bit: felt252 = if high {
                lowest.into() * TWO_POW_128
            } else {
                lowest.into()
            };
            // [Compute] Direction of the neighbour, lowest offsets first
            let (down, up) = if odd {
                (walk.down_odd, walk.up_odd)
            } else {
                (walk.down_even, walk.up_even)
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
            if weighted {
                cost =
                    Self::cost(
                        lowest,
                        Set::limb(classes.any, high),
                        Set::limb(classes.upper, high),
                        Set::limb(classes.odd, high),
                        has_upper,
                        classes.has_four,
                    );
            }
            bit = next_bit;
            time = previous;
        }
        path.span()
    }
}
