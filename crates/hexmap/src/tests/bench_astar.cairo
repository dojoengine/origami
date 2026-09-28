//! Lot L2: A* on the hex map, measured against the bit-parallel BFS. No A* formulation beats
//! `Bfs::search` (see `GAS.md`, section L2), so everything here is test-only: one `#[test]` per
//! pair and algorithm, each with an `#[available_gas(l2_gas: N)]` budget (measured + 5 %).
//!
//! `Astar::search` (the best formulation) keeps the open list as three bitmap buckets. The other
//! formulations reuse its expansion with other open lists (binary heap in a `Felt252Dict`, sorted
//! array, unsorted array scanned); `search_greedy` is a greedy best-first search, `search_pruned`
//! the BFS pruned by the hex distance with iterative deepening on the bound. The variants handle
//! interior endpoints only, like the fixtures; `Astar::search` has the full `Bfs::search`
//! contract. Every search is checked against `Bfs::search`.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{
    AddHelper, BoundedInt, ConstrainHelper, DivRemHelper, SubHelper, UnitInt, add, constrain,
    div_rem, sub, upcast,
};

// Internal imports

use origami_hexmap::finders::bfs::{Back, Bfs, BfsInternal, Endpoint};
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::generators::digger::Digger;
use origami_hexmap::generators::mazer::Mazer;
use origami_hexmap::helpers::bits::{Bits, POW128, TWO_POW_128};
use origami_hexmap::helpers::layout::{DilationTrait, LayoutTrait};
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::types::direction::Direction;

// Constants

const DIRECTIONS: [Direction; 6] = [
    Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
    Direction::SouthWest, Direction::SouthEast,
];

// A* with the hex distance as heuristic, open list as bitmap buckets
//
// With unit costs and a consistent heuristic, a neighbour's `f = g + h` is the parent's `f`, plus
// one or plus two: moving one tile changes the hex distance to the target by -1, 0 or +1. Only
// three buckets are live, `f`, `f + 1` and `f + 2`, each a bitmap on two `u128` limbs. The
// neighbours of the expanded tile are split into the three classes by 2 field products (the
// directions that bring it closer and those that take it away depend only on the signs of the
// cube offset to the target), then one AND with the unclosed set per class.
//
// Tie-break towards the smaller heuristic: the neighbours that stay in the bucket `f` (one step
// closer) are expanded first; the rest of the bucket in increasing position. Tiles are closed
// when expanded; a stale copy in a later bucket is dropped when that bucket becomes current. The
// search stops when the target enters the bucket `f`, which is final.
//
// The path is rebuilt from the list of expanded tiles, walked backwards once: a tile popped as a
// closer neighbour of the previous entry follows it, another tile at depth `g` takes the last
// expanded neighbour at depth `g - 1`.
//
// Endpoints follow `Bfs`: only interior tiles are expanded, an open edge tile may be an endpoint.

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Exponent of a power of two below 2^128, indexed by `2^i mod 131` (2 is a primitive root of
/// 131, so the 128 residues are distinct).
const LOG: [u8; 131] = [
    0, 0, 1, 72, 2, 46, 73, 96, 3, 14, 47, 56, 74, 18, 97, 118, 4, 43, 15, 35, 48, 38, 57, 23, 75,
    92, 19, 86, 98, 51, 119, 29, 5, 0, 44, 12, 16, 41, 36, 90, 49, 126, 39, 124, 58, 60, 24, 105,
    76, 62, 93, 115, 20, 26, 87, 102, 99, 107, 52, 82, 120, 78, 30, 110, 6, 64, 0, 71, 45, 95, 13,
    55, 17, 117, 42, 34, 37, 22, 91, 85, 50, 28, 127, 11, 40, 89, 125, 123, 59, 104, 61, 114, 25,
    101, 106, 81, 77, 109, 63, 70, 94, 54, 116, 33, 21, 84, 27, 10, 88, 122, 103, 113, 100, 80, 108,
    69, 53, 32, 83, 9, 121, 112, 79, 68, 31, 8, 111, 67, 7, 66, 65,
];

/// `DivRem` of a limb by 131.
impl DivRemLog of DivRemHelper<u128, UnitInt<131>> {
    type DivT = BoundedInt<0, 0x1f44659e4a427157f05dcd30dadec75>;
    type RemT = BoundedInt<0, 130>;
}

/// `DivRem` of a position by `2W`.
impl DivRemPeriod of DivRemHelper<u8, u8> {
    type DivT = BoundedInt<0, 255>;
    type RemT = BoundedInt<0, 254>;
}

/// Sum of two coordinates.
impl SumAdd of AddHelper<u8, u8> {
    type Result = BoundedInt<0, 510>;
}

/// Axial column offset.
impl DeltaSub of SubHelper<BoundedInt<0, 510>, BoundedInt<0, 510>> {
    type Result = BoundedInt<-510, 510>;
}

/// Sign of the axial column offset.
impl DeltaSign of ConstrainHelper<BoundedInt<-510, 510>, 0> {
    type LowT = BoundedInt<-510, -1>;
    type HighT = BoundedInt<0, 510>;
}

/// Row offset, and column minus width.
impl RowSub of SubHelper<u8, u8> {
    type Result = BoundedInt<-255, 255>;
}

/// Sign of a row offset.
impl RowSign of ConstrainHelper<BoundedInt<-255, 255>, 0> {
    type LowT = BoundedInt<-255, -1>;
    type HighT = BoundedInt<0, 255>;
}

/// `a + b` with `a >= 0` and `b < 0`.
impl MixAdd of AddHelper<BoundedInt<0, 510>, BoundedInt<-255, -1>> {
    type Result = BoundedInt<-255, 509>;
}

/// Sign of `a + b`, `a >= 0`, `b < 0`.
impl MixSign of ConstrainHelper<BoundedInt<-255, 509>, 0> {
    type LowT = BoundedInt<-255, -1>;
    type HighT = BoundedInt<0, 509>;
}

/// `a + b` with `a < 0` and `b >= 0`.
impl MixAddNegative of AddHelper<BoundedInt<-510, -1>, BoundedInt<0, 255>> {
    type Result = BoundedInt<-510, 254>;
}

/// Sign of `a + b`, `a < 0`, `b >= 0`.
impl MixSignNegative of ConstrainHelper<BoundedInt<-510, 254>, 0> {
    type LowT = BoundedInt<-510, -1>;
    type HighT = BoundedInt<0, 254>;
}

/// Constants of a search: the board and the target.
#[derive(Copy, Drop)]
pub(crate) struct Frame {
    pub back: Back,
    /// 2W
    pub period: NonZero<u8>,
    /// Target column.
    pub x: u8,
    /// Target row.
    pub y: u8,
    /// Target half row, `y / 2`.
    pub half: u8,
    /// `128 - (W + 1)`: below it, the neighbours of a low-limb tile stay in the low limb.
    pub low_limit: u8,
}

/// An expanded tile and its neighbours by class.
#[derive(Copy, Drop)]
pub(crate) struct Node {
    pub position: u8,
    /// Whether the row is odd.
    pub odd: bool,
    /// Hex distance to the target.
    pub h: u8,
    /// Neighbour bits one step closer to the target (same `f`).
    pub down: felt252,
    /// Neighbour bits at the same distance (`f + 1`).
    pub same: felt252,
    /// Neighbour bits one step farther (`f + 2`).
    pub up: felt252,
}

/// An expanded tile, as logged for the backtracking.
#[derive(Copy, Drop)]
pub(crate) struct Closed {
    pub position: u8,
    /// Depth, the number of steps from the start.
    pub g: felt252,
    /// Whether the row is odd.
    pub odd: bool,
    /// Whether it was a closer neighbour of the previous entry, its parent.
    pub chained: bool,
}

/// The open buckets and the unclosed tiles, limb by limb.
#[derive(Copy, Drop)]
pub(crate) struct Buckets {
    /// Unclosed tiles.
    pub avail_low: u128,
    pub avail_high: u128,
    /// Closer neighbours of the last expanded tile (bucket `f`, expanded first).
    pub hot_low: u128,
    pub hot_high: u128,
    /// Bucket `f`.
    pub current_low: u128,
    pub current_high: u128,
    /// Bucket `f + 1`.
    pub next_low: u128,
    pub next_high: u128,
    /// Bucket `f + 2`.
    pub after_low: u128,
    pub after_high: u128,
}

/// A bitmap on two limbs.
#[derive(Copy, Drop)]
pub(crate) struct Limbs {
    pub low: u128,
    pub high: u128,
}

#[generate_trait]
pub impl Astar of AstarTrait {
    /// Search the shortest path between two tiles with A*.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    /// # Panics
    /// * If the dimensions are invalid, or an endpoint is outside the board or not walkable
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        let (path, _) = AstarInternal::run(grid, width, height, from, to);
        path
    }
}

#[generate_trait]
pub(crate) impl AstarInternal of AstarInternalTrait {
    /// `search`, with the number of expanded tiles.
    #[inline(always)]
    fn run(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
        // [Check] Dimensions and endpoints
        let open: u256 = BfsInternal::check(grid, width, height, from, to);
        if from == to {
            return (array![].span(), 0);
        }
        // [Compute] Constants and endpoints
        let (frame, free, start, target) = Self::setup(open, width, height, from, to);
        if !start.interior && Bits::get(start.around.into(), to) {
            return (array![to].span(), 0);
        }
        // [Check] Target neighbourhood, empty means unreachable
        let goal = Bits::and(target.around.into(), free);
        if goal.low == 0 && goal.high == 0 {
            return (array![].span(), 0);
        }
        // [Compute] Unclosed tiles: the free interior, the target, not the start
        let mut avail = free;
        if !target.interior {
            avail = (Bits::to_felt(avail) + target.power).into();
        }
        if start.interior {
            avail = (Bits::to_felt(avail) - start.power).into();
        }
        Self::solve(@frame, @start, @target, height, avail)
    }

    /// Board and target constants, the walkable interior tiles and the endpoints.
    #[inline]
    fn setup(
        open: u256, width: u8, height: u8, from: u8, to: u8,
    ) -> (Frame, u256, Endpoint, Endpoint) {
        let (layout, interior) = LayoutTrait::with_interior(width, height);
        let back = BfsInternal::back_constants(width, layout.up_even, layout.down_even);
        let start = BfsInternal::endpoint(@back, height, from);
        let target = BfsInternal::endpoint(@back, height, to);
        let period: NonZero<u8> = (2 * width).try_into().unwrap();
        let frame = Frame {
            back, period, x: target.x, y: target.y, half: target.half, low_limit: 127 - width,
        };
        (frame, Bits::and(open, interior.into()), start, target)
    }

