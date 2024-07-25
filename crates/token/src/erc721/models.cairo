// Starknet imports

use starknet::ContractAddress;

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721Meta {
    #[key]
    token: ContractAddress,
    name: felt252,
    symbol: felt252,
    base_uri: felt252,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721OperatorApproval {
    #[key]
    token: ContractAddress,
    #[key]
    owner: ContractAddress,
    #[key]
    operator: ContractAddress,
    approved: bool
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721Owner {
    #[key]
    token: ContractAddress,
    #[key]
    token_id: felt252,
    address: ContractAddress
}

#[dojo::model]
#[derive(Model, Copy, Drop, Serde)]
struct ERC721Balance {
    #[key]
    token: ContractAddress,
    #[key]
    account: ContractAddress,
    amount: u256,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721TokenApproval {
    #[key]
    token: ContractAddress,
    #[key]
    token_id: felt252,
    address: ContractAddress,
}
