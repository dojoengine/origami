#[dojo::contract]
mod erc721_approval_mock {
    use token::components::token::erc721::erc721_approval::erc721_approval_component;
    use token::components::token::erc721::erc721_owner::erc721_owner_component;

    component!(
        path: erc721_approval_component, storage: erc721_approval, event: ERC721ApprovalEvent
    );
    component!(path: erc721_owner_component, storage: erc721_owner, event: ERC721OwnerEvent);

    #[abi(embed_v0)]
    impl ERC721ApprovalImpl =
        erc721_approval_component::ERC721ApprovalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ApprovalCamelImpl =
        erc721_approval_component::ERC721ApprovalCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721OwnerImpl = erc721_owner_component::ERC721OwnerImpl<ContractState>;

    impl ERC721ApprovalInternalImpl = erc721_approval_component::InternalImpl<ContractState>;
    impl ERC721OwnerInternalImpl = erc721_owner_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_approval: erc721_approval_component::Storage,
        #[substorage(v0)]
        erc721_owner: erc721_owner_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721ApprovalEvent: erc721_approval_component::Event,
        ERC721OwnerEvent: erc721_owner_component::Event
    }
}
