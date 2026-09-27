//! Gas benchmarks of study S1: `u252` (`[0, P - 1]` in one felt) against `u256`, `u128`, raw
//! `felt252` and a `[0, 2^251 - 1]` newtype, 100 repetitions per test.
//! Per-operation cost = (test - matching baseline) / 100, see `GAS.md`, section "S1 u252".
//! Budgets are `#[available_gas(l2_gas: N)]` = measured sierra gas + 5 %, rounded up to 1000.

// Core imports

use core::felt252_div;
use core::num::traits::{OverflowingMul, WrappingAdd, WrappingMul, WrappingSub, Zero};

// Internal imports

use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::tests::fixtures::{CAVE_17X14, CAVE_17X14_FAR_FROM};
use origami_hexmap::types::u252::{PRIME, U252Trait, u252};
use starknet::storage_access::StorePacking;

// Constants

const REPS: u8 = 100;
/// Wide operands: `A` has 250 bits, `B` 237 bits, `A + B < P`, `A > B`.
const A: felt252 = 0x2468ace02468ace02468ace02468ace02468ace02468ace02468ace02468ace;
const B: felt252 = 0x13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf1357;
const A_HIGH: u128 = 0x2468ace02468ace02468ace02468ace;
const A_LOW: u128 = 0x2468ace02468ace02468ace02468ace;
const B_HIGH: u128 = 0x13579bdf13579bdf13579bdf1357;
const B_LOW: u128 = 0x9bdf13579bdf13579bdf13579bdf1357;
/// Shift operand, 221 bits: `C * 2^17 < 2^251`.
const C: felt252 = 0x13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf13579bdf;
const C_HIGH: u128 = 0x13579bdf13579bdf13579bdf;
const C_LOW: u128 = 0x13579bdf13579bdf13579bdf13579bdf;
/// 2^128 + 1: adds `n` to both limbs.
const LIMBS_ONE: felt252 = 0x100000000000000000000000000000001;
/// Narrow operand, below 2^128.
const N: felt252 = 0x13579bdf13579bdf;
/// Shift of the shift benchmarks.
const SHIFT: u8 = 17;
/// 2^17.
const POW_SHIFT: u256 = 0x20000;
/// 2^123, bound of the high limb of a value below 2^251.
const TWO_POW_123: u128 = 0x8000000000000000000000000000000;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

// Operands, identical integers in every representation

// Both limbs vary with `n` so that no comparison or conversion folds at compile time:
// `fa(n) = A + n * (2^128 + 1)` is the integer `ua(n)`.

#[inline(always)]
fn fa(n: u8) -> felt252 {
    A + n.into() * LIMBS_ONE
}

#[inline(always)]
fn fb(n: u8) -> felt252 {
    B + n.into() * LIMBS_ONE
}

#[inline(always)]
fn fc(n: u8) -> felt252 {
    C + n.into() * LIMBS_ONE
}

#[inline(always)]
fn ua(n: u8) -> u256 {
    u256 { low: A_LOW + n.into(), high: A_HIGH + n.into() }
}

#[inline(always)]
fn ub(n: u8) -> u256 {
    u256 { low: B_LOW + n.into(), high: B_HIGH + n.into() }
}

#[inline(always)]
fn uc(n: u8) -> u256 {
    u256 { low: C_LOW + n.into(), high: C_HIGH + n.into() }
}

// Losing variants and the `[0, 2^251 - 1]` candidate

/// Checked add through the integer sum of both splits (loser).
#[inline]
fn add_via_sum(x: u252, y: u252) -> u252 {
    let sum: u256 = x.into() + y.into();
    assert(sum < PRIME, 'u252_add Overflow');
    x.wrapping_add(y)
}

/// Checked sub comparing both operand splits (loser).
#[inline]
fn sub_via_operands(x: u252, y: u252) -> u252 {
    assert(Into::<u252, u256>::into(x) >= y.into(), 'u252_sub Overflow');
    x.wrapping_sub(y)
}

