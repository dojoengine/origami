
/// 
/// An empty implementation of the ERC721MetadataHooksTrait
/// 
/// When the hook is not required, import together with the component:
/// use token::components::token::erc721::erc721_metadata::erc721_metadata_component;
/// use token::components::token::erc721::erc721_metadata_hooks::ERC721MetadataHooksEmptyImpl;
/// 
/// Or implement your own (example on erc721_metadata_hooks_mock.cairo)
/// 

use token::components::token::erc721::erc721_metadata::erc721_metadata_component;

impl ERC721MetadataHooksEmptyImpl<TContractState> of erc721_metadata_component::ERC721MetadataHooksTrait<TContractState> {
    fn custom_uri(
        self: @erc721_metadata_component::ComponentState<TContractState>,
        base_uri: @ByteArray,
        token_id: u256,
    ) -> ByteArray { "" }
}
