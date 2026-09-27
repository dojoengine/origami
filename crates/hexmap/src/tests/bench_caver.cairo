//! Gas benchmarks of lot L4, cave generator: one `#[test]` per fixture and algorithm, each with an
//! `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! The losing formulations live here (test-only), next to a scalar reference automaton that every
//! formulation is checked against.

// Core imports

use core::num::traits::OverflowingAdd;
use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::generators::caver::Caver;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::helpers::printer::HexPrinter;
use origami_hexmap::tests::fixtures::{
    MAZE_17X14, MAZE_17X14_FAR_FROM, SERPENTINE_17X14, SERPENTINE_17X14_FAR_FROM,
};
use origami_hexmap::tests::variants::Variants;
use origami_hexmap::types::direction::Direction;

// Constants

const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
const SEED: felt252 = 'CAVER';
/// `fill_half(17, 14, SEED)`.
const FILL_17X14: felt252 = 0xced810e216a71359cdfca69663bef8793026be673435110eb080000;
/// `fill_half(7, 7, SEED)`.
const FILL_7X7: felt252 = 0x110e30a9500;
/// `Caver::generate(17, 14, 3, SEED)`.
const CAVE_17X14: felt252 = 0x47c833e61fe70ff9cffcc7fe73fff07ffc7ffc7f3e3f100e0000000;

// Reference

/// Scalar reference: one synchronous generation, tile by tile, with `Layout::neighbor`.
/// `born` and `survive` are the minimum floor-neighbour counts.
pub fn reference_step(grid: felt252, width: u8, height: u8, born: u8, survive: u8) -> felt252 {
    let open: u256 = grid.into();
    let directions = array![
        Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
        Direction::SouthWest, Direction::SouthEast,
    ];
    let mut next: felt252 = 0;
    let mut y: u8 = 1;
    while y != height - 1 {
        let mut x: u8 = 1;
        while x != width - 1 {
            let position = y * width + x;
            let mut count: u8 = 0;
            for direction in directions.span() {
                if let Some(neighbor) = LayoutTrait::neighbor(width, height, position, *direction) {
                    if Bits::get(open, neighbor) {
                        count += 1;
                    }
                }
            }
            let alive = Bits::get(open, position);
            if (alive && count >= survive) || (!alive && count >= born) {
                next += Bits::pow(position);
            }
            x += 1;
        }
        y += 1;
    }
    next
}

/// Scalar reference over `order` generations.
pub fn reference(
    grid: felt252, width: u8, height: u8, order: u8, born: u8, survive: u8,
) -> felt252 {
    let mut grid = grid;
    let mut order = order;
    while order != 0 {
        order -= 1;
        grid = reference_step(grid, width, height, born, survive);
    }
    grid
}

// Variants

/// Per-map constants of the variants.
#[derive(Copy, Drop)]
pub struct Consts {
    pub even: u256,
    pub interior: u256,
    pub up_even: felt252,
    pub up_odd: felt252,
    pub up_wide: felt252,
    pub down_even: felt252,
    pub down_odd: felt252,
    pub down_wide: felt252,
}

pub fn consts(width: u8, height: u8) -> Consts {
    let layout = LayoutTrait::new(width, height);
    Consts {
        even: layout.even,
        interior: LayoutTrait::interior(width, height).into(),
        up_even: layout.up_even,
        up_odd: layout.up_odd,
        up_wide: layout.up_odd + layout.up_odd,
        down_even: layout.down_even,
        down_odd: layout.down_odd,
        down_wide: layout.down_odd + layout.down_odd,
    }
}

/// One generation of a variant.
pub trait Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256;
}

/// `order` generations of a variant, same loop as the library.
pub fn evolve<impl S: Step>(width: u8, height: u8, order: u8, grid: felt252) -> felt252 {
    let consts = consts(width, height);
    let mut felt = grid;
    let mut grid: u256 = grid.into();
    let mut order = order;
    while order != 0 {
        order -= 1;
        grid = S::step(@consts, grid, felt);
        felt = Bits::to_felt(grid);
    }
    felt
}

