use starknet::ContractAddress;

///
/// Model
///

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC721OwnerModel {
    #[key]
    token: ContractAddress,
    #[key]
    token_id: u128,
    address: ContractAddress,
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Owner<TState> {
    fn owner_of(self: @TState, token_id: u256) -> ContractAddress;
}

#[starknet::interface]
trait IERC721OwnerCamel<TState> {
    fn ownerOf(self: @TState, token_id: u256) -> ContractAddress;
}

///
/// ERC721Owner Component
///
#[starknet::component]
mod erc721_owner_component {
    use super::ERC721OwnerModel;
    use super::IERC721Owner;
    use super::IERC721OwnerCamel;

    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    #[embeddable_as(ERC721OwnerImpl)]
    impl ERC721Owner<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721Owner<ComponentState<TContractState>> {
        fn owner_of(self: @ComponentState<TContractState>, token_id: u256) -> ContractAddress {
            self.get_owner(token_id).address
        }
    }

    #[embeddable_as(ERC721OwnerCamelImpl)]
    impl ERC721OwnerCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721OwnerCamel<ComponentState<TContractState>> {
        fn ownerOf(self: @ComponentState<TContractState>, token_id: u256) -> ContractAddress {
            self.get_owner(token_id).address
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_owner(self: @ComponentState<TContractState>, token_id: u256) -> ERC721OwnerModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), token_id.low),
                (ERC721OwnerModel)
            )
        }

        fn set_owner(
            ref self: ComponentState<TContractState>, token_id: u256, address: ContractAddress
        ) {
            set!(
                self.get_contract().world(),
                ERC721OwnerModel { token: get_contract_address(), token_id: token_id.low, address }
            );
        }

        fn exists(self: @ComponentState<TContractState>, token_id: u256) -> bool {
            let owner = self.get_owner(token_id).address;
            owner.is_non_zero()
        }
    }
}
