// Core imports

use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;

#[generate_trait]
pub impl Seeder of SeederTrait {
    #[inline]
    fn reseed(lhs: felt252, rhs: felt252) -> felt252 {
        let mut state = PoseidonTrait::new();
        state = state.update(lhs);
        state = state.update(rhs);
        state.finalize()
    }
}