/// Checked left shift, low limb times `2^-count` cast to `u128` as in `shr_exact` (loser: the
/// inverse costs a second table lookup).
#[inline]
fn shl_inv_cast(x: u252, count: u8) -> u252 {
    let product = x.value() * Bits::pow(count);
    let bits: u256 = product.into();
    let exact: Option<u128> = (bits.low.into() * Bits::inv(count)).try_into();
    assert(exact.is_some(), 'u252_shl Overflow');
    product.into()
}

/// Checked left shift, mask split to a `u256` and a two-limb AND (loser, first version).
#[inline]
fn shl_mask_u256(x: u252, count: u8) -> u252 {
    let pow = Bits::pow(count);
    let product = x.value() * pow;
    let bits: u256 = product.into();
    let mask: u256 = (pow - 1).into();
    assert((bits & mask).is_zero(), 'u252_shl Overflow');
    product.into()
}

/// Checked mul through the `u256` overflowing product compared to P (loser).
#[inline]
fn mul_u256_product(x: u252, y: u252) -> u252 {
    let (product, overflow) = Into::<u252, u256>::into(x).overflowing_mul(y.into());
    assert(!overflow && product < PRIME, 'u252_mul Overflow');
    x.wrapping_mul(y)
}

/// Exact right shift checked by a mask cast and a limb AND (loser).
#[inline]
fn shr_exact_and(x: u252, count: u8) -> u252 {
    let bits: u256 = x.into();
    let mask: u128 = (Bits::pow(count) - 1).try_into().unwrap();
    assert(bits.low & mask == 0, 'u252_shr Inexact');
    (x.value() * Bits::inv(count)).into()
}

/// Ordered comparison, high limbs first, written by hand.
#[inline]
fn lt_manual(x: u252, y: u252) -> bool {
    let a: u256 = x.into();
    let b: u256 = y.into();
    if a.high == b.high {
        a.low < b.low
    } else {
        a.high < b.high
    }
}

/// Checked left shift through a `u256` product compared to P (loser).
#[inline]
fn shl_via_u256(x: u252, count: u8) -> u252 {
    let pow = Bits::pow(count);
    let (product, overflow) = Into::<u252, u256>::into(x).overflowing_mul(pow.into());
    assert(!overflow && product < PRIME, 'u252_shl Overflow');
    (x.value() * pow).into()
}

/// DivRem by a divisor below 2^64: remainder from u128 divisions, quotient by an exact field
/// division (loser).
#[inline]
fn div_rem_felt(x: u252, divisor: NonZero<u128>) -> (u252, u128) {
    let bits: u256 = x.into();
    let (_, high) = DivRem::div_rem(bits.high, divisor);
    let (_, low) = DivRem::div_rem(bits.low, divisor);
    let (_, shift) = DivRem::div_rem(0xffffffffffffffffffffffffffffffff, divisor);
    let d: u128 = divisor.into();
    let shift = if shift + 1 == d {
        0
    } else {
        shift + 1
    };
    let (_, remainder) = DivRem::div_rem(high * shift + low, divisor);
    let quotient = felt252_div(
        x.value() - remainder.into(), Into::<u128, felt252>::into(d).try_into().unwrap(),
    );
    (quotient.into(), remainder)
}

/// Candidate `[0, 2^251 - 1]`: `Into<felt252, _>` cannot be infallible, only `TryInto`.
#[derive(Copy, Drop)]
struct U251 {
    value: felt252,
}

#[generate_trait]
impl U251Impl of U251Trait {
    /// Range proof: split, then the high limb below 2^123.
    #[inline]
    fn try_new(value: felt252) -> Option<U251> {
        let bits: u256 = value.into();
        if bits.high < TWO_POW_123 {
            Some(U251 { value })
        } else {
            None
        }
    }

    /// `2 * MAX > P`: the field sum alone cannot tell `t` from `t - P`, both splits are needed.
    #[inline]
    fn add(self: U251, other: U251) -> U251 {
        let sum: u256 = Into::<felt252, u256>::into(self.value) + other.value.into();
        assert(sum.high < TWO_POW_123, 'u251_add Overflow');
        U251 { value: self.value + other.value }
    }

