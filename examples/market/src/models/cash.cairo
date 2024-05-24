// Starknet imports

use starknet::ContractAddress;

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Cash {
    #[key]
    player: ContractAddress,
    amount: u128,
}
