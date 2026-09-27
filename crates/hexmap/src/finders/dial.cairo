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
//! skips the buckets.
//!
//! Backtracking: the predecessor of a tile of arrival time `d` and cost `c` is a neighbour
//! settled at `d - c`, the lowest bit of the neighbour mask intersected with that layer.
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

/// Errors module.
pub mod errors {
    pub const DIAL_TOO_MANY_COSTS: felt252 = 'Dial: too many costs';
    pub const DIAL_POSITION_NOT_WALKABLE: felt252 = 'Dial: position not walkable';
}

/// AND, XOR and OR of two limbs in a single application of the bitwise builtin, see
/// `generators::caver`.
extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

/// Walkable tiles of each cost class, disjoint (the highest class wins), and the bit planes of
/// `cost - 1` used by the backtracking.
#[derive(Copy, Drop)]
struct Classes {
    /// Tiles of cost 2.
    two: u256,
    /// Tiles of cost 3.
    three: u256,
    /// Tiles of cost 4.
    four: u256,
    /// Tiles of cost 2, 3 or 4.
    any: u256,
    /// Tiles of cost 2 or 4.
    odd: u256,
    /// Tiles of cost 3 or 4.
    high: u256,
    has_two: bool,
    has_three: bool,
    has_four: bool,
}

/// Neighbour masks and limb bounds of the backtracking.
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
        // [Compute] Constants and unvisited set: interior tiles, plus an edge target
        let layout = LayoutTrait::new(width, height);
        let interior = LayoutTrait::interior(width, height);
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
            DialInternal::expand(@layout, from_bit.into(), from_bit, unvisited)
        };
        // [Compute] Forward search, then backtrack from the target
        let target: u256 = to_bit.into();
        let walk = DialInternal::walk(@layout);
        if costs.len() == 0 {
            let (layers, time) =
                match DialInternal::forward_unit(@layout, unvisited, arrivals, target) {
                Option::Some(result) => result,
                Option::None => { return array![].span(); },
            };
            let classes = DialInternal::classes(open, costs);
            return DialInternal::backtrack(
                walk, classes, false, layers.span(), height, to, to_bit, to_y, to_edge, time,
            );
        }
        let classes = DialInternal::classes(open, costs);
        let (layers, time) =
            match DialInternal::forward(@layout, classes, unvisited, arrivals, target) {
            Option::Some(result) => result,
            Option::None => { return array![].span(); },
        };
        DialInternal::backtrack(
            walk, classes, true, layers.span(), height, to, to_bit, to_y, to_edge, time,
        )
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
        // [Compute] Constants and unvisited set, open edge tiles included
        let layout = LayoutTrait::new(width, height);
        let interior: u256 = LayoutTrait::interior(width, height).into();
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
            DialInternal::expand(@layout, from_bit.into(), from_bit, unvisited)
        };
        // [Return] Settled tiles up to the budget
        if costs.len() == 0 {
            return DialInternal::field_unit(
                @layout, interior, edges, from_bit, budget, unvisited, arrivals,
            );
        }
        let classes = DialInternal::classes(open, costs);
        DialInternal::field(
            @layout, classes, interior, edges, from_bit, budget, unvisited, arrivals,
        )
    }
}

#[generate_trait]
impl DialInternal of DialInternalTrait {
    /// Hex dilation (`Layout::expand`) intersected with a set: the same field shifts, the set
    /// operations on limbs, one builtin application each.
    /// # Arguments
    /// * `layout` - The layout
    /// * `frontier` - The frontier, interior tiles only (border invariant)
    /// * `felt` - The same frontier as a felt
    /// * `unvisited` - The set to intersect with
    /// # Returns
    /// * The neighbours of the frontier in `unvisited`
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

    /// Whether a set is empty.
    #[inline(always)]
    fn is_empty(value: u256) -> bool {
        value.low == 0 && value.high == 0
    }

