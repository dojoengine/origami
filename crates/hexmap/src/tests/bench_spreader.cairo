//! Gas benchmarks of lot L7, spreader: one `#[test]` per fixture, count and algorithm, each with
//! an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//! The draws of rejection-based algorithms depend on the seed, so every benchmark runs the same
//! 8 seeds; per-call cost = (test - `bench_spreader_baseline`) / 8.
//! The measured losers live here, test-only; the winner is `Spreader::generate`.

// Core imports

use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::generators::spreader::{BitSetTrait, Spreader};
use origami_hexmap::helpers::bits::{Bits, POW128};
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::tests::fixtures::*;

// Constants

const SEED: felt252 = 'SEED';

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
    fn spread_u256(grid: felt252, size: u8, count: u8, seed: felt252) -> felt252 {
        let (value, walkable, complement, draws) = prepare(grid, count);
        let free = Bits::to_felt(Spreader::spread(value, walkable, draws, size, seed));
        finish(grid, grid - free, complement)
    }
}

// Baseline: the 8-seed loop around a trivial body

#[test]
#[available_gas(l2_gas: 31000)]
fn bench_spreader_baseline() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        assert!(seed != 0);
    }
}

// library winner

#[test]
#[available_gas(l2_gas: 515000)]
fn bench_spreader_generate_empty_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_17X14, 17, 14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1098000)]
fn bench_spreader_generate_empty_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_17X14, 17, 14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1510000)]
fn bench_spreader_generate_empty_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_17X14, 17, 14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1831000)]
fn bench_spreader_generate_empty_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_17X14, 17, 14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 568000)]
fn bench_spreader_generate_cave_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_17X14, 17, 14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1063000)]
fn bench_spreader_generate_cave_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_17X14, 17, 14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1474000)]
fn bench_spreader_generate_cave_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_17X14, 17, 14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1422000)]
fn bench_spreader_generate_cave_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_17X14, 17, 14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 709000)]
fn bench_spreader_generate_maze_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_17X14, 17, 14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1199000)]
fn bench_spreader_generate_maze_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_17X14, 17, 14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1744000)]
fn bench_spreader_generate_maze_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_17X14, 17, 14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1374000)]
fn bench_spreader_generate_maze_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_17X14, 17, 14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 535000)]
fn bench_spreader_generate_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_7X7, 7, 7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 929000)]
fn bench_spreader_generate_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_7X7, 7, 7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 930000)]
fn bench_spreader_generate_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(EMPTY_7X7, 7, 7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 535000)]
fn bench_spreader_generate_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_7X7, 7, 7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 990000)]
fn bench_spreader_generate_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_7X7, 7, 7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 810000)]
fn bench_spreader_generate_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(CAVE_7X7, 7, 7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 654000)]
fn bench_spreader_generate_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_7X7, 7, 7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1111000)]
fn bench_spreader_generate_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_7X7, 7, 7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 367000)]
fn bench_spreader_generate_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = Spreader::generate(MAZE_7X7, 7, 7, 16, seed);
        assert!(objects != 0);
    }
}

// selection sampling

#[test]
#[available_gas(l2_gas: 7193000)]
fn bench_spreader_selection_empty_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 9659000)]
fn bench_spreader_selection_empty_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 13480000)]
fn bench_spreader_selection_empty_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 14178000)]
fn bench_spreader_selection_empty_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 6698000)]
fn bench_spreader_selection_cave_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 9131000)]
fn bench_spreader_selection_cave_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 10235000)]
fn bench_spreader_selection_cave_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 10419000)]
fn bench_spreader_selection_cave_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2889000)]
fn bench_spreader_selection_maze_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 5700000)]
fn bench_spreader_selection_maze_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 7113000)]
fn bench_spreader_selection_maze_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 7241000)]
fn bench_spreader_selection_maze_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 924000)]
fn bench_spreader_selection_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1858000)]
fn bench_spreader_selection_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1858000)]
fn bench_spreader_selection_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(EMPTY_7X7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1168000)]
fn bench_spreader_selection_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1859000)]
fn bench_spreader_selection_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1739000)]
fn bench_spreader_selection_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(CAVE_7X7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1046000)]
fn bench_spreader_selection_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1370000)]
fn bench_spreader_selection_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 334000)]
fn bench_spreader_selection_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::selection(MAZE_7X7, 16, seed);
        assert!(objects != 0);
    }
}

