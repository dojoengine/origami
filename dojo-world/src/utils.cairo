

pub fn get_random(salt: felt252, max: u32) -> u32 {
   let hash: u256 = pedersen::pedersen( starknet::get_tx_info().unbox().transaction_hash, salt).into();
    (hash % max.into()).try_into().unwrap()
}