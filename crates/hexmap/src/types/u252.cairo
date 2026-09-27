//! `u252`: an unsigned integer with the value set of `felt252`, `[0, P - 1]`.
//!
//! The value is a single field element, so `Into<felt252, u252>`, `Into<u252, felt252>`, `Serde`
//! and storage packing are free and cannot fail. Every value is canonical: the invariant
//! `value < P` holds by construction of the field, nothing has to re-establish it.
//!
//! The checked operations panic exactly when the true integer result leaves `[0, P - 1]`. A field
//! operation cannot see a wrap-around by itself (`a + b` and `a + b - P` are the same element),
//! so each check compares canonical integers: the `felt252 -> u256` split (`u128s_from_felt252`,
//! 1 range check below 2^128, 3 above) is the only sound range proof on a full-range felt.
//! Measurements and the comparison with `u256` are in `GAS.md`, section "S1 u252".

// Core imports

use core::num::traits::{
    Bounded, CheckedAdd, CheckedMul, CheckedSub, One, OverflowingAdd, WideMul, WrappingAdd,
    WrappingMul, WrappingSub, Zero,
};
use core::traits::{BitAnd, BitOr, BitXor};

// Internal imports

use origami_hexmap::helpers::bits::{Bits, POW128, TWO_POW_128};

// Constants

/// The field prime `P = 2^251 + 17 * 2^192 + 1` as a `u256`.
pub const PRIME: u256 = u256 { low: 1, high: 0x8000000000000110000000000000000 };
/// `P - 1`, the largest `u252`.
const MAX_VALUE: felt252 = 0x800000000000011000000000000000000000000000000000000000000000000;
/// 2^-128 in the field.
const INV_TWO_POW_128: felt252 = 0x800000000000010fffffffffffffffff7ffffffffffffef0000000000000001;

/// An unsigned integer in `[0, P - 1]`, held in one field element.
#[derive(Copy, Drop, PartialEq, Serde, Debug, Default)]
pub struct u252 {
    value: felt252,
}

#[generate_trait]
pub impl U252Impl of U252Trait {
    /// Build a `u252` from a field element, free.
    /// # Arguments
    /// * `value` - The field element
    /// # Returns
    /// * The same value as an unsigned integer
    #[inline(always)]
    fn new(value: felt252) -> u252 {
        u252 { value }
    }

    /// The field element of a `u252`, free.
    /// # Arguments
    /// * `self` - The integer
    /// # Returns
    /// * The field element
    #[inline(always)]
    fn value(self: u252) -> felt252 {
        self.value
    }

    /// Shift toward the high bits, panics if a set bit would reach `P` or above.
    /// The product `a * 2^k` wraps iff `a * 2^k = p + m * P` with `1 <= m < 2^k`. `P` is odd, so
    /// `m * P` is not a multiple of `2^k` and the canonical `p` has a non-zero low bit: one split
    /// and one AND prove the shift exact.
    /// # Arguments
    /// * `self` - The integer
    /// * `count` - The shift, at most 251
    /// # Returns
    /// * `self * 2^count`
    #[inline]
    fn shl(self: u252, count: u8) -> u252 {
        let pow = Bits::pow(count);
        let product = self.value * pow;
        // [Check] The low `count` bits of the canonical product are zero
        assert(low_bits(split(product), pow, count) == 0, 'u252_shl Overflow');
        // [Return] Exact product
        u252 { value: product }
    }

    /// Shift toward the low bits when no set bit is dropped, panics otherwise.
    /// # Arguments
    /// * `self` - The integer, its `count` lowest bits must be zero
    /// * `count` - The shift, at most 251
    /// # Returns
    /// * `self / 2^count`
    #[inline]
    fn shr_exact(self: u252, count: u8) -> u252 {
        let bits = split(self.value);
        let inv = Bits::inv(count);
        // [Check] The low `count` bits are zero. Up to 123, `low * 2^-count` is `low / 2^count`
        // below 2^128 if exact, else `(low + m * P) / 2^count >= P / 2^123 > 2^128`: one cast.
        if count < 124 {
            let exact: Option<u128> = (bits.low.into() * inv).try_into();
            assert(exact.is_some(), 'u252_shr Inexact');
        } else {
            assert(low_bits(bits, Bits::pow(count), count) == 0, 'u252_shr Inexact');
        }
        // [Return] Exact quotient
        u252 { value: self.value * inv }
    }