    #[inline]
    fn sub(self: U251, other: U251) -> U251 {
        let a: u256 = self.value.into();
        assert(a >= other.value.into(), 'u251_sub Overflow');
        U251 { value: self.value - other.value }
    }

    #[inline]
    fn lt(self: U251, other: U251) -> bool {
        Into::<felt252, u256>::into(self.value) < other.value.into()
    }
}

// `Layout::expand` and one BFS layer step on `u252` (copies, `helpers/layout.cairo` unchanged)

/// `expand` with a `u252` frontier and result: one more split (the frontier) and one join (the
/// union), the East shift reads the felt directly.
#[inline]
fn expand_u252(layout: @Layout, frontier: u252) -> u252 {
    let layout = *layout;
    let bits: u256 = frontier.into();
    let pairs = bits | (bits + bits);
    let pairs_even = Bits::to_felt(pairs & layout.even);
    let pairs_felt = Bits::to_felt(pairs);
    let pairs_odd = pairs_felt - pairs_even;
    let up = pairs_even * layout.up_even + pairs_odd * layout.up_odd;
    let down = pairs_even * layout.down_even + pairs_odd * layout.down_odd;
    let east = frontier.value() * INV_2;
    // [Return] Union below 2^251 under the border invariant, the join is exact
    Bits::to_felt(pairs | east.into() | up.into() | down.into()).into()
}

/// `expand` returning the `u256` union, for a fused step.
#[inline]
fn expand_u252_wide(layout: @Layout, frontier: u252) -> u256 {
    let layout = *layout;
    let bits: u256 = frontier.into();
    let pairs = bits | (bits + bits);
    let pairs_even = Bits::to_felt(pairs & layout.even);
    let pairs_felt = Bits::to_felt(pairs);
    let pairs_odd = pairs_felt - pairs_even;
    let up = pairs_even * layout.up_even + pairs_odd * layout.up_odd;
    let down = pairs_even * layout.down_even + pairs_odd * layout.down_odd;
    let east = frontier.value() * INV_2;
    pairs | east.into() | up.into() | down.into()
}

// Baselines

#[test]
#[available_gas(l2_gas: 150000)]
fn bench_u252_baseline_loop() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += n.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 222000)]
fn bench_u252_baseline_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fa(n) + fb(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 355000)]
fn bench_u252_baseline_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ua(n).low.into() + ub(n).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 258000)]
fn bench_u252_baseline_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).into() + (B_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 181000)]
fn bench_u252_baseline_shift() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fc(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 247000)]
fn bench_u252_baseline_shift_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += uc(n).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 198000)]
fn bench_u252_baseline_u128_one() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 170000)]
fn bench_u252_baseline_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += N + n.into();
    }
    assert!(acc != 0);
}

// Checked add

#[test]
#[available_gas(l2_gas: 550000)]
fn bench_u252_add_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) + ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 286000)]
fn bench_u252_add_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((A_LOW + n.into()) + (B_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 222000)]
fn bench_u252_add_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fa(n) + fb(n);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 666000)]
fn bench_u252_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x + y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 484000)]
fn bench_u252_add_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += (x + x).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 891000)]
fn bench_u252_add_via_sum() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += add_via_sum(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 860000)]
fn bench_u251_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        acc += x.add(y).value;
    }
    assert!(acc != 0);
}

// Checked sub

#[test]
#[available_gas(l2_gas: 558000)]
fn bench_u252_sub_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) - ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 286000)]
fn bench_u252_sub_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((B_LOW + n.into()) - (A_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 666000)]
fn bench_u252_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x - y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 687000)]
fn bench_u252_sub_via_operands() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += sub_via_operands(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 687000)]
fn bench_u251_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        acc += x.sub(y).value;
    }
    assert!(acc != 0);
}

// Wrapping add and sub

#[test]
#[available_gas(l2_gas: 529000)]
fn bench_u252_wrapping_add_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ua(n).wrapping_add(ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 339000)]
fn bench_u252_wrapping_add_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (A_LOW + n.into()).wrapping_add(B_LOW + n.into()).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 222000)]
fn bench_u252_wrapping_add() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += x.wrapping_add(y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 222000)]
fn bench_u252_wrapping_sub() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += x.wrapping_sub(y).value();
    }
    assert!(acc != 0);
}

