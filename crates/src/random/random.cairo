use poseidon::PoseidonTrait;
use hash::HashStateTrait;
use traits::Into;

#[derive(Drop)]
struct Random {
    last_number: u8,
    seed: felt252,
    nonce: felt252,
}



trait RandomTrait {
    fn new(last_number: u8, seed: felt252) -> Random;
    fn getRandomWithInterval(ref self:Random,min_number:u8,max_number:u8) -> u8;
}

impl RandomImpl of RandomTrait {

    #[inline(always)]
    fn new(last_number: u8, seed: felt252) -> Random {
        Random { last_number, seed, nonce: 0 }
    }

    #[inline(always)]
    fn getRandomWithInterval(ref self:Random,min_number:u8,max_number:u8) -> u8 {
        let mut state = PoseidonTrait::new();
        state = state.update(self.seed);
        state = state.update(self.nonce);
        self.nonce += 1;
        let random: u256 = state.finalize().into();
        let range = (max_number - min_number).into();
        let scaled_random = (random % range) + min_number.into();
        scaled_random.try_into().unwrap()
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use debug::PrintTrait;

    // Local imports

    use super::RandomTrait;

    // Constants


    #[test]
    #[available_gas(2000000)]
    fn test_random() {
       let mut random = RandomTrait::new(0, 0);
       assert(random.getRandomWithInterval(0,100) == 92, 'wrong random number');
       assert(random.getRandomWithInterval(0,100) == 75, 'wrong random number');
       assert(random.getRandomWithInterval(0,100) == 21, 'wrong random number');
    }

}