#[inline(always)]
fn bw(lhs: u256, rhs: u256) -> (u256, u256, u256) {
    let (la, lx, lo) = Bits::bitwise(lhs.low, rhs.low);
    let (ha, hx, ho) = Bits::bitwise(lhs.high, rhs.high);
    (u256 { low: la, high: ha }, u256 { low: lx, high: hx }, u256 { low: lo, high: ho })
}

/// Sum of two disjoint bitmaps, limb by limb (no carry can occur).
#[inline(always)]
fn add(lhs: u256, rhs: u256) -> u256 {
    u256 { low: lhs.low + rhs.low, high: lhs.high + rhs.high }
}

/// Library planes: one parity split, `north` and `south` are parity free (bit `i` is the grid at
/// `i + W` / `i - W`), only the two other vertical planes use the split.
#[inline(always)]
fn planes(consts: @Consts, grid: u256, felt: felt252) -> (u256, u256, u256, u256, u256, u256) {
    let c = *consts;
    let (grid_even, _, _) = bw(grid, c.even);
    let grid_even = Bits::to_felt(grid_even);
    let grid_odd = felt - grid_even;
    (
        (felt + felt).into(),
        (felt * INV_2).into(),
        (felt * c.down_odd).into(),
        (grid_odd * c.down_wide + grid_even * c.down_even).into(),
        (felt * c.up_odd).into(),
        (grid_odd * c.up_wide + grid_even * c.up_even).into(),
    )
}

/// Design planes (section 2.4): the 4 vertical planes all built from the parity halves.
#[inline(always)]
fn planes_split(
    consts: @Consts, grid: u256, felt: felt252,
) -> (u256, u256, u256, u256, u256, u256) {
    let c = *consts;
    let (grid_even, _, _) = bw(grid, c.even);
    let ge = Bits::to_felt(grid_even);
    let go = felt - ge;
    (
        (felt + felt).into(),
        (felt * INV_2).into(),
        (go * c.down_wide + ge * c.down_odd).into(),
        (go * c.down_odd + ge * c.down_even).into(),
        (go * c.up_wide + ge * c.up_odd).into(),
        (go * c.up_odd + ge * c.up_even).into(),
    )
}

/// Carry-save front end: full adders on (a, b, c) and (d, e, f), half adder on the sums.
/// Returns the three weight-2 carries and the weight-1 sum: `count = b0 + 2 * (c1 + c2 + c3)`.
#[inline(always)]
fn carries(a: u256, b: u256, c: u256, d: u256, e: u256, f: u256) -> (u256, u256, u256, u256) {
    let (ab, x, _) = bw(a, b);
    let (xc, s1, _) = bw(x, c);
    let (de, y, _) = bw(d, e);
    let (yf, s2, _) = bw(y, f);
    let (c3, b0, _) = bw(s1, s2);
    (add(ab, xc), add(de, yf), c3, b0)
}

/// At least 2 of 4 bitmaps.
#[inline(always)]
fn two_of_four(p: u256, q: u256, r: u256, s: u256) -> u256 {
    let (a1, x1, _) = bw(p, q);
    let (a2, x2, _) = bw(r, s);
    let (a3, _, _) = bw(x1, x2);
    let (_, _, a12) = bw(a1, a2);
    add(a12, a3)
}

/// Library final stage: full adder on the weight-2 carries, then `b2 | (grid & b1)`.
#[inline(always)]
fn full_count(c1: u256, c2: u256, c3: u256, grid: u256) -> u256 {
    let (a12, x12, _) = bw(c1, c2);
    let (x3, b1, _) = bw(x12, c3);
    let (g, _, _) = bw(grid, b1);
    let (_, _, next) = bw(add(a12, x3), g);
    next
}

/// B4/S2 with the final stage as "at least 2 of `c1, c2, c3, grid`" (`count = b0 + 2 * (c1 +
/// c2 + c3)`): same builtin count as the full count.
pub impl StepTwoOfFour of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let (c1, c2, c3, _) = carries(a, b, c, d, e, f);
        two_of_four(c1, c2, c3, grid)
    }
}

/// B4/S3: `b2 | (grid & b1 & b0)` = at least 2 of `c1, c2, c3, grid & b0`.
pub impl StepB4S3 of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let (c1, c2, c3, b0) = carries(a, b, c, d, e, f);
        let (g, _, _) = bw(grid, b0);
        two_of_four(c1, c2, c3, g)
    }
}

