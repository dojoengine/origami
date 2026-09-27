//! Gas benchmarks of lot L1, bit-parallel BFS: one `#[test]` per fixture and algorithm, each with
//! an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! The losing formulations live here (test-only). Each variant changes one choice of the library
//! and takes the rest from `BfsInternal` (constants, endpoints, layer step, backtracking step).
//! The variants handle interior endpoints only, like the fixtures, and every variant asserts the
//! path length of the fixture. Variants that change a loop are compared with a harness copy of the
//! library in the same loop shape (`*_harness_*`), not with the library itself.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_hexmap::finders::bfs::{ArrayStore, Back, Bfs, BfsInternal, CountStore, Endpoint, Store};
use origami_hexmap::generators::caver::Caver;
use origami_hexmap::helpers::bits::{Bits, POW128, TWO_POW_128};
use origami_hexmap::helpers::layout::{Dilation, DilationTrait, LayoutTrait};
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::Variants;

// Constants

const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

// Shared prologue

/// Library prologue: checks, constants, endpoints and walkable interior tiles.
fn setup(
    grid: felt252, width: u8, height: u8, from: u8, to: u8,
) -> (Dilation, Back, Endpoint, Endpoint, u256) {
    let open = BfsInternal::check(grid, width, height, from, to);
    let (step, back, free) = BfsInternal::constants(open, width, height);
    let start = BfsInternal::endpoint(@back, height, from);
    let target = BfsInternal::endpoint(@back, height, to);
    (step, back, start, target, free)
}

/// Library backtracking (interior target), for the storage variants.
fn backtrack(back: Back, target: @Endpoint, layers: Span<u256>) -> Span<u8> {
    let mut path: Array<u8> = array![*target.position];
    BfsInternal::backtrack(
        BoxTrait::new(back), *target.position, *target.power, *target.odd, layers, ref path,
    );
    path.span()
}

/// First layer: the closed neighbourhood of an interior start.
fn first_layer(start: @Endpoint, free: u256) -> u256 {
    Bits::and((*start.around + *start.power).into(), free)
}

/// Target neighbourhood.
fn goal(target: @Endpoint, free: u256) -> u256 {
    Bits::and((*target.around).into(), free)
}

/// Whether a layer touches the goal, both limbs.
#[inline(always)]
fn touches(low: u128, high: u128, goal: u256) -> bool {
    let (hit_low, _, _) = Bits::bitwise(low, goal.low);
    let (hit_high, _, _) = Bits::bitwise(high, goal.high);
    hit_low != 0 || hit_high != 0
}

// Variants: layer storage

/// Layers stored as felts, converted back to `u256` before the backtracking.
impl FeltStore of Store<Array<felt252>> {
    fn push(ref self: Array<felt252>, low: u128, high: u128) {
        self.append(low.into() + high.into() * TWO_POW_128);
    }
}

fn search_felt_layers(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (step, back, start, target, free) = setup(grid, width, height, from, to);
    let mut layers: Array<felt252> = array![];
    assert!(BfsInternal::advance(@step, @start, @target, free, ref layers));
    let mut wide: Array<u256> = array![];
    for layer in layers.span() {
        wide.append((*layer).into());
    }
    backtrack(back, @target, wide.span())
}

/// Only layers `4m` and `4m + 1` are stored; `4m + 2` and `4m + 3` are recomputed on the way back
/// from the pair: `L(j+1) = expand(L(j)) & free - L(j) - L(j-1)`.
#[derive(Drop)]
struct Checkpoints {
    layers: Array<u256>,
    count: u32,
}

impl CheckpointStore of Store<Checkpoints> {
    fn push(ref self: Checkpoints, low: u128, high: u128) {
        let (_, rem) = DivRem::div_rem(self.count, 4);
        if rem < 2 {
            self.layers.append(u256 { low, high });
        }
        self.count += 1;
    }
}

/// Next layer from the two previous ones, corelib operators.
fn next_layer(step: @Dilation, previous: u256, current: u256, free: u256) -> u256 {
    let felt = Bits::to_felt(current);
    let (low, high) = step.dilate(current.low, current.high, felt);
    u256 { low, high } & free & ~current & ~previous
}

fn search_checkpoints(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (step, back, start, target, free) = setup(grid, width, height, from, to);
    let mut store = Checkpoints { layers: array![], count: 0 };
    assert!(BfsInternal::advance(@step, @start, @target, free, ref store));
    let total = store.count;
    let stored = store.layers.span();
    let mut path: Array<u8> = array![to];
    let boxed = BoxTrait::new(back);
    let mut position = to;
    let mut power = target.power;
    let mut odd = target.odd;
    let (mut blocks, rem) = DivRem::div_rem(total, 4);
    if rem != 0 {
        blocks += 1;
    }
    while blocks != 0 {
        blocks -= 1;
        // [Compute] The layers of the block, rebuilt from its pair
        let index = 4 * blocks;
        let first = *stored.at(2 * blocks);
        let mut block: Array<u256> = array![first];
        if index + 1 < total {
            let second = *stored.at(2 * blocks + 1);
            block.append(second);
            if index + 2 < total {
                let third = next_layer(@step, first, second, free);
                block.append(third);
                if index + 3 < total {
                    block.append(next_layer(@step, second, third, free));
                }
            }
        }
        let mut block = block.span();
        while let Option::Some(layer) = block.pop_back() {
            let (next, next_power, next_odd) = BfsInternal::back(
                boxed, position, power, odd, *layer,
            );
            position = next;
            power = next_power;
            odd = next_odd;
            path.append(position);
        }
    }
    path.span()
}

