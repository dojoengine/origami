//! Gas benchmarks of lot L7, spreader: one fuzz test per algorithm, fixture and count, see
//! `GAS.md`. The cost depends on the seed, so every benchmark runs 256 seeds (`fuzzer`, fixed
//! fuzzer seed, argument `k: u16`, seed `'SEED' + k`); snforge reports the max, min and mean per
//! run. Per call = run - mean of `bench_spreader_baseline` (the harness around a trivial body).
//! `#[available_gas]` applies to every run: the budget is the max + 5 %.
//! The measured losers live here, test-only; the winner is `Spreader::generate`.
//!
//! CI time: the library benchmarks take their number of runs from the command line (256 by
//! default, `--fuzzer-runs 64` in the pull-request job: the budgets hold on any subset of the
//! seeds); the losers are `#[ignore]`d and run with the non-blocking job on `main`. Every figure
//! of `GAS.md` comes from `snforge test --package origami_hexmap bench_spreader --include-ignored`.

// Core imports

use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::generators::spreader::{BitSetTrait, Spreader, SpreaderInternal};
use origami_hexmap::helpers::bits::{BYTES_ONE, Bits, POW128, TWO_POW_120};
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::tests::fixtures::*;

// Constants

const SEED: felt252 = 'SEED';
/// 10x25 board (250 bits), 2 walkable tiles in opposite corners (audit A2, finding 1).
const SPARSE2_10X25: felt252 = 0x200000000000000000000000000000000000000000000000000000000000001;
/// 17x14 board, 5 walkable tiles (20, 77, 130, 185, 218) of 238.
const SPARSE5_17X14: felt252 = 0x4000000020000000000000400000000000020000000000000100000;
/// 17x14 board, 71 interior tiles drawn at random (30 % of the board, maze-like density).
const D30_17X14: felt252 = 0xb10c5a483196889444060584021da123f42200343911d60c7180000;

/// Split a grid, count its walkable tiles and choose between the picked set and its complement.
/// Returns `(value, walkable, complement, draws)`.
fn prepare(grid: felt252, count: u8) -> (u256, u8, bool, u8) {
    let value: u256 = grid.into();
    let walkable = Bits::popcount(value);
    assert(count <= walkable, 'Spreader: not enough place');
    let complement = count > walkable - count;
    let draws = if complement {
        walkable - count
    } else {
        count
    };
    (value, walkable, complement, draws)
}

/// Rebuild the result from the drawn tiles.
#[inline]
fn finish(grid: felt252, drawn: felt252, complement: bool) -> felt252 {
    if complement {
        grid - drawn
    } else {
        drawn
    }
}

#[generate_trait]
pub impl SpreaderVariants of SpreaderVariantsTrait {
    /// Knuth's selection sampling over the set bits (design), per `u128` limb: lowest set bit by
    /// `x & (x - 1)`, one pool draw per visited walkable tile, complement trick.
    fn selection(grid: felt252, count: u8, seed: felt252) -> felt252 {
        let (value, walkable, complement, draws) = prepare(grid, count);
        let mut rng = RngTrait::new(seed);
        let remaining: u128 = walkable.into();
        let left: u128 = draws.into();
        let (low, remaining, left) = Self::select_limb(value.low, remaining, left, ref rng);
        let (high, _, _) = Self::select_limb(value.high, remaining, left, ref rng);
        finish(grid, Bits::to_felt(u256 { low, high }), complement)
    }

    #[inline]
    fn select_limb(
        mut x: u128, mut remaining: u128, mut left: u128, ref rng: Rng,
    ) -> (u128, u128, u128) {
        let mut picked: u128 = 0;
        while left != 0 && x != 0 {
            let rest = x & (x - 1);
            let bit = x - rest;
            x = rest;
            if rng.draw(remaining.try_into().unwrap()) < left {
                picked += bit;
                left -= 1;
            }
            remaining -= 1;
        }
        (picked, remaining, left)
    }