// Shifts by 2^17

#[test]
#[available_gas(l2_gas: 1713000)]
fn bench_u252_shl_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (uc(n) * POW_SHIFT).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 335000)]
fn bench_u252_shl_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::shl(fc(n), SHIFT);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 724000)]
fn bench_u252_shl() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += x.shl(SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2171000)]
fn bench_u252_shl_via_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_via_u256(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 766000)]
fn bench_u252_shl_inv_cast() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_inv_cast(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 917000)]
fn bench_u252_shl_mask_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fc(n).into();
        acc += shl_mask_u256(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 755000)]
fn bench_u252_shl_high() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += x.shl(SHIFT + 128).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 914000)]
fn bench_u252_shr_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) / POW_SHIFT).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 346000)]
fn bench_u252_shr_exact_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::shr_exact(fc(n) * 0x20000, SHIFT);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 633000)]
fn bench_u252_shr_exact() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (fc(n) * 0x20000).into();
        acc += x.shr_exact(SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 878000)]
fn bench_u252_shr_exact_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (fc(n) * 0x20000).into();
        acc += shr_exact_and(x, SHIFT).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 868000)]
fn bench_u252_shr() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        acc += x.shr(SHIFT).value();
    }
    assert!(acc != 0);
}

// DivRem by 7

#[test]
#[available_gas(l2_gas: 924000)]
fn bench_u252_divrem_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (q, r) = DivRem::div_rem(ua(n), 7);
        acc += q.low.into() + r.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 363000)]
fn bench_u252_divrem_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (q, r) = DivRem::div_rem(A_LOW + n.into(), 7);
        acc += q.into() + r.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1091000)]
fn bench_u252_divrem() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let (q, r) = x.div_rem(7);
        acc += q.value() + r.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1352000)]
fn bench_u252_divrem_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let (q, r) = div_rem_felt(x, 7);
        acc += q.value() + r.into();
    }
    assert!(acc != 0);
}

// Comparisons

#[test]
#[available_gas(l2_gas: 442000)]
fn bench_u252_eq_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if ua(n) == ub(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 254000)]
fn bench_u252_eq_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if fa(n) == fb(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 254000)]
fn bench_u252_eq() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if x == y {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 449000)]
fn bench_u252_lt_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if ub(n) < ua(n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 338000)]
fn bench_u252_lt_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if (A_LOW + n.into()) < (B_LOW + n.into()) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 677000)]
fn bench_u252_lt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if y < x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 547000)]
fn bench_u252_lt_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = ((N + n.into()).into(), N.into());
        if y < x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 695000)]
fn bench_u252_lt_manual() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if lt_manual(y, x) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 677000)]
fn bench_u251_lt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y) = (U251 { value: fa(n) }, U251 { value: fb(n) });
        if y.lt(x) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 698000)]
fn bench_u252_le() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        if y <= x {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 212000)]
fn bench_u252_is_zero_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if fa(n) == 0 {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 212000)]
fn bench_u252_is_zero() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        if x.is_zero() {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

// Bitwise

#[test]
#[available_gas(l2_gas: 606000)]
fn bench_u252_and_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) & ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 606000)]
fn bench_u252_or_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) | ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 606000)]
fn bench_u252_xor_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ua(n) ^ ub(n)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 415000)]
fn bench_u252_and_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += ((A_LOW + n.into()) & (B_LOW + n.into())).into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 863000)]
fn bench_u252_and() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x & y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 958000)]
fn bench_u252_or() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x | y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 958000)]
fn bench_u252_xor() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let (x, y): (u252, u252) = (fa(n).into(), fb(n).into());
        acc += (x ^ y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 816000)]
fn bench_u252_bit_test_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        if Bits::get(ua(n), 2 * n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 929000)]
fn bench_u252_bit_test() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        if x.bit(2 * n) {
            acc += 2;
        } else {
            acc += 1;
        }
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 443000)]
fn bench_u252_bit_set_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += Bits::set(fb(n), 2 * n + 50);
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 976000)]
fn bench_u252_bit_set() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        acc += x.set_bit(2 * n + 50).value();
    }
    assert!(acc != 0);
}

