//! Gas benchmarks of lot L0: primitives, 100 repetitions per test, and fixture baselines.
//! Per-operation cost = (test - matching baseline) / 100, see `GAS.md`.
//! Budgets are `#[available_gas(l2_gas: N)]` = measured sierra gas + 5 %, rounded up to 1000.

// Core imports

use core::dict::Felt252Dict;
use core::felt252_div;
use core::hash::HashStateTrait;
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{BoundedInt, DivRemHelper, UnitInt, div_rem, upcast};
use core::poseidon::PoseidonTrait;

// Internal imports

use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::geometry::Geometry;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::helpers::rng::{PERMUTATIONS, RngTrait};
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::{MaskLayoutTrait, Variants};
use origami_hexmap::types::direction::Direction;

// Constants

const REPS: u8 = 100;
const WIDE: felt252 = 0x100000000000000000000000000000000000000000000000000;
const MASK: u256 = 0x5555555555555555555555555555555555555555555555555555555555555;
const POOL: u128 = 0xfedcba9876543210fedcba9876543210;
const PERMUTATION_COUNT: NonZero<u128> = 720;

// Loop baselines

#[test]
#[available_gas(l2_gas: 150000)]
fn bench_baseline_loop() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 150000)]
fn bench_baseline_loop_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += value.low.into();
    }
    assert!(acc == 4950);
}

// Field operations and lookups

#[test]
#[available_gas(l2_gas: 283000)]
fn bench_pow_lookup() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::pow(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 282000)]
fn bench_pow_match() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::pow_match(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 160000)]
fn bench_felt_mul() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value: felt252 = n.into();
        acc += value * 0x20000;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 202000)]
fn bench_felt_div_nonzero() {
    let divisor: NonZero<felt252> = 0x20000;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += felt252_div(n.into(), divisor);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 304000)]
fn bench_shr_exact_inverse_table() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::shr_exact(WIDE, n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 357000)]
fn bench_shr_exact_div() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::shr_div(WIDE, n);
    }
    assert!(acc != 0);
}

// Conversions

#[test]
#[available_gas(l2_gas: 236000)]
fn bench_felt_to_u256_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value: u256 = Into::<u8, felt252>::into(n).into();
        acc += value.low.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 340000)]
fn bench_felt_to_u256_wide() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value: u256 = (WIDE + n.into()).into();
        acc += value.low.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 178000)]
fn bench_felt_to_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value: u128 = Into::<u8, felt252>::into(n).try_into().unwrap();
        acc += value.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 170000)]
fn bench_u256_to_felt_unchecked() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += Bits::to_felt(value);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 261000)]
fn bench_u256_to_felt_checked() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        let value: felt252 = value.try_into().unwrap();
        acc += value;
    }
    assert!(acc != 0);
}

// Integer operations

#[test]
#[available_gas(l2_gas: 328000)]
fn bench_u128_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value.low & MASK.low).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 431000)]
fn bench_u256_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value & MASK).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 431000)]
fn bench_u256_or() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value | MASK).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 354000)]
fn bench_u256_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value + value).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1616000)]
fn bench_u256_mul_pow() {
    let shift: u256 = 0x20000;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value * shift).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 816000)]
fn bench_u256_div_pow() {
    let shift: u256 = 0x20000;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        acc += (value / shift).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 265000)]
fn bench_u8_divrem() {
    let divisor: NonZero<u8> = 17;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (q, r) = DivRem::div_rem(n, divisor);
        acc += q.into() + r.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 314000)]
fn bench_u128_divrem() {
    let divisor: NonZero<u128> = 6;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        let (q, r) = DivRem::div_rem(value.low, divisor);
        acc += q.into() + r.into();
    }
    assert!(acc != 0);
}

// Bit operations

#[test]
#[available_gas(l2_gas: 1189000)]
fn bench_bit_test_limb() {
    let value: u256 = MAZE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        // Alternate both limbs: n and n + 128
        if Bits::get(value, n) {
            acc += 1;
        }
        if Bits::get(value, n + 128) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 3843000)]
fn bench_bit_test_divmod() {
    let value: u256 = MAZE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if Variants::get_divmod(value, n) {
            acc += 1;
        }
        if Variants::get_divmod(value, n + 128) {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 363000)]
fn bench_bit_set_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::set(1, n + 128);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 660000)]
fn bench_bit_set_or() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::set_or(1, n + 128).high.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1786000)]
fn bench_popcount_swar_dense() {
    let value: u256 = EMPTY_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::popcount(value).into();
    }
    assert!(acc == 18000);
}

#[test]
#[available_gas(l2_gas: 56652000)]
fn bench_popcount_sparse_dense() {
    let value: u256 = EMPTY_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::popcount_sparse(value).into();
    }
    assert!(acc == 18000);
}

