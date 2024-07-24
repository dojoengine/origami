use starknet::ContractAddress;

///
/// Model
///
///

#[dojo::model(namespace: "origami_token")]
#[derive(Copy, Drop, Serde)]
struct ERC721EnumerableIndexModel {
    #[key]
    token: ContractAddress,
    #[key]
    index: u128,
    token_id: u128,
}

#[derive(Copy, Drop, Serde)]
#[dojo::model(namespace: "origami_token")]
struct ERC721EnumerableOwnerIndexModel {
    #[key]
    token: ContractAddress,
    #[key]
    owner: ContractAddress,
    #[key]
    index: u128,
    token_id: u128,
}

#[derive(Copy, Drop, Serde)]
#[dojo::model(namespace: "origami_token")]
struct ERC721EnumerableTokenModel {
    #[key]
    token: ContractAddress,
    #[key]
    token_id: u128,
    index: u128,
}

#[derive(Copy, Drop, Serde)]
#[dojo::model(namespace: "origami_token")]
struct ERC721EnumerableOwnerTokenModel {
    #[key]
    token: ContractAddress,
    #[key]
    owner: ContractAddress,
    #[key]
    token_id: u128,
    index: u128,
}

#[derive(Copy, Drop, Serde)]
#[dojo::model(namespace: "origami_token")]
struct ERC721EnumerableTotalModel {
    #[key]
    token: ContractAddress,
    total_supply: u128,
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Enumerable<TState> {
    fn total_supply(self: @TState) -> u256;
    fn token_by_index(self: @TState, index: u256) -> u256;
    fn token_of_owner_by_index(ref self: TState, owner: ContractAddress, index: u256,) -> u256;
}

#[starknet::interface]
trait IERC721EnumerableCamel<TState> {
    fn totalSupply(self: @TState) -> u256;
    fn tokenByIndex(self: @TState, index: u256) -> u256;
    fn tokenOfOwnerByIndex(ref self: TState, owner: ContractAddress, index: u256,) -> u256;
}

///
/// ERC721Enumerable Component
///
#[starknet::component]
mod erc721_enumerable_component {
    use super::ERC721EnumerableIndexModel;
    use super::ERC721EnumerableOwnerIndexModel;
    use super::ERC721EnumerableTokenModel;
    use super::ERC721EnumerableOwnerTokenModel;
    use super::{ERC721EnumerableTotalModel, ERC721EnumerableTotalModelTrait};
    use super::IERC721Enumerable;
    use super::IERC721EnumerableCamel;

    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use origami_token::components::token::erc721::erc721_approval::erc721_approval_component as erc721_approval_comp;
    use origami_token::components::token::erc721::erc721_balance::erc721_balance_component as erc721_balance_comp;
    use origami_token::components::token::erc721::erc721_owner::erc721_owner_component as erc721_owner_comp;

    use erc721_approval_comp::InternalImpl as ERC721ApprovalInternal;
    use erc721_balance_comp::InternalImpl as ERC721BalanceInternal;
    use erc721_owner_comp::InternalImpl as ERC721OwnerInternal;

    #[storage]
    struct Storage {}

    mod Errors {
        const INDEX_INVALID: felt252 = 'ERC721: invalid token index';
        const OWNER_INDEX_INVALID: felt252 = 'ERC721: invalid owner index';
        const INVALID_OWNER: felt252 = 'ERC721: invalid owner';
    }

    #[embeddable_as(ERC721EnumerableImpl)]
    impl ERC721Enumerable<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Balance: erc721_balance_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721Enumerable<ComponentState<TContractState>> {
        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            self.get_total_supply().total_supply.into()
        }

        fn token_by_index(self: @ComponentState<TContractState>, index: u256) -> u256 {
            let total_supply = self.get_total_supply().total_supply.into();
            assert(index < total_supply, Errors::INDEX_INVALID);
            self.get_token_by_index(index).token_id.into()
        }

        fn token_of_owner_by_index(
            ref self: ComponentState<TContractState>, owner: ContractAddress, index: u256
        ) -> u256 {
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let owner_balance = erc721_balance.get_balance(owner).amount.into();
            assert(index < owner_balance, Errors::OWNER_INDEX_INVALID);
            assert(owner.is_non_zero(), Errors::INVALID_OWNER);
            self.get_token_of_owner_by_index(owner, index).token_id.into()
        }
    }

    #[embeddable_as(ERC721EnumerableCamelImpl)]
    impl ERC721EnumerableCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Balance: erc721_balance_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721EnumerableCamel<ComponentState<TContractState>> {
        fn totalSupply(self: @ComponentState<TContractState>) -> u256 {
            self.get_total_supply().total_supply.into()
        }

        fn tokenByIndex(self: @ComponentState<TContractState>, index: u256) -> u256 {
            let total_supply = self.get_total_supply().total_supply.into();
            assert(index < total_supply, Errors::INDEX_INVALID);
            self.get_token_by_index(index).token_id.into()
        }