    /// Shift toward the low bits, dropping the low bits (floor division by `2^count`).
    /// # Arguments
    /// * `self` - The integer
    /// * `count` - The shift, at most 251
    /// # Returns
    /// * `floor(self / 2^count)`
    #[inline]
    fn shr(self: u252, count: u8) -> u252 {
        // [Compute] Dropped bits, then an exact field division
        let dropped = low_bits(split(self.value), Bits::pow(count), count);
        u252 { value: (self.value - dropped) * Bits::inv(count) }
    }

    /// Quotient and remainder by a non-zero `u128`.
    /// # Arguments
    /// * `self` - The integer
    /// * `divisor` - The divisor
    /// # Returns
    /// * The quotient and the remainder
    #[inline]
    fn div_rem(self: u252, divisor: NonZero<u128>) -> (u252, u128) {
        let bits: u256 = self.value.into();
        let divisor: u128 = divisor.into();
        let divisor: NonZero<u256> = u256 { low: divisor, high: 0 }.try_into().unwrap();
        let (quotient, remainder) = DivRem::div_rem(bits, divisor);
        (u252 { value: Bits::to_felt(quotient) }, remainder.low)
    }

    /// Test a bit.
    /// # Arguments
    /// * `self` - The integer
    /// * `index` - The bit index, at most 251
    /// # Returns
    /// * `true` if the bit is set
    #[inline]
    fn bit(self: u252, index: u8) -> bool {
        Bits::get(self.value.into(), index)
    }

    /// Set a bit, panics if the result reaches `P`.
    /// # Arguments
    /// * `self` - The integer
    /// * `index` - The bit index, at most 251
    /// # Returns
    /// * The integer with bit `index` set
    #[inline]
    fn set_bit(self: u252, index: u8) -> u252 {
        let bits = split(self.value);
        if index < 128 {
            let pow = *POW128.span().at(index.into());
            if bits.low & pow != 0 {
                return self;
            }
            // [Check] Below P with a high limb equal to P's, the low limb is 0: any bit overflows
            assert(bits.high != PRIME.high, 'u252_or Overflow');
            u252 { value: self.value + pow.into() }
        } else {
            let pow = *POW128.span().at(index.into() - 128);
            if bits.high & pow != 0 {
                return self;
            }
            // [Check] The bit was unset: the sum is the integer OR, compare it to P
            assert(u256 { low: bits.low, high: bits.high + pow } < PRIME, 'u252_or Overflow');
            u252 { value: self.value + pow.into() * TWO_POW_128 }
        }
    }
}

// Helpers

/// Canonical integer of a field element: `u128s_from_felt252`, 1 range check below 2^128, 3 above.
#[inline(always)]
fn split(value: felt252) -> u256 {
    value.into()
}

/// Rebuild a field element from a `u256` below `P`.
#[inline(always)]
fn join(value: u256) -> felt252 {
    value.low.into() + value.high.into() * TWO_POW_128
}

/// The `count` lowest bits of a canonical integer, as a felt: one limb AND, the mask comes from
/// `pow = 2^count` (a `felt252 -> u128` cast is cheaper than a second table lookup).
#[inline(always)]
fn low_bits(bits: u256, pow: felt252, count: u8) -> felt252 {
    if count < 128 {
        let mask: u128 = (pow - 1).try_into().unwrap();
        (bits.low & mask).into()
    } else {
        let mask: u128 = (pow * INV_TWO_POW_128 - 1).try_into().unwrap();
        bits.low.into() + (bits.high & mask).into() * TWO_POW_128
    }
}

// Conversions

pub impl Felt252IntoU252 of Into<felt252, u252> {
    #[inline(always)]
    fn into(self: felt252) -> u252 {
        u252 { value: self }
    }
}

pub impl U252IntoFelt252 of Into<u252, felt252> {
    #[inline(always)]
    fn into(self: u252) -> felt252 {
        self.value
    }
}

pub impl U252IntoU256 of Into<u252, u256> {
    #[inline(always)]
    fn into(self: u252) -> u256 {
        split(self.value)
    }
}

pub impl U256TryIntoU252 of TryInto<u256, u252> {
    #[inline]
    fn try_into(self: u256) -> Option<u252> {
        if self < PRIME {
            Some(u252 { value: join(self) })
        } else {
            None
        }
    }
}

pub impl U128IntoU252 of Into<u128, u252> {
    #[inline(always)]
    fn into(self: u128) -> u252 {
        u252 { value: self.into() }
    }
}