#[test]
#[available_gas(l2_gas: 1796000)]
fn bench_popcount_swar_sparse() {
    // 8 bits, 4 per limb
    let value: u256 = (Bits::pow(20)
        + Bits::pow(40)
        + Bits::pow(60)
        + Bits::pow(80)
        + Bits::pow(140)
        + Bits::pow(160)
        + Bits::pow(180)
        + Bits::pow(200))
        .into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::popcount(value).into();
    }
    assert!(acc == 800);
}

#[test]
#[available_gas(l2_gas: 3331000)]
fn bench_popcount_sparse_sparse() {
    let value: u256 = (Bits::pow(20)
        + Bits::pow(40)
        + Bits::pow(60)
        + Bits::pow(80)
        + Bits::pow(140)
        + Bits::pow(160)
        + Bits::pow(180)
        + Bits::pow(200))
        .into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::popcount_sparse(value).into();
    }
    assert!(acc == 800);
}

// Randomness

#[test]
#[available_gas(l2_gas: 464000)]
fn bench_poseidon_hash_state() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += PoseidonTrait::new().update(n.into()).update(acc).finalize();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 329000)]
fn bench_poseidon_hades() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += RngTrait::mix(n.into(), acc);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 628000)]
fn bench_rng_next_below() {
    let mut rng = RngTrait::new('seed');
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += rng.next_below(6).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 589000)]
fn bench_rng_draw() {
    let bound: NonZero<u128> = 6;
    let mut rng = RngTrait::new('seed');
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += rng.draw(bound).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 776000)]
fn bench_rng_shuffle6() {
    let mut rng = RngTrait::new('seed');
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += rng.shuffle6().into();
    }
    assert!(acc != 0);
}

// Lot P1: draws of a constant bound (`bounded_int::div_rem`) and a counter-refilled pool

/// A pool with a refill counter instead of the `pool < 2^64` test (loser, see `GAS.md`, P1).
#[derive(Copy, Drop)]
struct CountedPool {
    seed: felt252,
    pool: u128,
    left: felt252,
}

/// `DivRem` of a pool by 6, with the ranges of the quotient and the remainder.
impl BenchDivRem6 of DivRemHelper<u128, UnitInt<6>> {
    type DivT = BoundedInt<0, 0x2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>;
    type RemT = BoundedInt<0, 5>;
}

#[test]
#[available_gas(l2_gas: 600000)]
fn bench_rng_draw6() {
    let mut rng = RngTrait::new('seed');
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += rng.draw6().into();
    }
    assert!(acc != 0);
}

#[test]
#[feature("bounded-int-utils")]
#[available_gas(l2_gas: 600000)]
fn bench_u128_divrem_bounded() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let value = u256 { low: n.into(), high: n.into() };
        let (q, r) = div_rem::<_, _, BenchDivRem6>(value.low, 6);
        acc += upcast::<_, felt252>(q) + upcast::<_, felt252>(r);
    }
    assert!(acc != 0);
}

#[test]
#[feature("bounded-int-utils")]
#[available_gas(l2_gas: 600000)]
fn bench_rng_draw6_counter() {
    // 24 draws of 6 per 128-bit pool (6^24 < 2^63), the refill decided by a felt counter
    let mut state = CountedPool { seed: 'seed', pool: 0, left: 0 };
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if state.left == 0 {
            let (seed, word, _) = core::poseidon::hades_permutation(state.seed, 0, 2);
            let word: u256 = word.into();
            state.seed = seed;
            state.pool = word.low;
            state.left = 24;
        }
        state.left -= 1;
        let (pool, value) = div_rem::<_, _, BenchDivRem6>(state.pool, 6);
        state.pool = upcast(pool);
        acc += upcast::<_, felt252>(value);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 524000)]
fn bench_shuffle6_table() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let pool: u128 = POOL + n.into();
        let (_, index) = DivRem::div_rem(pool, PERMUTATION_COUNT);
        let packed: u32 = *PERMUTATIONS.span().at(index.try_into().unwrap());
        acc += packed.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 12033000)]
fn bench_shuffle6_fisher_yates() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let mut pool: u128 = POOL + n.into();
        acc += Variants::shuffle6_fisher_yates(ref pool).into();
    }
    assert!(acc != 0);
}

// Containers

#[test]
#[available_gas(l2_gas: 730000)]
fn bench_dict_insert() {
    let mut dict: Felt252Dict<felt252> = Default::default();
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        dict.insert(n.into(), n.into());
    }
    dict.squash();
}

#[test]
#[available_gas(l2_gas: 1034000)]
fn bench_dict_insert_get() {
    let mut dict: Felt252Dict<felt252> = Default::default();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        dict.insert(n.into(), n.into());
    }
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += dict.get(n.into());
    }
    dict.squash();
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 307000)]
fn bench_array_build() {
    let mut array: Array<felt252> = array![];
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        array.append(n.into());
    }
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc == 4950);
}

