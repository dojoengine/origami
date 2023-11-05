// Starknet imports

use starknet::ContractAddress;

#[derive(Model, Copy, Drop, Serde)]
struct Item {
    #[key]
    player: ContractAddress,
    #[key]
    item_id: u32,
    quantity: u128,
}
