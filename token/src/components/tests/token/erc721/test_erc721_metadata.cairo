use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{NAME, SYMBOL, URI, TOKEN_ID};

use token::components::token::erc721::erc721_metadata::{erc_721_meta_model, ERC721MetaModel,};
use token::components::token::erc721::erc721_metadata::erc721_metadata_component::{
    ERC721MetadataImpl, ERC721MetadataCamelImpl, InternalImpl
};
use token::components::tests::mocks::erc721::erc721_metadata_mock::erc721_metadata_mock;
use token::components::tests::mocks::erc721::erc721_metadata_mock::erc721_metadata_mock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, erc721_metadata_mock::ContractState) {
    let world = spawn_test_world(array![erc_721_meta_model::TEST_CLASS_HASH,]);

    let mut state = erc721_metadata_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
fn test_erc721_metadata_initialize() {
    let (_world, mut state) = STATE();

    state.erc721_metadata.initialize(NAME, SYMBOL, URI);

    assert(state.erc721_metadata.name() == NAME, 'Should be NAME');
    assert(state.erc721_metadata.symbol() == SYMBOL, 'Should be SYMBOL');
    assert(state.erc721_metadata.token_uri(TOKEN_ID) == URI, 'Should be URI');
    assert(state.erc721_metadata.tokenURI(TOKEN_ID) == URI, 'Should be URI');
}