    /// The A* loop once the endpoints are known.
    /// # Arguments
    /// * `frame` - The constants
    /// * `start` - The start
    /// * `target` - The target
    /// * `height` - The height of the map
    /// * `avail` - The unclosed tiles: walkable interior tiles and the target, not the start
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable, and
    /// the number of expanded tiles
    #[inline(always)]
    fn solve(
        frame: @Frame, start: @Endpoint, target: @Endpoint, height: u8, avail: u256,
    ) -> (Span<u8>, u32) {
        let mut log: Array<Closed> = array![];
        // [Compute] Expand the start
        let gap = BfsInternal::gap(start, target);
        let mut f: felt252 = gap.into();
        let to = *target.position;
        let (goal_high, goal_bit) = Self::split(*target.power);
        let node = if *start.interior {
            Self::node(frame, *start.position, *start.power)
        } else {
            Self::edge_node(frame, height, start, gap)
        };
        log.append(Closed { position: *start.position, g: 0, odd: *start.odd, chained: false });
        let down: u256 = node.down.into();
        if node.h == 1 {
            let limb = if goal_high {
                down.high
            } else {
                down.low
            };
            let (hit, _, _) = Bits::bitwise(limb, goal_bit);
            if hit != 0 {
                return (array![to].span(), 1);
            }
        }
        let same: u256 = node.same.into();
        let up: u256 = node.up.into();
        let (hot_low, _, _) = Bits::bitwise(down.low, avail.low);
        let (hot_high, _, _) = Bits::bitwise(down.high, avail.high);
        let (next_low, _, _) = Bits::bitwise(same.low, avail.low);
        let (next_high, _, _) = Bits::bitwise(same.high, avail.high);
        let (after_low, _, _) = Bits::bitwise(up.low, avail.low);
        let (after_high, _, _) = Bits::bitwise(up.high, avail.high);
        let mut buckets = Buckets {
            avail_low: avail.low,
            avail_high: avail.high,
            hot_low,
            hot_high,
            current_low: 0,
            current_high: 0,
            next_low,
            next_high,
            after_low,
            after_high,
        };
        // [Compute] Pop the best tile, expand it, until the target enters the bucket `f`
        let boxed = BoxTrait::new(*frame);
        let outcome = loop {
            let outcome = Self::step(boxed, goal_high, goal_bit, ref buckets, ref f, ref log);
            if outcome != 0 {
                break outcome;
            }
            let outcome = Self::step(boxed, goal_high, goal_bit, ref buckets, ref f, ref log);
            if outcome != 0 {
                break outcome;
            }
        };
        let count = log.len();
        if outcome == 2 {
            return (array![].span(), count);
        }
        // [Return] Backtrack through the expanded tiles
        (Self::backtrack(frame, to, f, log), count)
    }

    /// One step: pop the best tile (a closer neighbour of the last one first, then the bucket
    /// `f`, then the next buckets), close it, expand it and log it.
    /// # Returns
    /// * 0 to go on, 1 when the target is reached, 2 when the buckets are empty
    #[inline(always)]
    fn step(
        frame: Box<Frame>,
        goal_high: bool,
        goal_bit: u128,
        ref buckets: Buckets,
        ref f: felt252,
        ref log: Array<Closed>,
    ) -> u8 {
        let (high, bit, chained) = if buckets.hot_low != 0 {
            let hot = buckets.hot_low;
            let (rest, _, _) = Bits::bitwise(hot, hot - 1);
            buckets.hot_low = rest;
            (false, hot - rest, true)
        } else if buckets.hot_high != 0 {
            let hot = buckets.hot_high;
            let (rest, _, _) = Bits::bitwise(hot, hot - 1);
            buckets.hot_high = rest;
            (true, hot - rest, true)
        } else {
            if buckets.current_low == 0 && buckets.current_high == 0 {
                // [Compute] Rotate the buckets, dropping the closed tiles
                loop {
                    if buckets.next_low == 0
                        && buckets.next_high == 0
                        && buckets.after_low == 0
                        && buckets.after_high == 0 {
                        return 2;
                    }
                    let (low, _, _) = Bits::bitwise(buckets.next_low, buckets.avail_low);
                    let (high, _, _) = Bits::bitwise(buckets.next_high, buckets.avail_high);
                    buckets.current_low = low;
                    buckets.current_high = high;
                    buckets.next_low = buckets.after_low;
                    buckets.next_high = buckets.after_high;
                    buckets.after_low = 0;
                    buckets.after_high = 0;
                    f += 1;
                    if low != 0 || high != 0 {
                        break;
                    }
                }
            }
            if buckets.current_low != 0 {
                let current = buckets.current_low;
                let (rest, _, _) = Bits::bitwise(current, current - 1);
                buckets.current_low = rest;
                (false, current - rest, false)
            } else {
                let current = buckets.current_high;
                let (rest, _, _) = Bits::bitwise(current, current - 1);
                buckets.current_high = rest;
                (true, current - rest, false)
            }
        };
        // [Effect] Close it, expand it and log it
        if high {
            buckets.avail_high -= bit;
        } else {
            buckets.avail_low -= bit;
        }
        let (position, odd, h, reached) = Self::expand(
            frame, high, bit, goal_high, goal_bit, ref buckets,
        );
        log.append(Closed { position, g: f - h, odd, chained });
        if reached {
            1
        } else {
            0
        }
    }

    /// Expand a popped tile: classify its neighbours and push them into the buckets, on the limb
    /// that holds them when there is one.
    /// # Returns
    /// * The position, its row parity, its hex distance to the target, and whether the target
    /// is one of its closer neighbours (nothing pushed then)
    #[inline(always)]
    fn expand(
        frame: Box<Frame>,
        high: bool,
        bit: u128,
        goal_high: bool,
        goal_bit: u128,
        ref buckets: Buckets,
    ) -> (u8, bool, felt252, bool) {
        let frame = frame.unbox();
        let back = frame.back;
        let width = back.width;
        // [Compute] Position and coordinates
        let local = Self::log2(bit);
        let position = if high {
            local + 128
        } else {
            local
        };
        let (half, x, y, odd) = Self::coords(position, width, frame.period);
        let (around, nw, ne, sw, se) = if odd {
            (back.around_odd, back.up_odd, back.up_wide, back.down_odd, back.down_wide)
        } else {
            (back.around_even, back.up_even, back.up_odd, back.down_even, back.down_odd)
        };
        let (h, down, up) = Self::classes_bounded(frame, x, y, half, nw, ne, sw, se);
        let same = around - down - up;
        // [Compute] Merge the previous closer neighbours into the bucket
        let (_, _, merged) = Bits::bitwise(buckets.current_low, buckets.hot_low);
        buckets.current_low = merged;
        let (_, _, merged) = Bits::bitwise(buckets.current_high, buckets.hot_high);
        buckets.current_high = merged;
        let unit: felt252 = bit.into();
        if !high && local < frame.low_limit {
            // [Compute] Neighbourhood in the low limb
            let down: u128 = (unit * down).try_into().unwrap();
            if h == 1 && !goal_high {
                let (hit, _, _) = Bits::bitwise(down, goal_bit);
                if hit != 0 {
                    return (position, odd, h, true);
                }
            }
            buckets.hot_high = 0;
            let (hot, next, after) = Self::push_limb(
                down,
                (unit * same).try_into().unwrap(),
                (unit * up).try_into().unwrap(),
                buckets.avail_low,
                buckets.current_low,
                buckets.next_low,
                buckets.after_low,
            );
            buckets.hot_low = hot;
            buckets.next_low = next;
            buckets.after_low = after;
        } else if high && local >= back.wide {
            // [Compute] Neighbourhood in the high limb
            let down: u128 = (unit * down).try_into().unwrap();
            if h == 1 && goal_high {
                let (hit, _, _) = Bits::bitwise(down, goal_bit);
                if hit != 0 {
                    return (position, odd, h, true);
                }
            }
            buckets.hot_low = 0;
            let (hot, next, after) = Self::push_limb(
                down,
                (unit * same).try_into().unwrap(),
                (unit * up).try_into().unwrap(),
                buckets.avail_high,
                buckets.current_high,
                buckets.next_high,
                buckets.after_high,
            );
            buckets.hot_high = hot;
            buckets.next_high = next;
            buckets.after_high = after;
        } else {
            // [Compute] Neighbourhood across the limbs
            let power = if high {
                unit * TWO_POW_128
            } else {
                unit
            };
            let down: u256 = (power * down).into();
            if h == 1 {
                let limb = if goal_high {
                    down.high
                } else {
                    down.low
                };
                let (hit, _, _) = Bits::bitwise(limb, goal_bit);
                if hit != 0 {
                    return (position, odd, h, true);
                }
            }
            let same: u256 = (power * same).into();
            let up: u256 = (power * up).into();
            let (hot, next, after) = Self::push_limb(
                down.low,
                same.low,
                up.low,
                buckets.avail_low,
                buckets.current_low,
                buckets.next_low,
                buckets.after_low,
            );
            buckets.hot_low = hot;
            buckets.next_low = next;
            buckets.after_low = after;
            let (hot, next, after) = Self::push_limb(
                down.high,
                same.high,
                up.high,
                buckets.avail_high,
                buckets.current_high,
                buckets.next_high,
                buckets.after_high,
            );
            buckets.hot_high = hot;
            buckets.next_high = next;
            buckets.after_high = after;
        }
        (position, odd, h, false)
    }

    /// Push the classes of one limb, the previous closer neighbours already merged.
    /// # Returns
    /// * The new closer neighbours, the buckets `f + 1` and `f + 2`
    #[inline(always)]
    fn push_limb(
        down: u128, same: u128, up: u128, avail: u128, current: u128, next: u128, after: u128,
    ) -> (u128, u128, u128) {
        let (hot, _, _) = Bits::bitwise(down, avail - current);
        let (same, _, _) = Bits::bitwise(same, avail);
        let (_, _, next) = Bits::bitwise(next, same);
        let (up, _, _) = Bits::bitwise(up, avail);
        let (_, _, after) = Bits::bitwise(after, up);
        (hot, next, after)
    }

    /// Half row, column, row and row parity of a position, one `bounded_int` division by `2W`.
    #[feature("bounded-int-utils")]
    #[inline(always)]
    fn coords(position: u8, width: u8, period: NonZero<u8>) -> (u8, u8, u8, bool) {
        let (half, rem) = div_rem::<_, _, DivRemPeriod>(position, period);
        let half: u8 = upcast(half);
        let rem: u8 = upcast(rem);
        let double: felt252 = half.into() + half.into();
        match constrain::<_, 0, RowSign>(sub::<_, _, RowSub>(rem, width)) {
            Ok(_) => (half, rem, double.try_into().unwrap(), false),
            Err(x) => (half, upcast(x), (double + 1).try_into().unwrap(), true),
        }
    }

