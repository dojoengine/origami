use starknet::ContractAddress;

///
/// Model
///

#[derive(Drop, Serde)]
#[dojo::model]
struct ERC721MetaModel {
    #[key]
    token: ContractAddress,
    name: ByteArray,
    symbol: ByteArray,
    base_uri: ByteArray,
}

///
/// Interface
///

#[starknet::interface]
trait IERC721Metadata<TState> {
    fn name(self: @TState) -> ByteArray;
    fn symbol(self: @TState) -> ByteArray;
    fn token_uri(ref self: TState, token_id: u256) -> ByteArray;
}

#[starknet::interface]
trait IERC721MetadataCamel<TState> {
    fn tokenURI(ref self: TState, tokenId: u256) -> ByteArray;
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

    use token::components::token::erc721::erc721_owner::erc721_owner_component as erc721_owner_comp;
    use erc721_owner_comp::InternalImpl as ERC721OwnerInternal;

    #[storage]
    struct Storage {}

    mod Errors {
        const INVALID_TOKEN_ID: felt252 = 'ERC721: invalid token ID';
    }

    #[embeddable_as(ERC721MetadataImpl)]
    impl ERC721Metadata<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IERC721Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> ByteArray {
            self.get_meta().name
        }
        fn symbol(self: @ComponentState<TContractState>) -> ByteArray {
            self.get_meta().symbol
        }
        fn token_uri(ref self: ComponentState<TContractState>, token_id: u256) -> ByteArray {
            self.get_uri(token_id)
        }
    }

    #[embeddable_as(ERC721MetadataCamelImpl)]
    impl ERC721MetadataCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IERC721MetadataCamel<ComponentState<TContractState>> {
        fn tokenURI(ref self: ComponentState<TContractState>, tokenId: u256) -> ByteArray {
            self.get_uri(tokenId)
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC721Owner: erc721_owner_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_meta(self: @ComponentState<TContractState>) -> ERC721MetaModel {
            get!(self.get_contract().world(), get_contract_address(), (ERC721MetaModel))
        }

        fn get_uri(ref self: ComponentState<TContractState>, token_id: u256) -> ByteArray {
            let mut erc721_owner = get_dep_component_mut!(ref self, ERC721Owner);
            assert(erc721_owner.exists(token_id), Errors::INVALID_TOKEN_ID);
            let base_uri = self.get_meta().base_uri;
            if base_uri.len() == 0 {
                return "";
            } else {
                return format!("{}{}", base_uri, token_id);
            }
        }

        fn initialize(
            ref self: ComponentState<TContractState>,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray
        ) {
            set!(
                self.get_contract().world(),
                ERC721MetaModel { token: get_contract_address(), name, symbol, base_uri }
            )
        }
    }
}
