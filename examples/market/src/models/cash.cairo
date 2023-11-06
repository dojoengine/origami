// Starknet imports

use starknet::ContractAddress;

#[derive(Model, Copy, Drop, Serde)]
struct Cash {
    #[key]
    player: ContractAddress,
    amount: u128,
}