/// B3/S3: `count >= 3` = at least 2 of `c1, c2, c3, b0`, masked by the interior (border tiles can
/// have 3 floor neighbours).
pub impl StepB3S3 of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let (c1, c2, c3, b0) = carries(a, b, c, d, e, f);
        let (next, _, _) = bw(two_of_four(c1, c2, c3, b0), *consts.interior);
        next
    }
}

/// Library formulation (B4/S2, full count: third full adder on the carries, then
/// `b2 | (grid & b1)`, per-limb triple builtin), on `u256` values.
pub impl StepLibrary of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let (c1, c2, c3, _) = carries(a, b, c, d, e, f);
        full_count(c1, c2, c3, grid)
    }
}

/// Full count, East plane `2G` doubled limb by limb from the `u256` grid instead of converted.
pub impl StepEastAdd of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (_, b, c, d, e, f) = planes(consts, grid, felt);
        let (low, carry) = grid.low.overflowing_add(grid.low);
        let a = if carry {
            u256 { low, high: grid.high + grid.high + 1 }
        } else {
            u256 { low, high: grid.high + grid.high }
        };
        let (c1, c2, c3, _) = carries(a, b, c, d, e, f);
        full_count(c1, c2, c3, grid)
    }
}

/// Full count with the rule folded: `next = x3 + (a12 | (grid & b1))`, `x3` disjoint from both.
pub impl StepFolded of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let (c1, c2, c3, _) = carries(a, b, c, d, e, f);
        let (a12, x12, _) = bw(c1, c2);
        let (x3, b1, _) = bw(x12, c3);
        let (g, _, _) = bw(grid, b1);
        let (_, _, next) = bw(a12, g);
        add(next, x3)
    }
}

/// Design planes (all vertical planes from the parity halves), library network.
pub impl StepSplitPlanes of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes_split(consts, grid, felt);
        let (c1, c2, c3, _) = carries(a, b, c, d, e, f);
        full_count(c1, c2, c3, grid)
    }
}

/// Library network written with the corelib `u256` operators: one builtin application per
/// operator and limb, carries as `|`.
pub impl StepU256Ops of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes(consts, grid, felt);
        let ab = a & b;
        let x = a ^ b;
        let s1 = x ^ c;
        let c1 = ab | (x & c);
        let de = d & e;
        let y = d ^ e;
        let s2 = y ^ f;
        let c2 = de | (y & f);
        let c3 = s1 & s2;
        let x12 = c1 ^ c2;
        let b2 = (c1 & c2) | (x12 & c3);
        let b1 = x12 ^ c3;
        b2 | (grid & b1)
    }
}

/// Design network (section 2.4): AND-only adders, XOR and carries by field arithmetic, so every
/// intermediate goes back to `u256` for the next AND; rule `(b2 | (grid & b1)) & INTERIOR`.
pub impl StepDesign of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let (a, b, c, d, e, f) = planes_split(consts, grid, felt);
        let (s1, c1) = design_fa(a, b, c);
        let (s2, c2) = design_fa(d, e, f);
        // [Compute] Half adder: only the carry is used
        let c3 = s1.into() & s2.into();
        let (b1, b2) = design_fa(c1.into(), c2.into(), c3);
        let b1: u256 = b1.into();
        ((b2.into() | (grid & b1)) & *consts.interior)
    }
}

/// Design full adder: `ab = a & b; x = a + b - 2ab; xc = x & c; s = x + c - 2xc; carry = ab + xc`.
#[inline(always)]
fn design_fa(a: u256, b: u256, c: u256) -> (felt252, felt252) {
    let ab = Bits::to_felt(a & b);
    let x = Bits::to_felt(a) + Bits::to_felt(b) - 2 * ab;
    let xc = Bits::to_felt(x.into() & c);
    (x + Bits::to_felt(c) - 2 * xc, ab + xc)
}