        fn tokenOfOwnerByIndex(
            ref self: ComponentState<TContractState>, owner: ContractAddress, index: u256
        ) -> u256 {
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let owner_balance = erc721_balance.get_balance(owner).amount.into();
            assert(index < owner_balance, Errors::OWNER_INDEX_INVALID);
            assert(owner.is_non_zero(), Errors::INVALID_OWNER);
            self.get_token_of_owner_by_index(owner, index).token_id.into()
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Approval: erc721_approval_comp::HasComponent<TContractState>,
        impl ERC721Balance: erc721_balance_comp::HasComponent<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        fn get_total_supply(self: @ComponentState<TContractState>) -> ERC721EnumerableTotalModel {
            ERC721EnumerableTotalModelTrait::get(
                self.get_contract().world(), get_contract_address()
            )
        }

        fn get_token_by_index(
            self: @ComponentState<TContractState>, index: u256
        ) -> ERC721EnumerableIndexModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), index.low),
                (ERC721EnumerableIndexModel)
            )
        }

        fn get_token_of_owner_by_index(
            self: @ComponentState<TContractState>, owner: ContractAddress, index: u256
        ) -> ERC721EnumerableOwnerIndexModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), owner, index.low),
                (ERC721EnumerableOwnerIndexModel)
            )
        }

        fn get_index_by_token(
            self: @ComponentState<TContractState>, token_id: u256
        ) -> ERC721EnumerableTokenModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), token_id.low),
                (ERC721EnumerableTokenModel)
            )
        }

        fn get_index_of_owner_by_token(
            self: @ComponentState<TContractState>, owner: ContractAddress, token_id: u256
        ) -> ERC721EnumerableOwnerTokenModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), owner, token_id.low),
                (ERC721EnumerableOwnerTokenModel)
            )
        }

        fn add_token_to_owner_enumeration(
            ref self: ComponentState<TContractState>, to: ContractAddress, token_id: u256
        ) {
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let length = erc721_balance.get_balance(to).amount.into() - 1;
            self.set_token_of_owner_by_index(to, length, token_id);
            self.set_index_of_owner_by_token(to, token_id, length);
        }

        fn add_token_to_all_tokens_enumeration(
            ref self: ComponentState<TContractState>, token_id: u256
        ) {
            let total_supply = self.get_total_supply().total_supply.into();
            self.set_index_by_token(token_id, total_supply);
            self.set_token_by_index(total_supply, token_id);
            self.set_total_supply(total_supply + 1)
        }

        fn remove_token_from_owner_enumeration(
            ref self: ComponentState<TContractState>, from: ContractAddress, token_id: u256
        ) {
            let mut erc721_balance = get_dep_component_mut!(ref self, ERC721Balance);
            let last_token_index = erc721_balance.get_balance(from).amount.into();
            let token_index = self.get_index_by_token(token_id).index.into();

            // When the token to delete is the last token, the swap operation is unnecessary
            if (token_index != last_token_index) {
                let last_token_id = self
                    .get_token_of_owner_by_index(from, last_token_index)
                    .token_id
                    .into();

                self
                    .set_token_of_owner_by_index(
                        from, token_index, last_token_id
                    ); // Move the last token to the slot of the to-delete token
                self
                    .set_index_of_owner_by_token(
                        from, last_token_id, token_index
                    ); // Update the moved token's index
            }

            // This also deletes the contents at the last position of the array
            self.set_index_of_owner_by_token(from, token_id, 0);
            self.set_token_of_owner_by_index(from, last_token_index, 0);
        }

        fn remove_token_from_all_tokens_enumeration(
            ref self: ComponentState<TContractState>, token_id: u256
        ) {
            let last_token_index = self.get_total_supply().total_supply.into() - 1;
            let token_index = self.get_index_by_token(token_id).index.into();

            let last_token_id = self.get_token_by_index(last_token_index).token_id.into();

            self
                .set_token_by_index(
                    token_index, last_token_id
                ); // Move the last token to the slot of the to-delete token
            self.set_index_by_token(last_token_id, token_index); // Update the moved token's index

            self.set_index_by_token(token_id, 0);
            self.set_token_by_index(last_token_id, 0);
            self.set_total_supply(last_token_index);
        }

        fn set_total_supply(self: @ComponentState<TContractState>, total_supply: u256) {
            set!(
                self.get_contract().world(),
                ERC721EnumerableTotalModel {
                    token: get_contract_address(), total_supply: total_supply.low
                }
            );
        }

        fn set_token_by_index(self: @ComponentState<TContractState>, index: u256, token_id: u256) {
            set!(
                self.get_contract().world(),
                ERC721EnumerableIndexModel {
                    token: get_contract_address(), index: index.low, token_id: token_id.low
                }
            );
        }

        fn set_token_of_owner_by_index(
            self: @ComponentState<TContractState>,
            owner: ContractAddress,
            index: u256,
            token_id: u256
        ) {
            set!(
                self.get_contract().world(),
                ERC721EnumerableOwnerIndexModel {
                    token: get_contract_address(),
                    owner: owner,
                    index: index.low,
                    token_id: token_id.low
                }
            );
        }

        fn set_index_by_token(self: @ComponentState<TContractState>, token_id: u256, index: u256) {
            set!(
                self.get_contract().world(),
                ERC721EnumerableTokenModel {
                    token: get_contract_address(), token_id: token_id.low, index: index.low
                }
            );
        }

        fn set_index_of_owner_by_token(
            self: @ComponentState<TContractState>,
            owner: ContractAddress,
            token_id: u256,
            index: u256
        ) {
            set!(
                self.get_contract().world(),
                ERC721EnumerableOwnerTokenModel {
                    token: get_contract_address(),
                    owner: owner,
                    token_id: token_id.low,
                    index: index.low
                }
            );
        }
    }
}