    /// `classes` with `bounded_int` sums, differences and sign tests: the hex distance as a felt.
    #[feature("bounded-int-utils")]
    #[inline(always)]
    fn classes_bounded(
        frame: Frame, x: u8, y: u8, half: u8, nw: felt252, ne: felt252, sw: felt252, se: felt252,
    ) -> (felt252, felt252, felt252) {
        // [Compute] a = (tx + y / 2) - (x + ty / 2), b = ty - y
        let lhs = add::<_, _, SumAdd>(frame.x, half);
        let rhs = add::<_, _, SumAdd>(x, frame.half);
        let a = sub::<_, _, DeltaSub>(lhs, rhs);
        let b = sub::<_, _, RowSub>(frame.y, y);
        let a_felt: felt252 = upcast(a);
        let b_felt: felt252 = upcast(b);
        match constrain::<_, 0, DeltaSign>(a) {
            Err(positive) => {
                if a_felt == 0 {
                    match constrain::<_, 0, RowSign>(b) {
                        Err(_) => (b_felt, ne, INV_2 + sw + se),
                        Ok(_) => (-b_felt, sw, 2 + nw + ne),
                    }
                } else {
                    match constrain::<_, 0, RowSign>(b) {
                        Err(_) => if b_felt == 0 {
                            (a_felt, 2, INV_2 + nw + sw)
                        } else {
                            (a_felt + b_felt, 2 + ne, INV_2 + sw)
                        },
                        Ok(negative) => {
                            let sum = add::<_, _, MixAdd>(positive, negative);
                            let sum_felt: felt252 = upcast(sum);
                            match constrain::<_, 0, MixSign>(sum) {
                                Ok(_) => (-b_felt, se + sw, nw + ne),
                                Err(_) => if sum_felt == 0 {
                                    (a_felt, se, INV_2 + nw + ne)
                                } else {
                                    (a_felt, 2 + se, INV_2 + nw)
                                },
                            }
                        },
                    }
                }
            },
            Ok(negative) => {
                match constrain::<_, 0, RowSign>(b) {
                    Ok(_) => (-a_felt - b_felt, INV_2 + sw, 2 + ne),
                    Err(positive) => {
                        if b_felt == 0 {
                            return (-a_felt, INV_2, 2 + se + ne);
                        }
                        let sum = add::<_, _, MixAddNegative>(negative, positive);
                        let sum_felt: felt252 = upcast(sum);
                        match constrain::<_, 0, MixSignNegative>(sum) {
                            Ok(_) => (-a_felt, INV_2 + nw, 2 + se),
                            Err(_) => if sum_felt == 0 {
                                (b_felt, nw, 2 + se + sw)
                            } else {
                                (b_felt, nw + ne, sw + se)
                            },
                        }
                    },
                }
            },
        }
    }

    /// Exponent of a one-hot limb: its residue modulo 131 in the `LOG` table.
    #[feature("bounded-int-utils")]
    #[inline(always)]
    fn log2(bit: u128) -> u8 {
        let (_, rem) = div_rem::<_, _, DivRemLog>(bit, 131);
        *LOG.span().at(upcast(rem))
    }

    /// Split a one-hot felt into its limb and bit.
    #[inline(always)]
    fn split(power: felt252) -> (bool, u128) {
        let wide: u256 = power.into();
        if wide.high == 0 {
            (false, wide.low)
        } else {
            (true, wide.high)
        }
    }

    /// Pop the lowest tile of a bucket.
    /// # Returns
    /// * Whether it is on the high limb, and its bit on that limb
    #[inline(always)]
    fn pop(ref bucket: Limbs) -> (bool, u128) {
        if bucket.low != 0 {
            let low = bucket.low;
            let (rest, _, _) = Bits::bitwise(low, low - 1);
            bucket.low = rest;
            (false, low - rest)
        } else {
            let high = bucket.high;
            let (rest, _, _) = Bits::bitwise(high, high - 1);
            bucket.high = rest;
            (true, high - rest)
        }
    }

    /// Position and power of a one-hot limb bit: its residue modulo 131 in the `LOG` table.
    #[feature("bounded-int-utils")]
    #[inline(always)]
    fn locate(high: bool, bit: u128) -> (u8, felt252) {
        let (_, rem) = div_rem::<_, _, DivRemLog>(bit, 131);
        let index: u8 = *LOG.span().at(upcast(rem));
        if high {
            (index + 128, bit.into() * TWO_POW_128)
        } else {
            (index, bit.into())
        }
    }

    /// Describe an interior tile: coordinates, hex distance to the target and neighbour classes.
    /// A direction brings the tile closer iff the two cube components it changes have its signs;
    /// it takes it away iff it grows a component of maximal absolute value.
    /// # Arguments
    /// * `frame` - The constants
    /// * `position` - The tile, interior, not the target
    /// * `power` - 2^position
    /// # Returns
    /// * The node
    #[inline(always)]
    fn node(frame: @Frame, position: u8, power: felt252) -> Node {
        let frame = *frame;
        let back = frame.back;
        let (half, x, y, odd) = Self::coords(position, back.width, frame.period);
        // [Compute] Offsets of the 6 directions: East 2, West 1/2, then NW, NE, SW, SE
        let (around, nw, ne, sw, se) = if odd {
            (back.around_odd, back.up_odd, back.up_wide, back.down_odd, back.down_wide)
        } else {
            (back.around_even, back.up_even, back.up_odd, back.down_even, back.down_odd)
        };
        let (h, down, up) = Self::classes_bounded(frame, x, y, half, nw, ne, sw, se);
        Node {
            position,
            odd,
            h: h.try_into().unwrap(),
            down: power * down,
            same: power * (around - down - up),
            up: power * up,
        }
    }

    /// Hex distance to the target and the offsets of the closer and farther directions, with
    /// checked `u8` operations (loser of `classes_bounded`, see `bench_astar_micro_*`).
    /// Axial directions: East (+1, 0), West (-1, 0), NW (-1, +1), NE (0, +1), SW (0, -1),
    /// SE (+1, -1), with `q = x - y / 2`, `r = y`.
    #[inline(always)]
    fn classes(
        frame: Frame, x: u8, y: u8, half: u8, nw: felt252, ne: felt252, sw: felt252, se: felt252,
    ) -> (u8, felt252, felt252) {
        let lhs = frame.x + half;
        let rhs = x + frame.half;
        let ty = frame.y;
        if lhs > rhs {
            let a = lhs - rhs;
            if ty > y {
                // a > 0, b > 0: s is the maximum
                (a + ty - y, 2 + ne, INV_2 + sw)
            } else if ty < y {
                let b = y - ty;
                if a > b {
                    (a, 2 + se, INV_2 + nw)
                } else if a < b {
                    (b, se + sw, nw + ne)
                } else {
                    (a, se, INV_2 + nw + ne)
                }
            } else {
                (a, 2, INV_2 + nw + sw)
            }
        } else if lhs < rhs {
            let a = rhs - lhs;
            if ty < y {
                // a < 0, b < 0: s is the maximum
                (a + y - ty, INV_2 + sw, 2 + ne)
            } else if ty > y {
                let b = ty - y;
                if a > b {
                    (a, INV_2 + nw, 2 + se)
                } else if a < b {
                    (b, nw + ne, sw + se)
                } else {
                    (a, nw, 2 + se + sw)
                }
            } else {
                (a, INV_2, 2 + se + ne)
            }
        } else if ty > y {
            (ty - y, ne, INV_2 + sw + se)
        } else {
            (y - ty, sw, 2 + nw + ne)
        }
    }

    /// Node of an edge start: its board neighbours classified one by one.
    #[inline(never)]
    fn edge_node(frame: @Frame, height: u8, start: @Endpoint, h: u8) -> Node {
        let width = (*frame).back.width;
        let target = Endpoint {
            position: 0,
            power: 0,
            interior: true,
            odd: false,
            x: *frame.x,
            y: *frame.y,
            half: *frame.half,
            around: 0,
        };
        let mut down: felt252 = 0;
        let mut same: felt252 = 0;
        let mut up: felt252 = 0;
        for direction in DIRECTIONS.span() {
            if let Option::Some(next) =
                LayoutTrait::neighbor(width, height, *start.position, *direction) {
                let tile = BfsInternal::endpoint(frame.back, height, next);
                let distance = BfsInternal::gap(@tile, @target);
                if distance < h {
                    down += tile.power;
                } else if distance == h {
                    same += tile.power;
                } else {
                    up += tile.power;
                }
            }
        }
        Node { position: *start.position, odd: *start.odd, h, down, same, up }
    }

    /// Rebuild the path from the expanded tiles, walked backwards once: a tile popped as a closer
    /// neighbour of the previous entry follows it, the others take the last expanded neighbour at
    /// depth `g - 1`.
    /// # Arguments
    /// * `frame` - The constants
    /// * `to` - The target
    /// * `f` - The path length
    /// * `log` - The expanded tiles, the one that reached the target last, at depth `f - 1`
    /// # Returns
    /// * The path from the target (included) to the start (excluded)
    #[inline(always)]
    fn backtrack(frame: @Frame, to: u8, f: felt252, log: Array<Closed>) -> Span<u8> {
        let mut path: Array<u8> = array![to];
        let mut g = f - 1;
        if g == 0 {
            return path.span();
        }
        let width = (*frame).back.width;
        let narrow = (*frame).back.narrow;
        let wide = (*frame).back.wide;
        let mut log = log.span();
        let last = *log.pop_back().unwrap();
        let mut position = last.position;
        let mut odd = last.odd;
        let mut chained = last.chained;
        path.append(position);
        while g != 1 {
            let entry = *log.pop_back().unwrap();
            // [Check] A chained tile follows its parent, others scan for a neighbour at g - 1
            if !chained {
                if entry.g + 1 != g {
                    continue;
                }
                if !Self::adjacent(position, odd, entry.position, width, narrow, wide) {
                    continue;
                }
            }
            position = entry.position;
            odd = entry.odd;
            chained = entry.chained;
            g -= 1;
            path.append(position);
        }
        path.span()
    }

    /// Whether `other` is a neighbour of the interior tile `position`.
    #[inline(always)]
    fn adjacent(position: u8, odd: bool, other: u8, width: u8, narrow: u8, wide: u8) -> bool {
        if other > position {
            let delta = other - position;
            if odd {
                delta == 1 || delta == width || delta == wide
            } else {
                delta == 1 || delta == narrow || delta == width
            }
        } else {
            let delta = position - other;
            if odd {
                delta == 1 || delta == width || delta == narrow
            } else {
                delta == 1 || delta == wide || delta == width
            }
        }
    }
}

// Extra pairs: hex distance 1, 2, 5 and 10 from the centre of EMPTY and from a cave tile
// (BFS length in parentheses).

/// EMPTY 17x14, 110 -> 111 (1).
pub const EMPTY_D1_FROM: u8 = 110;
pub const EMPTY_D1_TO: u8 = 111;
pub const EMPTY_D1_DISTANCE: u32 = 1;
/// CAVE 17x14, 104 -> 105 (1).
pub const CAVE_D1_FROM: u8 = 104;
pub const CAVE_D1_TO: u8 = 105;
pub const CAVE_D1_DISTANCE: u32 = 1;

