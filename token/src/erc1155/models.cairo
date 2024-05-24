// Starknet imports

use starknet::ContractAddress;

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC1155Meta {
    #[key]
    token: ContractAddress,
    name: felt252,
    symbol: felt252,
    base_uri: felt252,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC1155OperatorApproval {
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
struct ERC1155Balance {
    #[key]
    token: ContractAddress,
    #[key]
    account: ContractAddress,
    #[key]
    id: felt252,
    amount: u256
}
