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
        let mut ring: [felt252; 4] = [0, 0, 0, 0];
        let mut unvisited = Set::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let found = loop {
            // [Check] Target scheduled: its arrival time is final
            if Set::hits(arrivals, target) {
                break true;
            }
            // [Effect] Schedule the arrivals in the bucket of their cost
            let two = if classes.has_two {
                Set::to_felt(Set::and(arrivals, classes.two))
            } else {
                0
            };
            let three = if classes.has_three {
                Set::to_felt(Set::and(arrivals, classes.three))
            } else {
                0
            };
            let four = if classes.has_four {
                Set::to_felt(Set::and(arrivals, classes.four))
            } else {
                0
            };
            let [first, second, third, fourth] = ring;
            ring =
                [
                    first + Set::to_felt(arrivals) - two - three - four, second + two,
                    third + three, fourth + four,
                ];
            // [Effect] Pop the next non-empty bucket, the buckets are disjoint
            let frontier = loop {
                let [frontier, second, third, fourth] = ring;
                ring = [second, third, fourth, 0];
                time += 1;
                if frontier != 0 || second + third + fourth == 0 {
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
        let mut ring: [felt252; 4] = [0, 0, 0, 0];
        let mut unvisited = unvisited;
        let mut arrivals: T = Set::from_felt(arrivals);
        let mut time: u8 = 0;
        let mut field = start;
        loop {
            let two = if classes.has_two {
                Set::to_felt(Set::and(arrivals, classes.two))
            } else {
                0
            };
            let three = if classes.has_three {
                Set::to_felt(Set::and(arrivals, classes.three))
            } else {
                0
            };
            let four = if classes.has_four {
                Set::to_felt(Set::and(arrivals, classes.four))
            } else {
                0
            };
            let [first, second, third, fourth] = ring;
            ring =
                [
                    first + Set::to_felt(arrivals) - two - three - four, second + two,
                    third + three, fourth + four,
                ];
            let frontier = loop {
                let [frontier, second, third, fourth] = ring;
                ring = [second, third, fourth, 0];
                time += 1;
                if frontier != 0 || second + third + fourth == 0 || time == budget {
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
        // [Compute] Constants boxed: the loop state is copied on every iteration
        let boxed_walk = BoxTrait::new(walk);
        let boxed_classes = BoxTrait::new(classes);
        loop {
            let walk = boxed_walk.unbox();
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
                let classes = boxed_classes.unbox();
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

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::generators::caver::Caver;
    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::tests::bench_dial::{check_path, dijkstra, field_oracle};
    use origami_hexmap::tests::fixtures::{
        CAVE_17X14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, EMPTY_7X7, UNREACHABLE_7X7,
        UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    };

    // Local imports

    use super::Dial;

    // Constants

    /// Row 3 of a 7x7 board, x = 2..5.
    const SWAMP_7X7: felt252 = 0xf * 0x800000;

    /// Search and check the path against the oracle.
    fn search_checked(
        grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
    ) -> Span<u8> {
        let path = Dial::search(grid, width, height, from, to, costs);
        let expected = *dijkstra(grid, width, height, from, costs)[to.into()];
        check_path(grid, width, height, from, to, costs, path, expected);
        assert!(path == Dial::search(grid, width, height, from, to, costs));
        path
    }

    #[test]
    fn test_dial_search_detour() {
        // Cost 4 on x = 2..5 of row 3: 7 tiles of cost 1 instead of 6 tiles of cost 9
        //  0 0 0 0 0 0 0
        // 0 S 1 1 1 1 0
        //  0 * * * * 1 0
        // 0 1 1 1 1 * 0      <- 4 4 4 4 on this row, the path crosses at x = 1
        //  0 1 1 1 1 * 0
        // 0 1 1 1 1 E 0
        //  0 0 0 0 0 0 0
        let path = search_checked(EMPTY_7X7, 7, 7, 40, 8, array![0, 0, SWAMP_7X7].span());
        assert!(path == array![8, 15, 22, 30, 31, 32, 33].span());
    }

    #[test]
    fn test_dial_search_unit() {
        //  0 0 0 0 0 0 0
        // 0 S 1 1 1 1 0
        //  0 * 1 1 1 1 0
        // 0 1 * 1 1 1 0
        //  0 1 * 1 1 1 0
        // 0 1 1 * * E 0
        //  0 0 0 0 0 0 0
        let path = search_checked(EMPTY_7X7, 7, 7, 40, 8, array![].span());
        assert!(path == array![8, 9, 10, 18, 25, 33].span());
    }

    #[test]
    fn test_dial_search_overlap_highest_class_wins() {
        // The swamp is in the classes of cost 2 and 4: it costs 4
        let overlap = Dial::search(EMPTY_7X7, 7, 7, 40, 8, array![SWAMP_7X7, 0, SWAMP_7X7].span());
        let four = Dial::search(EMPTY_7X7, 7, 7, 40, 8, array![0, 0, SWAMP_7X7].span());
        assert!(overlap == four);
        // Cost 3 and 2: crossing costs 8, the detour 7
        let path = search_checked(EMPTY_7X7, 7, 7, 40, 8, array![SWAMP_7X7, SWAMP_7X7].span());
        assert!(path.len() == 7);
    }

    #[test]
    fn test_dial_search_trivial() {
        assert!(Dial::search(EMPTY_7X7, 7, 7, 24, 24, array![SWAMP_7X7].span()).len() == 0);
        // Adjacent: the target only, whatever its cost
        let path = Dial::search(EMPTY_7X7, 7, 7, 31, 24, array![0, 0, SWAMP_7X7].span());
        assert!(path == array![24].span());
        let path = Dial::search(
            UNREACHABLE_7X7,
            7,
            7,
            UNREACHABLE_7X7_FAR_FROM,
            UNREACHABLE_7X7_FAR_TO,
            array![SWAMP_7X7].span(),
        );
        assert!(path.len() == 0);
    }

    #[test]
    fn test_dial_search_edges() {
        // Open edge tiles: 3 (bottom), 21 (x = 0), 27 (x = 6), 45 (top), corner 48
        let grid = EMPTY_7X7
            + Bits::pow(3)
            + Bits::pow(21)
            + Bits::pow(27)
            + Bits::pow(45)
            + Bits::pow(48);
        let costs = array![0, 0, SWAMP_7X7].span();
        // Edge to interior, interior to edge, edge to edge, corner
        search_checked(grid, 7, 7, 3, 40, costs);
        search_checked(grid, 7, 7, 40, 3, costs);
        search_checked(grid, 7, 7, 3, 45, costs);
        search_checked(grid, 7, 7, 21, 27, costs);
        // The corner (even row) reaches the interior through its South-East neighbour 40
        search_checked(grid, 7, 7, 48, 24, costs);
        let path = search_checked(grid, 7, 7, 24, 48, costs);
        assert!(*path[1] == 40);
    }

    #[test]
    fn test_dial_search_edges_adjacent() {
        // Two adjacent open edge tiles 3 and 4 (bottom row), 4 also next to 11
        let grid = EMPTY_7X7 + Bits::pow(3) + Bits::pow(4);
        let path = Dial::search(grid, 7, 7, 3, 4, array![SWAMP_7X7].span());
        assert!(path == array![4].span());
        let path = search_checked(grid, 7, 7, 11, 4, array![].span());
        assert!(path == array![4].span());
    }

    #[test]
    fn test_dial_search_dimensions() {
        // 3x3: a single interior tile between open edge tiles
        let grid: felt252 = 0x1ff - 1 - 0x100;
        let path = search_checked(grid, 3, 3, 1, 7, array![0x10].span());
        assert!(path == array![7, 4].span());
        // 17x14 and 19x13 (u256 path), 7x7 (u128 path)
        let costs = array![0x5555555555555555555555555555555555555555555555555555555555555].span();
        search_checked(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, costs);
        let grid = Caver::generate(19, 13, 3, 'DIAL');
        let open: u256 = grid.into();
        let mut from: u8 = 20;
        while !Bits::get(open, from) {
            from += 1;
        }
        let mut to: u8 = 226;
        while !Bits::get(open, to) {
            to -= 1;
        }
        search_checked(grid, 19, 13, from, to, costs);
        search_checked(EMPTY_7X7, 7, 7, 36, 12, costs);
    }

    #[test]
    fn test_dial_field_of_movement() {
        // From 24 with budget 2, the swamp costs 2: its tiles next to 24 only
        //  0 0 0 0 0 0 0
        // 0 0 1 1 1 0 0
        //  0 1 1 1 1 0 0
        // 0 0 1 1 1 0 0
        //  0 1 1 1 1 0 0
        // 0 0 1 1 1 0 0
        //  0 0 0 0 0 0 0
        let field = Dial::field_of_movement(EMPTY_7X7, 7, 7, 24, 2, array![SWAMP_7X7].span());
        assert!(field == 978238508544);
        // Budget 0: the start only
        let field = Dial::field_of_movement(EMPTY_7X7, 7, 7, 24, 0, array![SWAMP_7X7].span());
        assert!(field == Bits::pow(24));
        // Unit costs, budget 1: the start and its 6 neighbours
        let field = Dial::field_of_movement(EMPTY_7X7, 7, 7, 24, 1, array![].span());
        let expected = Bits::pow(24)
            + Bits::pow(23)
            + Bits::pow(25)
            + Bits::pow(31)
            + Bits::pow(32)
            + Bits::pow(17)
            + Bits::pow(18);
        assert!(field == expected);
        // A large budget floods the component
        let field = Dial::field_of_movement(EMPTY_7X7, 7, 7, 24, 255, array![SWAMP_7X7].span());
        assert!(field == EMPTY_7X7);
    }

    #[test]
    fn test_dial_field_of_movement_edges() {
        // An edge start reaches its open neighbours, an open edge tile is an endpoint only
        let grid = EMPTY_7X7 + Bits::pow(3) + Bits::pow(4);
        let field = Dial::field_of_movement(grid, 7, 7, 3, 1, array![].span());
        assert!(field == Bits::pow(3) + Bits::pow(4) + Bits::pow(9) + Bits::pow(10));
        let costs = array![SWAMP_7X7].span();
        let mut budget: u8 = 0;
        while budget != 8 {
            let field = Dial::field_of_movement(grid, 7, 7, 17, budget, costs);
            assert!(field == field_oracle(dijkstra(grid, 7, 7, 17, costs), budget));
            budget += 1;
        }
    }

    #[test]
    #[should_panic(expected: 'Dial: too many costs')]
    fn test_dial_search_revert_too_many_costs() {
        Dial::search(EMPTY_7X7, 7, 7, 40, 8, array![0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'Dial: too many costs')]
    fn test_dial_field_revert_too_many_costs() {
        Dial::field_of_movement(EMPTY_7X7, 7, 7, 40, 3, array![0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'Dial: position not walkable')]
    fn test_dial_search_revert_from_not_walkable() {
        Dial::search(EMPTY_7X7, 7, 7, 0, 8, array![].span());
    }

    #[test]
    #[should_panic(expected: 'Dial: position not walkable')]
    fn test_dial_search_revert_to_not_walkable() {
        Dial::search(EMPTY_7X7, 7, 7, 8, 6, array![].span());
    }

    #[test]
    #[should_panic(expected: 'Dial: position not walkable')]
    fn test_dial_field_revert_not_walkable() {
        Dial::field_of_movement(EMPTY_7X7, 7, 7, 0, 3, array![].span());
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not inside')]
    fn test_dial_search_revert_outside() {
        Dial::search(EMPTY_7X7, 7, 7, 8, 49, array![].span());
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_dial_search_revert_dimension() {
        Dial::search(EMPTY_7X7, 18, 14, 8, 9, array![].span());
    }
}