/// Layer `index` recomputed from the start neighbourhood.
fn layer_at(step: @Dilation, first: u256, free: u256, index: u8) -> u256 {
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut index = index;
    while index != 0 {
        index -= 1;
        BfsInternal::layer(step, ref low, ref high, ref free_low, ref free_high);
    }
    u256 { low, high }
}

/// No layer stored: the forward pass counts the layers, every backtracking step recomputes its
/// layer from the start.
fn search_recompute(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (step, back, start, target, free) = setup(grid, width, height, from, to);
    let mut count: u8 = 0;
    assert!(BfsInternal::advance(@step, @start, @target, free, ref count));
    let first = first_layer(@start, free);
    let mut path: Array<u8> = array![to];
    let boxed = BoxTrait::new(back);
    let mut position = to;
    let mut power = target.power;
    let mut odd = target.odd;
    while count != 0 {
        count -= 1;
        let layer = layer_at(@step, first, free, count);
        let (next, next_power, next_odd) = BfsInternal::back(boxed, position, power, odd, layer);
        position = next;
        power = next_power;
        odd = next_odd;
        path.append(position);
    }
    path.span()
}

// Variants: backtracking step

/// Library forward pass, then the given loop.
fn forward_layers(
    grid: felt252, width: u8, height: u8, from: u8, to: u8,
) -> (Back, Endpoint, Span<u256>) {
    let (step, back, start, target, free) = setup(grid, width, height, from, to);
    let mut layers: Array<u256> = array![];
    assert!(BfsInternal::advance(@step, @start, @target, free, ref layers));
    (back, target, layers.span())
}

/// Harness: library step in a plain loop, one layer per iteration.
fn search_back_harness(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (back, target, layers) = forward_layers(grid, width, height, from, to);
    let boxed = BoxTrait::new(back);
    let mut path: Array<u8> = array![to];
    let mut position = to;
    let mut power = target.power;
    let mut odd = target.odd;
    let mut layers = layers;
    while let Option::Some(layer) = layers.pop_back() {
        let (next, next_power, next_odd) = BfsInternal::back(boxed, position, power, odd, *layer);
        position = next;
        power = next_power;
        odd = next_odd;
        path.append(position);
    }
    path.span()
}

/// Six single-bit tests (`Bits::get`) in the fixed direction order E, NE, NW, W, SW, SE.
fn search_back_bits(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (back, _, layers) = forward_layers(grid, width, height, from, to);
    let mut path: Array<u8> = array![to];
    let mut position = to;
    let mut layers = layers;
    while let Option::Some(layer) = layers.pop_back() {
        position = back_bits(back.width, position, *layer);
        path.append(position);
    }
    path.span()
}

#[inline(always)]
fn back_bits(width: u8, position: u8, layer: u256) -> u8 {
    let (_, rem) = DivRem::div_rem(position, (2 * width).try_into().unwrap());
    let odd = rem >= width;
    if Bits::get(layer, position - 1) {
        return position - 1;
    }
    let (north_east, north_west, south_west, south_east) = if odd {
        (position + width, position + width + 1, position + 1 - width, position - width)
    } else {
        (position + width - 1, position + width, position - width, position - width - 1)
    };
    if Bits::get(layer, north_east) {
        north_east
    } else if Bits::get(layer, north_west) {
        north_west
    } else if Bits::get(layer, position + 1) {
        position + 1
    } else if Bits::get(layer, south_west) {
        south_west
    } else {
        south_east
    }
}

/// Straight first: the last move is tried with one bit test before the neighbour mask.
#[derive(Copy, Drop)]
struct Walk {
    position: felt252,
    power: felt252,
    odd: bool,
    factor: felt252,
    offset: felt252,
    factor_other: felt252,
    offset_other: felt252,
    vertical: bool,
}

fn search_back_straight(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (back, target, layers) = forward_layers(grid, width, height, from, to);
    let boxed = BoxTrait::new(back);
    let mut path: Array<u8> = array![to];
    let mut walk = Walk {
        position: to.into(),
        power: target.power,
        odd: target.odd,
        factor: 0,
        offset: 0,
        factor_other: 0,
        offset_other: 0,
        vertical: false,
    };
    let mut layers = layers;
    while let Option::Some(layer) = layers.pop_back() {
        walk = back_straight(boxed, walk, *layer);
        path.append(walk.position.try_into().unwrap());
    }
    path.span()
}

#[inline(always)]
fn back_straight(back: Box<Back>, walk: Walk, layer: u256) -> Walk {
    let power = walk.power * walk.factor;
    let bits: u256 = power.into();
    let (hit, _, _) = if bits.high == 0 {
        Bits::bitwise(bits.low, layer.low)
    } else {
        Bits::bitwise(bits.high, layer.high)
    };
    if hit == 0 {
        return turn(back, walk, layer);
    }
    let position = walk.position + walk.offset;
    if walk.vertical {
        Walk {
            position,
            power,
            odd: !walk.odd,
            factor: walk.factor_other,
            offset: walk.offset_other,
            factor_other: walk.factor,
            offset_other: walk.offset,
            vertical: true,
        }
    } else {
        Walk { position, power, ..walk }
    }
}

