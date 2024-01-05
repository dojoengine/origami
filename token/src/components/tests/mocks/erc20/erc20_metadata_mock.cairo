#[dojo::contract]
mod erc20_metadata_mock {
    use token::components::token::erc20::erc20_metadata::erc20_metadata_component;

    component!(path: erc20_metadata_component, storage: erc20_metadata, event: ERC20MetadataEvent);

    #[abi(embed_v0)]
    impl ERC20MetadataImpl =
        erc20_metadata_component::ERC20MetadataImpl<ContractState>;

    impl ERC20MetadataInternalImpl = erc20_metadata_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_metadata: erc20_metadata_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20MetadataEvent: erc20_metadata_component::Event
    }
}
