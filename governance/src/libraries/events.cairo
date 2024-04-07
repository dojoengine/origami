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
