#[dojo::contract]
mod ERC20MintableBurnableMock {
    use token::components::token::erc20_balance::ERC20BalanceComponent;
    use token::components::token::erc20_metadata::ERC20MetadataComponent;
    use token::components::token::erc20_mintable::ERC20MintableComponent;
    use token::components::token::erc20_burnable::ERC20BurnableComponent;

    component!(path: ERC20BalanceComponent, storage: erc20_balance, event: ERC20BalanceEvent);
    component!(path: ERC20MetadataComponent, storage: erc20_metadata, event: ERC20MetadataEvent);
    component!(path: ERC20MintableComponent, storage: erc20_mintable, event: ERC20MintableEvent);
    component!(path: ERC20BurnableComponent, storage: erc20_burnable, event: ERC20BurnableEvent);

    impl ERC20BalanceInternalImpl = ERC20BalanceComponent::InternalImpl<ContractState>;
    impl ERC20MetadataInternalImpl = ERC20MetadataComponent::InternalImpl<ContractState>;
    impl ERC20MintableInternalImpl = ERC20MintableComponent::InternalImpl<ContractState>;
    impl ERC20BurnableInternalImpl = ERC20BurnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_balance: ERC20BalanceComponent::Storage,
        #[substorage(v0)]
        erc20_metadata: ERC20MetadataComponent::Storage,
        #[substorage(v0)]
        erc20_mintable: ERC20MintableComponent::Storage,
        #[substorage(v0)]
        erc20_burnable: ERC20BurnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20BalanceEvent: ERC20BalanceComponent::Event,
        ERC20MetadataEvent: ERC20MetadataComponent::Event,
        ERC20MintableEvent: ERC20MintableComponent::Event,
        ERC20BurnableEvent: ERC20BurnableComponent::Event
    }
}
