#[dojo::contract]
mod erc20_allowance_mock {
    use origami_token::components::token::erc20::erc20_allowance::erc20_allowance_component;

    component!(
        path: erc20_allowance_component, storage: erc20_allowance, event: ERC20AllowanceEvent
    );

    #[abi(embed_v0)]
    impl ERC20AllowanceImpl =
        erc20_allowance_component::ERC20AllowanceImpl<ContractState>;

    impl ERC20AllowanceInternalImpl = erc20_allowance_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_allowance: erc20_allowance_component::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20AllowanceEvent: erc20_allowance_component::Event
    }
}