/// EMPTY 17x14, 110 -> 145 (2).
pub const EMPTY_D2_FROM: u8 = 110;
pub const EMPTY_D2_TO: u8 = 145;
pub const EMPTY_D2_DISTANCE: u32 = 2;
/// EMPTY 17x14, 110 -> 157 (5).
pub const EMPTY_D5_FROM: u8 = 110;
pub const EMPTY_D5_TO: u8 = 157;
pub const EMPTY_D5_DISTANCE: u32 = 5;
/// EMPTY 17x14, 110 -> 205 (10).
pub const EMPTY_D10_FROM: u8 = 110;
pub const EMPTY_D10_TO: u8 = 205;
pub const EMPTY_D10_DISTANCE: u32 = 10;
/// CAVE 17x14, 104 -> 71 (2).
pub const CAVE_D2_FROM: u8 = 104;
pub const CAVE_D2_TO: u8 = 71;
pub const CAVE_D2_DISTANCE: u32 = 2;
/// CAVE 17x14, 104 -> 109 (7, a wall between).
pub const CAVE_D5_FROM: u8 = 104;
pub const CAVE_D5_TO: u8 = 109;
pub const CAVE_D5_DISTANCE: u32 = 7;
/// CAVE 17x14, 104 -> 96 (12, a wall between).
pub const CAVE_D10_FROM: u8 = 104;
pub const CAVE_D10_TO: u8 = 96;
pub const CAVE_D10_DISTANCE: u32 = 12;

// Shared pieces of the variants

/// Library setup for interior endpoints: constants, the unclosed tiles (the start closed), the
/// start node and the limb of the target.
fn prologue(
    grid: felt252, width: u8, height: u8, from: u8, to: u8,
) -> (Frame, Endpoint, Endpoint, Limbs, bool, u128) {
    let open = BfsInternal::check(grid, width, height, from, to);
    let (frame, free, start, target) = AstarInternal::setup(open, width, height, from, to);
    let avail: u256 = (Bits::to_felt(free) - start.power).into();
    let (target_high, target_bit) = AstarInternal::split(target.power);
    (frame, start, target, Limbs { low: avail.low, high: avail.high }, target_high, target_bit)
}

/// Whether the closer neighbours of a node hold the target.
#[inline(always)]
fn reaches(node: @Node, target_high: bool, target_bit: u128) -> bool {
    if *node.h != 1 {
        return false;
    }
    let down: u256 = (*node.down).into();
    let limb = if target_high {
        down.high
    } else {
        down.low
    };
    let (hit, _, _) = Bits::bitwise(limb, target_bit);
    hit != 0
}

/// Limb and bit of a position.
#[inline(always)]
fn bit_of(position: u8) -> (bool, u128) {
    if position < 128 {
        (false, *POW128.span().at(position.into()))
    } else {
        (true, *POW128.span().at(position.into() - 128))
    }
}

// Variants: open lists of explicit entries (lazy deletion)

/// An open list of `u32` keys, smallest first.
trait Queue<Q> {
    fn put(ref self: Q, key: u32);
    fn take(ref self: Q) -> Option<u32>;
}

/// Key of an entry: `f`, then `h` (tie-break), then the position.
#[inline(always)]
fn key(f: u8, h: u8, position: u8) -> u32 {
    let f: u32 = f.into();
    let h: u32 = h.into();
    f * 0x10000 + h * 0x100 + position.into()
}

/// Push every unclosed tile of a class.
#[inline]
fn put_class<Q, +Queue<Q>, +Destruct<Q>>(ref queue: Q, class: felt252, avail: Limbs, f: u8, h: u8) {
    let wide: u256 = class.into();
    let (low, _, _) = Bits::bitwise(wide.low, avail.low);
    let (high, _, _) = Bits::bitwise(wide.high, avail.high);
    let mut bucket = Limbs { low, high };
    while bucket.low != 0 || bucket.high != 0 {
        let (high, bit) = AstarInternal::pop(ref bucket);
        let (position, _) = AstarInternal::locate(high, bit);
        queue.put(key(f, h, position));
    }
}

/// Push the three classes of a node at `f`.
#[inline]
fn put_node<Q, +Queue<Q>, +Destruct<Q>>(ref queue: Q, node: @Node, avail: Limbs, f: u8) {
    let h = *node.h;
    put_class(ref queue, *node.down, avail, f, h - 1);
    put_class(ref queue, *node.same, avail, f + 1, h);
    put_class(ref queue, *node.up, avail, f + 2, h + 1);
}

/// A* with an open list of entries, stale entries skipped when popped.
fn search_queue<Q, +Queue<Q>, +Destruct<Q>>(
    grid: felt252, width: u8, height: u8, from: u8, to: u8, ref queue: Q, ref count: u32,
) -> Span<u8> {
    let (frame, start, target, mut avail, target_high, target_bit) = prologue(
        grid, width, height, from, to,
    );
    let mut f = BfsInternal::gap(@start, @target);
    let mut last = AstarInternal::node(@frame, from, start.power);
    let mut log: Array<Closed> = array![
        Closed { position: from, g: 0, odd: start.odd, chained: false },
    ];
    count += 1;
    if reaches(@last, target_high, target_bit) {
        return array![to].span();
    }
    put_node(ref queue, @last, avail, f);
    loop {
        let entry = match queue.take() {
            Option::Some(entry) => entry,
            Option::None => { return array![].span(); },
        };
        let (rest, position) = DivRem::div_rem(entry, 0x100);
        let (entry_f, entry_h) = DivRem::div_rem(rest, 0x100);
        let position: u8 = position.try_into().unwrap();
        // [Check] Stale entry
        let (high, bit) = bit_of(position);
        let limb = if high {
            avail.high
        } else {
            avail.low
        };
        let (hit, _, _) = Bits::bitwise(limb, bit);
        if hit == 0 {
            continue;
        }
        // [Effect] Close and expand
        let power: felt252 = if high {
            avail.high -= bit;
            bit.into() * TWO_POW_128
        } else {
            avail.low -= bit;
            bit.into()
        };
        f = entry_f.try_into().unwrap();
        let entry_h: u8 = entry_h.try_into().unwrap();
        let node = AstarInternal::node(@frame, position, power);
        log.append(Closed { position, g: (f - entry_h).into(), odd: node.odd, chained: false });
        count += 1;
        last = node;
        if reaches(@node, target_high, target_bit) {
            break;
        }
        put_node(ref queue, @node, avail, f);
    }
    AstarInternal::backtrack(@frame, to, f.into(), log)
}

/// Binary heap in a dictionary.
#[derive(Destruct)]
struct DictHeap {
    items: Felt252Dict<u32>,
    size: u32,
}

impl DictHeapQueue of Queue<DictHeap> {
    fn put(ref self: DictHeap, key: u32) {
        let mut index = self.size;
        self.size += 1;
        while index != 0 {
            let parent = (index - 1) / 2;
            let above = self.items.get(parent.into());
            if above <= key {
                break;
            }
            self.items.insert(index.into(), above);
            index = parent;
        }
        self.items.insert(index.into(), key);
    }

    fn take(ref self: DictHeap) -> Option<u32> {
        if self.size == 0 {
            return Option::None;
        }
        let top = self.items.get(0);
        self.size -= 1;
        let size = self.size;
        if size == 0 {
            return Option::Some(top);
        }
        let last = self.items.get(size.into());
        let mut index: u32 = 0;
        loop {
            let left = 2 * index + 1;
            if left >= size {
                break;
            }
            let mut child = left;
            let mut below = self.items.get(left.into());
            if left + 1 < size {
                let right = self.items.get((left + 1).into());
                if right < below {
                    child = left + 1;
                    below = right;
                }
            }
            if below >= last {
                break;
            }
            self.items.insert(index.into(), below);
            index = child;
        }
        self.items.insert(index.into(), last);
        Option::Some(top)
    }
}

fn search_dict_heap(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    let mut queue = DictHeap { items: Default::default(), size: 0 };
    let mut count: u32 = 0;
    let path = search_queue(grid, width, height, from, to, ref queue, ref count);
    (path, count)
}

/// Array sorted in decreasing order, the smallest key last: one copy per insertion.
#[derive(Drop)]
struct Sorted {
    items: Span<u32>,
}

impl SortedQueue of Queue<Sorted> {
    fn put(ref self: Sorted, key: u32) {
        let mut items: Array<u32> = array![];
        let mut rest = self.items;
        loop {
            match rest.pop_front() {
                Option::Some(item) => {
                    if *item <= key {
                        items.append(key);
                        items.append(*item);
                        items.append_span(rest);
                        break;
                    }
                    items.append(*item);
                },
                Option::None => {
                    items.append(key);
                    break;
                },
            }
        }
        self.items = items.span();
    }

    fn take(ref self: Sorted) -> Option<u32> {
        match self.items.pop_back() {
            Option::Some(item) => Option::Some(*item),
            Option::None => Option::None,
        }
    }
}

fn search_sorted(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    let mut queue = Sorted { items: array![].span() };
    let mut count: u32 = 0;
    let path = search_queue(grid, width, height, from, to, ref queue, ref count);
    (path, count)
}

/// Unsorted array, scanned for the smallest key and rebuilt without it.
#[derive(Drop)]
struct Scan {
    items: Array<u32>,
}

impl ScanQueue of Queue<Scan> {
    fn put(ref self: Scan, key: u32) {
        self.items.append(key);
    }

    fn take(ref self: Scan) -> Option<u32> {
        let items = self.items.span();
        if items.len() == 0 {
            return Option::None;
        }
        let mut best = *items[0];
        let mut index: u32 = 0;
        let mut at: u32 = 1;
        while at != items.len() {
            let item = *items[at];
            if item < best {
                best = item;
                index = at;
            }
            at += 1;
        }
        let mut rest: Array<u32> = array![];
        rest.append_span(items.slice(0, index));
        rest.append_span(items.slice(index + 1, items.len() - index - 1));
        self.items = rest;
        Option::Some(best)
    }
}

fn search_scan(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    let mut queue = Scan { items: array![] };
    let mut count: u32 = 0;
    let path = search_queue(grid, width, height, from, to, ref queue, ref count);
    (path, count)
}

/// Library A*, counting the expanded tiles.
fn search_bucket(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    AstarInternal::run(grid, width, height, from, to)
}

// Variant: greedy best-first (not shortest), buckets by `h` in a dictionary

fn search_greedy(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    let (frame, _, _, mut unseen, target_high, target_bit) = prologue(
        grid, width, height, from, to,
    );
    let start = AstarInternal::node(@frame, from, Bits::pow(from));
    let mut last = start;
    let mut log: Array<Closed> = array![
        Closed { position: from, g: 0, odd: start.odd, chained: false },
    ];
    let mut count: u32 = 1;
    let mut buckets: Felt252Dict<felt252> = Default::default();
    let mut cursor: u8 = start.h;
    let mut top: u8 = start.h;
    let mut node = start;
    loop {
        if reaches(@node, target_high, target_bit) {
            break;
        }
        // [Compute] Push the unseen neighbours by distance to the target
        let h = node.h;
        let down = greedy_class(ref buckets, ref unseen, node.down, h - 1);
        greedy_class(ref buckets, ref unseen, node.same, h);
        if greedy_class(ref buckets, ref unseen, node.up, h + 1) && h + 1 > top {
            top = h + 1;
        }
        if down {
            cursor = h - 1;
        }
        // [Compute] Lowest non-empty bucket
        let mut bucket = buckets.get(cursor.into());
        while bucket == 0 && cursor < top {
            cursor += 1;
            bucket = buckets.get(cursor.into());
        }
        if bucket == 0 {
            return (array![].span(), count);
        }
        let wide: u256 = bucket.into();
        let mut limbs = Limbs { low: wide.low, high: wide.high };
        let (high, bit) = AstarInternal::pop(ref limbs);
        let (position, power) = AstarInternal::locate(high, bit);
        buckets.insert(cursor.into(), bucket - power);
        node = AstarInternal::node(@frame, position, power);
        log.append(Closed { position, g: 0, odd: node.odd, chained: false });
        count += 1;
        last = node;
    }
    (backtrack_any(@frame, to, last, log), count)
}

