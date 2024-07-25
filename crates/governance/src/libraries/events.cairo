mod tokenevents {
    use starknet::ContractAddress;

    #[derive(Copy, Drop, Serde)]
    #[dojo::model]
    #[dojo::event]
    struct DelegateChanged {
        #[key]
        delegator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct DelegateVotesChanged {
        #[key]
        delegatee: ContractAddress,
        prev_balance: u128,
        new_balance: u128,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::model]
    #[dojo::event]
    struct Transfer {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        amount: u128,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::model]
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

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct NewAdmin {
        #[key]
        contract_selector: felt252,
        address: ContractAddress,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct NewDelay {
        #[key]
        contract_selector: felt252,
        value: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct CancelTransaction {
        #[key]
        target_selector: felt252,
        class_hash: ClassHash,
        eta: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct ExecuteTransaction {
        #[key]
        target_selector: felt252,
        class_hash: ClassHash,
        eta: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct QueueTransaction {
        #[key]
        target_selector: felt252,
        class_hash: ClassHash,
        eta: u64,
    }
}

mod governorevents {
    use origami_governance::models::governor::Support;
    use starknet::{ContractAddress, ClassHash};

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct ProposalCreated {
        #[key]
        id: usize,
        proposer: ContractAddress,
        target_selector: felt252,
        class_hash: ClassHash,
        start_block: u64,
        end_block: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct VoteCast {
        #[key]
        voter: ContractAddress,
        proposal_id: usize,
        support: Support,
        votes: u128,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct ProposalCanceled {
        #[key]
        id: usize,
        cancelled: bool,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct ProposalQueued {
        #[key]
        id: usize,
        eta: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    #[dojo::model]
    struct ProposalExecuted {
        #[key]
        id: usize,
        executed: bool,
    }
}
