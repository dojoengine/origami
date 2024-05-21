///
/// ERC721Mintable Component
///
#[starknet::component]
mod erc721_mintable_component {
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::token::erc721::erc721_approval::erc721_approval_component as erc721_approval_comp;
    use token::components::token::erc721::erc721_balance::erc721_balance_component as erc721_balance_comp;
    use token::components::token::erc721::erc721_owner::erc721_owner_component as erc721_owner_comp;

    use erc721_approval_comp::InternalImpl as ERC721ApprovalInternal;
    use erc721_balance_comp::InternalImpl as ERC721BalanceInternal;
    use erc721_owner_comp::InternalImpl as ERC721OwnerInternal;

    #[storage]
    struct Storage {}

    mod Errors {
        const INVALID_RECEIVER: felt252 = 'ERC721: invalid receiver';
        const ALREADY_MINTED: felt252 = 'ERC721: token already minted';
        const SAFE_MINT_FAILED: felt252 = 'ERC721: safe mint failed';
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Balance: erc721_balance_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn mint(ref self: ComponentState<TContractState>, to: ContractAddress, token_id: u256) {
            assert(!to.is_zero(), Errors::INVALID_RECEIVER);
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);
            assert(!erc721_owner.exists(token_id), Errors::ALREADY_MINTED);

            erc721_balance.set_balance(to, erc721_balance.get_balance(to).amount.into() + 1);
            erc721_owner.set_owner(token_id, to);

            let transfer_event = erc721_balance_comp::Transfer {
                from: Zeroable::zero(), to, token_id
            };

            erc721_balance.emit(transfer_event.clone());
            emit!(
                self.get_contract().world(), (erc721_balance_comp::Event::Transfer(transfer_event))
            );
        }

        fn safe_mint(
            ref self: ComponentState<TContractState>,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            self.mint(to, token_id);
            assert(
                erc721_balance.check_on_erc721_received(Zeroable::zero(), to, token_id, data),
                Errors::SAFE_MINT_FAILED
            );
        }
    }
}