pub impl U64IntoU252 of Into<u64, u252> {
    #[inline(always)]
    fn into(self: u64) -> u252 {
        u252 { value: self.into() }
    }
}

pub impl U32IntoU252 of Into<u32, u252> {
    #[inline(always)]
    fn into(self: u32) -> u252 {
        u252 { value: self.into() }
    }
}

pub impl U16IntoU252 of Into<u16, u252> {
    #[inline(always)]
    fn into(self: u16) -> u252 {
        u252 { value: self.into() }
    }
}

pub impl U8IntoU252 of Into<u8, u252> {
    #[inline(always)]
    fn into(self: u8) -> u252 {
        u252 { value: self.into() }
    }
}

pub impl U252TryIntoU128 of TryInto<u252, u128> {
    #[inline(always)]
    fn try_into(self: u252) -> Option<u128> {
        self.value.try_into()
    }
}

pub impl U252TryIntoU64 of TryInto<u252, u64> {
    #[inline(always)]
    fn try_into(self: u252) -> Option<u64> {
        self.value.try_into()
    }
}

pub impl U252TryIntoU32 of TryInto<u252, u32> {
    #[inline(always)]
    fn try_into(self: u252) -> Option<u32> {
        self.value.try_into()
    }
}

pub impl U252TryIntoU16 of TryInto<u252, u16> {
    #[inline(always)]
    fn try_into(self: u252) -> Option<u16> {
        self.value.try_into()
    }
}

pub impl U252TryIntoU8 of TryInto<u252, u8> {
    #[inline(always)]
    fn try_into(self: u252) -> Option<u8> {
        self.value.try_into()
    }
}

/// Storage packing: a `u252` is stored as its field element, no range check on read.
pub impl U252StorePacking of starknet::storage_access::StorePacking<u252, felt252> {
    #[inline(always)]
    fn pack(value: u252) -> felt252 {
        value.value
    }

    #[inline(always)]
    fn unpack(value: felt252) -> u252 {
        u252 { value }
    }
}

// Arithmetic

pub impl U252CheckedAdd of CheckedAdd<u252> {
    /// The field sum wraps iff the integer sum reaches `P`, and then it is below `self`.
    #[inline]
    fn checked_add(self: u252, v: u252) -> Option<u252> {
        let value = self.value + v.value;
        if split(value) < split(self.value) {
            None
        } else {
            Some(u252 { value })
        }
    }
}

pub impl U252Add of Add<u252> {
    #[inline]
    fn add(lhs: u252, rhs: u252) -> u252 {
        let value = lhs.value + rhs.value;
        assert(split(value) >= split(lhs.value), 'u252_add Overflow');
        u252 { value }
    }
}

pub impl U252CheckedSub of CheckedSub<u252> {
    /// The field difference wraps iff `v > self`, and then it is `P + self - v > self`.
    #[inline]
    fn checked_sub(self: u252, v: u252) -> Option<u252> {
        let value = self.value - v.value;
        if split(value) > split(self.value) {
            None
        } else {
            Some(u252 { value })
        }
    }
}

pub impl U252Sub of Sub<u252> {
    #[inline]
    fn sub(lhs: u252, rhs: u252) -> u252 {
        let value = lhs.value - rhs.value;
        assert(split(value) <= split(lhs.value), 'u252_sub Overflow');
        u252 { value }
    }
}

/// Whether the integer product of two canonical integers is below `P`. Two high limbs set give at
/// least 2^256; otherwise two `u128` wide products of the wide operand by the narrow one.
#[inline]
fn product_fits(a: u256, b: u256) -> bool {
    let (wide, narrow) = if b.high == 0 {
        (a, b.low)
    } else if a.high == 0 {
        (b, a.low)
    } else {
        return false;
    };
    let low: u256 = WideMul::wide_mul(wide.low, narrow);
    let high: u256 = WideMul::wide_mul(wide.high, narrow);
    if high.high != 0 {
        return false;
    }
    let (top, carry) = low.high.overflowing_add(high.low);
    !carry && u256 { low: low.low, high: top } < PRIME
}

pub impl U252CheckedMul of CheckedMul<u252> {
    #[inline]
    fn checked_mul(self: u252, v: u252) -> Option<u252> {
        if product_fits(split(self.value), split(v.value)) {
            Some(u252 { value: self.value * v.value })
        } else {
            None
        }
    }
}