/// Library step, then the move is recorded for both row parities.
#[inline(never)]
fn turn(back: Box<Back>, walk: Walk, layer: u256) -> Walk {
    let position: u8 = walk.position.try_into().unwrap();
    let (next, power, odd) = BfsInternal::back(back, position, walk.power, walk.odd, layer);
    let back = back.unbox();
    let width: felt252 = back.width.into();
    let offset: felt252 = next.into() - walk.position;
    let (factor, factor_other, offset_same, offset_other, vertical) = if offset == -1 {
        (INV_2, INV_2, -1, -1, false)
    } else if offset == 1 {
        (2, 2, 1, 1, false)
    } else if offset == width - 1 || offset == width || offset == width + 1 {
        // North, factors of the new parity then of the old one
        if walk.odd {
            if offset == width {
                (back.up_even, back.up_odd, width - 1, width, true)
            } else {
                (back.up_odd, back.up_wide, width, width + 1, true)
            }
        } else if offset == width - 1 {
            (back.up_odd, back.up_even, width, width - 1, true)
        } else {
            (back.up_wide, back.up_odd, width + 1, width, true)
        }
    } else if walk.odd {
        if offset == -width {
            (back.down_even, back.down_odd, -width - 1, -width, true)
        } else {
            (back.down_odd, back.down_wide, -width, 1 - width, true)
        }
    } else if offset == -width - 1 {
        (back.down_odd, back.down_even, -width, -width - 1, true)
    } else {
        (back.down_wide, back.down_odd, 1 - width, -width, true)
    };
    Walk {
        position: next.into(),
        power,
        odd,
        factor,
        offset: offset_same,
        factor_other,
        offset_other,
        vertical,
    }
}

/// Highest neighbour by binary search in a normalised window: the hit is shifted down by
/// `c - W - 1` (tracked factor), then compared with the thresholds `2^W`, `2^(2W)`...
#[derive(Copy, Drop)]
struct Window {
    row: u128,
    row_west: u128,
    top: u128,
    top_odd: u128,
    top_west: u128,
}

fn search_back_window(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let (back, target, layers) = forward_layers(grid, width, height, from, to);
    let row: u128 = back.up_odd.try_into().unwrap();
    let top: u128 = (back.up_odd * back.up_odd).try_into().unwrap();
    let window = Window { row, row_west: 4 * row, top, top_odd: 2 * top, top_west: 4 * top };
    let boxed = BoxTrait::new(back);
    let mut path: Array<u8> = array![to];
    let mut position = to;
    let mut power = target.power;
    let mut shift = Bits::inv(to - width - 1);
    let mut odd = target.odd;
    let mut layers = layers;
    while let Option::Some(layer) = layers.pop_back() {
        let (next, next_power, next_shift, next_odd) = back_window(
            boxed, @window, position, power, shift, odd, *layer,
        );
        position = next;
        power = next_power;
        shift = next_shift;
        odd = next_odd;
        path.append(position);
    }
    path.span()
}

#[inline(always)]
fn back_window(
    back: Box<Back>,
    window: @Window,
    position: u8,
    power: felt252,
    shift: felt252,
    odd: bool,
    layer: u256,
) -> (u8, felt252, felt252, bool) {
    let back = back.unbox();
    let window = *window;
    let width = back.width;
    let mask: u256 = (power * if odd {
        back.around_odd
    } else {
        back.around_even
    }).into();
    let (low, _, _) = Bits::bitwise(mask.low, layer.low);
    let (high, _, _) = Bits::bitwise(mask.high, layer.high);
    let hit: u128 = ((low.into() + high.into() * TWO_POW_128) * shift).try_into().unwrap();
    if odd {
        if hit >= window.top_odd {
            if hit >= window.top_west {
                (position + width + 1, power * back.up_wide, shift * back.down_even, false)
            } else {
                (position + width, power * back.up_odd, shift * back.down_odd, false)
            }
        } else if hit >= window.row {
            if hit >= window.row_west {
                (position + 1, power * 2, shift * INV_2, true)
            } else {
                (position - 1, power * INV_2, shift * 2, true)
            }
        } else if hit >= 4 {
            (position + 1 - width, power * back.down_wide, shift * back.up_even, false)
        } else {
            (position - width, power * back.down_odd, shift * back.up_odd, false)
        }
    } else if hit >= window.top {
        if hit >= window.top_odd {
            (position + width, power * back.up_odd, shift * back.down_odd, true)
        } else {
            (position + width - 1, power * back.up_even, shift * back.down_wide, true)
        }
    } else if hit >= window.row {
        if hit >= window.row_west {
            (position + 1, power * 2, shift * INV_2, false)
        } else {
            (position - 1, power * INV_2, shift * 2, false)
        }
    } else if hit >= 2 {
        (position - width, power * back.down_odd, shift * back.up_odd, true)
    } else {
        (position - width - 1, power * back.down_even, shift * back.up_wide, true)
    }
}

// Variants: target test, early exit, set operations (forward pass only, layer count)