/// Add the unseen tiles of a class to the bucket `h`.
#[inline(always)]
fn greedy_class(
    ref buckets: Felt252Dict<felt252>, ref unseen: Limbs, class: felt252, h: u8,
) -> bool {
    let wide: u256 = class.into();
    let (low, _, _) = Bits::bitwise(wide.low, unseen.low);
    let (high, _, _) = Bits::bitwise(wide.high, unseen.high);
    if low == 0 && high == 0 {
        return false;
    }
    unseen.low -= low;
    unseen.high -= high;
    let bucket = buckets.get(h.into());
    buckets.insert(h.into(), bucket + low.into() + high.into() * TWO_POW_128);
    true
}

/// Path through the expanded tiles: the last expanded neighbour, down to the start.
fn backtrack_any(frame: @Frame, to: u8, last: Node, log: Array<Closed>) -> Span<u8> {
    let mut path: Array<u8> = array![to];
    let mut log = log.span();
    let _ = log.pop_back();
    if log.len() == 0 {
        return path.span();
    }
    let width = (*frame).back.width;
    let narrow = (*frame).back.narrow;
    let wide = (*frame).back.wide;
    let from = *log[0].position;
    let mut position = last.position;
    let mut odd = last.odd;
    path.append(position);
    while !AstarInternal::adjacent(position, odd, from, width, narrow, wide) {
        let entry = *log.pop_back().unwrap();
        if AstarInternal::adjacent(position, odd, entry.position, width, narrow, wide) {
            position = entry.position;
            odd = entry.odd;
            path.append(position);
        }
    }
    path.span()
}

// Variant: BFS pruned by the hex distance, iterative deepening on the bound

/// Layers restricted to `layer + distance(tile, target) <= bound`, `bound` from the hex distance
/// up. The balls around the target come from dilations of the target on the empty interior.
fn search_pruned(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (Span<u8>, u32) {
    let open = BfsInternal::check(grid, width, height, from, to);
    let (step, back, free) = BfsInternal::constants(open, width, height);
    let start = BfsInternal::endpoint(@back, height, from);
    let target = BfsInternal::endpoint(@back, height, to);
    let goal = Bits::and(target.around.into(), free);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    let first = Bits::and((start.around + start.power).into(), free);
    // [Compute] Balls of radius 0 and 1
    let centre: u256 = target.power.into();
    let mut balls: Array<u256> = array![centre];
    let (low, high) = step.dilate(centre.low, centre.high, target.power);
    let mut ball = Bits::and(u256 { low, high }, interior);
    balls.append(ball);
    let mut bound = BfsInternal::gap(@start, @target);
    let mut rounds: u32 = 0;
    loop {
        rounds += 1;
        // [Compute] Balls up to the bound
        while balls.len() <= bound.into() {
            let (low, high) = step.dilate(ball.low, ball.high, Bits::to_felt(ball));
            ball = Bits::and(u256 { low, high }, interior);
            balls.append(ball);
        }
        let masks = balls.span();
        // [Compute] Restricted layers, the first one at distance 1
        let mut layers: Array<u256> = array![];
        let mut layer = Bits::and(first, *masks[(bound - 1).into()]);
        let mut pruned = layer.low != first.low || layer.high != first.high;
        let mut free_low = free.low - first.low;
        let mut free_high = free.high - first.high;
        let mut depth: u8 = 1;
        let found = loop {
            layers.append(layer);
            let hit = Bits::and(layer, goal);
            if hit.low != 0 || hit.high != 0 {
                break true;
            }
            if depth + 1 >= bound {
                pruned = true;
                break false;
            }
            let mut low = layer.low;
            let mut high = layer.high;
            if !BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high) {
                break false;
            }
            depth += 1;
            let next = u256 { low, high };
            layer = Bits::and(next, *masks[(bound - depth).into()]);
            if layer.low != next.low || layer.high != next.high {
                pruned = true;
            }
        };
        if found {
            let mut path: Array<u8> = array![to];
            let mut layers = layers.span();
            if layers.len() == 1 && Bits::get(start.around.into(), to) {
                return (path.span(), rounds);
            }
            BfsInternal::backtrack(
                BoxTrait::new(back), to, target.power, target.odd, layers, ref path,
            );
            return (path.span(), rounds);
        }
        if !pruned {
            return (array![].span(), rounds);
        }
        bound += 1;
    }
}

// Reference counts

/// Tiles in the BFS layers of a search and the number of layers.
fn bfs_tiles(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> (u32, u32) {
    let open = BfsInternal::check(grid, width, height, from, to);
    let (step, back, free) = BfsInternal::constants(open, width, height);
    let start = BfsInternal::endpoint(@back, height, from);
    let target = BfsInternal::endpoint(@back, height, to);
    let mut layers: Array<u256> = array![];
    BfsInternal::advance(@step, @start, @target, free, ref layers);
    let mut tiles: u32 = 0;
    let count = layers.len();
    let mut layers = layers.span();
    while let Option::Some(layer) = layers.pop_front() {
        tiles += Bits::popcount(*layer).into();
    }
    (tiles, count)
}

// Oracle

/// Whether two tiles are neighbours.
fn adjacent(width: u8, height: u8, lhs: u8, rhs: u8) -> bool {
    for direction in DIRECTIONS.span() {
        if LayoutTrait::neighbor(width, height, lhs, *direction) == Option::Some(rhs) {
            return true;
        }
    }
    false
}

/// A valid path from `to` back to a neighbour of `from`, through walkable interior tiles.
fn check_path(grid: felt252, width: u8, height: u8, from: u8, to: u8, path: Span<u8>) {
    if path.len() == 0 {
        return;
    }
    let open: u256 = grid.into();
    let inner = open & LayoutTrait::interior(width, height).into();
    assert!(*path[0] == to);
    let mut index = 1;
    while index != path.len() {
        let tile = *path[index];
        assert!(Bits::get(inner, tile), "tile {} not interior walkable", tile);
        assert!(adjacent(width, height, *path[index - 1], tile));
        index += 1;
    }
    assert!(adjacent(width, height, *path[path.len() - 1], from));
}

/// `Astar::search` against `Bfs::search`: same length, valid path.
fn check(grid: felt252, width: u8, height: u8, from: u8, to: u8) {
    let expected = Bfs::search(grid, width, height, from, to);
    let path = Astar::search(grid, width, height, from, to);
    assert!(
        path.len() == expected.len(),
        "astar {} -> {}: {} vs {}",
        from,
        to,
        path.len(),
        expected.len(),
    );
    check_path(grid, width, height, from, to, path);
}

/// Every variant against `Bfs::search` (interior endpoints).
fn check_variants(grid: felt252, width: u8, height: u8, from: u8, to: u8) {
    let expected = Bfs::search(grid, width, height, from, to).len();
    let (path, _) = search_dict_heap(grid, width, height, from, to);
    assert!(path.len() == expected, "heap {} -> {}", from, to);
    check_path(grid, width, height, from, to, path);
    let (path, _) = search_sorted(grid, width, height, from, to);
    assert!(path.len() == expected, "sorted {} -> {}", from, to);
    check_path(grid, width, height, from, to, path);
    let (path, _) = search_scan(grid, width, height, from, to);
    assert!(path.len() == expected, "scan {} -> {}", from, to);
    check_path(grid, width, height, from, to, path);
    let (path, _) = search_pruned(grid, width, height, from, to);
    assert!(path.len() == expected, "pruned {} -> {}", from, to);
    check_path(grid, width, height, from, to, path);
    let (path, _) = search_greedy(grid, width, height, from, to);
    assert!((path.len() == 0) == (expected == 0), "greedy {} -> {}", from, to);
    assert!(path.len() >= expected);
    check_path(grid, width, height, from, to, path);
}

/// Pairs of a sample of walkable tiles: starts one in `stride`, targets one in 5.
fn check_sample(grid: felt252, width: u8, height: u8, stride: u8, variants: bool) {
    let open: u256 = grid.into();
    let interior: u256 = LayoutTrait::interior(width, height).into();
    let size: u16 = width.into() * height.into();
    let mut from: u16 = 0;
    while from < size {
        let start: u8 = from.try_into().unwrap();
        if Bits::get(open, start) {
            let mut to: u16 = (from * 7) % 5;
            while to < size {
                let target: u8 = to.try_into().unwrap();
                if Bits::get(open, target) {
                    check(grid, width, height, start, target);
                    if variants
                        && Bits::get(interior, start)
                        && Bits::get(interior, target)
                        && start != target {
                        check_variants(grid, width, height, start, target);
                    }
                }
                to += 5;
            }
        }
        from += stride.into();
    }
}

/// `EMPTY_17X14` with open edge tiles.
fn empty_with(tiles: Span<u8>) -> felt252 {
    let mut grid = EMPTY_17X14;
    let mut tiles = tiles;
    while let Option::Some(tile) = tiles.pop_front() {
        grid += Bits::pow(*tile);
    }
    grid
}

#[test]
fn test_astar_oracle_fixtures() {
    let pairs: Array<(felt252, u8, u8, u8, u8)> = array![
        (EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO),
        (EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO),
        (CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO),
        (CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO),
        (MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO),
        (MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO),
        (SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO),
        (SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO),
        (UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO),
        (UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO),
        (EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO),
        (EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO),
        (CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO),
        (CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO),
        (MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO),
        (MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO),
        (SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO),
        (SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO),
        (UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO),
        (UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO),
        (EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO),
        (CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO),
        (EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO),
        (EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO),
        (EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO),
        (CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO),
        (CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO),
        (CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO),
    ];
    let mut pairs = pairs.span();
    while let Option::Some((grid, width, height, from, to)) = pairs.pop_front() {
        let (grid, width, height, from, to) = (*grid, *width, *height, *from, *to);
        check(grid, width, height, from, to);
        check_variants(grid, width, height, from, to);
    }
}

#[test]
fn test_astar_oracle_extra_pairs() {
    assert!(
        Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO).len() == EMPTY_D2_DISTANCE,
    );
    assert!(
        Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO).len() == EMPTY_D5_DISTANCE,
    );
    assert!(
        Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO).len() == EMPTY_D10_DISTANCE,
    );
    assert!(Bfs::search(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO).len() == CAVE_D2_DISTANCE);
    assert!(Bfs::search(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO).len() == CAVE_D5_DISTANCE);
    assert!(Bfs::search(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO).len() == CAVE_D10_DISTANCE);
}

