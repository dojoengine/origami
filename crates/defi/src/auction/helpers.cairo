// External imports

use fixed::{Fixed, FixedTrait};

// Constants

/// One day in seconds, as a Q32.32 raw value (86400 * 2^32).
const DAY_RAW: i64 = 371085174374400;

pub fn to_days_fp(x: Fixed) -> Fixed {
    x / FixedTrait::from_raw(DAY_RAW)
}

pub fn from_days_fp(x: Fixed) -> Fixed {
    x * FixedTrait::from_raw(DAY_RAW)
}

/// Returns `a * b / c`, the product kept exact on 128 bits and the quotient truncated toward zero:
/// only the result has to fit the Q32.32 range (`fixed` has no wide division).
///
/// # Panics
///
/// * `'Fixed: overflow'` if the result does not fit, `'Division by 0'` if `c` is zero.
pub(crate) fn mul_div(a: Fixed, b: Fixed, c: Fixed) -> Fixed {
    // |a * b| < 2^126: the felt252 product is exact and always fits an i128.
    let num: felt252 = a.to_raw().into() * b.to_raw().into();
    let num: i128 = num.try_into().unwrap();
    let raw: i128 = num / c.to_raw().into();
    FixedTrait::from_raw(raw.try_into().expect('Fixed: overflow'))
}

/// Storage packing of a `Fixed` into its raw `i64`, so that the auction structs can derive
/// `starknet::Store`.
pub impl FixedStorePacking of starknet::storage_access::StorePacking<Fixed, i64> {
    #[inline]
    fn pack(value: Fixed) -> i64 {
        value.to_raw()
    }

    #[inline]
    fn unpack(value: i64) -> Fixed {
        FixedTrait::from_raw(value)
    }
}

#[cfg(test)]
mod tests {
    // External imports

    use fixed::FixedTrait;

    // Local imports

    use super::{from_days_fp, mul_div, to_days_fp};

    // Constants

    const TOLERANCE: i64 = 4294967; // 0.001

    #[test]
    fn test_mul_div_signs() {
        let (two, three, four) = (
            FixedTrait::from_int(2), FixedTrait::from_int(3), FixedTrait::from_int(4),
        );
        assert(mul_div(-three, two, four) == FixedTrait::from_ratio(-3, 2), 'mul_div -++');
        assert(mul_div(three, -two, -four) == FixedTrait::from_ratio(3, 2), 'mul_div +--');
        assert(mul_div(-three, -two, four) == FixedTrait::from_ratio(3, 2), 'mul_div --+');
    }

    #[test]
    fn test_mul_div_wide_intermediate() {
        // 2^30 * 2^30 = 2^60 does not fit, 2^60 / 2^30 does.
        let big = FixedTrait::from_int(0x40000000);
        assert(mul_div(big, big, big) == big, 'mul_div wide');
    }

    #[test]
    #[should_panic(expected: ('Fixed: overflow',))]
    fn test_mul_div_overflow() {
        let big = FixedTrait::from_int(0x40000000);
        mul_div(big, big, FixedTrait::from_int(2));
    }

    #[test]
    fn test_days_convertions() {
        let days = FixedTrait::from_int(2);
        let actual = to_days_fp(from_days_fp(days));
        let tolerance = TOLERANCE * 10;
        let left_bound = days - FixedTrait::from_raw(tolerance);
        let right_bound = days + FixedTrait::from_raw(tolerance);
        assert(left_bound <= actual && actual <= right_bound, 'Not approx eq');
    }
}
