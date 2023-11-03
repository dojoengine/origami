// External imports

use cubit::f128::math::core::{ln, abs, exp};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

/// A Linear Variable Rate Gradual Dutch Auction (VRGDA) struct.
/// Represents an auction where the price decays linearly based on the target price,
/// decay constant, and per-time-unit rate.
#[derive(Copy, Drop, Serde, starknet::Storage)]
struct LinearVRGDA {
    target_price: Fixed,
    decay_constant: Fixed,
    per_time_unit: Fixed,
}

#[generate_trait]
impl LinearVRGDAImpl of LinearVRGDATrait {
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
        sold / *self.per_time_unit
    }

    /// Calculates the VRGDA price at a specific time since the auction started.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the auction started.
    /// * `sold`: Quantity sold.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the price.
    fn get_vrgda_price(self: @LinearVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * exp(
                *self.decay_constant
                    * (time_since_start
                        - self.get_target_sale_time(sold + FixedTrait::new(1, false)))
            )
    }

    fn get_reverse_vrgda_price(self: @LinearVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * exp(
                (*self.decay_constant * FixedTrait::new(1, true))
                    * (time_since_start
                        - self.get_target_sale_time(sold + FixedTrait::new(1, false)))
            )
    }
}

#[derive(Copy, Drop, Serde, starknet::Storage)]
struct LogisticVRGDA {
    target_price: Fixed,
    decay_constant: Fixed,
    max_sellable: Fixed,
    time_scale: Fixed,
}

// A Logistic Variable Rate Gradual Dutch Auction (VRGDA) struct.
/// Represents an auction where the price decays according to a logistic function,
/// based on the target price, decay constant, max sellable quantity, and time scale.
#[generate_trait]
impl LogisticVRGDAImpl of LogisticVRGDATrait {
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
        let logistic_limit_double = logistic_limit * FixedTrait::new_unscaled(2, false);
        abs(
            ln(logistic_limit_double / (sold + logistic_limit) - FixedTrait::ONE())
                / *self.time_scale
        )
    }

    /// Calculates the VRGDA price at a specific time since the auction started,
    /// using the logistic function.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the auction started.
    /// * `sold`: Quantity sold.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the price.
    fn get_vrgda_price(self: @LogisticVRGDA, time_since_start: Fixed, sold: Fixed) -> Fixed {
        *self.target_price
            * exp(
                *self.decay_constant
                    * (time_since_start
                        - self.get_target_sale_time(sold + FixedTrait::new(1, false)))
            )
    }

    fn get_reverse_vrgda_price(
        self: @LogisticVRGDA, time_since_start: Fixed, sold: Fixed
    ) -> Fixed {
        *self.target_price
            * exp(
                (*self.decay_constant * FixedTrait::new(1, true))
                    * (time_since_start
                        - self.get_target_sale_time(sold + FixedTrait::new(1, false)))
            )
    }
}

#[cfg(test)]
mod tests {
    // External imports

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    // Constants

    // Helpers

    fn to_days_fp(x: Fixed) -> Fixed {
        x / FixedTrait::new(86400, false)
    }

    fn from_days_fp(x: Fixed) -> Fixed {
        x * FixedTrait::new(86400, false)
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

        use super::{Fixed, FixedTrait};
        use super::{to_days_fp, from_days_fp};
        use super::assert_rel_approx_eq;
        use super::super::{LinearVRGDA, LinearVRGDATrait};

        // Constants

        const _69_42: u128 = 1280572973596917000000;
        const _0_31: u128 = 5718490662849961000;
        const DELTA_0_0005: u128 = 9223372036854776;
        const DELTA_0_02: u128 = 368934881474191000;
        const DELTA: u128 = 184467440737095;

        #[test]
        #[available_gas(2000000)]
        fn test_target_price() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                per_time_unit: FixedTrait::new_unscaled(2, false),
            };
            let time = from_days_fp(auction.get_target_sale_time(FixedTrait::new(1, false)));
            let cost = auction
                .get_vrgda_price(to_days_fp(time + FixedTrait::new(1, false)), FixedTrait::ZERO());
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_0005, false));
        }

        #[test]
        #[available_gas(20000000)]
        fn test_pricing_basic() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                per_time_unit: FixedTrait::new_unscaled(2, false),
            };
            let time_delta = FixedTrait::new(10368001, false); // 120 days
            let num_mint = FixedTrait::new(239, true);
            let cost = auction.get_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }

        #[test]
        #[available_gas(20000000)]
        fn test_pricing_basic_reverse() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                per_time_unit: FixedTrait::new_unscaled(2, false),
            };
            let time_delta = FixedTrait::new(10368001, false); // 120 days
            let num_mint = FixedTrait::new(239, true);
            let cost = auction.get_reverse_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }
    }

    mod logistic {
        // Local imports

        use super::{Fixed, FixedTrait};
        use super::{to_days_fp, from_days_fp};
        use super::assert_rel_approx_eq;
        use super::super::{LogisticVRGDA, LogisticVRGDATrait};

        // Constants

        const _69_42: u128 = 1280572973596917000000;
        const _0_31: u128 = 5718490662849961000;
        const DELTA_0_0005: u128 = 9223372036854776;
        const DELTA_0_02: u128 = 368934881474191000;
        const MAX_SELLABLE: u128 = 6392;
        const _0_0023: u128 = 42427511369531970;

        #[test]
        #[available_gas(200000000)]
        fn test_target_price() {
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_scale: FixedTrait::new(_0_0023, false),
            };
            let time = from_days_fp(auction.get_target_sale_time(FixedTrait::new(1, false)));

            let cost = auction
                .get_vrgda_price(time + FixedTrait::new(1, false), FixedTrait::ZERO());
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_0005, false));
        }

        #[test]
        #[available_gas(200000000)]
        fn test_pricing_basic() {
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_scale: FixedTrait::new(_0_0023, false),
            };
            let time_delta = FixedTrait::new(10368001, false);
            let num_mint = FixedTrait::new(876, false);

            let cost = auction.get_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }

        #[test]
        #[available_gas(200000000)]
        fn test_pricing_basic_reverse() {
            let auction = LogisticVRGDA {
                target_price: FixedTrait::new(_69_42, false),
                decay_constant: FixedTrait::new(_0_31, false),
                max_sellable: FixedTrait::new_unscaled(MAX_SELLABLE, false),
                time_scale: FixedTrait::new(_0_0023, false),
            };
            let time_delta = FixedTrait::new(10368001, false);
            let num_mint = FixedTrait::new(876, false);

            let cost = auction.get_reverse_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::new(DELTA_0_02, false));
        }
    }
}

