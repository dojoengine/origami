#[dojo::contract]
mod ERC20Preset {
    use token::erc20::interface;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_contract_address};
    use zeroable::Zeroable;

    use token::components::security::initializable::InitializableComponent;

    use token::components::token::erc20_metadata::ERC20MetadataComponent;
    use token::components::token::erc20_balance::ERC20BalanceComponent;
    use token::components::token::erc20_allowance::ERC20AllowanceComponent;
    use token::components::token::erc20_mintable::ERC20MintableComponent;
    use token::components::token::erc20_burnable::ERC20BurnableComponent;

    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);

    component!(path: ERC20MetadataComponent, storage: erc20_metadata, event: ERC20MetadataEvent);
    component!(path: ERC20BalanceComponent, storage: erc20_balance, event: ERC20BalanceEvent);
    component!(path: ERC20AllowanceComponent, storage: erc20_allowance, event: ERC20AllowanceEvent);
    component!(path: ERC20MintableComponent, storage: erc20_mintable, event: ERC20MintableEvent);
    component!(path: ERC20BurnableComponent, storage: erc20_burnable, event: ERC20BurnableEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        #[substorage(v0)]
        erc20_metadata: ERC20MetadataComponent::Storage,
        #[substorage(v0)]
        erc20_balance: ERC20BalanceComponent::Storage,
        #[substorage(v0)]
        erc20_allowance: ERC20AllowanceComponent::Storage,
        #[substorage(v0)]
        erc20_mintable: ERC20MintableComponent::Storage,
        #[substorage(v0)]
        erc20_burnable: ERC20BurnableComponent::Storage,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        // #[flat]
        InitializableEvent: InitializableComponent::Event,
        // #[flat]
        ERC20MetadataEvent: ERC20MetadataComponent::Event,
        // #[flat]
        ERC20BalanceEvent: ERC20BalanceComponent::Event,
        // #[flat]
        ERC20AllowanceEvent: ERC20AllowanceComponent::Event,
        // #[flat]
        ERC20MintableEvent: ERC20MintableComponent::Event,
        // #[flat]
        ERC20BurnableEvent: ERC20BurnableComponent::Event,
    }

    mod Errors {
        const ALREADY_INITIALIZED: felt252 = 'ERC20: already initialized';
        const CALLER_IS_NOT_OWNER: felt252 = 'ERC20: caller is not owner';

        const BURN_FROM_ZERO: felt252 = 'ERC20: burn from 0';
        const MINT_TO_ZERO: felt252 = 'ERC20: mint to 0';
    }


    impl InitializableImpl = InitializableComponent::InitializableImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl =
        ERC20MetadataComponent::ERC20MetadataImpl<ContractState>;
    impl ERC20MetadataTotalSupplyImpl =
        ERC20MetadataComponent::ERC20MetadataTotalSupplyImpl<ContractState>;
    // #[abi(embed_v0)]
    impl ERC20BalanceImpl = ERC20BalanceComponent::ERC20BalanceImpl<ContractState>;
    //#[abi(embed_v0)]
    impl ERC20AllowanceImpl = ERC20AllowanceComponent::ERC20AllowanceImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20SafeAllowanceImpl =
        ERC20AllowanceComponent::ERC20SafeAllowanceImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20SafeAllowanceCamelImpl =
        ERC20AllowanceComponent::ERC20SafeAllowanceCamelImpl<ContractState>;


    //
    // Internal Impls
    //

    impl InitializableInternalImpl = InitializableComponent::InternalImpl<ContractState>;
    impl ERC20MetadataInternalImpl = ERC20MetadataComponent::InternalImpl<ContractState>;
    impl ERC20BalanceInternalImpl = ERC20BalanceComponent::InternalImpl<ContractState>;
    impl ERC20AllowanceInternalImpl = ERC20AllowanceComponent::InternalImpl<ContractState>;
    impl ERC20MintableInternalImpl = ERC20MintableComponent::InternalImpl<ContractState>;
    impl ERC20BurnableInternalImpl = ERC20BurnableComponent::InternalImpl<ContractState>;

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
        ) {
            assert(!self.initializable.is_initialized(), Errors::ALREADY_INITIALIZED);
            assert(
                self.world().is_owner(get_caller_address(), get_contract_address().into()),
                Errors::CALLER_IS_NOT_OWNER
            );

            self.erc20_metadata._initialize(name, symbol, 18);
            self.erc20_mintable._mint(recipient, initial_supply);

            self.initializable.initialize();
        }
    }

    #[external(v0)]
    impl ERC20Impl of interface::IERC20<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20_metadata.total_supply()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20_balance.balance_of(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20_allowance.allowance(owner, spender)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20_balance.transfer(recipient, amount)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self.erc20_allowance._spend_allowance(sender, caller, amount);
            self.erc20_balance._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20_allowance.approve(spender, amount)
        }
    }

    #[external(v0)]
    impl ERC20CamelOnlyImpl of interface::IERC20CamelOnly<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            ERC20Impl::total_supply(self)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            ERC20Impl::balance_of(self, account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            ERC20Impl::transfer_from(ref self, sender, recipient, amount)
        }
    }
// #[generate_trait]
// impl WorldInteractionsImpl of WorldInteractionsTrait {
//     fn emit_event<S, +traits::Into<S, Event>, +Drop<S>, +Copy<S>>(
//         ref self: ContractState, event: S
//     ) {
//         self.emit(event.clone());
//         emit!(self.world(), event);
//     }
// }
}
