//! The examples of `README.md`, compiled against the public API.

use fixed::{Fixed, FixedTrait, ONE};
use origami_defi::auction::gda::{ContinuousGDA, ContinuousGDATrait, DiscreteGDA, DiscreteGDATrait};
use origami_defi::auction::vrgda::{LinearVRGDA, LogisticVRGDA, VRGDATargetTimeTrait, VRGDATrait};

#[test]
fn test_readme_discrete_gda() {
    let gda = DiscreteGDA {
        sold: FixedTrait::from_int(0),
        initial_price: FixedTrait::from_int(100),
        scale_factor: FixedTrait::from_ratio(11, 10), // 1.1
        decay_constant: FixedTrait::from_ratio(1, 2) // 0.5
    };
    let time_since_start = FixedTrait::from_int(2); // 2 days since the start
    let quantity = FixedTrait::from_int(5); // Quantity to purchase
    let price = gda.purchase_price(time_since_start, quantity);
    assert!(price > FixedTrait::from_int(0));
}

#[test]
fn test_readme_continuous_gda() {
    let gda = ContinuousGDA {
        initial_price: FixedTrait::from_int(1000),
        emission_rate: ONE,
        decay_constant: FixedTrait::from_ratio(1, 2),
    };
    let time_since_last = FixedTrait::from_int(1); // 1 day since the last purchase
    let quantity = FixedTrait::from_int(3); // Quantity to purchase
    let price = gda.purchase_price(time_since_last, quantity);
    assert!(price > FixedTrait::from_int(0));
}

#[test]
fn test_readme_linear_vrgda() {
    let auction = LinearVRGDA {
        target_price: FixedTrait::from_ratio(6942, 100), // 69.42
        decay_constant: FixedTrait::from_ratio(31, 100), // 0.31
        target_units_per_time: FixedTrait::from_int(2),
    };
    let sold_quantity: Fixed = FixedTrait::from_int(10);
    let time_since_start: Fixed = FixedTrait::from_int(5);
    let target_sale_time = auction.get_target_sale_time(sold_quantity);
    let price = auction.get_vrgda_price(time_since_start, sold_quantity);
    assert!(target_sale_time == FixedTrait::from_int(5));
    assert!(price > FixedTrait::from_int(0));
}

#[test]
fn test_readme_logistic_vrgda() {
    let auction = LogisticVRGDA {
        target_price: FixedTrait::from_ratio(6942, 100), // 69.42
        decay_constant: FixedTrait::from_ratio(31, 100), // 0.31
        max_sellable: FixedTrait::from_int(6392),
        time_scale: FixedTrait::from_ratio(23, 10000) // 0.0023
    };
    let sold_quantity: Fixed = FixedTrait::from_int(10);
    let time_since_start: Fixed = FixedTrait::from_int(5);
    let target_sale_time = auction.get_target_sale_time(sold_quantity);
    let price = auction.get_vrgda_price(time_since_start, sold_quantity);
    assert!(target_sale_time > FixedTrait::from_int(0));
    assert!(price > FixedTrait::from_int(0));
}
