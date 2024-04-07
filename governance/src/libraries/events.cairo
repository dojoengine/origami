mod tokenevents {
    use starknet::ContractAddress;

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct DelegateChanged {
        #[key]
        delegator: ContractAddress,
        from_delegate: ContractAddress,
        to_delegate: ContractAddress,
    }

    #[derive(Model, Copy, Drop, Serde)]
    #[dojo::event]
    struct DelegateVotesChanged {
        #[key]
        delegate: ContractAddress,
        previous_balance: u128,
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
