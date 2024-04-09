///
/// ERC721Burnable Component
///
#[starknet::component]
mod erc721_burnable_component {
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
        fn burn(ref self: ComponentState<TContractState>, token_id: u128) {
            let mut erc721_approval = get_dep_component_mut!(ref self, ERC721Approval);
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);
        
            let owner = erc721_owner.get_owner(token_id).address;

            // Implicit clear approvals, no need to emit an event
            erc721_approval.set_token_approval(owner, Zeroable::zero(), token_id, false);

            erc721_balance.set_balance(owner, erc721_balance.get_balance(owner).amount - 1);
            erc721_owner.set_owner(token_id, Zeroable::zero());

            let transfer_event = erc721_balance_comp::Transfer { from: owner, to: Zeroable::zero(), token_id };

            erc721_balance.emit(transfer_event.clone());
            emit!(
                self.get_contract().world(), (erc721_balance_comp::Event::Transfer(transfer_event))
            );
        }
    }
}