    /// Rank selection: Floyd's algorithm draws `draws` distinct ranks in `0..walkable` into a
    /// rank bitmap, then one merged pass over the set bits of the grid keeps the selected ranks.
    fn floyd(grid: felt252, count: u8, seed: felt252) -> felt252 {
        let (value, walkable, complement, draws) = prepare(grid, count);
        let mut rng = RngTrait::new(seed);
        // [Compute] Floyd: for j in walkable - draws .. walkable, t = draw(j + 1)
        let mut ranks_low: u128 = 0;
        let mut ranks_high: u128 = 0;
        let mut j: u128 = (walkable - draws).into();
        let end: u128 = walkable.into();
        while j != end {
            let t = rng.draw((j + 1).try_into().unwrap());
            let t = if Self::has(ranks_low, ranks_high, t) {
                j
            } else {
                t
            };
            if t < 128 {
                ranks_low += *POW128.span().at(t.try_into().unwrap());
            } else {
                ranks_high += *POW128.span().at((t - 128).try_into().unwrap());
            }
            j += 1;
        }
        // [Compute] Merged pass: rank r of the grid is kept when bit r of the ranks is set
        let mut picks = draws;
        let mut rank: u128 = 0;
        let mut low: u128 = 0;
        let mut x = value.low;
        while picks != 0 && x != 0 {
            let rest = x & (x - 1);
            if Self::has(ranks_low, ranks_high, rank) {
                low += x - rest;
                picks -= 1;
            }
            x = rest;
            rank += 1;
        }
        let mut high: u128 = 0;
        let mut x = value.high;
        while picks != 0 && x != 0 {
            let rest = x & (x - 1);
            if Self::has(ranks_low, ranks_high, rank) {
                high += x - rest;
                picks -= 1;
            }
            x = rest;
            rank += 1;
        }
        finish(grid, Bits::to_felt(u256 { low, high }), complement)
    }

    #[inline]
    fn has(low: u128, high: u128, index: u128) -> bool {
        if index < 128 {
            low & *POW128.span().at(index.try_into().unwrap()) != 0
        } else {
            high & *POW128.span().at((index - 128).try_into().unwrap()) != 0
        }
    }

    /// Plain rejection sampling on the board positions (no mask), complement trick.
    fn reject(grid: felt252, size: u8, count: u8, seed: felt252) -> felt252 {
        let (value, _, complement, draws) = prepare(grid, count);
        let mut rng = RngTrait::new(seed);
        let range: u128 = size.into();
        let free = value.reject(draws, range.try_into().unwrap(), ref rng);
        finish(grid, grid - Bits::to_felt(free), complement)
    }

    /// Hash-and-mask, one round: density `q / 16` with `q = floor(16 * draws / walkable)`, then
    /// rejection sampling adds the missing tiles or removes the extra ones.
    fn mask(grid: felt252, size: u8, count: u8, seed: felt252) -> felt252 {
        let (value, walkable, complement, draws) = prepare(grid, count);
        let q: u16 = draws.into() * 16 / walkable.into();
        let (a, b, c) = hades_permutation(seed, 0, 2);
        let (d, e, _) = hades_permutation(a, 1, 2);
        let a: u256 = a.into();
        let b: u256 = b.into();
        let c: u256 = c.into();
        let d: u256 = d.into();
        let mask: u256 = match q {
            0 => 0,
            1 => a & b & c & d,
            2 => a & b & c,
            3 => (a | b) & c & d,
            4 => a & b,
            5 => (c | (a & b)) & d,
            6 => (b | c) & d,
            7 => (a | b | c) & d,
            _ => a,
        };
        let candidates = value & mask;
        let picked = Bits::popcount(candidates);
        let mut rng = RngTrait::new(e);
        let range: u128 = size.into();
        let range: NonZero<u128> = range.try_into().unwrap();
        let drawn: felt252 = if picked <= draws {
            // [Compute] Add the missing tiles among the walkable tiles not yet picked
            let free = (value - candidates).reject(draws - picked, range, ref rng);
            grid - Bits::to_felt(free)
        } else {
            // [Compute] Remove the extra tiles among the picked ones
            Bits::to_felt(candidates.reject(picked - draws, range, ref rng))
        };
        finish(grid, drawn, complement)
    }