// Conversions

#[test]
#[available_gas(l2_gas: 181000)]
fn bench_u252_from_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        acc += x.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 350000)]
fn bench_u252_to_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let bits: u256 = x.into();
        acc += bits.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 256000)]
fn bench_u252_to_u256_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        let bits: u256 = x.into();
        acc += bits.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 359000)]
fn bench_u252_from_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = ua(n).try_into().unwrap();
        acc += x.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 198000)]
fn bench_u252_from_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (A_LOW + n.into()).into();
        acc += x.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 199000)]
fn bench_u252_to_u128() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        let value: u128 = x.try_into().unwrap();
        acc += value.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 160000)]
fn bench_u252_from_u8() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = n.into();
        acc += x.value() + 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 216000)]
fn bench_u252_to_u8() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = n.into();
        let value: u8 = x.try_into().unwrap();
        acc += value.into() + 1;
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 420000)]
fn bench_u251_from_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += U251Trait::try_new(fa(n)).unwrap().value;
    }
    assert!(acc != 0);
}

// Serde and storage packing

#[test]
#[available_gas(l2_gas: 244000)]
fn bench_u252_serde() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let mut out = array![];
        x.serialize(ref out);
        let mut span = out.span();
        let back: u252 = Serde::deserialize(ref span).unwrap();
        acc += back.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 462000)]
fn bench_u252_serde_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let mut out = array![];
        ua(n).serialize(ref out);
        let mut span = out.span();
        let back: u256 = Serde::deserialize(ref span).unwrap();
        acc += back.low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 181000)]
fn bench_u252_store_packing() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fa(n).into();
        let back: u252 = StorePacking::unpack(StorePacking::pack(x));
        acc += back.value();
    }
    assert!(acc != 0);
}

// Checked mul

#[test]
#[available_gas(l2_gas: 1826000)]
fn bench_u252_mul_u256() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += (ub(n) * (n.into() + 3)).low.into();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1368000)]
fn bench_u252_mul() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        let y: u252 = (n + 3).into();
        acc += (x * y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2086000)]
fn bench_u252_mul_u256_product() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = fb(n).into();
        let y: u252 = (n + 3).into();
        acc += mul_u256_product(x, y).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 1215000)]
fn bench_u252_mul_narrow() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let x: u252 = (N + n.into()).into();
        acc += (x * x).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 250000)]
fn bench_u252_mul_felt() {
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += fb(n) * (n + 3).into();
    }
    assert!(acc != 0);
}

// Expand and BFS step, 17x14

#[test]
#[available_gas(l2_gas: 2182000)]
fn bench_u252_expand_u256() {
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
#[available_gas(l2_gas: 2359000)]
fn bench_u252_expand() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u252 = CAVE_17X14.into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        acc += expand_u252(@layout, frontier).value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2210000)]
fn bench_u252_step_u256() {
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
#[available_gas(l2_gas: 2525000)]
fn bench_u252_step() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u252 = Bits::pow(CAVE_17X14_FAR_FROM).into();
    let unvisited: u252 = (CAVE_17X14 - Bits::pow(CAVE_17X14_FAR_FROM)).into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let next = expand_u252(@layout, frontier) & unvisited;
        let left = unvisited.wrapping_sub(next);
        acc += next.value() + left.value();
    }
    assert!(acc != 0);
}

#[test]
#[available_gas(l2_gas: 2407000)]
fn bench_u252_step_fused() {
    let layout = LayoutTrait::new(17, 14);
    let frontier: u252 = Bits::pow(CAVE_17X14_FAR_FROM).into();
    let unvisited: u252 = (CAVE_17X14 - Bits::pow(CAVE_17X14_FAR_FROM)).into();
    let mut acc: felt252 = 0;
    let mut n = REPS;
    while n != 0 {
        n -= 1;
        let next = Bits::to_felt(expand_u252_wide(@layout, frontier) & unvisited.into());
        let left = unvisited.value() - next;
        acc += next + left;
    }
    assert!(acc != 0);
}
