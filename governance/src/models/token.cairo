use starknet::ContractAddress;

#[derive(Model, Copy, Drop, Serde)]
struct Metadata {
    #[key]
    token: ContractAddress,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Model, Copy, Drop, Serde)]
struct TotalSupply {
    #[key]
    token: ContractAddress,
    amount: u128,
}

#[derive(Model, Copy, Drop, Serde)]
struct Allowances {
    #[key]
    delegator: ContractAddress,
    #[key]
    delegatee: ContractAddress,
    amount: u128,
}

#[derive(Model, Copy, Drop, Serde)]
struct Balances {
    #[key]
    account: ContractAddress,
    amount: u128,
}

#[derive(Model, Copy, Drop, Serde)]
struct Delegates {
    #[key]
    account: ContractAddress,
    address: ContractAddress,
}

#[derive(Model, Copy, Drop, Serde)]
struct Checkpoints {
    #[key]
    account: ContractAddress,
    #[key]
    index: u64,
    checkpoint: Checkpoint,
}

#[derive(Model, Copy, Drop, Serde)]
struct NumCheckpoints {
    #[key]
    account: ContractAddress,
    count: u64,
}

#[derive(Model, Copy, Drop, Serde)]
struct Nonces {
    #[key]
    account: ContractAddress,
    nonce: usize,
}

#[derive(Copy, Debug, Drop, Introspect, Serde)]
struct Checkpoint {
    from_block: u64,
    votes: u128,
}
