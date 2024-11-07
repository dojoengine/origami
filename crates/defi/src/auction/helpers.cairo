// External imports

use cubit::f128::types::fixed::{Fixed, FixedTrait};

pub fn to_days_fp(x: Fixed) -> Fixed {
    x / FixedTrait::new(86400, false)
}

pub fn from_days_fp(x: Fixed) -> Fixed {
    x * FixedTrait::new(86400, false)
}

#[cfg(test)]
mod tests {
    // External imports

    use cubit::f128::types::fixed::FixedTrait;

    // Local imports

    use super::{to_days_fp, from_days_fp};

    // Constants

    const TOLERANCE: u128 = 18446744073709550; // 0.001

    #[test]
    fn test_days_convertions() {
        let days = FixedTrait::new(2, false);
        let actual = to_days_fp(from_days_fp(days));
        let tolerance = TOLERANCE * 10;
        let left_bound = days - FixedTrait::new(tolerance, false);
        let right_bound = days + FixedTrait::new(tolerance, false);
        assert(left_bound <= actual && actual <= right_bound, 'Not approx eq');
    }
}

