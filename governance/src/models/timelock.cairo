use starknet::{ContractAddress, ClassHash};


#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct TimelockParams {
    #[key]
    contract: ContractAddress,
    admin: ContractAddress,
    delay: u64,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct PendingAdmin {
    #[key]
    contract: ContractAddress,
    address: ContractAddress,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct QueuedTransactions {
    #[key]
    contract: ContractAddress,
    #[key]
    class_hash: ClassHash,
    queued: bool,
}