    /// `Spreader::bernoulli` as a loop over the bits of `q` (loser: 2.5x the unrolled match).
    fn bernoulli_loop(q: u8, seed: felt252) -> u256 {
        let (a, b, c) = hades_permutation(seed, 0, 2);
        let (d, e, _) = hades_permutation(seed, 1, 2);
        let mut bits = q;
        let mut level: u8 = 0;
        while bits % 2 == 0 {
            bits /= 2;
            level += 1;
        }
        let mut mask = Self::word(a, b, c, d, e, level);
        bits /= 2;
        level += 1;
        while level != 5 {
            let word = Self::word(a, b, c, d, e, level);
            let (rest, bit) = DivRem::div_rem(bits, 2);
            mask = if bit == 0 {
                word & mask
            } else {
                word | mask
            };
            bits = rest;
            level += 1;
        }
        mask
    }

    #[inline]
    fn word(a: felt252, b: felt252, c: felt252, d: felt252, e: felt252, level: u8) -> u256 {
        match level {
            0 => a.into(),
            1 => b.into(),
            2 => c.into(),
            3 => d.into(),
            _ => e.into(),
        }
    }

    /// The library algorithm forced on `u256` (no single-limb path).
    fn choose_u256(grid: felt252, size: u8, count: u8, seed: felt252) -> felt252 {
        let value: u256 = grid.into();
        SpreaderInternal::choose(value, count, size, seed)
    }
}

/// Remove `draws` uniformly chosen set bits by uncapped rejection sampling on the board positions
/// (the fix-up of the first version of the library, unbounded: audit A2, finding 1).
#[generate_trait]
pub impl RejectSet of RejectSetTrait {
    fn reject(self: u256, draws: u8, range: NonZero<u128>, ref rng: Rng) -> u256 {
        let mut set = self;
        let mut draws = draws;
        while draws != 0 {
            let index: u32 = rng.draw(range).try_into().unwrap();
            if let Option::Some(bit) = set.probe(index) {
                set = set - bit;
                draws -= 1;
            }
        }
        set
    }
}

// Baseline: the fuzz harness around a trivial body, subtracted from every fuzz benchmark

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 72000)]
fn bench_spreader_baseline(k: u16) {
    assert!(SEED + k.into() != 0);
}

// library winner

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 214000)]
fn bench_spreader_generate_empty_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_17X14, 17, 14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 406000)]
fn bench_spreader_generate_empty_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_17X14, 17, 14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 368000)]
fn bench_spreader_generate_empty_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_17X14, 17, 14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 360000)]
fn bench_spreader_generate_empty_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_17X14, 17, 14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 216000)]
fn bench_spreader_generate_cave_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_17X14, 17, 14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 358000)]
fn bench_spreader_generate_cave_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_17X14, 17, 14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 325000)]
fn bench_spreader_generate_cave_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_17X14, 17, 14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 339000)]
fn bench_spreader_generate_cave_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_17X14, 17, 14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 216000)]
fn bench_spreader_generate_maze_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_17X14, 17, 14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 325000)]
fn bench_spreader_generate_maze_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_17X14, 17, 14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 334000)]
fn bench_spreader_generate_maze_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_17X14, 17, 14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 331000)]
fn bench_spreader_generate_maze_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_17X14, 17, 14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 186000)]
fn bench_spreader_generate_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_7X7, 7, 7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 246000)]
fn bench_spreader_generate_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_7X7, 7, 7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 247000)]
fn bench_spreader_generate_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(EMPTY_7X7, 7, 7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 186000)]
fn bench_spreader_generate_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_7X7, 7, 7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 246000)]
fn bench_spreader_generate_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_7X7, 7, 7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 231000)]
fn bench_spreader_generate_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(CAVE_7X7, 7, 7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 186000)]
fn bench_spreader_generate_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_7X7, 7, 7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 224000)]
fn bench_spreader_generate_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_7X7, 7, 7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 112000)]
fn bench_spreader_generate_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(MAZE_7X7, 7, 7, 16, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 143000)]
fn bench_spreader_generate_sparse2_10x25_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(SPARSE2_10X25, 10, 25, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 158000)]
fn bench_spreader_generate_sparse5_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(SPARSE5_17X14, 17, 14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 158000)]
fn bench_spreader_generate_sparse5_17x14_2(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(SPARSE5_17X14, 17, 14, 2, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 188000)]
fn bench_spreader_generate_d30_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(D30_17X14, 17, 14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 322000)]
fn bench_spreader_generate_d30_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(D30_17X14, 17, 14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 312000)]
fn bench_spreader_generate_d30_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(D30_17X14, 17, 14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[fuzzer(seed: 7)]
#[available_gas(l2_gas: 330000)]
fn bench_spreader_generate_d30_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = Spreader::generate(D30_17X14, 17, 14, 60, seed);
    assert!(objects != 0);
}

