#[dojo::contract]
mod ERC20MetadataMock {
    use token::components::token::erc20::erc20_metadata::ERC20MetadataComponent;

    component!(path: ERC20MetadataComponent, storage: erc20_metadata, event: ERC20MetadataEvent);

    #[abi(embed_v0)]
    impl ERC20MetadataImpl =
        ERC20MetadataComponent::ERC20MetadataImpl<ContractState>;

    impl ERC20MetadataInternalImpl = ERC20MetadataComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_metadata: ERC20MetadataComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20MetadataEvent: ERC20MetadataComponent::Event
    }
}
