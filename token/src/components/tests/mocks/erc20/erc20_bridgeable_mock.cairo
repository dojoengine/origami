#[dojo::contract]
mod ERC20BridgeableMock {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};

    use token::components::security::initializable::InitializableComponent;

    use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent;
    use token::components::token::erc20::erc20_balance::ERC20BalanceComponent;
    use token::components::token::erc20::erc20_metadata::ERC20MetadataComponent;
    use token::components::token::erc20::erc20_mintable::ERC20MintableComponent;
    use token::components::token::erc20::erc20_burnable::ERC20BurnableComponent;
    use token::components::token::erc20::erc20_bridgeable::ERC20BridgeableComponent;

    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);

    component!(path: ERC20AllowanceComponent, storage: erc20_allowance, event: ERC20AllowanceEvent);
    component!(path: ERC20BalanceComponent, storage: erc20_balance, event: ERC20BalanceEvent);
    component!(path: ERC20MetadataComponent, storage: erc20_metadata, event: ERC20MetadataEvent);
    component!(path: ERC20MintableComponent, storage: erc20_mintable, event: ERC20MintableEvent);
    component!(path: ERC20BurnableComponent, storage: erc20_burnable, event: ERC20BurnableEvent);
    component!(
        path: ERC20BridgeableComponent, storage: erc20_bridgeable, event: ERC20BridgeableEvent
    );

    impl InitializableInternalImpl = InitializableComponent::InternalImpl<ContractState>;
    
    impl ERC20AllowanceInternalImpl = ERC20AllowanceComponent::InternalImpl<ContractState>;
    impl ERC20BalanceInternalImpl = ERC20BalanceComponent::InternalImpl<ContractState>;
    impl ERC20MetadataInternalImpl = ERC20MetadataComponent::InternalImpl<ContractState>;
    impl ERC20MintableInternalImpl = ERC20MintableComponent::InternalImpl<ContractState>;
    impl ERC20BurnableInternalImpl = ERC20BurnableComponent::InternalImpl<ContractState>;
    impl ERC20BridgeableInternalImpl = ERC20BridgeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        #[substorage(v0)]
        erc20_allowance: ERC20AllowanceComponent::Storage,
        #[substorage(v0)]
        erc20_balance: ERC20BalanceComponent::Storage,
        #[substorage(v0)]
        erc20_metadata: ERC20MetadataComponent::Storage,
        #[substorage(v0)]
        erc20_mintable: ERC20MintableComponent::Storage,
        #[substorage(v0)]
        erc20_burnable: ERC20BurnableComponent::Storage,
        #[substorage(v0)]
        erc20_bridgeable: ERC20BridgeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        InitializableEvent: InitializableComponent::Event,
        ERC20AllowanceEvent: ERC20AllowanceComponent::Event,
        ERC20BalanceEvent: ERC20BalanceComponent::Event,
        ERC20MetadataEvent: ERC20MetadataComponent::Event,
        ERC20MintableEvent: ERC20MintableComponent::Event,
        ERC20BurnableEvent: ERC20BurnableComponent::Event,
        ERC20BridgeableEvent: ERC20BridgeableComponent::Event,
    }

    mod Errors {
        const CALLER_IS_NOT_OWNER: felt252 = 'ERC20: caller is not owner';
    }

    impl InitializableImpl = InitializableComponent::InitializableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20AllowanceImpl = ERC20AllowanceComponent::ERC20AllowanceImpl<ContractState>;

     #[abi(embed_v0)]
    impl ERC20BalanceImpl = ERC20BalanceComponent::ERC20BalanceImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MetadataImpl =
        ERC20MetadataComponent::ERC20MetadataImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20BridgeableImpl =
        ERC20BridgeableComponent::ERC20BridgeableImpl<ContractState>;

    //
    // Initializer
    //

    #[external(v0)]
    #[generate_trait]
    impl ERC20InitializerImpl of ERC20InitializerTrait {
        fn initializer(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            initial_supply: u256,
            recipient: ContractAddress,
            l2_bridge_address: ContractAddress,
        ) {
            assert(
                self.world().is_owner(get_caller_address(), get_contract_address().into()),
                Errors::CALLER_IS_NOT_OWNER
            );

            self.erc20_metadata.initialize(name, symbol, 18);
            self.erc20_mintable.mint(recipient, initial_supply);
            self.erc20_bridgeable.initialize(l2_bridge_address);

            self.initializable.initialize();
        }
    }
}