/// Harness: library choices (hex distance skip, single-limb test) in a plain loop.
fn distance_harness(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let goal = goal(@target, free);
    let first = first_layer(@start, free);
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut count: u8 = 1;
    let gap = BfsInternal::gap(@start, @target);
    let mut skip = if gap > 2 {
        gap - 2
    } else {
        0
    };
    while skip != 0 {
        skip -= 1;
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    while !touches(low, high, goal) {
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    count + 1
}

/// No hex distance skip: the target is tested on every layer.
fn distance_no_gap(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let goal = goal(@target, free);
    let first = first_layer(@start, free);
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut count: u8 = 1;
    while !touches(low, high, goal) {
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    count + 1
}

/// Harness for `distance_every_two`: library choices, two layers per iteration.
fn distance_harness_two(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let goal = goal(@target, free);
    let first = first_layer(@start, free);
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut count: u8 = 1;
    let gap = BfsInternal::gap(@start, @target);
    let mut skip = if gap > 2 {
        gap - 2
    } else {
        0
    };
    while skip != 0 {
        skip -= 1;
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    loop {
        if touches(low, high, goal) {
            break count + 1;
        }
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        if touches(low, high, goal) {
            break count + 2;
        }
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 2;
    }
}

/// Target tested every two layers against its closed neighbourhood (a layer that touches the
/// target neighbourhood is followed by one that holds the target), then the layer in between is
/// tested once to tell which one touched first. Same loop shape as `distance_harness_two`.
fn distance_every_two(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let goal = goal(@target, free);
    let closed = Bits::and((target.around + target.power).into(), free);
    let first = first_layer(@start, free);
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut count: u8 = 1;
    let gap = BfsInternal::gap(@start, @target);
    let mut skip = if gap > 2 {
        gap - 2
    } else {
        0
    };
    while skip != 0 {
        skip -= 1;
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    if touches(low, high, goal) {
        return count + 1;
    }
    loop {
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        let (middle_low, middle_high) = (low, high);
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 2;
        if touches(low, high, closed) {
            if touches(middle_low, middle_high, goal) {
                break count;
            }
            break count + 1;
        }
    }
}

/// Target tested on the unvisited set: reached when a goal tile left it.
fn distance_free_test(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let goal = goal(@target, free);
    let first = first_layer(@start, free);
    let mut low = first.low;
    let mut high = first.high;
    let mut free_low = free.low - low;
    let mut free_high = free.high - high;
    let mut count: u8 = 1;
    let gap = BfsInternal::gap(@start, @target);
    let mut skip = if gap > 2 {
        gap - 2
    } else {
        0
    };
    while skip != 0 {
        skip -= 1;
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    loop {
        let (left_low, _, _) = Bits::bitwise(free_low, goal.low);
        let (left_high, _, _) = Bits::bitwise(free_high, goal.high);
        if left_low != goal.low || left_high != goal.high {
            break;
        }
        assert!(BfsInternal::layer(@step, ref low, ref high, ref free_low, ref free_high));
        count += 1;
    }
    count + 1
}

/// Corelib `u256` operators (`Layout::expand`, `&`, `-`) instead of the local bitwise triple.
fn distance_corelib(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u8 {
    let (_, _, start, target, free) = setup(grid, width, height, from, to);
    let layout = LayoutTrait::new(width, height);
    let goal = goal(@target, free);
    let mut layer = first_layer(@start, free);
    let mut unvisited = free - layer;
    let mut count: u8 = 1;
    let gap = BfsInternal::gap(@start, @target);
    let mut skip = if gap > 2 {
        gap - 2
    } else {
        0
    };
    while skip != 0 {
        skip -= 1;
        layer = Variants::expand_felt(@layout, layer) & unvisited;
        unvisited = unvisited - layer;
        count += 1;
    }
    while layer & goal == 0 {
        layer = Variants::expand_felt(@layout, layer) & unvisited;
        assert!(layer != 0);
        unvisited = unvisited - layer;
        count += 1;
    }
    count + 1
}

/// Bidirectional: two frontiers expanded in turn, stop when a new layer meets the other
/// frontier (it cannot meet an older layer first), or when a frontier runs out.
fn distance_bidirectional(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Option<u8> {
    let (step, _, start, target, free) = setup(grid, width, height, from, to);
    let mut a: u256 = start.power.into();
    let mut b: u256 = target.power.into();
    let mut free_a = free - a;
    let mut free_b = free - b;
    let mut count: u8 = 0;
    loop {
        let (low, high) = step.dilate(a.low, a.high, Bits::to_felt(a));
        let next = Bits::and(u256 { low, high }, free_a);
        if next == 0 {
            break Option::None;
        }
        count += 1;
        if !(Bits::and(next, b) == 0) {
            break Option::Some(count);
        }
        free_a = free_a - next;
        a = next;
        let (low, high) = step.dilate(b.low, b.high, Bits::to_felt(b));
        let next = Bits::and(u256 { low, high }, free_b);
        if next == 0 {
            break Option::None;
        }
        count += 1;
        if !(Bits::and(next, a) == 0) {
            break Option::Some(count);
        }
        free_b = free_b - next;
        b = next;
    }
}

// Variant: scalar queue BFS, bitmap visited set, parents in a dictionary

fn search_scalar(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
    let open = BfsInternal::check(grid, width, height, from, to);
    let free = open & LayoutTrait::interior(width, height).into();
    let period: NonZero<u8> = (2 * width).try_into().unwrap();
    let mut visited: u256 = Bits::pow(from).into();
    let mut parents: Felt252Dict<u8> = Default::default();
    let mut queue: Array<u8> = array![from];
    let mut found = false;
    while let Option::Some(current) = queue.pop_front() {
        if current == to {
            found = true;
            break;
        }
        let (_, rem) = DivRem::div_rem(current, period);
        let neighbours = if rem < width {
            [
                current - 1, current + width - 1, current + width, current + 1, current - width,
                current - width - 1,
            ]
        } else {
            [
                current - 1, current + width, current + width + 1, current + 1, current + 1 - width,
                current - width,
            ]
        };
        for next in neighbours.span() {
            let next = *next;
            if Bits::get(free, next) && !Bits::get(visited, next) {
                visited = set_bit(visited, next);
                parents.insert(next.into(), current);
                queue.append(next);
            }
        }
    }
    let mut path: Array<u8> = array![];
    if !found {
        return path.span();
    }
    let mut current = to;
    while current != from {
        path.append(current);
        current = parents.get(current.into());
    }
    path.span()
}

#[inline(always)]
fn set_bit(value: u256, index: u8) -> u256 {
    if index < 128 {
        u256 { low: value.low | *POW128.span().at(index.into()), high: value.high }
    } else {
        u256 { low: value.low, high: value.high | *POW128.span().at(index.into() - 128) }
    }
}

// Benchmarks

// Library: search

#[test]
#[available_gas(l2_gas: 113000)]
fn bench_bfs_search_empty_near_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 599000)]
fn bench_bfs_search_empty_far_17x14() {
    let path = Bfs::search(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 118000)]
fn bench_bfs_search_cave_near_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 742000)]
fn bench_bfs_search_cave_far_17x14() {
    let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 108000)]
fn bench_bfs_search_maze_near_17x14() {
    let path = Bfs::search(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1596000)]
fn bench_bfs_search_maze_far_17x14() {
    let path = Bfs::search(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 108000)]
fn bench_bfs_search_serpentine_near_17x14() {
    let path = Bfs::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2659000)]
fn bench_bfs_search_serpentine_far_17x14() {
    let path = Bfs::search(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 280000)]
fn bench_bfs_search_unreachable_near_17x14() {
    let path = Bfs::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 277000)]
fn bench_bfs_search_unreachable_far_17x14() {
    let path = Bfs::search(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 87000)]
fn bench_bfs_search_empty_near_7x7() {
    let path = Bfs::search(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 139000)]
fn bench_bfs_search_empty_far_7x7() {
    let path = Bfs::search(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 86000)]
fn bench_bfs_search_cave_near_7x7() {
    let path = Bfs::search(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 139000)]
fn bench_bfs_search_cave_far_7x7() {
    let path = Bfs::search(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 83000)]
fn bench_bfs_search_maze_near_7x7() {
    let path = Bfs::search(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 252000)]
fn bench_bfs_search_maze_far_7x7() {
    let path = Bfs::search(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 85000)]
fn bench_bfs_search_serpentine_near_7x7() {
    let path = Bfs::search(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO);
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 271000)]
fn bench_bfs_search_serpentine_far_7x7() {
    let path = Bfs::search(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO);
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 72000)]
fn bench_bfs_search_unreachable_near_7x7() {
    let path = Bfs::search(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 95000)]
