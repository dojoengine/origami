#[dojo::contract]
mod ERC20AllowanceMock {
    use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent;

    component!(path: ERC20AllowanceComponent, storage: erc20_allowance, event: ERC20AllowanceEvent);

    #[abi(embed_v0)]
    impl ERC20AllowanceImpl =
        ERC20AllowanceComponent::ERC20AllowanceImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20SafeAllowanceImpl =
        ERC20AllowanceComponent::ERC20SafeAllowanceImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20SafeAllowanceCamelImpl =
        ERC20AllowanceComponent::ERC20SafeAllowanceCamelImpl<ContractState>;

    impl ERC20AllowanceInternalImpl = ERC20AllowanceComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_allowance: ERC20AllowanceComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20AllowanceEvent: ERC20AllowanceComponent::Event
    }
}
