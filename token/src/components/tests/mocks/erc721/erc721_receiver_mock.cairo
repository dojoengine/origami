use dojo::world::IWorldDispatcher;

#[starknet::interface]
trait IERC721ReceiverMock<TState> {
    fn supports_interface(self: @TState, interface_id: felt252) -> bool;
    fn supportsInterface(self: @TState, interfaceId: felt252) -> bool;

    fn initializer(ref self: TState);
}

#[starknet::interface]
trait IERC721ReceiverMockInit<TState> {
    fn initializer(ref self: TState);
}

#[dojo::contract(allow_ref_self)]
mod erc721_receiver_mock {
    use token::components::introspection::src5::src5_component;
    use token::components::token::erc721::erc721_receiver::erc721_receiver_component;

    component!(path: erc721_receiver_component, storage: erc721_receiver, event: ERC721ReceiverEvent);
    component!(path: src5_component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = src5_component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ReceiverImpl = erc721_receiver_component::ERC721ReceiverImpl<ContractState>;

    impl ERC721ReceiverInternalImpl = erc721_receiver_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_receiver: erc721_receiver_component::Storage,
        #[substorage(v0)]
        src5: src5_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721ReceiverEvent: erc721_receiver_component::Event,
        SRC5Event: src5_component::Event
    }

    #[abi(embed_v0)]
    impl InitializerImpl of super::IERC721ReceiverMockInit<ContractState> {
        fn initializer(ref self: ContractState) {
            // mint to recipient
            self.erc721_receiver.initializer();
        }
    }
}