// rank selection (Floyd)

#[test]
#[available_gas(l2_gas: 7067000)]
fn bench_spreader_floyd_empty_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 12491000)]
fn bench_spreader_floyd_empty_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 15668000)]
fn bench_spreader_floyd_empty_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 21471000)]
fn bench_spreader_floyd_empty_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 4809000)]
fn bench_spreader_floyd_cave_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 9530000)]
fn bench_spreader_floyd_cave_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 12255000)]
fn bench_spreader_floyd_cave_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 17576000)]
fn bench_spreader_floyd_cave_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 3268000)]
fn bench_spreader_floyd_maze_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_17X14, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 6711000)]
fn bench_spreader_floyd_maze_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_17X14, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 9652000)]
fn bench_spreader_floyd_maze_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_17X14, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 11058000)]
fn bench_spreader_floyd_maze_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_17X14, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1280000)]
fn bench_spreader_floyd_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2762000)]
fn bench_spreader_floyd_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2763000)]
fn bench_spreader_floyd_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(EMPTY_7X7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1309000)]
fn bench_spreader_floyd_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2490000)]
fn bench_spreader_floyd_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2216000)]
fn bench_spreader_floyd_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(CAVE_7X7, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1148000)]
fn bench_spreader_floyd_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_7X7, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2100000)]
fn bench_spreader_floyd_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_7X7, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 382000)]
fn bench_spreader_floyd_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::floyd(MAZE_7X7, 16, seed);
        assert!(objects != 0);
    }
}

// plain rejection sampling

#[test]
#[available_gas(l2_gas: 421000)]
fn bench_spreader_reject_empty_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 893000)]
fn bench_spreader_reject_empty_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2777000)]
fn bench_spreader_reject_empty_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 8871000)]
fn bench_spreader_reject_empty_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 474000)]
fn bench_spreader_reject_cave_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1152000)]
fn bench_spreader_reject_cave_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 3886000)]
fn bench_spreader_reject_cave_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 13256000)]
fn bench_spreader_reject_cave_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 615000)]
fn bench_spreader_reject_maze_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1421000)]
fn bench_spreader_reject_maze_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 4940000)]
fn bench_spreader_reject_maze_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 8283000)]
fn bench_spreader_reject_maze_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 484000)]
fn bench_spreader_reject_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1207000)]
fn bench_spreader_reject_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1207000)]
fn bench_spreader_reject_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(EMPTY_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 484000)]
fn bench_spreader_reject_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1228000)]
fn bench_spreader_reject_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 808000)]
fn bench_spreader_reject_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(CAVE_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 623000)]
fn bench_spreader_reject_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1988000)]
fn bench_spreader_reject_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 293000)]
fn bench_spreader_reject_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::reject(MAZE_7X7, 49, 16, seed);
        assert!(objects != 0);
    }
}

// hash-and-mask, one round

#[test]
#[available_gas(l2_gas: 750000)]
fn bench_spreader_mask_empty_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1286000)]
fn bench_spreader_mask_empty_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2084000)]
fn bench_spreader_mask_empty_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1554000)]
fn bench_spreader_mask_empty_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 826000)]
fn bench_spreader_mask_cave_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1550000)]
fn bench_spreader_mask_cave_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1694000)]
fn bench_spreader_mask_cave_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1712000)]
fn bench_spreader_mask_cave_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 987000)]
fn bench_spreader_mask_maze_17x14_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_17X14, 238, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2034000)]
fn bench_spreader_mask_maze_17x14_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_17X14, 238, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2555000)]
fn bench_spreader_mask_maze_17x14_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_17X14, 238, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 2344000)]
fn bench_spreader_mask_maze_17x14_60() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_17X14, 238, 60, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 802000)]
fn bench_spreader_mask_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 990000)]
fn bench_spreader_mask_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 990000)]
fn bench_spreader_mask_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(EMPTY_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 813000)]
fn bench_spreader_mask_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1053000)]
fn bench_spreader_mask_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1666000)]
fn bench_spreader_mask_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(CAVE_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1029000)]
fn bench_spreader_mask_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 880000)]
fn bench_spreader_mask_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 611000)]
fn bench_spreader_mask_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::mask(MAZE_7X7, 49, 16, seed);
        assert!(objects != 0);
    }
}