// selection sampling (design)

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1716000)]
fn bench_spreader_selection_empty_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1828000)]
fn bench_spreader_selection_empty_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1835000)]
fn bench_spreader_selection_empty_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1853000)]
fn bench_spreader_selection_empty_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1357000)]
fn bench_spreader_selection_cave_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1359000)]
fn bench_spreader_selection_cave_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1366000)]
fn bench_spreader_selection_cave_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1385000)]
fn bench_spreader_selection_cave_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 975000)]
fn bench_spreader_selection_maze_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 986000)]
fn bench_spreader_selection_maze_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 993000)]
fn bench_spreader_selection_maze_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1001000)]
fn bench_spreader_selection_maze_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 346000)]
fn bench_spreader_selection_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 348000)]
fn bench_spreader_selection_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 348000)]
fn bench_spreader_selection_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(EMPTY_7X7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 328000)]
fn bench_spreader_selection_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 330000)]
fn bench_spreader_selection_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 329000)]
fn bench_spreader_selection_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(CAVE_7X7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 262000)]
fn bench_spreader_selection_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 264000)]
fn bench_spreader_selection_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 111000)]
fn bench_spreader_selection_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::selection(MAZE_7X7, 16, seed);
    assert!(objects != 0);
}

// rank selection (Floyd)

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1842000)]
fn bench_spreader_floyd_empty_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1875000)]
fn bench_spreader_floyd_empty_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 2139000)]
fn bench_spreader_floyd_empty_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 2763000)]
fn bench_spreader_floyd_empty_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1352000)]
fn bench_spreader_floyd_cave_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1433000)]
fn bench_spreader_floyd_cave_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1664000)]
fn bench_spreader_floyd_cave_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 2281000)]
fn bench_spreader_floyd_cave_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1001000)]
fn bench_spreader_floyd_maze_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_17X14, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1063000)]
fn bench_spreader_floyd_maze_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_17X14, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1294000)]
fn bench_spreader_floyd_maze_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_17X14, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1480000)]
fn bench_spreader_floyd_maze_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_17X14, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 367000)]
fn bench_spreader_floyd_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 429000)]
fn bench_spreader_floyd_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 429000)]
fn bench_spreader_floyd_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(EMPTY_7X7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 348000)]
fn bench_spreader_floyd_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 410000)]
fn bench_spreader_floyd_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 379000)]
fn bench_spreader_floyd_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(CAVE_7X7, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 282000)]
fn bench_spreader_floyd_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_7X7, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 343000)]
fn bench_spreader_floyd_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_7X7, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 117000)]
fn bench_spreader_floyd_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::floyd(MAZE_7X7, 16, seed);
    assert!(objects != 0);
}

