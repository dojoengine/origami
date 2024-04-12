#[dojo::contract]
mod erc721_metadata_mock {
    use token::components::token::erc721::erc721_metadata::erc721_metadata_component;

    component!(
        path: erc721_metadata_component, storage: erc721_metadata, event: ERC721MetadataEvent
    );

    #[abi(embed_v0)]
    impl ERC721MetadataImpl =
        erc721_metadata_component::ERC721MetadataImpl<ContractState>;

    impl ERC721MetadataInternalImpl = erc721_metadata_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_metadata: erc721_metadata_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721MetadataEvent: erc721_metadata_component::Event
    }
}
