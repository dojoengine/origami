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

    use super::{from_days_fp, to_days_fp};

    // Constants

    const TOLERANCE: i64 = 4294967; // 0.001

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