// plain rejection sampling

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 142000)]
fn bench_spreader_reject_empty_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 259000)]
fn bench_spreader_reject_empty_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 550000)]
fn bench_spreader_reject_empty_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1417000)]
fn bench_spreader_reject_empty_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 153000)]
fn bench_spreader_reject_cave_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 301000)]
fn bench_spreader_reject_cave_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 723000)]
fn bench_spreader_reject_cave_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 2083000)]
fn bench_spreader_reject_cave_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 185000)]
fn bench_spreader_reject_maze_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 375000)]
fn bench_spreader_reject_maze_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1045000)]
fn bench_spreader_reject_maze_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1659000)]
fn bench_spreader_reject_maze_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 152000)]
fn bench_spreader_reject_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 362000)]
fn bench_spreader_reject_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 362000)]
fn bench_spreader_reject_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 152000)]
fn bench_spreader_reject_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 362000)]
fn bench_spreader_reject_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 315000)]
fn bench_spreader_reject_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(CAVE_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 183000)]
fn bench_spreader_reject_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 414000)]
fn bench_spreader_reject_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 106000)]
fn bench_spreader_reject_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(MAZE_7X7, 49, 16, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 3768000)]
fn bench_spreader_reject_sparse2_10x25_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(SPARSE2_10X25, 250, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1613000)]
fn bench_spreader_reject_sparse5_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(SPARSE5_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 2244000)]
fn bench_spreader_reject_sparse5_17x14_2(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(SPARSE5_17X14, 238, 2, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 195000)]
fn bench_spreader_reject_d30_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(D30_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 451000)]
fn bench_spreader_reject_d30_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(D30_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1430000)]
fn bench_spreader_reject_d30_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(D30_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 787000)]
fn bench_spreader_reject_d30_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::reject(D30_17X14, 238, 60, seed);
    assert!(objects != 0);
}

// hash-and-mask, one round

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 171000)]
fn bench_spreader_mask_empty_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 277000)]
fn bench_spreader_mask_empty_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 416000)]
fn bench_spreader_mask_empty_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 624000)]
fn bench_spreader_mask_empty_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 182000)]
fn bench_spreader_mask_cave_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 382000)]
fn bench_spreader_mask_cave_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 689000)]
fn bench_spreader_mask_cave_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 627000)]
fn bench_spreader_mask_cave_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 203000)]
fn bench_spreader_mask_maze_17x14_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_17X14, 238, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 384000)]
fn bench_spreader_mask_maze_17x14_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_17X14, 238, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 941000)]
fn bench_spreader_mask_maze_17x14_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_17X14, 238, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 594000)]
fn bench_spreader_mask_maze_17x14_60(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_17X14, 238, 60, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 254000)]
fn bench_spreader_mask_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 689000)]
fn bench_spreader_mask_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 689000)]
fn bench_spreader_mask_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 254000)]
fn bench_spreader_mask_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 689000)]
fn bench_spreader_mask_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 456000)]
fn bench_spreader_mask_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(CAVE_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 1284000)]
fn bench_spreader_mask_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 533000)]
fn bench_spreader_mask_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 32, seed: 7)]
#[available_gas(l2_gas: 145000)]
fn bench_spreader_mask_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::mask(MAZE_7X7, 49, 16, seed);
    assert!(objects != 0);
}

// library algorithm without the u128 path

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 208000)]
fn bench_spreader_u256_empty_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(EMPTY_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 283000)]
fn bench_spreader_u256_empty_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(EMPTY_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 283000)]
fn bench_spreader_u256_empty_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(EMPTY_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 208000)]
fn bench_spreader_u256_cave_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(CAVE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 283000)]
fn bench_spreader_u256_cave_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(CAVE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 263000)]
fn bench_spreader_u256_cave_7x7_20(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(CAVE_7X7, 49, 20, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 208000)]
fn bench_spreader_u256_maze_7x7_1(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(MAZE_7X7, 49, 1, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 254000)]
fn bench_spreader_u256_maze_7x7_5(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(MAZE_7X7, 49, 5, seed);
    assert!(objects != 0);
}

#[test]
#[ignore]
#[fuzzer(runs: 256, seed: 7)]
#[available_gas(l2_gas: 113000)]
fn bench_spreader_u256_maze_7x7_16(k: u16) {
    let seed = SEED + k.into();
    let objects = SpreaderVariants::choose_u256(MAZE_7X7, 49, 16, seed);
    assert!(objects != 0);
}

// Microbenchmarks, 10 repetitions each: per-operation cost = (test - loop) / 10

#[test]
#[available_gas(l2_gas: 33000)]
fn bench_spreader_micro_loop() {
    let mut acc: u128 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 258000)]
fn bench_spreader_micro_level_u256() {
    // One radix level on EMPTY_17X14: a Poseidon word, one AND, one popcount
    let value: u256 = EMPTY_17X14.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let (word, _, _) = hades_permutation(SEED, n.into(), 2);
        let word: u256 = word.into();
        acc = acc | (value & word).popcount();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 200000)]