fn bench_bfs_search_unreachable_far_7x7() {
    let path = Bfs::search(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO);
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

// Library: distance

#[test]
#[available_gas(l2_gas: 428000)]
fn bench_bfs_distance_empty_far_17x14() {
    let distance = Bfs::distance(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 528000)]
fn bench_bfs_distance_cave_far_17x14() {
    let distance = Bfs::distance(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1112000)]
fn bench_bfs_distance_maze_far_17x14() {
    let distance = Bfs::distance(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1863000)]
fn bench_bfs_distance_serpentine_far_17x14() {
    let distance = Bfs::distance(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 273000)]
fn bench_bfs_distance_unreachable_far_17x14() {
    let distance = Bfs::distance(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 94000)]
fn bench_bfs_distance_empty_far_7x7() {
    let distance = Bfs::distance(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 94000)]
fn bench_bfs_distance_cave_far_7x7() {
    let distance = Bfs::distance(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 163000)]
fn bench_bfs_distance_maze_far_7x7() {
    let distance = Bfs::distance(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 177000)]
fn bench_bfs_distance_serpentine_far_7x7() {
    let distance = Bfs::distance(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 92000)]
fn bench_bfs_distance_unreachable_far_7x7() {
    let distance = Bfs::distance(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    let expected: u32 = match distance {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(expected == UNREACHABLE_7X7_FAR_DISTANCE);
}

// Library: reachable, and `Caver::keep_component` on the same inputs

#[test]
#[available_gas(l2_gas: 585000)]
fn bench_bfs_reachable_cave_17x14() {
    let component = Bfs::reachable(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 612000)]
fn bench_bfs_keep_component_cave_17x14() {
    let component = Caver::keep_component(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 1213000)]
fn bench_bfs_reachable_maze_17x14() {
    let component = Bfs::reachable(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 1308000)]
fn bench_bfs_keep_component_maze_17x14() {
    let component = Caver::keep_component(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 2004000)]
fn bench_bfs_reachable_serpentine_17x14() {
    let component = Bfs::reachable(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 2185000)]
fn bench_bfs_keep_component_serpentine_17x14() {
    let component = Caver::keep_component(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 291000)]
fn bench_bfs_reachable_unreachable_17x14() {
    let component = Bfs::reachable(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 298000)]
fn bench_bfs_keep_component_unreachable_17x14() {
    let component = Caver::keep_component(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 110000)]
fn bench_bfs_reachable_cave_7x7() {
    let component = Bfs::reachable(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 179000)]
fn bench_bfs_keep_component_cave_7x7() {
    let component = Caver::keep_component(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 184000)]
fn bench_bfs_reachable_maze_7x7() {
    let component = Bfs::reachable(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 326000)]
fn bench_bfs_keep_component_maze_7x7() {
    let component = Caver::keep_component(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 195000)]
fn bench_bfs_reachable_serpentine_7x7() {
    let component = Bfs::reachable(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 347000)]
fn bench_bfs_keep_component_serpentine_7x7() {
    let component = Caver::keep_component(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 89000)]
fn bench_bfs_reachable_unreachable_7x7() {
    let component = Bfs::reachable(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM);
    assert!(component != 0);
}

#[test]
#[available_gas(l2_gas: 137000)]
fn bench_bfs_keep_component_unreachable_7x7() {
    let component = Caver::keep_component(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM);
    assert!(component != 0);
}

// Library: tiles within range

#[test]
#[available_gas(l2_gas: 97000)]
fn bench_bfs_range_3_empty_17x14() {
    let ball = Bfs::tiles_within_range(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 168000)]
fn bench_bfs_range_6_empty_17x14() {
    let ball = Bfs::tiles_within_range(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, 6);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 89000)]
fn bench_bfs_range_3_cave_17x14() {
    let ball = Bfs::tiles_within_range(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 154000)]
fn bench_bfs_range_6_cave_17x14() {
    let ball = Bfs::tiles_within_range(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 6);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 96000)]
fn bench_bfs_range_3_maze_17x14() {
    let ball = Bfs::tiles_within_range(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 158000)]
fn bench_bfs_range_6_maze_17x14() {
    let ball = Bfs::tiles_within_range(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, 6);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 66000)]
