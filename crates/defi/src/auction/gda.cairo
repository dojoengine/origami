// External imports

use fixed::exp::ExpTrait;
use fixed::{Fixed, ONE};

// Internal imports

use super::helpers::FixedStorePacking;

/// A Gradual Dutch Auction represented using discrete time steps.
/// The purchase price for a given quantity is calculated based on
/// the initial price, scale factor, decay constant, and the time since
/// the auction has started.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct DiscreteGDA {
    sold: Fixed,
    initial_price: Fixed,
    scale_factor: Fixed,
    decay_constant: Fixed,
}

#[generate_trait]
pub impl DiscreteGDAImpl of DiscreteGDATrait {
    /// Calculates the purchase price for a given quantity of the item at a specific time.
    ///
    /// # Arguments
    ///
    /// * `time_since_start`: Time since the start of the auction in days.
    /// * `quantity`: Quantity of the item being purchased.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the purchase price.
    fn purchase_price(self: @DiscreteGDA, time_since_start: Fixed, quantity: Fixed) -> Fixed {
        // initial_price * scale_factor^sold * (scale_factor^quantity - 1)
        //   / (exp(decay_constant * time_since_start) * (scale_factor - 1)),
        // with the powers and the decay folded into two exponentials sharing one logarithm, so
        // that no intermediate term leaves the Q32.32 range.
        let ln_scale = (*self.scale_factor).ln();
        let decay = *self.decay_constant * time_since_start;
        let low = (*self.sold * ln_scale - decay).exp();
        let high = ((*self.sold + quantity) * ln_scale - decay).exp();
        *self.initial_price * (high - low) / (*self.scale_factor - ONE)
    }
}

/// A Gradual Dutch Auction represented using continuous time steps.
/// The purchase price is calculated based on the initial price,
/// emission rate, decay constant, and the time since the last purchase in days.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ContinuousGDA {
    initial_price: Fixed,
    emission_rate: Fixed,
    decay_constant: Fixed,
}

#[generate_trait]
pub impl ContinuousGDAImpl of ContinuousGDATrait {
    /// Calculates the purchase price for a given quantity of the item at a specific time.
    ///
    /// # Arguments
    ///
    /// * `time_since_last`: Time since the last purchase in the auction in days.
    /// * `quantity`: Quantity of the item being purchased.
    ///
    /// # Returns
    ///
    /// * A `Fixed` representing the purchase price.
    fn purchase_price(self: @ContinuousGDA, time_since_last: Fixed, quantity: Fixed) -> Fixed {
        // initial_price / decay_constant * (exp(decay_constant * quantity / emission_rate) - 1)
        //   / exp(decay_constant * time_since_last),
        // with the decay folded into the exponentials so that no intermediate term leaves the
        // Q32.32 range.
        let decay = *self.decay_constant * time_since_last;
        let growth = (*self.decay_constant * quantity) / *self.emission_rate;
        let num = (growth - decay).exp() - (-decay).exp();
        (*self.initial_price / *self.decay_constant) * num
    }
}

#[cfg(test)]
mod tests {
    // External imports

    use fixed::{Fixed, FixedTrait, ONE, ZERO};

    // Constants

    const TOLERANCE: i64 = 4294967; // 0.001

    // Helpers

    fn assert_approx_equal(expected: Fixed, actual: Fixed, tolerance: i64) {
        let left_bound = expected - FixedTrait::from_raw(tolerance);
        let right_bound = expected + FixedTrait::from_raw(tolerance);
        assert(left_bound <= actual && actual <= right_bound, 'Not approx eq');
    }

    mod continuous {
        // Local imports

        use super::super::{ContinuousGDA, ContinuousGDATrait};
        use super::{Fixed, FixedTrait, ONE, TOLERANCE, assert_approx_equal};

        // ipynb with calculations at
        // https://colab.research.google.com/drive/14elIFRXdG3_gyiI43tP47lUC_aClDHfB?usp=sharing
        #[test]
        fn test_price_1() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::from_int(1000),
                emission_rate: ONE,
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(5152180170968); // 1199.585425427
            let time_since_last = FixedTrait::from_int(10);
            let quantity = FixedTrait::from_int(9);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }


        #[test]
        fn test_price_2() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::from_int(1000),
                emission_rate: ONE,
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(20902336640); // 4.866704494
            let time_since_last = FixedTrait::from_int(20);
            let quantity = FixedTrait::from_int(8);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_3() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::from_int(1000),
                emission_rate: ONE,
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(4748330883); // 1.105556936
            let time_since_last = FixedTrait::from_int(30);
            let quantity = FixedTrait::from_int(15);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_4() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::from_int(1000),
                emission_rate: ONE,
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(705104751459); // 164.169993125
            let time_since_last = FixedTrait::from_int(40);
            let quantity = FixedTrait::from_int(35);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }
    }

    mod discrete {
        // Local imports

        use super::super::{DiscreteGDA, DiscreteGDATrait};
        use super::{FixedTrait, ONE, TOLERANCE, ZERO, assert_approx_equal};

        #[test]
        fn test_initial_price() {
            let auction = DiscreteGDA {
                sold: FixedTrait::from_int(0),
                initial_price: FixedTrait::from_int(1000),
                scale_factor: FixedTrait::from_int(11) / FixedTrait::from_int(10),
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let price = auction.purchase_price(ZERO, ONE);
            assert_approx_equal(price, auction.initial_price, TOLERANCE)
        }

        // ipynb with calculations at
        // https://colab.research.google.com/drive/14elIFRXdG3_gyiI43tP47lUC_aClDHfB?usp=sharing
        #[test]
        fn test_price_1() {
            let auction = DiscreteGDA {
                sold: FixedTrait::from_int(1),
                initial_price: FixedTrait::from_int(1000),
                scale_factor: FixedTrait::from_int(11) / FixedTrait::from_int(10),
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(432278044182); // 100.647575264
            let price = auction.purchase_price(FixedTrait::from_int(10), FixedTrait::from_int(9));
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_2() {
            let auction = DiscreteGDA {
                sold: FixedTrait::from_int(2),
                initial_price: FixedTrait::from_int(1000),
                scale_factor: FixedTrait::from_int(11) / FixedTrait::from_int(10),
                decay_constant: FixedTrait::from_raw(1) / FixedTrait::from_raw(2),
            };
            let expected = FixedTrait::from_raw(475505848600); // 110.712332791
            let price = auction.purchase_price(FixedTrait::from_int(10), FixedTrait::from_int(9));
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_3() {
            let auction = DiscreteGDA {
                sold: FixedTrait::from_int(4),
                initial_price: FixedTrait::from_int(1000),
                scale_factor: FixedTrait::from_int(11) / FixedTrait::from_int(10),
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(575362076806); // 133.961922677
            let price = auction.purchase_price(FixedTrait::from_int(10), FixedTrait::from_int(9));
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_4() {
            let auction = DiscreteGDA {
                sold: FixedTrait::from_int(20),
                initial_price: FixedTrait::from_int(1000),
                scale_factor: FixedTrait::from_int(11) / FixedTrait::from_int(10),
                decay_constant: FixedTrait::from_int(1) / FixedTrait::from_int(2),
            };
            let expected = FixedTrait::from_raw(0); // 1.6e-17, below the Q32.32 resolution
            let price = auction.purchase_price(FixedTrait::from_int(85), FixedTrait::from_int(1));
            assert_approx_equal(price, expected, TOLERANCE)
        }
    }
}