fn bench_spreader_micro_level_u128() {
    let value: u256 = EMPTY_7X7.into();
    let value = value.low;
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let (word, _, _) = hades_permutation(SEED, n.into(), 2);
        let word: u128 = BitSetTrait::word(word);
        acc = acc | (value & word).popcount();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 207000)]
fn bench_spreader_micro_popcount_limbs() {
    // Two-limb popcount (`BitSetTrait<u256>`, winner)
    let value: u256 = EMPTY_17X14.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | value.popcount();
    }
    assert!(acc == 180);
}

/// The first `Bits::popcount` (lot L0, loser): SWAR on the whole `u256`, 3 `u256` ANDs.
fn popcount_swar(value: u256) -> u8 {
    let odd_bits: u256 = 0x0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
    let pairs_mask: u256 = 0x0333333333333333333333333333333333333333333333333333333333333333;
    let nibbles_mask: u256 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
    let inv_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
    let inv_4: felt252 = 0x60000000000000cc00000000000000000000000000000000000000000000001;
    let inv_16: felt252 = 0x78000000000000ff00000000000000000000000000000000000000000000001;
    let pairs = Bits::to_felt(value) - Bits::to_felt(value & odd_bits) * inv_2;
    let low = Bits::to_felt(pairs.into() & pairs_mask);
    let nibbles = low + (pairs - low) * inv_4;
    let low = Bits::to_felt(nibbles.into() & nibbles_mask);
    let bytes: u256 = (low + (nibbles - low) * inv_16).into();
    let total: felt252 = (bytes.low.into() + bytes.high.into()) * BYTES_ONE;
    let total: u256 = total.into();
    let (count, _) = DivRem::div_rem(total.low, TWO_POW_120);
    count.try_into().unwrap()
}

#[test]
#[available_gas(l2_gas: 243000)]
fn bench_spreader_micro_popcount_bits() {
    // The first `Bits::popcount`, SWAR on the whole `u256` (loser)
    let value: u256 = EMPTY_17X14.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | popcount_swar(value);
    }
    assert!(acc == 180);
}

#[test]
#[available_gas(l2_gas: 157000)]
fn bench_spreader_micro_popcount_u128() {
    let value: u256 = CAVE_7X7.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | value.low.popcount();
    }
    assert!(acc == 23);
}

#[test]
#[available_gas(l2_gas: 131000)]
fn bench_spreader_micro_trial() {
    // One rejection trial (draw, probe) on EMPTY_17X14
    let value: u256 = EMPTY_17X14.into();
    let mut rng = RngTrait::new(SEED);
    let range: NonZero<u128> = 238;
    let mut hits: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let index: u32 = rng.draw(range).try_into().unwrap();
        if let Option::Some(_) = value.probe(index) {
            hits += 1;
        }
    }
    assert!(hits != 0);
}

#[test]
#[available_gas(l2_gas: 273000)]
fn bench_spreader_micro_counts_u256() {
    let value: u256 = EMPTY_17X14.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | value.counts().low_count;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 374000)]
fn bench_spreader_micro_select_u256() {
    // Select with byte counts already built, ranks 50, 63, ..., 167 (both limbs)
    let value: u256 = EMPTY_17X14.into();
    let counts = value.counts();
    let mut acc: u256 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let mut copy = counts;
        acc = acc | value.select(ref copy, n * 13 + 50);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 299000)]
fn bench_spreader_micro_select_u128() {
    let value: u256 = EMPTY_7X7.into();
    let value = value.low;
    let counts = value.counts();
    let mut acc: u128 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let mut copy = counts;
        acc = acc | value.select(ref copy, n * 2);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 386000)]
fn bench_spreader_micro_walk_u256() {
    // Walk to rank 7 (7 steps)
    let value: u256 = EMPTY_17X14.into();
    let mut acc: u256 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | value.walk(7);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 342000)]
fn bench_spreader_micro_deposit_u256() {
    // Deposit a mask on a class of 5 tiles spread over both limbs
    let value: u256 = SPARSE5_17X14.into();
    let mut acc: felt252 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc += value.deposit(0b10110);
    }
    assert!(acc != 0);
}
