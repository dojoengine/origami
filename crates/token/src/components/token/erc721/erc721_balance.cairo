use starknet::ContractAddress;

///
/// Model
///

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721BalanceModel {
    #[key]
    token: ContractAddress,
    #[key]
    account: ContractAddress,
    amount: u128,
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Balance<TState> {
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn transfer_from(ref self: TState, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safe_transfer_from(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
}

#[starknet::interface]
trait IERC721BalanceCamel<TState> {
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(ref self: TState, from: ContractAddress, to: ContractAddress, tokenId: u256);
    fn safeTransferFrom(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data: Span<felt252>
    );
}

///
/// ERC721Balance Component
///
#[starknet::component]
mod erc721_balance_component {
    use super::ERC721BalanceModel;
    use super::IERC721Balance;
    use super::IERC721BalanceCamel;

    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };
    use origami_token::components::introspection::src5::{ISRC5Dispatcher, ISRC5DispatcherTrait};
    use origami_token::components::token::erc721::erc721_approval::erc721_approval_component as erc721_approval_comp;
    use origami_token::components::token::erc721::erc721_owner::erc721_owner_component as erc721_owner_comp;
    use origami_token::components::token::erc721::interface::{
        IERC721_RECEIVER_ID, IERC721ReceiverDispatcher, IERC721ReceiverDispatcherTrait
    };
    use erc721_approval_comp::InternalImpl as ERC721ApprovalInternal;
    use erc721_owner_comp::InternalImpl as ERC721OwnerInternal;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Copy, Drop, Serde, starknet::Event)]
    enum Event {
        Transfer: Transfer
    }

    #[derive(Copy, Drop, Serde, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256
    }

    mod Errors {
        const INVALID_ACCOUNT: felt252 = 'ERC721: invalid account';
        const UNAUTHORIZED: felt252 = 'ERC721: unauthorized caller';
        const INVALID_RECEIVER: felt252 = 'ERC721: invalid receiver';
        const WRONG_SENDER: felt252 = 'ERC721: wrong sender';
        const SAFE_TRANSFER_FAILED: felt252 = 'ERC721: safe transfer failed';
    }

    #[embeddable_as(ERC721BalanceImpl)]
    impl ERC721Balance<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721Balance<ComponentState<TContractState>> {
        fn balance_of(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            assert(account.is_non_zero(), Errors::INVALID_ACCOUNT);
            self.get_balance(account).amount.into()
        }

        fn transfer_from(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256
        ) {
            let mut erc721_approval = get_dep_component_mut!(ref self, ERC721Approval);
            assert(
                erc721_approval.is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.transfer_internal(from, to, token_id)
        }

        fn safe_transfer_from(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            let mut erc721_approval = get_dep_component_mut!(ref self, ERC721Approval);
            assert(
                erc721_approval.is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.safe_transfer_internal(from, to, token_id, data);
        }
    }

    #[embeddable_as(ERC721BalanceCamelImpl)]
    impl ERC721BalanceCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721BalanceCamel<ComponentState<TContractState>> {
        fn balanceOf(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256
        ) {
            self.transfer_from(from, to, tokenId)
        }
        fn safeTransferFrom(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            data: Span<felt252>
        ) {
            self.safe_transfer_from(from, to, tokenId, data)
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn get_balance(
            self: @ComponentState<TContractState>, account: ContractAddress
        ) -> ERC721BalanceModel {
            get!(
                self.get_contract().world(), (get_contract_address(), account), (ERC721BalanceModel)
            )
        }

        fn set_balance(
            self: @ComponentState<TContractState>, account: ContractAddress, amount: u256
        ) {
            set!(
                self.get_contract().world(),
                ERC721BalanceModel { token: get_contract_address(), account, amount: amount.low }
            );
        }

        fn transfer_internal(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256
        ) {
            assert(!to.is_zero(), Errors::INVALID_RECEIVER);
            let mut erc721_approval = get_dep_component_mut!(ref self, ERC721Approval);
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);

            let owner = erc721_owner.get_owner(token_id).address;
            assert(from == owner, Errors::WRONG_SENDER);

            // Implicit clear approvals, no need to emit an event
            erc721_approval.set_token_approval(owner, Zeroable::zero(), token_id, false);

            self.set_balance(from, self.get_balance(from).amount.into() - 1);
            self.set_balance(to, self.get_balance(to).amount.into() + 1);
            erc721_owner.set_owner(token_id, to);

            let transfer_event = Transfer { from, to, token_id };

            self.emit(transfer_event.clone());
            emit!(self.get_contract().world(), (Event::Transfer(transfer_event)));
        }

        fn safe_transfer_internal(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self.transfer_internal(from, to, token_id);
            assert(
                self.check_on_erc721_received(from, to, token_id, data),
                Errors::SAFE_TRANSFER_FAILED
            );
        }

        fn check_on_erc721_received(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) -> bool {
            let src5_dispatcher = ISRC5Dispatcher { contract_address: to };

            if src5_dispatcher.supports_interface(IERC721_RECEIVER_ID) {
                let erc721_dispatcher = IERC721ReceiverDispatcher { contract_address: to };
                erc721_dispatcher
                    .on_erc721_received(
                        get_caller_address(), from, token_id, data
                    ) == IERC721_RECEIVER_ID
            } else {
                false
            }
        }
    }
}
