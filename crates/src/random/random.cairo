//! Random struct and methods for generating random numbers with interval [min_number, max_number]

// Core imports
use poseidon::PoseidonTrait;
use hash::HashStateTrait;
use traits::Into;

// Random struct for managing random number generation
#[derive(Drop)]
struct Random {
    seed: felt252,
    nonce: felt252,
}

// Random trait for generating random numbers with interval [min_number, max_number]
trait RandomTrait {
    /// Returns a new `Random` struct.
    /// # Arguments
    /// * `seed` - A seed to initialize the random number generator.
    /// # Returns
    /// * The initialized `Random`.
    fn new(seed: felt252) -> Random;

    /// Returns a random number within the specified interval.
    /// # Arguments
    /// * `min_number` - The lower bound of the interval.
    /// * `max_number` - The upper bound of the interval.
    /// # Returns
    /// * A random number within the interval [min_number, max_number].

    fn getRandomWithInterval(ref self: Random, min_number: u256, max_number: u256) -> u256;
}

/// Implementation of the `RandomTrait` trait for the `Random` struct.
impl RandomImpl of RandomTrait {
    #[inline(always)]
    fn new(seed: felt252) -> Random {
        Random { seed, nonce: 0 }
    }

    #[inline(always)]
    fn getRandomWithInterval(ref self: Random, min_number: u256, max_number: u256) -> u256 {
        assert(min_number <= max_number, 'wrong interval');
        let mut state = PoseidonTrait::new();
        state = state.update(self.seed);
        state = state.update(self.nonce);
        self.nonce += 1;
        let random: u256 = state.finalize().into();
        let range: u256 = (max_number - min_number).into();
        let scaled_random: u256 = (random % range) + min_number.into();
        scaled_random
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use debug::PrintTrait;

    // Local imports

    use super::RandomTrait;

    // Constants

    const SEED: felt252 = 'SEED';
    const INTERVAL_START: u256 = 0;
    const INTERVAL_END: u256 = 100;

    #[test]
    #[available_gas(2000000)]
    fn test_random() {
        let mut random = RandomTrait::new(DICE_SEED);
        let mut x = random.getRandomWithInterval(INTERVAL_START, INTERVAL_END);

        assert(
            random.getRandomWithInterval(INTERVAL_START, INTERVAL_END) != 60,
            'random number is not random'
        );
        assert(
            random.getRandomWithInterval(INTERVAL_START, INTERVAL_END) != 65,
            'random number is not random'
        );
        assert(
            random.getRandomWithInterval(INTERVAL_START, INTERVAL_END) != 44,
            'random number is not random'
        );
    }

    #[test]
    #[should_panic(expected: ('wrong interval',))]
    #[available_gas(2000000)]
    fn test_wrong_interval() {
        let mut random = RandomTrait::new(DICE_SEED);
        let mut x = random.getRandomWithInterval(INTERVAL_END, INTERVAL_START);
    }
}
