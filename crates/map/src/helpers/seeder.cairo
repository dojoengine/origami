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

    #[inline]
    fn random_position(width: u8, height: u8, seed: felt252) -> u8 {
        let seed: u256 = seed.into();
        let x: u8 = (seed % (width - 2).into()).try_into().unwrap() + 1;
        let seed: u256 = Self::reseed(seed.low.into(), seed.high.into()).into();
        let y: u8 = (seed % (height - 2).into()).try_into().unwrap() + 1;
        x + y * width
    }
}
