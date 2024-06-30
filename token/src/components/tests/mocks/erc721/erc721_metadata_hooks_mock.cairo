use dojo::world::IWorldDispatcher;

#[starknet::interface]
// trait IERC721EnumMintBurnPreset {
trait IERC721MetadataHooksMock<TContractState> {
    // IWorldProvider
    fn world(self: @TContractState,) -> IWorldDispatcher;
}

#[dojo::contract]
mod erc721_metadata_hooks_mock {

    use starknet::{get_contract_address};
    use token::components::token::erc721::erc721_approval::erc721_approval_component;
    use token::components::token::erc721::erc721_balance::erc721_balance_component;
    use token::components::token::erc721::erc721_metadata::erc721_metadata_component;
    use token::components::token::erc721::erc721_mintable::erc721_mintable_component;
    use token::components::token::erc721::erc721_owner::erc721_owner_component;

    component!(
        path: erc721_approval_component, storage: erc721_approval, event: ERC721ApprovalEvent
    );
    component!(path: erc721_balance_component, storage: erc721_balance, event: ERC721BalanceEvent);
    component!(
        path: erc721_metadata_component, storage: erc721_metadata, event: ERC721MetadataEvent
    );
    component!(
        path: erc721_mintable_component, storage: erc721_mintable, event: ERC721MintableEvent
    );
    component!(path: erc721_owner_component, storage: erc721_owner, event: ERC721OwnerEvent);

    #[abi(embed_v0)]
    impl ERC721MetadataImpl =
        erc721_metadata_component::ERC721MetadataImpl<ContractState>;

    impl ERC721ApprovalInternalImpl = erc721_approval_component::InternalImpl<ContractState>;
    impl ERC721BalanceInternalImpl = erc721_balance_component::InternalImpl<ContractState>;
    impl ERC721MetadataInternalImpl = erc721_metadata_component::InternalImpl<ContractState>;
    impl ERC721MintableInternalImpl = erc721_mintable_component::InternalImpl<ContractState>;
    impl ERC721OwnerInternalImpl = erc721_owner_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_approval: erc721_approval_component::Storage,
        #[substorage(v0)]
        erc721_balance: erc721_balance_component::Storage,
        #[substorage(v0)]
        erc721_metadata: erc721_metadata_component::Storage,
        #[substorage(v0)]
        erc721_mintable: erc721_mintable_component::Storage,
        #[substorage(v0)]
        erc721_owner: erc721_owner_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721ApprovalEvent: erc721_approval_component::Event,
        ERC721BalanceEvent: erc721_balance_component::Event,
        ERC721MetadataEvent: erc721_metadata_component::Event,
        ERC721MintableEvent: erc721_mintable_component::Event,
        ERC721OwnerEvent: erc721_owner_component::Event
    }

    
    //
    // Metadata Hooks
    //
    use super::{IERC721MetadataHooksMockDispatcher, IERC721MetadataHooksMockDispatcherTrait};
    impl ERC721MetadataHooksImpl<TContractState> of erc721_metadata_component::ERC721MetadataHooksTrait<TContractState> {
        fn custom_uri(
            self: @erc721_metadata_component::ComponentState<TContractState>,
            base_uri: @ByteArray,
            token_id: u256,
        ) -> ByteArray {
            //
            // example on how to access the world
            // (does not work for testing, throws 'CONTRACT_NOT_DEPLOYED')
            //
            // let contract_address = get_contract_address();
            // let selfie = IERC721MetadataHooksMockDispatcher{ contract_address };
            // let _world = selfie.world();

            format!("CUSTOM{}{}", base_uri, token_id)
        }
    }
}
