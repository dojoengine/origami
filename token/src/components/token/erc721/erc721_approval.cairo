use starknet::ContractAddress;

///
/// Model
///

#[derive(Copy, Drop, Serde)]
#[dojo::model]
struct ERC721TokenApprovalModel {
    #[key]
    token: ContractAddress,
    #[key]
    token_id: u128,
    address: ContractAddress,
}

#[derive(Copy, Drop, Serde)]
#[dojo::model]
struct ERC721OperatorApprovalModel {
    #[key]
    token: ContractAddress,
    #[key]
    owner: ContractAddress,
    #[key]
    operator: ContractAddress,
    approved: bool
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Approval<TState> {
    fn get_approved(ref self: TState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn approve(ref self: TState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TState, operator: ContractAddress, approved: bool);
}

#[starknet::interface]
trait IERC721ApprovalCamel<TState> {
    fn getApproved(ref self: TState, tokenId: u256) -> ContractAddress;
    fn isApprovedForAll(self: @TState, owner: ContractAddress, operator: ContractAddress) -> bool;
    fn setApprovalForAll(ref self: TState, operator: ContractAddress, approved: bool);
}

///
/// ERC721Approval Component
///
#[starknet::component]
mod erc721_approval_component {
    use super::ERC721TokenApprovalModel;
    use super::ERC721OperatorApprovalModel;
    use super::IERC721Approval;
    use super::IERC721ApprovalCamel;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::token::erc721::erc721_balance::erc721_balance_component as erc721_balance_comp;
    use token::components::token::erc721::erc721_owner::erc721_owner_component as erc721_owner_comp;
    use erc721_balance_comp::InternalImpl as ERC721BalanceInternal;
    use erc721_owner_comp::InternalImpl as ERC721OwnerInternal;


    #[storage]
    struct Storage {}

    #[event]
    #[derive(Copy, Drop, Serde, starknet::Event)]
    enum Event {
        Approval: Approval,
        ApprovalForAll: ApprovalForAll
    }

    #[derive(Copy, Drop, Serde, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        token_id: u256
    }

    #[derive(Copy, Drop, Serde, starknet::Event)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    mod Errors {
        const INVALID_TOKEN_ID: felt252 = 'ERC721: invalid token ID';
        const UNAUTHORIZED: felt252 = 'ERC721: unauthorized caller';
        const APPROVAL_TO_OWNER: felt252 = 'ERC721: approval to owner';
        const SELF_APPROVAL: felt252 = 'ERC721: self approval';
    }


    #[embeddable_as(ERC721ApprovalImpl)]
    impl ERC721Approval<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721Approval<ComponentState<TContractState>> {
        fn get_approved(
            ref self: ComponentState<TContractState>, token_id: u256
        ) -> ContractAddress {
            self.get_approved_internal(token_id).address
        }

        fn is_approved_for_all(
            self: @ComponentState<TContractState>, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.get_approval_for_all(owner, operator).approved
        }

        fn approve(ref self: ComponentState<TContractState>, to: ContractAddress, token_id: u256) {
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);

            let owner = erc721_owner.get_owner(token_id).address;
            let caller = get_caller_address();
            assert(
                owner == caller || self.get_approval_for_all(owner, caller).approved,
                Errors::UNAUTHORIZED
            );
            self.set_token_approval(owner, to, token_id, true)
        }

        fn set_approval_for_all(
            ref self: ComponentState<TContractState>, operator: ContractAddress, approved: bool
        ) {
            self._set_approval_for_all(get_caller_address(), operator, approved)
        }
    }

    #[embeddable_as(ERC721ApprovalCamelImpl)]
    impl ERC721ApprovalCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721ApprovalCamel<ComponentState<TContractState>> {
        fn getApproved(ref self: ComponentState<TContractState>, tokenId: u256) -> ContractAddress {
            self.get_approved(tokenId)
        }

        fn isApprovedForAll(
            self: @ComponentState<TContractState>, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.get_approval_for_all(owner, operator).approved
        }

        fn setApprovalForAll(
            ref self: ComponentState<TContractState>, operator: ContractAddress, approved: bool
        ) {
            self.set_approval_for_all(operator, approved)
        }
    }

    ///
    /// Internal
    ///

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        // Helper function for allowance model
        fn get_approved_internal(
            ref self: ComponentState<TContractState>, token_id: u256
        ) -> ERC721TokenApprovalModel {
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);
            assert(erc721_owner.exists(token_id), Errors::INVALID_TOKEN_ID);
            get!(
                self.get_contract().world(),
                (get_contract_address(), token_id.low),
                ERC721TokenApprovalModel
            )
        }

        fn get_approval_for_all(
            self: @ComponentState<TContractState>, owner: ContractAddress, operator: ContractAddress
        ) -> ERC721OperatorApprovalModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), owner, operator),
                ERC721OperatorApprovalModel
            )
        }

        fn set_token_approval(
            ref self: ComponentState<TContractState>,
            owner: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            emit: bool
        ) {
            assert(owner != to, Errors::APPROVAL_TO_OWNER);
            set!(
                self.get_contract().world(),
                ERC721TokenApprovalModel {
                    token: get_contract_address(), token_id: token_id.low, address: to,
                }
            );
            if emit {
                let approval_event = Approval { owner, spender: to, token_id };

                self.emit(approval_event.clone());
                emit!(self.get_contract().world(), (Event::Approval(approval_event)));
            }
        }

        fn _set_approval_for_all(
            ref self: ComponentState<TContractState>,
            owner: ContractAddress,
            operator: ContractAddress,
            approved: bool
        ) {
            assert(owner != operator, Errors::SELF_APPROVAL);
            set!(
                self.get_contract().world(),
                ERC721OperatorApprovalModel {
                    token: get_contract_address(), owner, operator, approved
                }
            );
            let approval_event = ApprovalForAll { owner, operator, approved };

            self.emit(approval_event.clone());
            emit!(self.get_contract().world(), (Event::ApprovalForAll(approval_event)));
        }

        fn is_approved_or_owner(
            ref self: ComponentState<TContractState>, spender: ContractAddress, token_id: u256
        ) -> bool {
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);
            let owner = erc721_owner.get_owner(token_id).address;
            let is_approved_for_all = self.get_approval_for_all(owner, spender).approved;
            owner == spender
                || is_approved_for_all
                || spender == self.get_approved_internal(token_id).address
        }
    }
}