#[test]
fn test_astar_oracle_sample_cave() {
    check_sample(CAVE_17X14, 17, 14, 23, false);
}

#[test]
fn test_astar_oracle_sample_cave_variants() {
    check_sample(CAVE_17X14, 17, 14, 97, true);
}

#[test]
fn test_astar_oracle_sample_maze() {
    check_sample(MAZE_17X14, 17, 14, 31, false);
    check_sample(MAZE_7X7, 7, 7, 5, true);
}

#[test]
fn test_astar_oracle_sample_open() {
    check_sample(EMPTY_17X14, 17, 14, 37, false);
    check_sample(EMPTY_17X14, 17, 14, 83, true);
    check_sample(SERPENTINE_7X7, 7, 7, 3, true);
}

#[test]
fn test_astar_oracle_random_caves() {
    let mut seed: felt252 = 1;
    while seed != 4 {
        check_sample(Caver::generate(17, 14, 3, seed), 17, 14, 47, seed == 1);
        check_sample(Caver::generate(19, 13, 3, seed), 19, 13, 47, false);
        check_sample(Caver::generate(7, 7, 2, seed), 7, 7, 3, false);
        seed += 1;
    }
}

#[test]
fn test_astar_oracle_random_mazes() {
    check_sample(Mazer::generate(17, 14, 1, 'MAZE'), 17, 14, 29, true);
    check_sample(Mazer::generate(19, 13, 0, 'MAZE'), 19, 13, 37, false);
    check_sample(Mazer::generate(7, 7, 0, 'MAZE'), 7, 7, 2, false);
}

#[test]
fn test_astar_oracle_sizes() {
    check(Bits::pow(4), 3, 3, 4, 4);
    check_sample(LayoutTrait::interior(8, 16), 8, 16, 13, false);
    check_sample(LayoutTrait::interior(9, 15), 9, 15, 17, false);
    check(LayoutTrait::interior(83, 3), 83, 3, 84, 164);
    check_sample(LayoutTrait::interior(25, 10), 25, 10, 41, false);
    check(LayoutTrait::interior(3, 83), 3, 83, 4, 244);
}

#[test]
fn test_astar_oracle_edges() {
    // Entrances on the four sides, corners, a whole open bottom row
    let grid = empty_with(array![3, 225, 68, 84].span());
    let tiles = array![18, 120, 200, 3, 225, 68, 84].span();
    for from in tiles {
        for to in tiles {
            check(grid, 17, 14, *from, *to);
        }
    }
    let row = empty_with(array![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].span());
    check(row, 17, 14, 2, 12);
    check(row, 17, 14, 4, 5);
    check(row, 17, 14, 19, 3);
    let corners = empty_with(array![0, 1, 16].span());
    check(corners, 17, 14, 16, 200);
    check(corners, 17, 14, 200, 16);
    check(corners, 17, 14, 0, 1);
    check(corners, 17, 14, 0, 200);
    check(corners, 17, 14, 16, 0);
    let closed = UNREACHABLE_17X14 - Bits::pow(18) - Bits::pow(19) + Bits::pow(2);
    check(closed, 17, 14, 2, 120);
    check(closed, 17, 14, 120, 2);
    let cave = Digger::corridor(17, 14, 0, 3, CAVE_17X14, 'DIG');
    check_sample(cave, 17, 14, 19, false);
    let maze = Digger::maze(17, 14, 0, 230, 0, 'DIG');
    check_sample(maze, 17, 14, 23, false);
    let small = Digger::maze(7, 7, 0, 3, 0, 'DIG');
    check_sample(small, 7, 7, 2, false);
}

// Microbenchmarks: 100 interior-or-not positions 119 down to 20 of 17x14, target 202,
// per op = (test - `bench_astar_micro_loop`) / 100

/// Frame of the EMPTY 17x14 far pair.
fn micro_frame() -> Frame {
    let open: u256 = EMPTY_17X14.into();
    let (frame, _, _, _) = AstarInternal::setup(open, 17, 14, 202, 18);
    frame
}

#[test]
#[available_gas(l2_gas: 183000)]
fn bench_astar_micro_loop() {
    let frame = micro_frame();
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        acc += position.into();
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 316000)]
fn bench_astar_micro_bit() {
    let frame = micro_frame();
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let bit: u128 = *POW128.span().at(position.into());
        acc += bit.into();
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 556000)]
fn bench_astar_micro_log2() {
    let frame = micro_frame();
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let bit: u128 = *POW128.span().at(position.into());
        acc += AstarInternal::log2(bit).into();
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 502000)]
fn bench_astar_micro_coords() {
    let frame = micro_frame();
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let (half, rem) = DivRem::div_rem(position, frame.period);
        let (x, y) = if rem < frame.back.width {
            (rem, 2 * half)
        } else {
            (rem - frame.back.width, 2 * half + 1)
        };
        acc += x.into() + y.into();
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 1224000)]
fn bench_astar_micro_classes() {
    let frame = micro_frame();
    let back = frame.back;
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let (half, rem) = DivRem::div_rem(position, frame.period);
        let (x, y) = if rem < frame.back.width {
            (rem, 2 * half)
        } else {
            (rem - frame.back.width, 2 * half + 1)
        };
        let (h, down, up) = AstarInternal::classes(
            frame, x, y, half, back.up_even, back.up_odd, back.down_even, back.down_odd,
        );
        acc += h.into() + down + up;
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 478000)]
fn bench_astar_micro_coords_bounded() {
    let frame = micro_frame();
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let (_, x, y, _) = AstarInternal::coords(position, frame.back.width, frame.period);
        acc += x.into() + y.into();
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 927000)]
fn bench_astar_micro_classes_bounded() {
    let frame = micro_frame();
    let back = frame.back;
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let (half, x, y, _) = AstarInternal::coords(position, frame.back.width, frame.period);
        let (h, down, up) = AstarInternal::classes_bounded(
            frame, x, y, half, back.up_even, back.up_odd, back.down_even, back.down_odd,
        );
        acc += h + down + up;
    }
    assert!(acc != frame.x.into());
}

#[test]
#[available_gas(l2_gas: 2641000)]
fn bench_astar_micro_expand() {
    let frame = micro_frame();
    let boxed = BoxTrait::new(frame);
    let (goal_high, goal_bit) = AstarInternal::split(Bits::pow(18));
    let avail: u256 = EMPTY_17X14.into();
    let mut buckets = Buckets {
        avail_low: avail.low,
        avail_high: avail.high,
        hot_low: 0,
        hot_high: 0,
        current_low: 0,
        current_high: 0,
        next_low: 0,
        next_high: 0,
        after_low: 0,
        after_high: 0,
    };
    let mut acc: felt252 = 0;
    let mut position: u8 = 120;
    while position != 20 {
        position -= 1;
        let bit: u128 = *POW128.span().at(position.into());
        let (tile, _, h, _) = AstarInternal::expand(
            boxed, false, bit, goal_high, goal_bit, ref buckets,
        );
        acc += tile.into() + h;
    }
    let sum: felt252 = buckets.hot_low.into() + buckets.next_low.into();
    assert!(acc != sum);
}

// Panics: the contract of `Bfs::search`

#[test]
#[should_panic(expected: 'Bfs: position not walkable')]
fn test_astar_search_revert_start_wall() {
    let _ = Astar::search(UNREACHABLE_17X14, 17, 14, 25, 18);
}

#[test]
#[should_panic(expected: 'Bfs: position not walkable')]
fn test_astar_search_revert_target_wall() {
    let _ = Astar::search(UNREACHABLE_17X14, 17, 14, 18, 25);
}

#[test]
#[should_panic(expected: 'Bfs: position not walkable')]
fn test_astar_search_revert_edge_wall() {
    let _ = Astar::search(EMPTY_17X14, 17, 14, 3, 18);
}

#[test]
#[should_panic(expected: 'Asserter: position not inside')]
fn test_astar_search_revert_outside() {
    let _ = Astar::search(EMPTY_17X14, 17, 14, 18, 238);
}

#[test]
#[should_panic(expected: 'Asserter: invalid dimension')]
fn test_astar_search_revert_dimension() {
    let _ = Astar::search(EMPTY_17X14, 18, 14, 19, 20);
}

#[test]
fn test_astar_search_same_and_adjacent() {
    assert!(Astar::search(EMPTY_17X14, 17, 14, 19, 19).len() == 0);
    assert!(Astar::search(EMPTY_17X14, 17, 14, 19, 20) == array![20].span());
    assert!(Astar::search(Bits::pow(4), 3, 3, 4, 4).len() == 0);
}

// Benchmarks

// search

#[test]
#[available_gas(l2_gas: 140000)]
fn bench_astar_search_empty_near_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 696000)]
fn bench_astar_search_empty_far_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 138000)]
fn bench_astar_search_cave_near_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2947000)]
fn bench_astar_search_cave_far_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 130000)]
fn bench_astar_search_maze_near_17x14() {
    let path = Astar::search(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3741000)]
fn bench_astar_search_maze_far_17x14() {
    let path = Astar::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 130000)]
fn bench_astar_search_serpentine_near_17x14() {
    let path = Astar::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 4202000)]
fn bench_astar_search_serpentine_far_17x14() {
    let path = Astar::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3191000)]
fn bench_astar_search_unreachable_near_17x14() {
    let path = Astar::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3006000)]
fn bench_astar_search_unreachable_far_17x14() {
    let path = Astar::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 128000)]
fn bench_astar_search_empty_near_7x7() {
    let path = Astar::search(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 230000)]
fn bench_astar_search_empty_far_7x7() {
    let path = Astar::search(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 127000)]
fn bench_astar_search_cave_near_7x7() {
    let path = Astar::search(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 230000)]
fn bench_astar_search_cave_far_7x7() {
    let path = Astar::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 138000)]
fn bench_astar_search_maze_near_7x7() {
    let path = Astar::search(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 654000)]
fn bench_astar_search_maze_far_7x7() {
    let path = Astar::search(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 127000)]
fn bench_astar_search_serpentine_near_7x7() {
    let path = Astar::search(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 661000)]
fn bench_astar_search_serpentine_far_7x7() {
    let path = Astar::search(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO);
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 414000)]
fn bench_astar_search_unreachable_near_7x7() {
    let path = Astar::search(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 388000)]
fn bench_astar_search_unreachable_far_7x7() {
    let path = Astar::search(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 60000)]
fn bench_astar_search_empty_d1_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 103000)]
fn bench_astar_search_empty_d2_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 214000)]
fn bench_astar_search_empty_d5_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 400000)]
fn bench_astar_search_empty_d10_17x14() {
    let path = Astar::search(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 60000)]