pub impl U252Mul of Mul<u252> {
    #[inline]
    fn mul(lhs: u252, rhs: u252) -> u252 {
        assert(product_fits(split(lhs.value), split(rhs.value)), 'u252_mul Overflow');
        u252 { value: lhs.value * rhs.value }
    }
}

pub impl U252Div of Div<u252> {
    #[inline]
    fn div(lhs: u252, rhs: u252) -> u252 {
        u252 { value: join(split(lhs.value) / split(rhs.value)) }
    }
}

pub impl U252Rem of Rem<u252> {
    #[inline]
    fn rem(lhs: u252, rhs: u252) -> u252 {
        u252 { value: join(split(lhs.value) % split(rhs.value)) }
    }
}

/// Wrapping arithmetic is modulo `P`: the field operations themselves.
pub impl U252WrappingAdd of WrappingAdd<u252> {
    #[inline(always)]
    fn wrapping_add(self: u252, v: u252) -> u252 {
        u252 { value: self.value + v.value }
    }
}

pub impl U252WrappingSub of WrappingSub<u252> {
    #[inline(always)]
    fn wrapping_sub(self: u252, v: u252) -> u252 {
        u252 { value: self.value - v.value }
    }
}

pub impl U252WrappingMul of WrappingMul<u252> {
    #[inline(always)]
    fn wrapping_mul(self: u252, v: u252) -> u252 {
        u252 { value: self.value * v.value }
    }
}

// Comparisons

pub impl U252PartialOrd of PartialOrd<u252> {
    #[inline]
    fn lt(lhs: u252, rhs: u252) -> bool {
        split(lhs.value) < split(rhs.value)
    }

    #[inline]
    fn le(lhs: u252, rhs: u252) -> bool {
        split(lhs.value) <= split(rhs.value)
    }

    #[inline]
    fn gt(lhs: u252, rhs: u252) -> bool {
        split(lhs.value) > split(rhs.value)
    }

    #[inline]
    fn ge(lhs: u252, rhs: u252) -> bool {
        split(lhs.value) >= split(rhs.value)
    }
}

// Bitwise, one split per operand and two builtin applications

pub impl U252BitAnd of BitAnd<u252> {
    #[inline]
    fn bitand(lhs: u252, rhs: u252) -> u252 {
        // [Return] At most `lhs`, below P
        u252 { value: join(split(lhs.value) & split(rhs.value)) }
    }
}

pub impl U252BitOr of BitOr<u252> {
    #[inline]
    fn bitor(lhs: u252, rhs: u252) -> u252 {
        let bits = split(lhs.value) | split(rhs.value);
        assert(bits < PRIME, 'u252_or Overflow');
        u252 { value: join(bits) }
    }
}

pub impl U252BitXor of BitXor<u252> {
    #[inline]
    fn bitxor(lhs: u252, rhs: u252) -> u252 {
        let bits = split(lhs.value) ^ split(rhs.value);
        assert(bits < PRIME, 'u252_xor Overflow');
        u252 { value: join(bits) }
    }
}

// Constants

pub impl U252Zero of Zero<u252> {
    #[inline(always)]
    fn zero() -> u252 {
        u252 { value: 0 }
    }

    #[inline(always)]
    fn is_zero(self: @u252) -> bool {
        *self.value == 0
    }

    #[inline(always)]
    fn is_non_zero(self: @u252) -> bool {
        *self.value != 0
    }
}

pub impl U252One of One<u252> {
    #[inline(always)]
    fn one() -> u252 {
        u252 { value: 1 }
    }

    #[inline(always)]
    fn is_one(self: @u252) -> bool {
        *self.value == 1
    }

    #[inline(always)]
    fn is_non_one(self: @u252) -> bool {
        *self.value != 1
    }
}

pub impl U252Bounded of Bounded<u252> {
    const MIN: u252 = u252 { value: 0 };
    const MAX: u252 = u252 { value: MAX_VALUE };
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::num::traits::{
        Bounded, CheckedAdd, CheckedMul, CheckedSub, One, WrappingAdd, WrappingMul, WrappingSub,
        Zero,
    };
    use starknet::storage_access::StorePacking;

    // Local imports

    use super::{PRIME, U252Trait, u252};

    // Constants

    const P_MINUS_1: felt252 = 0x800000000000011000000000000000000000000000000000000000000000000;
    const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;
    const TWO_POW_251: felt252 = 0x800000000000000000000000000000000000000000000000000000000000000;