fn bench_bfs_range_3_empty_7x7() {
    let ball = Bfs::tiles_within_range(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 98000)]
fn bench_bfs_range_6_empty_7x7() {
    let ball = Bfs::tiles_within_range(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, 6);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 66000)]
fn bench_bfs_range_3_cave_7x7() {
    let ball = Bfs::tiles_within_range(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 98000)]
fn bench_bfs_range_6_cave_7x7() {
    let ball = Bfs::tiles_within_range(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, 6);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 66000)]
fn bench_bfs_range_3_maze_7x7() {
    let ball = Bfs::tiles_within_range(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, 3);
    assert!(ball != 0);
}

#[test]
#[available_gas(l2_gas: 98000)]
fn bench_bfs_range_6_maze_7x7() {
    let ball = Bfs::tiles_within_range(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, 6);
    assert!(ball != 0);
}

// Variants: layer storage (library: `bench_bfs_search_*`)

#[test]
#[available_gas(l2_gas: 702000)]
fn bench_bfs_variant_felt_layers_empty_17x14() {
    let path = search_felt_layers(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1015000)]
fn bench_bfs_variant_checkpoints_empty_17x14() {
    let path = search_checkpoints(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 860000)]
fn bench_bfs_variant_felt_layers_cave_17x14() {
    let path = search_felt_layers(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1283000)]
fn bench_bfs_variant_checkpoints_cave_17x14() {
    let path = search_checkpoints(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1802000)]
fn bench_bfs_variant_felt_layers_maze_17x14() {
    let path = search_felt_layers(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2779000)]
fn bench_bfs_variant_checkpoints_maze_17x14() {
    let path = search_checkpoints(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2980000)]
fn bench_bfs_variant_felt_layers_serpentine_17x14() {
    let path = search_felt_layers(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 4659000)]
fn bench_bfs_variant_checkpoints_serpentine_17x14() {
    let path = search_checkpoints(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 4457000)]
fn bench_bfs_variant_recompute_empty_17x14() {
    let path = search_recompute(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 6746000)]
