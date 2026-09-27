// External imports

use fixed::exp::ExpTrait;
use fixed::{Fixed, ONE};

// Internal imports

use super::helpers::FixedStorePacking;

// Based on https://www.paradigm.xyz/2022/08/vrgda

pub trait VRGDAVarsTrait<T> {
    fn get_target_price(self: @T) -> Fixed;
    fn get_decay_constant(self: @T) -> Fixed;
}

pub trait VRGDATrait<T> {
    fn get_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed;
    fn get_reverse_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed;
}

pub trait VRGDATargetTimeTrait<T> {
    fn get_target_sale_time(self: @T, sold: Fixed) -> Fixed;
}

/// `(1 - decay_constant)^x` is computed as `exp(x * ln(1 - decay_constant))`, cheaper than
/// `powf`.
pub impl TVRGDATrait<T, +VRGDAVarsTrait<T>, +VRGDATargetTimeTrait<T>> of VRGDATrait<T> {
    /// Calculates the VRGDA price at a specific time since the auction started.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the auction started.
    /// * `sold`: Quantity sold. (Not including this unit) eg if this the price for the first unit
    /// sold  is 0.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the price.
    fn get_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed {
        self.get_target_price()
            * ((time_since_start - self.get_target_sale_time(sold + ONE))
                * (ONE - self.get_decay_constant()).ln())
                .exp()
    }

    fn get_reverse_vrgda_price(self: @T, time_since_start: Fixed, sold: Fixed) -> Fixed {
        self.get_target_price()
            * ((self.get_target_sale_time(sold + ONE) - time_since_start)
                * (ONE - self.get_decay_constant()).ln())
                .exp()
    }
}

/// A Linear Variable Rate Gradual Dutch Auction (VRGDA) struct.
/// Represents an auction where the price decays linearly based on the target price,
/// decay constant, and per-time-unit rate.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct LinearVRGDA {
    pub target_price: Fixed,
    pub decay_constant: Fixed,
    pub target_units_per_time: Fixed,
}


pub impl LinearVRGDAVarsImpl of VRGDAVarsTrait<LinearVRGDA> {
    fn get_target_price(self: @LinearVRGDA) -> Fixed {
        *self.target_price
    }
    fn get_decay_constant(self: @LinearVRGDA) -> Fixed {
        *self.decay_constant
    }
}


impl LinearVRGDATargetTimeImpl of VRGDATargetTimeTrait<LinearVRGDA> {
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
}

pub impl LinearVRGDAImpl = TVRGDATrait<LinearVRGDA>;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct LogisticVRGDA {
    pub target_price: Fixed,
    pub decay_constant: Fixed,
    pub max_sellable: Fixed,
    pub time_scale: Fixed // target time to sell 46% of units
}

impl LogisticVRGDAVarsImpl of VRGDAVarsTrait<LogisticVRGDA> {
    fn get_target_price(self: @LogisticVRGDA) -> Fixed {
        *self.target_price
    }
    fn get_decay_constant(self: @LogisticVRGDA) -> Fixed {
        *self.decay_constant
    }
}

pub impl LogisticVRGDATargetTimeImpl of VRGDATargetTimeTrait<LogisticVRGDA> {
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
        // 2 * limit / (sold + limit) - 1 = (limit - sold) / (limit + sold)
        let logistic_limit = *self.max_sellable + ONE;
        -*self.time_scale * ((logistic_limit - sold) / (logistic_limit + sold)).ln()
    }
}
pub impl LogisticVRGDAImpl = TVRGDATrait<LogisticVRGDA>;


#[cfg(test)]
mod tests {
    // External imports

    use fixed::{Fixed, FixedTrait, ZERO};

    // Constants
    const DAY_FIXED_RAW: i64 = 371085174374400; // 2**32 * 60 * 60 * 24
    // Helpers

    fn to_days_fp(x: Fixed) -> Fixed {
        x / FixedTrait::from_raw(DAY_FIXED_RAW)
    }

    fn from_days_fp(x: Fixed) -> Fixed {
        x * FixedTrait::from_raw(DAY_FIXED_RAW)
    }

