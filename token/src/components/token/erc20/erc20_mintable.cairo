///
/// ERC20Mintable Component
///
#[starknet::component]
mod erc20_mintable_component {
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::token::erc20::erc20_balance::erc20_balance_component as erc20_balance_comp;
    use token::components::token::erc20::erc20_metadata::erc20_metadata_component as erc20_metadata_comp;

    use erc20_balance_comp::InternalImpl as ERC20BalanceInternal;
    use erc20_metadata_comp::InternalImpl as ERC20MetadataInternal;


    #[storage]
    struct Storage {}

    mod Errors {
        const MINT_TO_ZERO: felt252 = 'ERC20: mint to 0';
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Balance: erc20_balance_comp::HasComponent<TContractState>,
        impl ERC20Metadata: erc20_metadata_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn mint(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256
        ) {
            assert(!recipient.is_zero(), Errors::MINT_TO_ZERO);

            let mut erc20_balance = get_dep_component_mut!(ref self, ERC20Balance);
            let mut erc20_metadata = get_dep_component_mut!(ref self, ERC20Metadata);

            erc20_metadata.update_total_supply(0, amount);
            erc20_balance.update_balance(recipient, 0, amount);

            let transfer_event = erc20_balance_comp::Transfer {
                from: Zeroable::zero(), to: recipient, value: amount
            };

            erc20_balance.emit(transfer_event.clone());
            emit!(
                self.get_contract().world(), (erc20_balance_comp::Event::Transfer(transfer_event))
            );
        }
    }
}
