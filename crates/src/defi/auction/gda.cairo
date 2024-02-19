// External imports

use cubit::f128::math::ops::{exp, pow};
use cubit::f128::types::fixed::{Fixed, FixedTrait};

/// A Gradual Dutch Auction represented using discrete time steps.
/// The purchase price for a given quantity is calculated based on
/// the initial price, scale factor, decay constant, and the time since
/// the auction has started.
#[derive(Copy, Drop, Serde, starknet::Storage)]
struct DiscreteGDA {
    sold: Fixed,
    initial_price: Fixed,
    scale_factor: Fixed,
    decay_constant: Fixed,
}

#[generate_trait]
impl DiscreteGDAImpl of DiscreteGDATrait {
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
        let num1 = *self.initial_price * pow(*self.scale_factor, *self.sold);
        let num2 = pow(*self.scale_factor, quantity) - FixedTrait::ONE();
        let den1 = exp(*self.decay_constant * time_since_start);
        let den2 = *self.scale_factor - FixedTrait::ONE();
        (num1 * num2) / (den1 * den2)
    }
}

/// A Gradual Dutch Auction represented using continuous time steps.
/// The purchase price is calculated based on the initial price,
/// emission rate, decay constant, and the time since the last purchase in days.
#[derive(Copy, Drop, Serde, starknet::Storage)]
struct ContinuousGDA {
    initial_price: Fixed,
    emission_rate: Fixed,
    decay_constant: Fixed,
}

#[generate_trait]
impl ContinuousGDAImpl of ContinuousGDATrait {
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
        let num1 = *self.initial_price / *self.decay_constant;
        let num2 = exp((*self.decay_constant * quantity) / *self.emission_rate) - FixedTrait::ONE();
        let den = exp(*self.decay_constant * time_since_last);
        (num1 * num2) / den
    }
}

#[cfg(test)]
mod tests {
    // External imports

    use cubit::f128::types::fixed::{Fixed, FixedTrait};

    // Constants

    const TOLERANCE: u128 = 18446744073709550; // 0.001

    // Helpers

    fn assert_approx_equal(expected: Fixed, actual: Fixed, tolerance: u128) {
        let left_bound = expected - FixedTrait::new(tolerance, false);
        let right_bound = expected + FixedTrait::new(tolerance, false);
        assert(left_bound <= actual && actual <= right_bound, 'Not approx eq');
    }

    mod continuous {
        // Local imports

        use super::{Fixed, FixedTrait};
        use super::{assert_approx_equal, TOLERANCE};
        use super::super::{ContinuousGDA, ContinuousGDATrait};

        // ipynb with calculations at https://colab.research.google.com/drive/14elIFRXdG3_gyiI43tP47lUC_aClDHfB?usp=sharing
        #[test]
        fn test_price_1() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::new_unscaled(1000, false),
                emission_rate: FixedTrait::ONE(),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(22128445337405634000000, false);
            let time_since_last = FixedTrait::new_unscaled(10, false);
            let quantity = FixedTrait::new_unscaled(9, false);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }


        #[test]
        fn test_price_2() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::new_unscaled(1000, false),
                emission_rate: FixedTrait::ONE(),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(89774852279643700000, false);
            let time_since_last = FixedTrait::new_unscaled(20, false);
            let quantity = FixedTrait::new_unscaled(8, false);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_3() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::new_unscaled(1000, false),
                emission_rate: FixedTrait::ONE(),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(20393925850936156000, false);
            let time_since_last = FixedTrait::new_unscaled(30, false);
            let quantity = FixedTrait::new_unscaled(15, false);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_4() {
            let auction = ContinuousGDA {
                initial_price: FixedTrait::new_unscaled(1000, false),
                emission_rate: FixedTrait::ONE(),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(3028401847768577000000, false);
            let time_since_last = FixedTrait::new_unscaled(40, false);
            let quantity = FixedTrait::new_unscaled(35, false);
            let price: Fixed = auction.purchase_price(time_since_last, quantity);
            assert_approx_equal(price, expected, TOLERANCE)
        }
    }

    mod discrete {
        // Local imports

        use super::{Fixed, FixedTrait};
        use super::{assert_approx_equal, TOLERANCE};
        use super::super::{DiscreteGDA, DiscreteGDATrait};

        #[test]
        fn test_initial_price() {
            let auction = DiscreteGDA {
                sold: FixedTrait::new_unscaled(0, false),
                initial_price: FixedTrait::new_unscaled(1000, false),
                scale_factor: FixedTrait::new_unscaled(11, false)
                    / FixedTrait::new_unscaled(10, false),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let price = auction.purchase_price(FixedTrait::ZERO(), FixedTrait::ONE());
            assert_approx_equal(price, auction.initial_price, TOLERANCE)
        }

        // ipynb with calculations at https://colab.research.google.com/drive/14elIFRXdG3_gyiI43tP47lUC_aClDHfB?usp=sharing
        #[test]
        fn test_price_1() {
            let auction = DiscreteGDA {
                sold: FixedTrait::new_unscaled(1, false),
                initial_price: FixedTrait::new_unscaled(1000, false),
                scale_factor: FixedTrait::new_unscaled(11, false)
                    / FixedTrait::new_unscaled(10, false),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(1856620062541316600000, false);
            let price = auction
                .purchase_price(
                    FixedTrait::new_unscaled(10, false), FixedTrait::new_unscaled(9, false),
                );
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_2() {
            let auction = DiscreteGDA {
                sold: FixedTrait::new_unscaled(2, false),
                initial_price: FixedTrait::new_unscaled(1000, false),
                scale_factor: FixedTrait::new_unscaled(11, false)
                    / FixedTrait::new_unscaled(10, false),
                decay_constant: FixedTrait::new(1, false) / FixedTrait::new(2, false),
            };
            let expected = FixedTrait::new(2042282068795448600000, false);
            let price = auction
                .purchase_price(
                    FixedTrait::new_unscaled(10, false), FixedTrait::new_unscaled(9, false),
                );
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_3() {
            let auction = DiscreteGDA {
                sold: FixedTrait::new_unscaled(4, false),
                initial_price: FixedTrait::new_unscaled(1000, false),
                scale_factor: FixedTrait::new_unscaled(11, false)
                    / FixedTrait::new_unscaled(10, false),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(2471161303242493000000, false);
            let price = auction
                .purchase_price(
                    FixedTrait::new_unscaled(10, false), FixedTrait::new_unscaled(9, false),
                );
            assert_approx_equal(price, expected, TOLERANCE)
        }

        #[test]
        fn test_price_4() {
            let auction = DiscreteGDA {
                sold: FixedTrait::new_unscaled(20, false),
                initial_price: FixedTrait::new_unscaled(1000, false),
                scale_factor: FixedTrait::new_unscaled(11, false)
                    / FixedTrait::new_unscaled(10, false),
                decay_constant: FixedTrait::new_unscaled(1, false)
                    / FixedTrait::new_unscaled(2, false),
            };
            let expected = FixedTrait::new(291, false);
            let price = auction
                .purchase_price(
                    FixedTrait::new_unscaled(85, false), FixedTrait::new_unscaled(1, false),
                );
            assert_approx_equal(price, expected, TOLERANCE)
        }
    }
}