    fn assert_rel_approx_eq(a: Fixed, b: Fixed, max_percent_delta: Fixed) {
        if b == ZERO {
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

        use fixed::{FixedTrait, HALF, ZERO};
        use super::assert_rel_approx_eq;
        use super::super::{LinearVRGDA, VRGDATrait};

        // Constants

        const _69_42: i64 = 298156629688;
        const _0_31: i64 = 1331439862;
        const DELTA_0_0005: i64 = 2147484;
        const DELTA_0_02: i64 = 85899346;
        const DELTA: i64 = 42950;

        #[test]
        fn test_pricing_basic() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::from_raw(_69_42),
                decay_constant: FixedTrait::from_raw(_0_31),
                target_units_per_time: FixedTrait::from_int(2),
            };

            let time = HALF;
            let cost = auction.get_vrgda_price(time, ZERO);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::from_raw(DELTA_0_0005));
        }

        #[test]
        fn test_pricing_basic_reverse() {
            let auction = LinearVRGDA {
                target_price: FixedTrait::from_raw(_69_42),
                decay_constant: FixedTrait::from_raw(_0_31),
                target_units_per_time: FixedTrait::from_int(2),
            };

            let time = HALF;
            let cost = auction.get_reverse_vrgda_price(time, ZERO);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::from_raw(DELTA_0_0005));
        }
    }

    mod logistic {
        // Local imports

        use super::super::{LogisticVRGDA, VRGDATrait};
        use super::{FixedTrait, assert_rel_approx_eq};

        // Constants

        const _69_42: i64 = 298156629688;
        const _0_31: i64 = 1331439862;
        const DELTA_0_0005: i64 = 2147484;
        const DELTA_0_02: i64 = 85899346;
        const MAX_SELLABLE: i32 = 1000000;
        const _0_0023: i64 = 9878425;
        const HUNDRED_DAYS_RAW: i64 = 371085174374400;

        #[test]
        fn test_target_price() {
            let one_hundred = FixedTrait::from_int(100);
            let auction = LogisticVRGDA {
                target_price: FixedTrait::from_raw(_69_42),
                decay_constant: FixedTrait::from_raw(_0_31),
                max_sellable: FixedTrait::from_int(MAX_SELLABLE),
                time_scale: one_hundred,
            };

            let cost = auction.get_vrgda_price(one_hundred, FixedTrait::from_int(462116));

            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::from_raw(DELTA_0_0005));
        }

        #[test]
        fn test_pricing_basic() {
            let hundred_days = FixedTrait::from_raw(HUNDRED_DAYS_RAW);
            let auction = LogisticVRGDA {
                target_price: FixedTrait::from_raw(_69_42),
                decay_constant: FixedTrait::from_raw(_0_31),
                max_sellable: FixedTrait::from_int(MAX_SELLABLE),
                time_scale: hundred_days,
            };
            let time_delta = FixedTrait::from_raw(HUNDRED_DAYS_RAW / 2);
            let num_mint = FixedTrait::from_int(244918);

            let cost = auction.get_vrgda_price(time_delta, num_mint);
            println!("price {} target price {}", cost.to_raw(), auction.target_price.to_raw());
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::from_raw(DELTA_0_02));
        }

        #[test]
        fn test_pricing_basic_reverse() {
            let auction = LogisticVRGDA {
                target_price: FixedTrait::from_raw(_69_42),
                decay_constant: FixedTrait::from_raw(_0_31),
                max_sellable: FixedTrait::from_int(MAX_SELLABLE),
                time_scale: FixedTrait::from_raw(_0_0023),
            };
            // 5.6e-13, below the Q32.32 resolution
            let time_delta = FixedTrait::from_raw(0);
            // 4.7e-17, below the Q32.32 resolution
            let num_mint = FixedTrait::from_raw(0);

            let cost = auction.get_reverse_vrgda_price(time_delta, num_mint);
            assert_rel_approx_eq(cost, auction.target_price, FixedTrait::from_raw(DELTA_0_02));
        }
    }
}
