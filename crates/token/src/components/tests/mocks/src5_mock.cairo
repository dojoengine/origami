#[dojo::contract]
mod SRC5Mock {
    use origami_token::components::introspection::src5::src5_component;

    component!(path: src5_component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = src5_component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5CamelImpl = src5_component::SRC5CamelImpl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: src5_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SRC5Event: src5_component::Event
    }
}