    /// Edges of the brief plus pseudo-random values (a Poseidon chain).
    fn samples() -> Array<felt252> {
        let mut values = array![
            0, 1, 2, P_MINUS_1, P_MINUS_1 - 1, TWO_POW_128 - 1, TWO_POW_128, TWO_POW_128 + 1,
            TWO_POW_251 - 1, TWO_POW_251, TWO_POW_251 + 1,
            0x110000000000000000000000000000000000000,
        ];
        let mut seed: felt252 = 'u252';
        let mut n: u8 = 12;
        while n != 0 {
            n -= 1;
            let (next, _, _) = core::poseidon::hades_permutation(seed, n.into(), 0);
            seed = next;
            values.append(next);
            // [Compute] Narrow values too, below 2^128 and 2^64
            let wide: u256 = next.into();
            values.append(wide.low.into());
            values.append((wide.low / 0x10000000000000000).into());
        }
        values
    }

    #[test]
    fn test_u252_into_roundtrip() {
        for value in samples() {
            let x: u252 = value.into();
            let back: felt252 = x.into();
            assert!(back == value);
            let bits: u256 = x.into();
            assert!(bits < PRIME);
            let again: u252 = bits.try_into().unwrap();
            assert!(again == x);
        }
    }

    #[test]
    fn test_u252_u256_try_into_edges() {
        let prime: Option<u252> = PRIME.try_into();
        assert!(prime.is_none());
        let max: Option<u252> = (PRIME - 1).try_into();
        assert!(max.unwrap() == Bounded::MAX);
        let above: Option<u252> = Bounded::<u256>::MAX.try_into();
        assert!(above.is_none());
    }

    #[test]
    fn test_u252_arithmetic_against_u256() {
        let values = samples();
        for a in values.span() {
            for b in values.span() {
                let (x, y): (u252, u252) = ((*a).into(), (*b).into());
                let (u, v): (u256, u256) = ((*a).into(), (*b).into());
                // [Check] Addition
                let sum = x.checked_add(y);
                if u + v < PRIME {
                    assert!(sum.unwrap().into() == u + v);
                    assert!((x + y).into() == u + v);
                } else {
                    assert!(sum.is_none());
                }
                // [Check] Subtraction
                let diff = x.checked_sub(y);
                if u >= v {
                    assert!(diff.unwrap().into() == u - v);
                    assert!((x - y).into() == u - v);
                } else {
                    assert!(diff.is_none());
                }
                // [Check] Multiplication, u512 oracle through the high limbs
                let product = x.checked_mul(y);
                let fits = if u.high != 0 && v.high != 0 {
                    false
                } else {
                    match core::num::traits::CheckedMul::checked_mul(u, v) {
                        Some(w) => w < PRIME,
                        None => false,
                    }
                };
                if fits {
                    assert!(product.unwrap().into() == u * v);
                } else {
                    assert!(product.is_none());
                }
                // [Check] Order
                assert!((x < y) == (u < v));
                assert!((x <= y) == (u <= v));
                assert!((x > y) == (u > v));
                assert!((x >= y) == (u >= v));
                assert!((x == y) == (u == v));
                // [Check] Bitwise
                assert!((x & y).into() == (u & v));
                if (u | v) < PRIME {
                    assert!((x | y).into() == (u | v));
                }
                if (u ^ v) < PRIME {
                    assert!((x ^ y).into() == (u ^ v));
                }
                // [Check] Division
                if v != 0 {
                    assert!((x / y).into() == u / v);
                    assert!((x % y).into() == u % v);
                }
                // [Check] Wrapping is modulo P
                assert!(x.wrapping_add(y).value() == *a + *b);
                assert!(x.wrapping_sub(y).value() == *a - *b);
                assert!(x.wrapping_mul(y).value() == *a * *b);
            }
        }
    }

    #[test]
    fn test_u252_shifts_against_u256() {
        let counts: Array<u8> = array![0, 1, 5, 64, 127, 128, 129, 192, 193, 250, 251];
        for value in samples() {
            let x: u252 = value.into();
            let u: u256 = value.into();
            for count in counts.span() {
                let pow: u256 = super::Bits::pow(*count).into();
                // [Check] Floor and exact right shifts
                assert!(x.shr(*count).into() == u / pow);
                if u % pow == 0 {
                    assert!(x.shr_exact(*count).into() == u / pow);
                }
                // [Check] Bit test
                assert!(x.bit(*count) == ((u / pow) % 2 == 1));
            }
        }
    }

