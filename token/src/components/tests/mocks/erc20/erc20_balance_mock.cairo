#[dojo::contract]
mod ERC20BalanceMock {
    use token::components::token::erc20::erc20_balance::ERC20BalanceComponent;

    component!(path: ERC20BalanceComponent, storage: erc20_balance, event: ERC20BalanceEvent);

    #[abi(embed_v0)]
    impl ERC20BalanceImpl = ERC20BalanceComponent::ERC20BalanceImpl<ContractState>;

    impl ERC20BalanceInternalImpl = ERC20BalanceComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_balance: ERC20BalanceComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20BalanceEvent: ERC20BalanceComponent::Event
    }
}
