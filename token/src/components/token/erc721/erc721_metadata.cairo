use starknet::ContractAddress;

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct ERC721MetaModel {
    #[key]
    token: ContractAddress,
    name: felt252,
    symbol: felt252,
    base_uri: felt252,
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Metadata<TState> {
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn token_uri(self: @TState, token_id: u128) -> felt252;
}

#[starknet::interface]
trait IERC721MetadataCamel<TState> {
    fn tokenURI(self: @TState, tokenId: u128) -> felt252;
}

///
/// ERC20Metadata Component
///
#[starknet::component]
mod erc721_metadata_component {
    use super::ERC721MetaModel;
    use super::IERC721Metadata;
    use super::IERC721MetadataCamel;

    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    #[embeddable_as(ERC721MetadataImpl)]
    impl ERC721Metadata<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> felt252 {
            self.get_meta().name
        }
        fn symbol(self: @ComponentState<TContractState>) -> felt252 {
            self.get_meta().symbol
        }
        fn token_uri(self: @ComponentState<TContractState>, token_id: u128) -> felt252 {
            self.get_uri()
        }
    }

    #[embeddable_as(ERC721MetadataCamelImpl)]
    impl ERC721MetadataCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721MetadataCamel<ComponentState<TContractState>> {
        fn tokenURI(self: @ComponentState<TContractState>, tokenId: u128) -> felt252 {
            self.get_uri()
        }
    }



    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_meta(self: @ComponentState<TContractState>) -> ERC721MetaModel {
            get!(self.get_contract().world(), get_contract_address(), (ERC721MetaModel))
        }

        fn get_uri(self:  @ComponentState<TContractState>) -> felt252 {
            // TODO : concat with id when we have string type
            self.get_meta().base_uri
        }

        fn initialize(
            ref self: ComponentState<TContractState>, name: felt252, symbol: felt252, base_uri: felt252
        ) {
            set!(
                self.get_contract().world(),
                ERC721MetaModel {
                    token: get_contract_address(), name, symbol, base_uri
                }
            )
        }
    }
}