    #[test]
    fn test_u252_shl_edges() {
        let one: u252 = 1_u8.into();
        assert!(one.shl(251).value() == TWO_POW_251);
        assert!(one.shl(0) == one);
        let max: u252 = Bounded::MAX;
        // [Check] (P - 1) / 2 * 2 = P - 1 fits, (P + 1) / 2 * 2 = P does not
        let half: u252 = (P_MINUS_1 * super::Bits::inv(1)).into();
        assert!(half.shl(1) == max);
        // [Check] Every representable single-bit and edge shift matches the u256 oracle
        for value in samples() {
            let x: u252 = value.into();
            let u: u256 = value.into();
            let mut count: u8 = 0;
            while count < 252 {
                let pow: u256 = super::Bits::pow(count).into();
                let fits = u == 0 || (u <= (PRIME - 1) / pow);
                if fits {
                    assert!(x.shl(count).into() == u * pow);
                }
                count += 17;
            }
        }
    }

    #[test]
    #[should_panic(expected: 'u252_shl Overflow')]
    fn test_u252_shl_overflow_top() {
        let half: u252 = ((P_MINUS_1 + 2) * super::Bits::inv(1)).into();
        half.shl(1);
    }

    #[test]
    #[should_panic(expected: 'u252_shl Overflow')]
    fn test_u252_shl_overflow_wide() {
        let x: u252 = TWO_POW_128.into();
        x.shl(124);
    }

    #[test]
    #[should_panic(expected: 'u252_shr Inexact')]
    fn test_u252_shr_inexact() {
        let x: u252 = 0b1010_u8.into();
        x.shr_exact(2);
    }

    #[test]
    #[should_panic(expected: 'u252_add Overflow')]
    fn test_u252_add_overflow() {
        let max: u252 = Bounded::MAX;
        max + One::one();
    }

    #[test]
    #[should_panic(expected: 'u252_add Overflow')]
    fn test_u252_add_overflow_wide() {
        let x: u252 = TWO_POW_251.into();
        x + x;
    }

    #[test]
    #[should_panic(expected: 'u252_sub Overflow')]
    fn test_u252_sub_underflow() {
        let zero: u252 = Zero::zero();
        zero - One::one();
    }

    #[test]
    #[should_panic(expected: 'u252_mul Overflow')]
    fn test_u252_mul_overflow() {
        let x: u252 = TWO_POW_128.into();
        let y: u252 = 0x8000000000000110000000000000001_u128.into();
        x * y;
    }

    #[test]
    #[should_panic(expected: 'u252_or Overflow')]
    fn test_u252_or_overflow() {
        let x: u252 = TWO_POW_251.into();
        let y: u252 = (TWO_POW_251 - 1).into();
        x | y;
    }

    #[test]
    #[should_panic(expected: 'u252_or Overflow')]
    fn test_u252_set_bit_overflow() {
        let x: u252 = (TWO_POW_251 - 1).into();
        x.set_bit(251);
    }

    #[test]
    fn test_u252_div_rem_and_bits() {
        for value in samples() {
            let x: u252 = value.into();
            let u: u256 = value.into();
            let (q, r) = x.div_rem(7);
            assert!(q.into() == u / 7);
            assert!(r.into() == u % 7);
            if (u | 8) < PRIME {
                let set = x.set_bit(3);
                assert!(set.into() == (u | 8));
                assert!(set.bit(3));
            }
        }
    }

    #[test]
    fn test_u252_constants_and_conversions() {
        assert!(Zero::<u252>::zero().is_zero());
        assert!(One::<u252>::one().is_one());
        assert!(Bounded::<u252>::MIN.is_zero());
        assert!(Bounded::<u252>::MAX.value() == P_MINUS_1);
        let x: u252 = 200_u8.into();
        assert!(x.try_into() == Some(200_u8));
        let y: u252 = TWO_POW_128.into();
        assert!(TryInto::<u252, u128>::try_into(y).is_none());
        assert!(TryInto::<u252, u8>::try_into(y).is_none());
    }

    #[test]
    fn test_u252_serde_and_packing() {
        for value in samples() {
            let x: u252 = value.into();
            let mut out = array![];
            x.serialize(ref out);
            assert!(out.len() == 1 && *out.at(0) == value);
            let mut span = out.span();
            let back: u252 = Serde::deserialize(ref span).unwrap();
            assert!(back == x);
            assert!(StorePacking::<u252, felt252>::unpack(StorePacking::pack(x)) == x);
        }
    }
}