    /// Whether the target limb meets a set.
    #[inline(always)]
    fn hits(value: u256, target: u256) -> bool {
        let (hit, _, _) = if target.low != 0 {
            bitwise(value.low, target.low)
        } else {
            bitwise(value.high, target.high)
        };
        hit != 0
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
            return Classes {
                two: zero,
                three: zero,
                four: zero,
                any: zero,
                odd: zero,
                high: zero,
                has_two: false,
                has_three: false,
                has_four: false,
            };
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
        let two_felt = Bits::to_felt(two);
        let three_felt = Bits::to_felt(three);
        let four_felt = Bits::to_felt(four);
        Classes {
            two,
            three,
            four,
            any: (two_felt + three_felt + four_felt).into(),
            odd: (two_felt + four_felt).into(),
            high: (three_felt + four_felt).into(),
            has_two: !Self::is_empty(two),
            has_three: !Self::is_empty(three),
            has_four: !Self::is_empty(four),
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
    fn forward(
        layout: @Layout, classes: Classes, unvisited: u256, arrivals: u256, target: u256,
    ) -> Option<(Array<u256>, u32)> {
        let mut layers: Array<u256> = array![0];
        let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
            0, 0, 0, 0,
        );
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let found = loop {
            // [Check] Target scheduled: its arrival time is final
            if Self::hits(arrivals, target) {
                break true;
            }
            // [Effect] Schedule the arrivals in the bucket of their cost
            let mut ones = Bits::to_felt(arrivals);
            if classes.has_two {
                let two = Bits::to_felt(Self::and(arrivals, classes.two));
                ones -= two;
                second += two;
            }
            if classes.has_three {
                let three = Bits::to_felt(Self::and(arrivals, classes.three));
                ones -= three;
                third += three;
            }
            if classes.has_four {
                let four = Bits::to_felt(Self::and(arrivals, classes.four));
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
                layers.append(0);
            }
            let wide: u256 = frontier.into();
            layers.append(wide);
            arrivals = Self::expand(layout, wide, frontier, unvisited);
            unvisited = Self::sub(unvisited, arrivals);
        };
        if found {
            Option::Some((layers, time))
        } else {
            Option::None
        }
    }

    /// Unit costs: plain breadth-first layers, no buckets.
    /// # Arguments
    /// * `layout` - The layout
    /// * `unvisited` - The tiles not yet reached, `arrivals` included
    /// * `arrivals` - The tiles entered from the start
    /// * `target` - The target bit
    /// # Returns
    /// * The layers (index = distance, layer 0 left empty) and the distance of the layer that
    /// reaches the target minus one, `None` if unreachable
    fn forward_unit(
        layout: @Layout, unvisited: u256, arrivals: u256, target: u256,
    ) -> Option<(Array<u256>, u32)> {
        let mut layers: Array<u256> = array![0];
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u32 = 0;
        let found = loop {
            if Self::hits(arrivals, target) {
                break true;
            }
            if Self::is_empty(arrivals) {
                break false;
            }
            time += 1;
            layers.append(arrivals);
            arrivals = Self::expand(layout, arrivals, Bits::to_felt(arrivals), unvisited);
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
        let (mut first, mut second, mut third, mut fourth): (felt252, felt252, felt252, felt252) = (
            0, 0, 0, 0,
        );
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u8 = 0;
        let mut field = start;
        loop {
            let mut ones = Bits::to_felt(arrivals);
            if classes.has_two {
                let two = Bits::to_felt(Self::and(arrivals, classes.two));
                ones -= two;
                second += two;
            }
            if classes.has_three {
                let three = Bits::to_felt(Self::and(arrivals, classes.three));
                ones -= three;
                third += three;
            }
            if classes.has_four {
                let four = Bits::to_felt(Self::and(arrivals, classes.four));
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
            let wide: u256 = frontier.into();
            arrivals =
                if edges {
                    let inner = Self::and(wide, interior);
                    Self::expand(layout, inner, Bits::to_felt(inner), unvisited)
                } else {
                    Self::expand(layout, wide, frontier, unvisited)
                };
            unvisited = Self::sub(unvisited, arrivals);
        }
    }

    /// Unit costs: plain breadth-first layers up to the budget.
    fn field_unit(
        layout: @Layout,
        interior: u256,
        edges: bool,
        start: felt252,
        budget: u8,
        unvisited: u256,
        arrivals: u256,
    ) -> felt252 {
        let mut unvisited = Self::sub(unvisited, arrivals);
        let mut arrivals = arrivals;
        let mut time: u8 = 0;
        let mut field = start;
        loop {
            let felt = Bits::to_felt(arrivals);
            field += felt;
            time += 1;
            if time == budget || felt == 0 {
                break field;
            }
            arrivals =
                if edges {
                    let inner = Self::and(arrivals, interior);
                    Self::expand(layout, inner, Bits::to_felt(inner), unvisited)
                } else {
                    Self::expand(layout, arrivals, felt, unvisited)
                };
            unvisited = Self::sub(unvisited, arrivals);
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

    /// Cost of a tile given its one-hot limb: one test for the tiles of cost 1.
    #[inline(always)]
    fn cost(classes: @Classes, bit: u128, high: bool) -> u32 {
        let classes = *classes;
        let (any, upper, odd) = if high {
            (classes.any.high, classes.high.high, classes.odd.high)
        } else {
            (classes.any.low, classes.high.low, classes.odd.low)
        };
        let (hit, _, _) = bitwise(bit, any);
        if hit == 0 {
            return 1;
        }
        if !classes.has_three && !classes.has_four {
            return 2;
        }
        let (hit, _, _) = bitwise(bit, upper);
        if hit == 0 {
            return 2;
        }
        if !classes.has_four {
            return 3;
        }
        let (hit, _, _) = bitwise(bit, odd);
        if hit == 0 {
            3
        } else {
            4
        }
    }

    /// Cost of a tile given its bit.
    #[inline]
    fn cost_of(classes: @Classes, bit: felt252) -> u32 {
        let value: u256 = bit.into();
        if value.low != 0 {
            Self::cost(classes, value.low, false)
        } else {
            Self::cost(classes, value.high, true)
        }
    }

    /// Walk back from the target through the layers.
    /// # Arguments
    /// * `walk` - The backtracking constants
    /// * `classes` - The cost classes
    /// * `weighted` - Whether the costs are not all 1
    /// * `layers` - The settled layers, index = time
    /// * `height` - The height of the map
    /// * `to` - The target
    /// * `to_bit` - `2^to`
    /// * `to_y` - The row of the target
    /// * `to_edge` - Whether the target is an edge tile
    /// * `time` - The time of the layer that schedules the target
    /// # Returns
    /// * The path from the target (included) to the start (excluded)
    fn backtrack(
        walk: Walk,
        classes: Classes,
        weighted: bool,
        layers: Span<u256>,
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
        let width = walk.width;
        // [Compute] First tile: an edge target has no exact neighbour mask, scan its neighbours
        let (mut position, mut bit, mut odd, mut time) = if to_edge {
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
            (found, Bits::pow(found), y % 2 == 1, time)
        } else {
            let arrival = if weighted {
                time + Self::cost_of(@classes, to_bit)
            } else {
                time + 1
            };
            (to, to_bit, to_y % 2 == 1, arrival)
        };
        let mut cost = if weighted {
            Self::cost_of(@classes, bit)
        } else {
            1
        };
        loop {
            let previous = time - cost;
            if previous == 0 {
                break;
            }
            // [Compute] Neighbours settled at `previous`, on the limb that holds them
            let layer = *layers[previous];
            let mask = if odd {
                bit * walk.mask_odd
            } else {
                bit * walk.mask_even
            };
            let (hits, high) = if position < walk.low_limit {
                let (hits, _, _) = bitwise(mask.try_into().unwrap(), layer.low);
                (hits, false)
            } else if position >= walk.high_limit {
                let (hits, _, _) = bitwise((mask * INV_2_128).try_into().unwrap(), layer.high);
                (hits, true)
            } else {
                let mask: u256 = mask.into();
                let (hits, _, _) = bitwise(mask.low, layer.low);
                if hits != 0 {
                    (hits, false)
                } else {
                    let (hits, _, _) = bitwise(mask.high, layer.high);
                    (hits, true)
                }
            };
            // [Compute] Lowest hit
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
                cost = Self::cost(@classes, lowest, high);
            }
            bit = next_bit;
            time = previous;
        }
        path.span()
    }
}
