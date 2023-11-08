#[derive(Model, Copy, Drop, Serde)]
struct ERC20Balance {
    #[key]
    token: starknet::ContractAddress,
    #[key]
    account: starknet::ContractAddress,
    amount: u256,
}

#[derive(Model, Copy, Drop, Serde)]
struct ERC20Allowance {
    #[key]
    token: starknet::ContractAddress,
    #[key]
    owner: starknet::ContractAddress,
    #[key]
    spender: starknet::ContractAddress,
    amount: u256,
}

#[derive(Model, Copy, Drop, Serde)]
struct ERC20Meta {
    #[key]
    token: starknet::ContractAddress,
    name: felt252,
    symbol: felt252,
    total_supply: u256,
}