// library algorithm without the u128 path

#[test]
#[available_gas(l2_gas: 557000)]
fn bench_spreader_u256_empty_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(EMPTY_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1090000)]
fn bench_spreader_u256_empty_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(EMPTY_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1091000)]
fn bench_spreader_u256_empty_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(EMPTY_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 557000)]
fn bench_spreader_u256_cave_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(CAVE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1159000)]
fn bench_spreader_u256_cave_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(CAVE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 881000)]
fn bench_spreader_u256_cave_7x7_20() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(CAVE_7X7, 49, 20, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 695000)]
fn bench_spreader_u256_maze_7x7_1() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(MAZE_7X7, 49, 1, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 1299000)]
fn bench_spreader_u256_maze_7x7_5() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(MAZE_7X7, 49, 5, seed);
        assert!(objects != 0);
    }
}

#[test]
#[available_gas(l2_gas: 366000)]
fn bench_spreader_u256_maze_7x7_16() {
    let mut seed = SEED;
    let mut n: u8 = 8;
    while n != 0 {
        n -= 1;
        seed += 1;
        let objects = SpreaderVariants::spread_u256(MAZE_7X7, 49, 16, seed);
        assert!(objects != 0);
    }
}

// Reference points, one call each: `origami_map` measures 13_652_550 on an open 18x14 board with
// 35 objects (252 bits, not a valid hexmap board) and 1_246_064 on 9 tiles with 4 objects.

#[test]
#[available_gas(l2_gas: 190000)]
fn bench_spreader_reference_large() {
    // Open 19x13 board, 247 tiles, 35 objects
    let objects = Spreader::generate(Bits::pow(247) - 1, 19, 13, 35, SEED);
    assert!(objects != 0);
}

#[test]
#[available_gas(l2_gas: 113000)]
fn bench_spreader_reference_small() {
    // The 9-tile grid of `origami_map`, 4 objects
    let objects = Spreader::generate(0x38000E000380, 18, 13, 4, SEED);
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
#[available_gas(l2_gas: 251000)]
fn bench_spreader_micro_bernoulli_unrolled() {
    let mut acc: u128 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let (mask, _): (u256, felt252) = Spreader::bernoulli(7, n.into());
        acc = acc ^ mask.low;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 558000)]
fn bench_spreader_micro_bernoulli_loop() {
    let mut acc: u128 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let mask = SpreaderVariants::bernoulli_loop(7, n.into());
        acc = acc ^ mask.low;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 138000)]
fn bench_spreader_micro_trial() {
    // One rejection trial (draw, bit test) on EMPTY_17X14, without removal
    let value: u256 = EMPTY_17X14.into();
    let mut rng = RngTrait::new(SEED);
    let range: NonZero<u128> = 238;
    let mut hits: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        let index: u32 = rng.draw(range).try_into().unwrap();
        let hit = if index < 128 {
            value.low & *POW128.span().at(index) != 0
        } else {
            value.high & *POW128.span().at(index - 128) != 0
        };
        if hit {
            hits += 1;
        }
    }
    assert!(hits != 0);
}

#[test]
#[available_gas(l2_gas: 242000)]
fn bench_spreader_micro_popcount_u256() {
    let value: u256 = CAVE_7X7.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | BitSetTrait::<u256>::popcount(value);
    }
    assert!(acc == 23);
}

#[test]
#[available_gas(l2_gas: 157000)]
fn bench_spreader_micro_popcount_u128() {
    let value: u256 = CAVE_7X7.into();
    let mut acc: u8 = 0;
    let mut n: u8 = 10;
    while n != 0 {
        n -= 1;
        acc = acc | BitSetTrait::<u128>::popcount(value.low);
    }
    assert!(acc == 23);
}