/// Planes from shared sub-terms, like `expand`: the two vertical neighbours of a tile are an
/// adjacent pair of the next row, so the pair half adder `(G & G/2, G ^ G/2)` is computed once on
/// the source rows and shifted by parity, instead of 4 vertical planes.
pub impl StepPairs of Step {
    fn step(consts: @Consts, grid: u256, felt: felt252) -> u256 {
        let c = *consts;
        let half_felt = felt * INV_2;
        let half: u256 = half_felt.into();
        // [Compute] Pair half adder on the source rows: bit j = G[j] + G[j+1]
        let (pair_and, pair_xor, _) = bw(grid, half);
        let (and_even, _, _) = bw(pair_and, c.even);
        let (xor_even, _, _) = bw(pair_xor, c.even);
        let and_felt = Bits::to_felt(pair_and);
        let xor_felt = Bits::to_felt(pair_xor);
        let and_even = Bits::to_felt(and_even);
        let xor_even = Bits::to_felt(xor_even);
        let and_odd = and_felt - and_even;
        let xor_odd = xor_felt - xor_even;
        let up_and: u256 = (and_odd * c.down_wide + and_even * c.down_odd).into();
        let up_xor: u256 = (xor_odd * c.down_wide + xor_even * c.down_odd).into();
        let down_and: u256 = (and_odd * c.up_wide + and_even * c.up_odd).into();
        let down_xor: u256 = (xor_odd * c.up_wide + xor_even * c.up_odd).into();
        // [Compute] count = b0 + 2 * #(c, c', up_and, down_and)
        let (ew, x, _) = bw((felt + felt).into(), half);
        let (xu, s, _) = bw(x, up_xor);
        let carry = add(ew, xu);
        let (carry_down, _, _) = bw(s, down_xor);
        // [Compute] At least 2 of (carry, carry_down, up_and, down_and, grid)
        let (a1, x1, _) = bw(carry, carry_down);
        let (a2, x2, _) = bw(up_and, down_and);
        let (a3, _, o3) = bw(x1, x2);
        let (a4, _, _) = bw(grid, o3);
        let (_, _, a12) = bw(a1, a2);
        let (_, _, a34) = bw(a3, a4);
        let (_, _, next) = bw(a12, a34);
        next
    }
}

// Connectivity

/// Flood fill with a run fill after each dilation: `open + C` carries from the lowest bit of `C`
/// in each run of `open` up to the run end (toward West), so `open & ~(open + C)` completes every
/// reached run westward in one step. Exact: every run ends on the wall column `x = W - 1`.
pub fn keep_component_runs(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
    let open: u256 = grid.into();
    let layout = LayoutTrait::new(width, height);
    let mut component: u256 = Bits::pow(from).into();
    loop {
        let dilated = Variants::expand_felt(@layout, component) & open;
        let carried: u256 = (grid + Bits::to_felt(dilated)).into();
        let (kept, _, _) = bw(open, carried);
        let run = u256 { low: open.low - kept.low, high: open.high - kept.high };
        let (_, _, next) = bw(run, dilated);
        if next == component {
            break;
        }
        component = next;
    }
    Bits::to_felt(component)
}

/// `keep_component_runs` with the run fill before the dilation.
pub fn keep_component_runs_first(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
    let open: u256 = grid.into();
    let layout = LayoutTrait::new(width, height);
    let mut component: u256 = Bits::pow(from).into();
    loop {
        let carried: u256 = (grid + Bits::to_felt(component)).into();
        let (kept, _, _) = bw(open, carried);
        let run = u256 { low: open.low - kept.low, high: open.high - kept.high };
        let (_, _, filled) = bw(run, component);
        let next = Variants::expand_felt(@layout, filled) & open;
        if next == filled {
            component = next;
            break;
        }
        component = next;
    }
    Bits::to_felt(component)
}

// Initial fills

/// ~25 %: AND of two outputs of one permutation.
pub fn fill_sparse(width: u8, height: u8, seed: felt252) -> felt252 {
    let (lhs, rhs, _) = hades_permutation(seed, 0, 2);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    Bits::to_felt(lhs.into() & rhs.into() & interior)
}

/// ~50 %: one output (library).
pub fn fill_half(width: u8, height: u8, seed: felt252) -> felt252 {
    let (noise, _, _) = hades_permutation(seed, 0, 2);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    Bits::to_felt(noise.into() & interior)
}

/// ~75 %: OR of two outputs of one permutation.
pub fn fill_dense(width: u8, height: u8, seed: felt252) -> felt252 {
    let (lhs, rhs, _) = hades_permutation(seed, 0, 2);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    Bits::to_felt((lhs.into() | rhs.into()) & interior)
}

