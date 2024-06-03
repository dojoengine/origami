// Starknet imports

use starknet::ContractAddress;

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Item {
    #[key]
    player: ContractAddress,
    #[key]
    item_id: u32,
    quantity: u128,
}
