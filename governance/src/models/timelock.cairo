use starknet::{ContractAddress, ClassHash};

#[derive(Model, Copy, Drop, Serde)]
struct TimelockParams {
    #[key]
    contract: ContractAddress,
    admin: ContractAddress,
    delay: u64,
}

#[derive(Model, Copy, Drop, Serde)]
struct PendingAdmin {
    #[key]
    contract: ContractAddress,
    address: ContractAddress,
}

#[derive(Model, Copy, Drop, Serde)]
struct QueuedTransactions {
    #[key]
    contract: ContractAddress,
    #[key]
    class_hash: ClassHash,
    queued: bool,
}