// Correctness of the variants

fn check_variants(width: u8, height: u8, seed: felt252) {
    let grid = fill_half(width, height, seed);
    let order = 4;
    let b4s2 = reference(grid, width, height, order, 4, 2);
    assert!(Caver::generate(width, height, order, seed) == b4s2);
    assert!(evolve::<StepTwoOfFour>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepLibrary>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepSplitPlanes>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepU256Ops>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepDesign>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepPairs>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepEastAdd>(width, height, order, grid) == b4s2);
    assert!(evolve::<StepFolded>(width, height, order, grid) == b4s2);
    assert!(
        evolve::<
            StepB4S3,
        >(width, height, order, grid) == reference(grid, width, height, order, 4, 3),
    );
    assert!(
        evolve::<
            StepB3S3,
        >(width, height, order, grid) == reference(grid, width, height, order, 3, 3),
    );
    let sparse = fill_sparse(width, height, seed);
    assert!(
        evolve::<
            StepTwoOfFour,
        >(width, height, order, sparse) == reference(sparse, width, height, order, 4, 2),
    );
    let dense = fill_dense(width, height, seed);
    assert!(
        evolve::<
            StepB3S3,
        >(width, height, order, dense) == reference(dense, width, height, order, 3, 3),
    );
}

fn check_components(grid: felt252, width: u8, height: u8, from: u8) {
    let expected = Caver::keep_component(grid, width, height, from);
    assert!(keep_component_runs(grid, width, height, from) == expected);
    assert!(keep_component_runs_first(grid, width, height, from) == expected);
}

