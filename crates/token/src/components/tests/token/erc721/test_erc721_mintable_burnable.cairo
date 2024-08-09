use core::num::traits::Bounded;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::utils::test::spawn_test_world;
use origami_token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, TOKEN_ID};

use origami_token::components::token::erc721::erc721_metadata::{
    erc_721_meta_model, ERC721MetaModel,
};
use origami_token::components::token::erc721::erc721_metadata::erc721_metadata_component::{
    ERC721MetadataImpl, ERC721MetadataCamelImpl, InternalImpl as ERC721MetadataInternalImpl
};

use origami_token::components::token::erc721::erc721_balance::{
    erc_721_balance_model, ERC721BalanceModel,
};
use origami_token::components::token::erc721::erc721_balance::erc721_balance_component::{
    ERC721BalanceImpl, InternalImpl as ERC721BalanceInternalImpl
};
use origami_token::components::token::erc721::erc721_owner::{erc_721_owner_model, ERC721OwnerModel};
use origami_token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel,
};

use origami_token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;
use origami_token::components::token::erc721::erc721_burnable::erc721_burnable_component::InternalImpl as ERC721BurnableInternalImpl;

use origami_token::components::tests::mocks::erc721::erc721_mintable_burnable_mock::erc721_mintable_burnable_mock;

fn STATE() -> (IWorldDispatcher, erc721_mintable_burnable_mock::ContractState) {
    let world = spawn_test_world(
        "origami_token",
        array![
            erc_721_meta_model::TEST_CLASS_HASH,
            erc_721_balance_model::TEST_CLASS_HASH,
            erc_721_owner_model::TEST_CLASS_HASH,
            erc_721_token_approval_model::TEST_CLASS_HASH,
        ]
    );

    let mut state = erc721_mintable_burnable_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
fn test_erc721_mintable_mint() {
    let (_world, mut state) = STATE();

    state.erc721_mintable.mint(RECIPIENT(), TOKEN_ID);
    assert(state.balance_of(RECIPIENT()) == 1, 'invalid balance_of');
}

#[test]
#[should_panic(expected: ('ERC721: invalid receiver',))]
fn test_erc721_mintable_mint_to_zero() {
    let (_world, mut state) = STATE();
    state.erc721_mintable.mint(ZERO(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: token already minted',))]
fn test_erc721_mintable_already_minted() {
    let (_world, mut state) = STATE();
    state.erc721_mintable.mint(RECIPIENT(), TOKEN_ID);
    state.erc721_mintable.mint(RECIPIENT(), TOKEN_ID);
}

#[test]
fn test_erc721_burnable_burn() {
    let (_world, mut state) = STATE();
    state.erc721_mintable.mint(RECIPIENT(), TOKEN_ID);
    state.erc721_burnable.burn(TOKEN_ID);
    assert(state.balance_of(RECIPIENT()) == 0, 'invalid balance_of');
}