fn bench_astar_search_cave_d1_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 100000)]
fn bench_astar_search_cave_d2_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 657000)]
fn bench_astar_search_cave_d5_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 946000)]
fn bench_astar_search_cave_d10_17x14() {
    let path = Astar::search(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

// variant_heap

#[test]
#[available_gas(l2_gas: 554000)]
fn bench_astar_variant_heap_empty_near_17x14() {
    let (path, _) = search_dict_heap(
        EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO,
    );
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 4163000)]
fn bench_astar_variant_heap_empty_far_17x14() {
    let (path, _) = search_dict_heap(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 498000)]
fn bench_astar_variant_heap_cave_near_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 14111000)]
fn bench_astar_variant_heap_cave_far_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 256000)]
fn bench_astar_variant_heap_maze_near_17x14() {
    let (path, _) = search_dict_heap(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 7792000)]
fn bench_astar_variant_heap_maze_far_17x14() {
    let (path, _) = search_dict_heap(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 295000)]
fn bench_astar_variant_heap_serpentine_near_17x14() {
    let (path, _) = search_dict_heap(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 7373000)]
fn bench_astar_variant_heap_serpentine_far_17x14() {
    let (path, _) = search_dict_heap(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 19654000)]
fn bench_astar_variant_heap_unreachable_near_17x14() {
    let (path, _) = search_dict_heap(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 22944000)]
fn bench_astar_variant_heap_unreachable_far_17x14() {
    let (path, _) = search_dict_heap(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 509000)]
fn bench_astar_variant_heap_empty_near_7x7() {
    let (path, _) = search_dict_heap(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 979000)]
fn bench_astar_variant_heap_empty_far_7x7() {
    let (path, _) = search_dict_heap(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 541000)]
fn bench_astar_variant_heap_cave_near_7x7() {
    let (path, _) = search_dict_heap(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 931000)]
fn bench_astar_variant_heap_cave_far_7x7() {
    let (path, _) = search_dict_heap(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 293000)]
fn bench_astar_variant_heap_maze_near_7x7() {
    let (path, _) = search_dict_heap(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1165000)]
fn bench_astar_variant_heap_maze_far_7x7() {
    let (path, _) = search_dict_heap(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 291000)]
fn bench_astar_variant_heap_serpentine_near_7x7() {
    let (path, _) = search_dict_heap(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1381000)]
fn bench_astar_variant_heap_serpentine_far_7x7() {
    let (path, _) = search_dict_heap(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1413000)]
fn bench_astar_variant_heap_unreachable_near_7x7() {
    let (path, _) = search_dict_heap(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1406000)]
fn bench_astar_variant_heap_unreachable_far_7x7() {
    let (path, _) = search_dict_heap(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 106000)]
fn bench_astar_variant_heap_empty_d1_17x14() {
    let (path, _) = search_dict_heap(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 321000)]
fn bench_astar_variant_heap_empty_d2_17x14() {
    let (path, _) = search_dict_heap(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1014000)]
fn bench_astar_variant_heap_empty_d5_17x14() {
    let (path, _) = search_dict_heap(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2328000)]
fn bench_astar_variant_heap_empty_d10_17x14() {
    let (path, _) = search_dict_heap(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 106000)]
fn bench_astar_variant_heap_cave_d1_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 320000)]
fn bench_astar_variant_heap_cave_d2_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1758000)]
fn bench_astar_variant_heap_cave_d5_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3288000)]
fn bench_astar_variant_heap_cave_d10_17x14() {
    let (path, _) = search_dict_heap(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

// variant_sorted

#[test]
#[available_gas(l2_gas: 472000)]
fn bench_astar_variant_sorted_empty_near_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 6584000)]
fn bench_astar_variant_sorted_empty_far_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 412000)]
fn bench_astar_variant_sorted_cave_near_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 12869000)]
fn bench_astar_variant_sorted_cave_far_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 231000)]
fn bench_astar_variant_sorted_maze_near_17x14() {
    let (path, _) = search_sorted(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 6543000)]
fn bench_astar_variant_sorted_maze_far_17x14() {
    let (path, _) = search_sorted(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 250000)]
fn bench_astar_variant_sorted_serpentine_near_17x14() {
    let (path, _) = search_sorted(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 6705000)]
fn bench_astar_variant_sorted_serpentine_far_17x14() {
    let (path, _) = search_sorted(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 18247000)]
fn bench_astar_variant_sorted_unreachable_near_17x14() {
    let (path, _) = search_sorted(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 29790000)]
fn bench_astar_variant_sorted_unreachable_far_17x14() {
    let (path, _) = search_sorted(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 427000)]
fn bench_astar_variant_sorted_empty_near_7x7() {
    let (path, _) = search_sorted(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 907000)]
fn bench_astar_variant_sorted_empty_far_7x7() {
    let (path, _) = search_sorted(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 459000)]
fn bench_astar_variant_sorted_cave_near_7x7() {
    let (path, _) = search_sorted(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 807000)]
fn bench_astar_variant_sorted_cave_far_7x7() {
    let (path, _) = search_sorted(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 249000)]
fn bench_astar_variant_sorted_maze_near_7x7() {
    let (path, _) = search_sorted(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1046000)]
fn bench_astar_variant_sorted_maze_far_7x7() {
    let (path, _) = search_sorted(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 247000)]
fn bench_astar_variant_sorted_serpentine_near_7x7() {
    let (path, _) = search_sorted(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1192000)]
fn bench_astar_variant_sorted_serpentine_far_7x7() {
    let (path, _) = search_sorted(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1057000)]
fn bench_astar_variant_sorted_unreachable_near_7x7() {
    let (path, _) = search_sorted(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1053000)]
fn bench_astar_variant_sorted_unreachable_far_7x7() {
    let (path, _) = search_sorted(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 96000)]
fn bench_astar_variant_sorted_empty_d1_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 263000)]
fn bench_astar_variant_sorted_empty_d2_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1008000)]
fn bench_astar_variant_sorted_empty_d5_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3211000)]
fn bench_astar_variant_sorted_empty_d10_17x14() {
    let (path, _) = search_sorted(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 96000)]
fn bench_astar_variant_sorted_cave_d1_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 262000)]
fn bench_astar_variant_sorted_cave_d2_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1811000)]
fn bench_astar_variant_sorted_cave_d5_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3736000)]
fn bench_astar_variant_sorted_cave_d10_17x14() {
    let (path, _) = search_sorted(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

// variant_scan

#[test]
#[available_gas(l2_gas: 419000)]
fn bench_astar_variant_scan_empty_near_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 4948000)]
fn bench_astar_variant_scan_empty_far_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 387000)]
fn bench_astar_variant_scan_cave_near_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 19235000)]
fn bench_astar_variant_scan_cave_far_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 247000)]
fn bench_astar_variant_scan_maze_near_17x14() {
    let (path, _) = search_scan(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 7605000)]
fn bench_astar_variant_scan_maze_far_17x14() {
    let (path, _) = search_scan(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 268000)]
fn bench_astar_variant_scan_serpentine_near_17x14() {
    let (path, _) = search_scan(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 7544000)]
fn bench_astar_variant_scan_serpentine_far_17x14() {
    let (path, _) = search_scan(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 37346000)]
fn bench_astar_variant_scan_unreachable_near_17x14() {
    let (path, _) = search_scan(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 63004000)]
fn bench_astar_variant_scan_unreachable_far_17x14() {
    let (path, _) = search_scan(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 393000)]
fn bench_astar_variant_scan_empty_near_7x7() {
    let (path, _) = search_scan(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 813000)]
fn bench_astar_variant_scan_empty_far_7x7() {
    let (path, _) = search_scan(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 407000)]
fn bench_astar_variant_scan_cave_near_7x7() {
    let (path, _) = search_scan(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 757000)]
fn bench_astar_variant_scan_cave_far_7x7() {
    let (path, _) = search_scan(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 266000)]
fn bench_astar_variant_scan_maze_near_7x7() {
    let (path, _) = search_scan(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1166000)]
fn bench_astar_variant_scan_maze_far_7x7() {
    let (path, _) = search_scan(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 265000)]
fn bench_astar_variant_scan_serpentine_near_7x7() {
    let (path, _) = search_scan(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1367000)]
fn bench_astar_variant_scan_serpentine_far_7x7() {
    let (path, _) = search_scan(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1478000)]
fn bench_astar_variant_scan_unreachable_near_7x7() {
    let (path, _) = search_scan(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1435000)]
fn bench_astar_variant_scan_unreachable_far_7x7() {
    let (path, _) = search_scan(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 96000)]
fn bench_astar_variant_scan_empty_d1_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 251000)]
fn bench_astar_variant_scan_empty_d2_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 806000)]
fn bench_astar_variant_scan_empty_d5_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2165000)]
fn bench_astar_variant_scan_empty_d10_17x14() {
    let (path, _) = search_scan(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 96000)]