#[test]
fn test_bench_caver_components() {
    check_components(CAVE_17X14, 17, 14, 127);
    check_components(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
    check_components(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM);
    let mut seed = 1;
    while seed != 9 {
        let cave = Caver::generate(17, 14, 3, seed);
        let mut position: u8 = 0;
        while position < 238 {
            if Bits::get(cave.into(), position) {
                check_components(cave, 17, 14, position);
            }
            position += 23;
        }
        seed += 1;
    }
}

#[test]
fn test_bench_caver_variants_17x14() {
    check_variants(17, 14, 1);
    check_variants(17, 14, 2);
}

#[test]
fn test_bench_caver_variants_small() {
    check_variants(3, 3, 1);
    check_variants(7, 7, 1);
    check_variants(11, 11, 3);
}

#[test]
fn test_bench_caver_variants_extremes() {
    check_variants(19, 13, 1);
    check_variants(83, 3, 1);
    check_variants(3, 83, 1);
    check_variants(25, 10, 5);
}


// Benchmarks: library

#[test]
#[available_gas(l2_gas: 29000)]
fn bench_caver_generate_17x14_order_0() {
    assert!(Caver::generate(17, 14, 0, SEED) == FILL_17X14);
}

#[test]
#[available_gas(l2_gas: 80000)]
fn bench_caver_generate_17x14_order_1() {
    assert!(Caver::generate(17, 14, 1, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 155000)]
fn bench_caver_generate_17x14_order_3() {
    assert!(Caver::generate(17, 14, 3, SEED) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 230000)]
fn bench_caver_generate_17x14_order_5() {
    assert!(Caver::generate(17, 14, 5, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 155000)]
fn bench_caver_generate_19x13_order_3() {
    assert!(Caver::generate(19, 13, 3, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 29000)]
fn bench_caver_generate_7x7_order_0() {
    assert!(Caver::generate(7, 7, 0, SEED) == FILL_7X7);
}

#[test]
#[available_gas(l2_gas: 54000)]
fn bench_caver_generate_7x7_order_1() {
    assert!(Caver::generate(7, 7, 1, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 91000)]
fn bench_caver_generate_7x7_order_3() {
    assert!(Caver::generate(7, 7, 3, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 299000)]
fn bench_caver_keep_component_17x14() {
    // 7 * 17 + 8: centre of the board, floor in CAVE_17X14
    assert!(Caver::keep_component(CAVE_17X14, 17, 14, 127) != 0);
}

/// The `Caver::keep_component` of lot L4 (loser): dilate the whole component until stable,
/// `Layout::expand` of lot L0 and corelib `u256` operators. The library delegates to
/// `Bfs::reachable`, which dilates the frontier only.
pub fn keep_component_dilation(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
    let open: u256 = grid.into();
    let layout = LayoutTrait::new(width, height);
    let mut component: u256 = Bits::pow(from).into();
    loop {
        let next = Variants::expand_felt(@layout, component) & open;
        if next == component {
            break;
        }
        component = next;
    }
    Bits::to_felt(component)
}

#[test]
#[available_gas(l2_gas: 316000)]
fn bench_caver_variant_keep_component_dilation_17x14() {
    assert!(keep_component_dilation(CAVE_17X14, 17, 14, 127) != 0);
}

#[test]
#[available_gas(l2_gas: 454000)]
fn bench_caver_generate_connected_17x14() {
    let cave = Caver::generate(17, 14, 3, SEED);
    assert!(Caver::keep_component(cave, 17, 14, 127) != 0);
}

#[test]
#[available_gas(l2_gas: 396000)]
fn bench_caver_keep_component_runs_17x14() {
    assert!(keep_component_runs(CAVE_17X14, 17, 14, 127) != 0);
}

#[test]
#[available_gas(l2_gas: 400000)]
fn bench_caver_keep_component_runs_first_17x14() {
    assert!(keep_component_runs_first(CAVE_17X14, 17, 14, 127) != 0);
}

#[test]
#[available_gas(l2_gas: 1169000)]
fn bench_caver_keep_component_maze_17x14() {
    assert!(Caver::keep_component(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM) != 0);
}

#[test]
#[available_gas(l2_gas: 1518000)]
fn bench_caver_keep_component_runs_maze_17x14() {
    assert!(keep_component_runs(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM) != 0);
}

#[test]
#[available_gas(l2_gas: 1933000)]
fn bench_caver_keep_component_serpentine_17x14() {
    assert!(Caver::keep_component(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM) != 0);
}

#[test]
#[available_gas(l2_gas: 1581000)]
fn bench_caver_keep_component_runs_serpentine_17x14() {
    assert!(keep_component_runs(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM) != 0);
}

// Benchmarks: variants, 3 generations from the same fill (harness baseline: order 0)

#[test]
#[available_gas(l2_gas: 36000)]
fn bench_caver_variant_baseline_17x14() {
    assert!(evolve::<StepTwoOfFour>(17, 14, 0, FILL_17X14) == FILL_17X14);
}

#[test]
#[available_gas(l2_gas: 161000)]
fn bench_caver_variant_two_of_four_17x14() {
    assert!(evolve::<StepTwoOfFour>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 167000)]
fn bench_caver_variant_b4s3_17x14() {
    assert!(evolve::<StepB4S3>(17, 14, 3, FILL_17X14) != 0);
}

#[test]
#[available_gas(l2_gas: 165000)]
fn bench_caver_variant_b3s3_17x14() {
    assert!(evolve::<StepB3S3>(17, 14, 3, FILL_17X14) != 0);
}

#[test]
#[available_gas(l2_gas: 158000)]
fn bench_caver_variant_library_17x14() {
    assert!(evolve::<StepLibrary>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 163000)]
fn bench_caver_variant_east_add_17x14() {
    assert!(evolve::<StepEastAdd>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 161000)]
fn bench_caver_variant_folded_17x14() {
    assert!(evolve::<StepFolded>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 159000)]
fn bench_caver_variant_split_planes_17x14() {
    assert!(evolve::<StepSplitPlanes>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 194000)]
fn bench_caver_variant_u256_ops_17x14() {
    assert!(evolve::<StepU256Ops>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 215000)]
fn bench_caver_variant_design_17x14() {
    assert!(evolve::<StepDesign>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 171000)]
fn bench_caver_variant_pairs_17x14() {
    assert!(evolve::<StepPairs>(17, 14, 3, FILL_17X14) == CAVE_17X14);
}

#[test]
#[available_gas(l2_gas: 35000)]
fn bench_caver_variant_baseline_7x7() {
    assert!(evolve::<StepTwoOfFour>(7, 7, 0, FILL_7X7) == FILL_7X7);
}

#[test]
#[available_gas(l2_gas: 160000)]
fn bench_caver_variant_library_u256_7x7() {
    assert!(evolve::<StepTwoOfFour>(7, 7, 3, FILL_7X7) != 0);
}

// Benchmarks: initial fills

#[test]
#[available_gas(l2_gas: 34000)]
fn bench_caver_fill_sparse_17x14() {
    assert!(fill_sparse(17, 14, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 30000)]
fn bench_caver_fill_half_17x14() {
    assert!(fill_half(17, 14, SEED) == FILL_17X14);
}

#[test]
#[available_gas(l2_gas: 34000)]
fn bench_caver_fill_dense_17x14() {
    assert!(fill_dense(17, 14, SEED) != 0);
}

// Visual quality (printouts for the report, ignored in CI)

fn print_rule(rule: u8, fill: u8) {
    let mut seed: felt252 = 1;
    while seed != 4 {
        let grid = if fill == 0 {
            fill_sparse(17, 14, seed)
        } else if fill == 1 {
            fill_half(17, 14, seed)
        } else {
            fill_dense(17, 14, seed)
        };
        let mut order: u8 = 1;
        while order != 6 {
            let next = if rule == 0 {
                evolve::<StepTwoOfFour>(17, 14, order, grid)
            } else if rule == 1 {
                evolve::<StepB4S3>(17, 14, order, grid)
            } else {
                evolve::<StepB3S3>(17, 14, order, grid)
            };
            println!("rule {} fill {} seed {} order {}", rule, fill, seed, order);
            print!("{}", HexPrinter::render(next, 17, 14));
            order += 1;
        }
        seed += 1;
    }
}

/// Floor tiles, components and largest component of a grid.
fn components(grid: felt252, width: u8, height: u8) -> (u32, u32, u32) {
    let mut left = grid;
    let mut floor: u32 = 0;
    let mut count: u32 = 0;
    let mut largest: u32 = 0;
    let size = width * height;
    let mut position: u8 = 0;
    while position != size {
        if Bits::get(left.into(), position) {
            let component = Caver::keep_component(left, width, height, position);
            let tiles: u32 = Bits::popcount(component.into()).into();
            floor += tiles;
            count += 1;
            if tiles > largest {
                largest = tiles;
            }
            left -= component;
        }
        position += 1;
    }
    (floor, count, largest)
}

fn print_stats(rule: u8, order: u8) {
    let mut seed: felt252 = 1;
    let mut floor: u32 = 0;
    let mut count: u32 = 0;
    let mut largest: u32 = 0;
    let mut empty: u32 = 0;
    while seed != 33 {
        let grid = fill_half(17, 14, seed);
        let next = if rule == 0 {
            evolve::<StepTwoOfFour>(17, 14, order, grid)
        } else if rule == 1 {
            evolve::<StepB4S3>(17, 14, order, grid)
        } else {
            evolve::<StepB3S3>(17, 14, order, grid)
        };
        let (f, c, l) = components(next, 17, 14);
        floor += f;
        count += c;
        largest += l;
        if f < 36 {
            empty += 1;
        }
        seed += 1;
    }
    println!(
        "stats rule {} order {}: floor {} components {} largest {} (sums over 32 seeds), maps under 20% floor {}",
        rule,
        order,
        floor,
        count,
        largest,
        empty,
    );
}

#[test]
#[ignore] // Printouts for the report: `snforge test test_bench_caver_print_stats --include-ignored`
fn test_bench_caver_print_stats() {
    let mut rule = 0;
    while rule != 3 {
        print_stats(rule, 1);
        print_stats(rule, 3);
        print_stats(rule, 5);
        rule += 1;
    }
}

#[test]
#[ignore] // Printouts for the report: `snforge test test_bench_caver_print_rules --include-ignored`
fn test_bench_caver_print_rules() {
    print_rule(0, 1);
    print_rule(1, 1);
    print_rule(2, 1);
}

#[test]
#[ignore] // Printouts for the report: `snforge test test_bench_caver_print_fills --include-ignored`
fn test_bench_caver_print_fills() {
    let mut rule = 0;
    while rule != 3 {
        print_rule(rule, 0);
        print_rule(rule, 2);
        rule += 1;
    }
}