#[test]
#[available_gas(l2_gas: 409000)]
fn bench_array_span_at() {
    let mut array: Array<felt252> = array![];
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        array.append(n.into());
    }
    let span = array.span();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += *span.at(n.into());
    }
    assert!(acc == 4950);
}

// Layout

#[test]
#[available_gas(l2_gas: 916000)]
fn bench_layout_new() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += LayoutTrait::new(17, 14).up_even;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 522000)]
fn bench_layout_interior() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += LayoutTrait::interior(17, 14);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2182000)]
fn bench_expand_felt() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += layout.expand(frontier).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2271000)]
fn bench_expand_felt_double() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::expand_felt_double(@layout, frontier).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2482000)]
fn bench_expand_felt_vertical() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::expand_felt_vertical(@layout, frontier).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 6875000)]
fn bench_expand_masks() {
    let masks = MaskLayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += masks.expand(frontier).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2271000)]
fn bench_expand_limbs() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (low, _) = Variants::expand_limbs(@layout, frontier.low, frontier.high);
        acc += low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1912000)]
fn bench_expand_felt_7x7() {
    let layout = LayoutTrait::new(7, 7);
    let frontier: u256 = CAVE_7X7.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += layout.expand(frontier).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1002000)]
fn bench_expand_small_7x7() {
    let layout = LayoutTrait::new(7, 7);
    let frontier: u128 = CAVE_7X7.try_into().unwrap();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += layout.expand_small(frontier).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1341000)]
fn bench_expand_small_felt_double_7x7() {
    let layout = LayoutTrait::new(7, 7);
    let frontier: u128 = CAVE_7X7.try_into().unwrap();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::expand_small_felt_double(@layout, frontier).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2352000)]
fn bench_step_or() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = Bits::pow(CAVE_17X14_FAR_FROM).into();
    let unvisited: u256 = CAVE_17X14.into() - frontier;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let next = layout.expand(frontier) & unvisited;
        let left = unvisited - next;
        acc += next.low.into() + left.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 6097000)]
fn bench_step_sequential() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u256 = Bits::pow(CAVE_17X14_FAR_FROM).into();
    let unvisited: u256 = CAVE_17X14.into() - frontier;
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (next, left) = Variants::step_sequential(@layout, frontier, unvisited);
        acc += next.low.into() + left.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 764000)]
fn bench_neighbour_mask() {
    let layout = LayoutTrait::new(17, 14);
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += layout.neighbour_mask(n + 18);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1583000)]
fn bench_neighbour_mask_lookups() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::neighbour_mask_lookups(17, n + 18);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 821000)]
fn bench_neighbor() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if let Option::Some(next) = LayoutTrait::neighbor(17, 14, n + 18, Direction::NorthEast) {
            acc += next.into();
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 265000)]
fn bench_coords() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = LayoutTrait::coords(17, n);
        acc += x.into() + y.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1143000)]
fn bench_distance() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Geometry::distance(17, n, 237 - n).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1552000)]
fn bench_distance_split() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Variants::distance_split(17, n, 237 - n).into();
    }
    assert!(acc != 0);
}

// Fixture baselines: load the fixture, assert something trivial

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_empty_17x14() {
    assert!(EMPTY_17X14 != 0 && EMPTY_17X14_FAR_FROM != EMPTY_17X14_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_cave_17x14() {
    assert!(CAVE_17X14 != 0 && CAVE_17X14_FAR_FROM != CAVE_17X14_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_maze_17x14() {
    assert!(MAZE_17X14 != 0 && MAZE_17X14_FAR_FROM != MAZE_17X14_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_serpentine_17x14() {
    assert!(SERPENTINE_17X14 != 0 && SERPENTINE_17X14_FAR_FROM != SERPENTINE_17X14_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_unreachable_17x14() {
    assert!(UNREACHABLE_17X14 != 0 && UNREACHABLE_17X14_FAR_FROM != UNREACHABLE_17X14_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_empty_7x7() {
    assert!(EMPTY_7X7 != 0 && EMPTY_7X7_FAR_FROM != EMPTY_7X7_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_cave_7x7() {
    assert!(CAVE_7X7 != 0 && CAVE_7X7_FAR_FROM != CAVE_7X7_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_maze_7x7() {
    assert!(MAZE_7X7 != 0 && MAZE_7X7_FAR_FROM != MAZE_7X7_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_serpentine_7x7() {
    assert!(SERPENTINE_7X7 != 0 && SERPENTINE_7X7_FAR_FROM != SERPENTINE_7X7_FAR_TO);
}

#[test]
#[available_gas(l2_gas: 16000)]
fn bench_baseline_unreachable_7x7() {
    assert!(UNREACHABLE_7X7 != 0 && UNREACHABLE_7X7_FAR_FROM != UNREACHABLE_7X7_FAR_TO);
}
