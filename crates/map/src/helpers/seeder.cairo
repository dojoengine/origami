// Core imports

use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;

#[generate_trait]
pub impl Seeder of SeederTrait {
    /// Shuffle two values to generate a new value.
    /// # Arguments
    /// * `lhs` - The left value
    /// * `rhs` - The right value
    /// # Returns
    /// * The shuffled value
    #[inline]
    fn shuffle(lhs: felt252, rhs: felt252) -> felt252 {
        let mut state = PoseidonTrait::new();
        state = state.update(lhs);
        state = state.update(rhs);
        state.finalize()
    }

    /// Generate a random position on the map excluding the edges.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `seed` - The seed to generate the position
    /// # Returns
    /// * The random position
    #[inline]
    fn random_position(width: u8, height: u8, seed: felt252) -> u8 {
        let seed: u256 = seed.into();
        let x: u8 = (seed % (width - 2).into()).try_into().unwrap() + 1;
        let seed: u256 = Self::shuffle(seed.low.into(), seed.high.into()).into();
        let y: u8 = (seed % (height - 2).into()).try_into().unwrap() + 1;
        x + y * width
    }
}