fn bench_astar_variant_scan_cave_d1_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 250000)]
fn bench_astar_variant_scan_cave_d2_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1662000)]
fn bench_astar_variant_scan_cave_d5_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3673000)]
fn bench_astar_variant_scan_cave_d10_17x14() {
    let (path, _) = search_scan(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

// variant_greedy

#[test]
#[available_gas(l2_gas: 241000)]
fn bench_astar_variant_greedy_empty_near_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!((path.len() == 0) == (EMPTY_17X14_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 1183000)]
fn bench_astar_variant_greedy_empty_far_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!((path.len() == 0) == (EMPTY_17X14_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 250000)]
fn bench_astar_variant_greedy_cave_near_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!((path.len() == 0) == (CAVE_17X14_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 2989000)]
fn bench_astar_variant_greedy_cave_far_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!((path.len() == 0) == (CAVE_17X14_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 218000)]
fn bench_astar_variant_greedy_maze_near_17x14() {
    let (path, _) = search_greedy(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!((path.len() == 0) == (MAZE_17X14_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 4503000)]
fn bench_astar_variant_greedy_maze_far_17x14() {
    let (path, _) = search_greedy(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!((path.len() == 0) == (MAZE_17X14_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 227000)]
fn bench_astar_variant_greedy_serpentine_near_17x14() {
    let (path, _) = search_greedy(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!((path.len() == 0) == (SERPENTINE_17X14_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 5233000)]
fn bench_astar_variant_greedy_serpentine_far_17x14() {
    let (path, _) = search_greedy(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!((path.len() == 0) == (SERPENTINE_17X14_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 4073000)]
fn bench_astar_variant_greedy_unreachable_near_17x14() {
    let (path, _) = search_greedy(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!((path.len() == 0) == (UNREACHABLE_17X14_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 4057000)]
fn bench_astar_variant_greedy_unreachable_far_17x14() {
    let (path, _) = search_greedy(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!((path.len() == 0) == (UNREACHABLE_17X14_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 233000)]
fn bench_astar_variant_greedy_empty_near_7x7() {
    let (path, _) = search_greedy(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!((path.len() == 0) == (EMPTY_7X7_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 391000)]
fn bench_astar_variant_greedy_empty_far_7x7() {
    let (path, _) = search_greedy(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!((path.len() == 0) == (EMPTY_7X7_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 235000)]
fn bench_astar_variant_greedy_cave_near_7x7() {
    let (path, _) = search_greedy(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!((path.len() == 0) == (CAVE_7X7_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 388000)]
fn bench_astar_variant_greedy_cave_far_7x7() {
    let (path, _) = search_greedy(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!((path.len() == 0) == (CAVE_7X7_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 226000)]
fn bench_astar_variant_greedy_maze_near_7x7() {
    let (path, _) = search_greedy(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!((path.len() == 0) == (MAZE_7X7_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 864000)]
fn bench_astar_variant_greedy_maze_far_7x7() {
    let (path, _) = search_greedy(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!((path.len() == 0) == (MAZE_7X7_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 223000)]
fn bench_astar_variant_greedy_serpentine_near_7x7() {
    let (path, _) = search_greedy(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!((path.len() == 0) == (SERPENTINE_7X7_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 901000)]
fn bench_astar_variant_greedy_serpentine_far_7x7() {
    let (path, _) = search_greedy(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    assert!((path.len() == 0) == (SERPENTINE_7X7_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 534000)]
fn bench_astar_variant_greedy_unreachable_near_7x7() {
    let (path, _) = search_greedy(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!((path.len() == 0) == (UNREACHABLE_7X7_NEAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 544000)]
fn bench_astar_variant_greedy_unreachable_far_7x7() {
    let (path, _) = search_greedy(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!((path.len() == 0) == (UNREACHABLE_7X7_FAR_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 110000)]
fn bench_astar_variant_greedy_empty_d1_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!((path.len() == 0) == (EMPTY_D1_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 182000)]
fn bench_astar_variant_greedy_empty_d2_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!((path.len() == 0) == (EMPTY_D2_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 366000)]
fn bench_astar_variant_greedy_empty_d5_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!((path.len() == 0) == (EMPTY_D5_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 673000)]
fn bench_astar_variant_greedy_empty_d10_17x14() {
    let (path, _) = search_greedy(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!((path.len() == 0) == (EMPTY_D10_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 110000)]
fn bench_astar_variant_greedy_cave_d1_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!((path.len() == 0) == (CAVE_D1_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 181000)]
fn bench_astar_variant_greedy_cave_d2_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!((path.len() == 0) == (CAVE_D2_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 535000)]
fn bench_astar_variant_greedy_cave_d5_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!((path.len() == 0) == (CAVE_D5_DISTANCE == 0));
}

#[test]
#[available_gas(l2_gas: 975000)]
fn bench_astar_variant_greedy_cave_d10_17x14() {
    let (path, _) = search_greedy(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!((path.len() == 0) == (CAVE_D10_DISTANCE == 0));
}

// variant_pruned

#[test]
#[available_gas(l2_gas: 192000)]
fn bench_astar_variant_pruned_empty_near_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1190000)]
fn bench_astar_variant_pruned_empty_far_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 209000)]
fn bench_astar_variant_pruned_cave_near_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 6221000)]
fn bench_astar_variant_pruned_cave_far_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 190000)]
fn bench_astar_variant_pruned_maze_near_17x14() {
    let (path, _) = search_pruned(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 31754000)]
fn bench_astar_variant_pruned_maze_far_17x14() {
    let (path, _) = search_pruned(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 190000)]
fn bench_astar_variant_pruned_serpentine_near_17x14() {
    let (path, _) = search_pruned(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 105674000)]
fn bench_astar_variant_pruned_serpentine_far_17x14() {
    let (path, _) = search_pruned(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3937000)]
fn bench_astar_variant_pruned_unreachable_near_17x14() {
    let (path, _) = search_pruned(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3193000)]
fn bench_astar_variant_pruned_unreachable_far_17x14() {
    let (path, _) = search_pruned(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 186000)]
fn bench_astar_variant_pruned_empty_near_7x7() {
    let (path, _) = search_pruned(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 358000)]
fn bench_astar_variant_pruned_empty_far_7x7() {
    let (path, _) = search_pruned(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 186000)]
fn bench_astar_variant_pruned_cave_near_7x7() {
    let (path, _) = search_pruned(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 359000)]
fn bench_astar_variant_pruned_cave_far_7x7() {
    let (path, _) = search_pruned(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 212000)]
fn bench_astar_variant_pruned_maze_near_7x7() {
    let (path, _) = search_pruned(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2027000)]
fn bench_astar_variant_pruned_maze_far_7x7() {
    let (path, _) = search_pruned(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 186000)]
fn bench_astar_variant_pruned_serpentine_near_7x7() {
    let (path, _) = search_pruned(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2385000)]
fn bench_astar_variant_pruned_serpentine_far_7x7() {
    let (path, _) = search_pruned(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 476000)]
fn bench_astar_variant_pruned_unreachable_near_7x7() {
    let (path, _) = search_pruned(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 578000)]
fn bench_astar_variant_pruned_unreachable_far_7x7() {
    let (path, _) = search_pruned(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 151000)]
fn bench_astar_variant_pruned_empty_d1_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 147000)]
fn bench_astar_variant_pruned_empty_d2_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 333000)]
fn bench_astar_variant_pruned_empty_d5_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 652000)]
fn bench_astar_variant_pruned_empty_d10_17x14() {
    let (path, _) = search_pruned(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 148000)]
fn bench_astar_variant_pruned_cave_d1_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 138000)]
fn bench_astar_variant_pruned_cave_d2_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 594000)]
fn bench_astar_variant_pruned_cave_d5_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 944000)]
fn bench_astar_variant_pruned_cave_d10_17x14() {
    let (path, _) = search_pruned(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

// Bfs::search on the extra pairs

#[test]
#[available_gas(l2_gas: 66000)]
fn bench_astar_bfs_empty_d1_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO);
    assert!(path.len() == EMPTY_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 84000)]
fn bench_astar_bfs_empty_d2_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO);
    assert!(path.len() == EMPTY_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 174000)]
fn bench_astar_bfs_empty_d5_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO);
    assert!(path.len() == EMPTY_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 329000)]
fn bench_astar_bfs_empty_d10_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO);
    assert!(path.len() == EMPTY_D10_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 64000)]
fn bench_astar_bfs_cave_d1_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO);
    assert!(path.len() == CAVE_D1_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 82000)]
fn bench_astar_bfs_cave_d2_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO);
    assert!(path.len() == CAVE_D2_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 233000)]
fn bench_astar_bfs_cave_d5_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO);
    assert!(path.len() == CAVE_D5_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 391000)]
fn bench_astar_bfs_cave_d10_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO);
    assert!(path.len() == CAVE_D10_DISTANCE);
}

#[test]
fn test_astar_counts() {
    let pairs: Array<(felt252, u8, u8, u8, u8, felt252)> = array![
        (EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO, 'empty_near_17x14'),
        (EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, 'empty_far_17x14'),
        (CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO, 'cave_near_17x14'),
        (CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, 'cave_far_17x14'),
        (MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO, 'maze_near_17x14'),
        (MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, 'maze_far_17x14'),
        (
            SERPENTINE_17X14,
            17,
            14,
            SERPENTINE_17X14_NEAR_FROM,
            SERPENTINE_17X14_NEAR_TO,
            'serpentine_near_17x14',
        ),
        (
            SERPENTINE_17X14,
            17,
            14,
            SERPENTINE_17X14_FAR_FROM,
            SERPENTINE_17X14_FAR_TO,
            'serpentine_far_17x14',
        ),
        (
            UNREACHABLE_17X14,
            17,
            14,
            UNREACHABLE_17X14_NEAR_FROM,
            UNREACHABLE_17X14_NEAR_TO,
            'unreachable_near_17x14',
        ),
        (
            UNREACHABLE_17X14,
            17,
            14,
            UNREACHABLE_17X14_FAR_FROM,
            UNREACHABLE_17X14_FAR_TO,
            'unreachable_far_17x14',
        ),
        (EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO, 'empty_near_7x7'),
        (EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO, 'empty_far_7x7'),
        (CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO, 'cave_near_7x7'),
        (CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, 'cave_far_7x7'),
        (MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO, 'maze_near_7x7'),
        (MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO, 'maze_far_7x7'),
        (
            SERPENTINE_7X7,
            7,
            7,
            SERPENTINE_7X7_NEAR_FROM,
            SERPENTINE_7X7_NEAR_TO,
            'serpentine_near_7x7',
        ),
        (
            SERPENTINE_7X7,
            7,
            7,
            SERPENTINE_7X7_FAR_FROM,
            SERPENTINE_7X7_FAR_TO,
            'serpentine_far_7x7',
        ),
        (
            UNREACHABLE_7X7,
            7,
            7,
            UNREACHABLE_7X7_NEAR_FROM,
            UNREACHABLE_7X7_NEAR_TO,
            'unreachable_near_7x7',
        ),
        (
            UNREACHABLE_7X7,
            7,
            7,
            UNREACHABLE_7X7_FAR_FROM,
            UNREACHABLE_7X7_FAR_TO,
            'unreachable_far_7x7',
        ),
        (EMPTY_17X14, 17, 14, EMPTY_D1_FROM, EMPTY_D1_TO, 'empty_d1_17x14'),
        (EMPTY_17X14, 17, 14, EMPTY_D2_FROM, EMPTY_D2_TO, 'empty_d2_17x14'),
        (EMPTY_17X14, 17, 14, EMPTY_D5_FROM, EMPTY_D5_TO, 'empty_d5_17x14'),
        (EMPTY_17X14, 17, 14, EMPTY_D10_FROM, EMPTY_D10_TO, 'empty_d10_17x14'),
        (CAVE_17X14, 17, 14, CAVE_D1_FROM, CAVE_D1_TO, 'cave_d1_17x14'),
        (CAVE_17X14, 17, 14, CAVE_D2_FROM, CAVE_D2_TO, 'cave_d2_17x14'),
        (CAVE_17X14, 17, 14, CAVE_D5_FROM, CAVE_D5_TO, 'cave_d5_17x14'),
        (CAVE_17X14, 17, 14, CAVE_D10_FROM, CAVE_D10_TO, 'cave_d10_17x14'),
    ];
    let mut pairs = pairs.span();
    while let Option::Some((grid, width, height, from, to, name)) = pairs.pop_front() {
        let (grid, width, height, from, to) = (*grid, *width, *height, *from, *to);
        let (tiles, layers) = bfs_tiles(grid, width, height, from, to);
        let (path, bucket) = search_bucket(grid, width, height, from, to);
        let (_, heap) = search_dict_heap(grid, width, height, from, to);
        let (greedy_path, greedy) = search_greedy(grid, width, height, from, to);
        let (_, rounds) = search_pruned(grid, width, height, from, to);
        println!(
            "COUNT {} len {} bfs_layers {} bfs_tiles {} astar {} heap {} greedy {} greedy_len {} pruned_rounds {}",
            name,
            path.len(),
            layers,
            tiles,
            bucket,
            heap,
            greedy,
            greedy_path.len(),
            rounds,
        );
    }
}
