/// ERC20Burnable Component
///
/// TODO: desc
#[starknet::component]
mod ERC20BurnableComponent {
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::token::erc20_balance::ERC20BalanceComponent as erc20_balance_comp;
    use token::components::token::erc20_metadata::ERC20MetadataComponent as erc20_metadata_comp;

    use erc20_balance_comp::InternalImpl as ERC20BalanceInternal;
    use erc20_metadata_comp::InternalImpl as ERC20MetadataInternal;

    #[storage]
    struct Storage {}

    mod Errors {
        const BURN_FROM_ZERO: felt252 = 'ERC20: burn from 0';
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Balance: erc20_balance_comp::HasComponent<TContractState>,
        impl ERC20Metadata: erc20_metadata_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn _burn(ref self: ComponentState<TContractState>, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), Errors::BURN_FROM_ZERO);

            // macro is not supported yet
            // let mut erc20_balance = get_dep_component_mut!(ref self, ERC20Balance);
            // let mut erc20_metadata = get_dep_component_mut!(ref self, ERC20Metadata);

            let mut contract = self.get_contract_mut();
            let mut erc20_balance = ERC20Balance::get_component_mut(ref contract);
            let mut erc20_metadata = ERC20Metadata::get_component_mut(ref contract);

            erc20_metadata._update_total_supply(amount, 0);
            erc20_balance._update_balance(account, amount, 0);

            let transfer_event = erc20_balance_comp::Transfer {
                from: account, to: Zeroable::zero(), value: amount
            };
            erc20_balance.emit(transfer_event.clone());
        // emit!(self.get_contract().world(), transfer_event);
        }
    }
}