fn bench_bfs_variant_recompute_cave_17x14() {
    let path = search_recompute(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

// Variants: backtracking step, plain loop

#[test]
#[available_gas(l2_gas: 686000)]
fn bench_bfs_variant_back_harness_empty_17x14() {
    let path = search_back_harness(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 888000)]
fn bench_bfs_variant_back_bits_empty_17x14() {
    let path = search_back_bits(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 688000)]
fn bench_bfs_variant_back_straight_empty_17x14() {
    let path = search_back_straight(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 692000)]
fn bench_bfs_variant_back_window_empty_17x14() {
    let path = search_back_window(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 848000)]
fn bench_bfs_variant_back_harness_cave_17x14() {
    let path = search_back_harness(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1038000)]
fn bench_bfs_variant_back_bits_cave_17x14() {
    let path = search_back_bits(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 914000)]
fn bench_bfs_variant_back_straight_cave_17x14() {
    let path = search_back_straight(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 851000)]
fn bench_bfs_variant_back_window_cave_17x14() {
    let path = search_back_window(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1779000)]
fn bench_bfs_variant_back_harness_maze_17x14() {
    let path = search_back_harness(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2321000)]
fn bench_bfs_variant_back_bits_maze_17x14() {
    let path = search_back_bits(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2202000)]
fn bench_bfs_variant_back_straight_maze_17x14() {
    let path = search_back_straight(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1768000)]
fn bench_bfs_variant_back_window_maze_17x14() {
    let path = search_back_window(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2953000)]
fn bench_bfs_variant_back_harness_serpentine_17x14() {
    let path = search_back_harness(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3564000)]
fn bench_bfs_variant_back_bits_serpentine_17x14() {
    let path = search_back_bits(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 3066000)]
fn bench_bfs_variant_back_straight_serpentine_17x14() {
    let path = search_back_straight(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2908000)]
fn bench_bfs_variant_back_window_serpentine_17x14() {
    let path = search_back_window(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

// Variants: target test and set operations, forward pass only, plain loop

#[test]
#[available_gas(l2_gas: 493000)]
fn bench_bfs_variant_distance_harness_empty_17x14() {
    let distance: u32 = distance_harness(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 529000)]
fn bench_bfs_variant_distance_no_gap_empty_17x14() {
    let distance: u32 = distance_no_gap(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 493000)]
fn bench_bfs_variant_distance_harness_two_empty_17x14() {
    let distance: u32 = distance_harness_two(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 492000)]
fn bench_bfs_variant_distance_every_two_empty_17x14() {
    let distance: u32 = distance_every_two(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 494000)]
fn bench_bfs_variant_distance_free_test_empty_17x14() {
    let distance: u32 = distance_free_test(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 546000)]
fn bench_bfs_variant_distance_corelib_empty_17x14() {
    let distance: u32 = distance_corelib(
        EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
    )
        .into();
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 647000)]
fn bench_bfs_variant_distance_harness_cave_17x14() {
    let distance: u32 = distance_harness(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO)
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 637000)]
fn bench_bfs_variant_distance_no_gap_cave_17x14() {
    let distance: u32 = distance_no_gap(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO)
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 615000)]
fn bench_bfs_variant_distance_harness_two_cave_17x14() {
    let distance: u32 = distance_harness_two(
        CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 619000)]
fn bench_bfs_variant_distance_every_two_cave_17x14() {
    let distance: u32 = distance_every_two(
        CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 654000)]
fn bench_bfs_variant_distance_free_test_cave_17x14() {
    let distance: u32 = distance_free_test(
        CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 722000)]
fn bench_bfs_variant_distance_corelib_cave_17x14() {
    let distance: u32 = distance_corelib(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO)
        .into();
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1319000)]
fn bench_bfs_variant_distance_harness_maze_17x14() {
    let distance: u32 = distance_harness(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO)
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1343000)]
fn bench_bfs_variant_distance_no_gap_maze_17x14() {
    let distance: u32 = distance_no_gap(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO)
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1263000)]
fn bench_bfs_variant_distance_harness_two_maze_17x14() {
    let distance: u32 = distance_harness_two(
        MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1231000)]
fn bench_bfs_variant_distance_every_two_maze_17x14() {
    let distance: u32 = distance_every_two(
        MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1331000)]
fn bench_bfs_variant_distance_free_test_maze_17x14() {
    let distance: u32 = distance_free_test(
        MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1481000)]
fn bench_bfs_variant_distance_corelib_maze_17x14() {
    let distance: u32 = distance_corelib(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO)
        .into();
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2224000)]
fn bench_bfs_variant_distance_harness_serpentine_17x14() {
    let distance: u32 = distance_harness(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2234000)]
fn bench_bfs_variant_distance_no_gap_serpentine_17x14() {
    let distance: u32 = distance_no_gap(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2107000)]
fn bench_bfs_variant_distance_harness_two_serpentine_17x14() {
    let distance: u32 = distance_harness_two(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2038000)]
fn bench_bfs_variant_distance_every_two_serpentine_17x14() {
    let distance: u32 = distance_every_two(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2250000)]
fn bench_bfs_variant_distance_free_test_serpentine_17x14() {
    let distance: u32 = distance_free_test(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2503000)]
fn bench_bfs_variant_distance_corelib_serpentine_17x14() {
    let distance: u32 = distance_corelib(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    )
        .into();
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

// Variant: bidirectional (library: `bench_bfs_distance_*`)

#[test]
#[available_gas(l2_gas: 153000)]
fn bench_bfs_variant_bidirectional_empty_near_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 552000)]
fn bench_bfs_variant_bidirectional_empty_far_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 158000)]
fn bench_bfs_variant_bidirectional_cave_near_17x14() {
    let distance: u32 =
        match distance_bidirectional(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 647000)]
fn bench_bfs_variant_bidirectional_cave_far_17x14() {
    let distance: u32 =
        match distance_bidirectional(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 146000)]
fn bench_bfs_variant_bidirectional_maze_near_17x14() {
    let distance: u32 =
        match distance_bidirectional(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1360000)]
fn bench_bfs_variant_bidirectional_maze_far_17x14() {
    let distance: u32 =
        match distance_bidirectional(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 147000)]
