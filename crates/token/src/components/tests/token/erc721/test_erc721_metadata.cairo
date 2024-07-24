use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use origami_token::tests::constants::{OWNER};

use origami_token::components::token::erc721::erc721_metadata::{erc_721_meta_model, ERC721MetaModel,};
use origami_token::components::token::erc721::erc721_metadata::erc721_metadata_component::{
    ERC721MetadataImpl, ERC721MetadataCamelImpl, InternalImpl
};
use origami_token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;

use origami_token::components::tests::mocks::erc721::erc721_metadata_mock::erc721_metadata_mock;
use starknet::storage::{StorageMemberAccessTrait};


fn STATE() -> (IWorldDispatcher, erc721_metadata_mock::ContractState) {
    let world = spawn_test_world(array![erc_721_meta_model::TEST_CLASS_HASH,]);

    let mut state = erc721_metadata_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
fn test_erc721_metadata_initialize() {
    let (_world, mut state) = STATE();

    let NAME: ByteArray = "NAME";
    let SYMBOL: ByteArray = "SYMBOL";
    let URI: ByteArray = "URI";

    state.erc721_metadata.initialize(NAME, SYMBOL, URI);

    assert(state.erc721_metadata.name() == "NAME", 'Should be NAME');
    assert(state.erc721_metadata.symbol() == "SYMBOL", 'Should be SYMBOL');

    state.erc721_mintable.mint(OWNER(), 1);
    assert(state.erc721_metadata.token_uri(1) == "URI1", 'Should be URI1');
    assert(state.erc721_metadata.tokenURI(1) == "URI1", 'Should be URI1');
}
