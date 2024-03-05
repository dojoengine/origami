// External imports

use cubit::f128::math::ops::{ln, abs, exp};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

// Based on https://www.paradigm.xyz/2022/08/vrgda

/// A Linear Variable Rate Gradual Dutch Auction (VRGDA) struct.
/// Represents an auction where the price decays linearly based on the target price,
/// decay constant, and per-time-unit rate.
#[derive(Copy, Drop, Serde, starknet::Storage)]
struct LinearVRGDA {
    target_price: Fixed,
    decay_constant: Fixed,
    target_units_per_time: Fixed,
}

trait VRGDATrait<T> {
    fn get_target_sale_time(self: @T, sold: Fixed) -> Fixed;
    fn get_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed;
    fn get_reverse_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed;
}

impl LinearVRGDAImpl of VRGDATrait<LinearVRGDA> {
    /// Calculates the target sale time based on the quantity sold.
    ///
    /// # Arguments
    ///
    /// * `sold`: Quantity sold.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the target sale time.
    fn get_target_sale_time(self: @LinearVRGDA, sold: Fixed) -> Fixed {
        sold / *self.target_units_per_time
    }

    /// Calculates the VRGDA price at a specific time since the auction started.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the auction started.
    /// * `sold`: Quantity sold. (Not including this unit) eg if this the price for the first unit sold  is 0.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the price.
    fn get_vrgda_price(self: @LinearVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * (FixedTrait::ONE() - *self.decay_constant)
                .pow(time_since_start - self.get_target_sale_time(sold + FixedTrait::ONE()))
    }

    fn get_reverse_vrgda_price(self: @LinearVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * (FixedTrait::ONE() - *self.decay_constant)
                .pow(self.get_target_sale_time(sold + FixedTrait::ONE()) - time_since_start)
    }
}


#[derive(Copy, Drop, Serde, starknet::Storage)]
struct LogisticVRGDA {
    target_price: Fixed,
    decay_constant: Fixed,
    max_sellable: Fixed,
    time_units: Fixed, // target time to sell 46% of units
}

// A Logistic Variable Rate Gradual Dutch Auction (VRGDA) struct.
/// Represents an auction where the price decays according to a logistic function,
/// based on the target price, decay constant, max sellable quantity, and time scale.
impl LogisticVRGDAImpl of VRGDATrait<LogisticVRGDA> {
    /// Calculates the target sale time using a logistic function based on the quantity sold.
    ///
    /// # Arguments
    ///
    /// * `sold`: Quantity sold.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the target sale time.
    fn get_target_sale_time(self: @LogisticVRGDA, sold: Fixed) -> Fixed {
        let logistic_limit = *self.max_sellable + FixedTrait::ONE();
        let logistic_limit_double = logistic_limit + logistic_limit;
        -*self.time_units
            * ln((logistic_limit_double / (sold + logistic_limit)) - FixedTrait::ONE())
    }

    /// Calculates the VRGDA price at a specific time since the auction started.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the auction started.
    /// * `sold`: Quantity sold. (Not including this unit) eg if this the price for the first unit sold  is 0.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the price.
    fn get_vrgda_price(self: @LogisticVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * (FixedTrait::ONE() - *self.decay_constant)
                .pow(time_since_start - self.get_target_sale_time(sold + FixedTrait::ONE()))
    }

    fn get_reverse_vrgda_price(
        self: @LogisticVRGDA, time_since_start: Fixed, sold: Fixed
    ) -> Fixed {
        *self.target_price
            * (FixedTrait::ONE() - *self.decay_constant)
                .pow(self.get_target_sale_time(sold + FixedTrait::ONE()) - time_since_start)
    }
}

#[cfg(test)]
mod tests {
    // External imports

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    // Constants
    const DAY_FIXED_MAG: u128 = 1593798687968505259622400; // 2**64 * 60 * 60 * 24
    // Helpers

    fn to_days_fp(x: Fixed) -> Fixed {
        x / Fixed { mag: DAY_FIXED_MAG, sign: false }
    }

    fn from_days_fp(x: Fixed) -> Fixed {
        x * Fixed { mag: DAY_FIXED_MAG, sign: false }
    }

    fn assert_rel_approx_eq(a: Fixed, b: Fixed, max_percent_delta: Fixed) {
        if b == FixedTrait::ZERO() {
            assert(a == b, 'a should eq ZERO');
        }
        let percent_delta = if a > b {
            (a - b) / b
        } else {
            (b - a) / b
        };

        assert(percent_delta < max_percent_delta, 'a ~= b not satisfied');
    }

    mod linear {
        // Local imports

        use cubit::f128::types::fixed::{Fixed, FixedTrait, HALF_u128};
        use super::{to_days_fp, from_days_fp};
        use super::assert_rel_approx_eq;
        use super::super::{LinearVRGDA, VRGDATrait};

        // Constants

        const _69_42: u128 = 1280572973596917000000;
        const _0_31: u128 = 5718490662849961000;
        const DELTA_0_0005: u128 = 9223372036854776;
        const DELTA_0_02: u128 = 368934881474191000;
        const DELTA: u128 = 184467440737095;

        #[test]
        fn test_pricing_basic() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                target_units_per_time: FixedTrait::new_unscaled(2, false),
            };

            let time = FixedTrait::new(HALF_u128, false);
            let cost = auction.get_vrgda_price(time, FixedTrait::ZERO());
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_0005, false));
        }

        #[test]
        fn test_pricing_basic_reverse() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                target_units_per_time: FixedTrait::new_unscaled(2, false),
            };

            let time = FixedTrait::new(HALF_u128, false);
            let cost = auction.get_reverse_vrgda_price(time, FixedTrait::ZERO());
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_0005, false));
        }
    }

    mod logistic {
        // Local imports

        use super::{Fixed, FixedTrait};
        use super::{to_days_fp, from_days_fp};
        use super::assert_rel_approx_eq;
        use super::super::{LogisticVRGDA, VRGDATrait};

        // Constants

        const _69_42: u128 = 1280572973596917000000;
        const _0_31: u128 = 5718490662849961000;
        const DELTA_0_0005: u128 = 9223372036854776;
        const DELTA_0_02: u128 = 368934881474191000;
        const MAX_SELLABLE: u128 = 1000000;
        const _0_0023: u128 = 42427511369531970;
        const HUNDRED_DAYS_MAG: u128 = 1593798687968505259622400;

        #[test]
        fn test_target_price() {
            let one_hundred = FixedTrait::new_unscaled(100, false);
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_units: one_hundred,
            };

            let cost = auction
                .get_vrgda_price(one_hundred, FixedTrait::new_unscaled(462116, false));

            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_0005, false));
        }

        #[test]
        fn test_pricing_basic() {
            let hundred_days = Fixed { mag: HUNDRED_DAYS_MAG, sign: false };
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_units: hundred_days,
            };
            let time_delta = FixedTrait::new(HUNDRED_DAYS_MAG / 2, false);
            let num_mint = FixedTrait::new_unscaled(244918, false);

            let cost = auction.get_vrgda_price(time_delta, num_mint);
            println!("price {} target price {}", cost.mag, auction.target_price.mag);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }

        #[test]
        fn test_pricing_basic_reverse() {
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_units: FixedTrait::new(_0_0023, false),
            };
            let time_delta = FixedTrait::new(10368001, false);
            let num_mint = FixedTrait::new(876, false);

            let cost = auction.get_reverse_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }
    }
}