fn bench_bfs_variant_bidirectional_serpentine_near_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2254000)]
fn bench_bfs_variant_bidirectional_serpentine_far_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 568000)]
fn bench_bfs_variant_bidirectional_unreachable_near_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 649000)]
fn bench_bfs_variant_bidirectional_unreachable_far_17x14() {
    let distance: u32 =
        match distance_bidirectional(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
        ) {
        Option::Some(distance) => distance.into(),
        Option::None => 0,
    };
    assert!(distance == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 275000)]
fn bench_bfs_distance_unreachable_near_17x14_library() {
    assert!(
        Bfs::distance(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
        )
            .is_none(),
    );
}

#[test]
#[available_gas(l2_gas: 273000)]
fn bench_bfs_distance_unreachable_far_17x14_library() {
    assert!(
        Bfs::distance(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
        )
            .is_none(),
    );
}

// Variant: two-limb path on boards of at most 128 bits (library: single limb)

#[test]
#[available_gas(l2_gas: 204000)]
fn bench_bfs_variant_wide_empty_far_7x7() {
    let (step, back, start, target, free) = setup(
        EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO,
    );
    let path = BfsInternal::search_wide(@step, back, @start, @target, 7, free);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 204000)]
fn bench_bfs_variant_wide_cave_far_7x7() {
    let (step, back, start, target, free) = setup(
        CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO,
    );
    let path = BfsInternal::search_wide(@step, back, @start, @target, 7, free);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 392000)]
fn bench_bfs_variant_wide_maze_far_7x7() {
    let (step, back, start, target, free) = setup(
        MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO,
    );
    let path = BfsInternal::search_wide(@step, back, @start, @target, 7, free);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 423000)]
fn bench_bfs_variant_wide_serpentine_far_7x7() {
    let (step, back, start, target, free) = setup(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO,
    );
    let path = BfsInternal::search_wide(@step, back, @start, @target, 7, free);
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 151000)]
fn bench_bfs_variant_wide_unreachable_far_7x7() {
    let (step, back, start, target, free) = setup(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    let path = BfsInternal::search_wide(@step, back, @start, @target, 7, free);
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}

// Variant: scalar queue BFS, bitmap visited set (baseline to beat)

#[test]
#[available_gas(l2_gas: 3963000)]
fn bench_bfs_variant_scalar_empty_near_17x14() {
    let path = search_scalar(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
    assert!(path.len() == EMPTY_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 18147000)]
fn bench_bfs_variant_scalar_empty_far_17x14() {
    let path = search_scalar(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
    assert!(path.len() == EMPTY_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2048000)]
fn bench_bfs_variant_scalar_cave_near_17x14() {
    let path = search_scalar(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
    assert!(path.len() == CAVE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 13010000)]
fn bench_bfs_variant_scalar_cave_far_17x14() {
    let path = search_scalar(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
    assert!(path.len() == CAVE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 411000)]
fn bench_bfs_variant_scalar_maze_near_17x14() {
    let path = search_scalar(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
    assert!(path.len() == MAZE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 8218000)]
fn bench_bfs_variant_scalar_maze_far_17x14() {
    let path = search_scalar(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
    assert!(path.len() == MAZE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 499000)]
fn bench_bfs_variant_scalar_serpentine_near_17x14() {
    let path = search_scalar(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 8621000)]
fn bench_bfs_variant_scalar_serpentine_far_17x14() {
    let path = search_scalar(
        SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO,
    );
    assert!(path.len() == SERPENTINE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 8394000)]
fn bench_bfs_variant_scalar_unreachable_near_17x14() {
    let path = search_scalar(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 8394000)]
fn bench_bfs_variant_scalar_unreachable_far_17x14() {
    let path = search_scalar(
        UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_17X14_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1938000)]
fn bench_bfs_variant_scalar_empty_near_7x7() {
    let path = search_scalar(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
    assert!(path.len() == EMPTY_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2372000)]
fn bench_bfs_variant_scalar_empty_far_7x7() {
    let path = search_scalar(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
    assert!(path.len() == EMPTY_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2005000)]
fn bench_bfs_variant_scalar_cave_near_7x7() {
    let path = search_scalar(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
    assert!(path.len() == CAVE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 2172000)]
fn bench_bfs_variant_scalar_cave_far_7x7() {
    let path = search_scalar(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
    assert!(path.len() == CAVE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 584000)]
fn bench_bfs_variant_scalar_maze_near_7x7() {
    let path = search_scalar(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
    assert!(path.len() == MAZE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1388000)]
fn bench_bfs_variant_scalar_maze_far_7x7() {
    let path = search_scalar(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
    assert!(path.len() == MAZE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 584000)]
fn bench_bfs_variant_scalar_serpentine_near_7x7() {
    let path = search_scalar(
        SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO,
    );
    assert!(path.len() == SERPENTINE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 1493000)]
fn bench_bfs_variant_scalar_serpentine_far_7x7() {
    let path = search_scalar(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO);
    assert!(path.len() == SERPENTINE_7X7_FAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 953000)]
fn bench_bfs_variant_scalar_unreachable_near_7x7() {
    let path = search_scalar(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_NEAR_DISTANCE);
}

#[test]
#[available_gas(l2_gas: 953000)]
fn bench_bfs_variant_scalar_unreachable_far_7x7() {
    let path = search_scalar(
        UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO,
    );
    assert!(path.len() == UNREACHABLE_7X7_FAR_DISTANCE);
}
