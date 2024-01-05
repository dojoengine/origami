#[dojo::contract]
mod InitializableMock {
    use token::components::security::initializable::initializable_component;

    component!(path: initializable_component, storage: initializable, event: InitializableEvent);

    #[abi(embed_v0)]
    impl InitializableImpl =
        initializable_component::InitializableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        initializable: initializable_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        InitializableEvent: initializable_component::Event
    }
}
