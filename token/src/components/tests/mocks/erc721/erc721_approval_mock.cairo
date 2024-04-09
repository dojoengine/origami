#[dojo::contract]
mod erc721_approval_mock {
    use token::components::token::erc721::erc721_approval::erc721_approval_component;

    component!(
        path: erc721_approval_component, storage: erc721_approval, event: ERC721ApprovalEvent
    );

    #[abi(embed_v0)]
    impl ERC721ApprovalImpl =
        erc721_approval_component::ERC721ApprovalImpl<ContractState>;

    impl ERC721ApprovalInternalImpl = erc721_approval_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_approval: erc721_approval_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721ApprovalEvent: erc721_approval_component::Event
    }
}
