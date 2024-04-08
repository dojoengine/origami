mod tokenevents {
    use starknet::ContractAddress;

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct DelegateChanged {
        #[key]
        delegator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct DelegateVotesChanged {
        #[key]
        delegatee: ContractAddress,
        prev_balance: u128,
        new_balance: u128,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct Transfer {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        amount: u128,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct Approval {
        #[key]
        owner: ContractAddress,
        spender: ContractAddress,
        amount: u128,
    }
}

mod timelockevents {
    use starknet::{ContractAddress, ClassHash};

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct NewAdmin {
        #[key]
        contract: ContractAddress,
        address: ContractAddress,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct NewDelay {
        #[key]
        contract: ContractAddress,
        value: u64,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct CancelTransaction {
        #[key]
        target: ContractAddress,
        class_hash: ClassHash,
        eta: u64,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct ExecuteTransaction {
        #[key]
        target: ContractAddress,
        class_hash: ClassHash,
        eta: u64,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct QueueTransaction {
        #[key]
        target: ContractAddress,
        class_hash: ClassHash,
        eta: u64,
    }
}

mod governorevents {
    use starknet::{ContractAddress, ClassHash};

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct ProposalCreated {
        #[key]
        id: usize,
        proposer: ContractAddress,
        target: ContractAddress,
        class_hash: ClassHash,
        start_block: u64,
        end_block: u64,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct VoteCast {
        #[key]
        voter: ContractAddress,
        proposal_id: usize,
        support: bool,
        votes: u128,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct ProposalCanceled {
        #[key]
        id: usize,
        cancelled: bool,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct ProposalQueued {
        #[key]
        id: usize,
        eta: u64,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct ProposalExecuted {
        #[key]
        id: usize,
        executed: bool,
    }
}
