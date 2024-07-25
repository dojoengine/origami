use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use origami_token::tests::constants::{
    ZERO, OWNER, SPENDER, RECIPIENT, TOKEN_ID, TOKEN_ID_2, TOKEN_ID_3
};

use origami_token::tests::utils;

use origami_token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel, erc_721_operator_approval_model,
    ERC721OperatorApprovalModel
};
use origami_token::components::token::erc721::erc721_approval::erc721_approval_component;
use origami_token::components::token::erc721::erc721_approval::erc721_approval_component::{
    Approval, ApprovalForAll, ERC721ApprovalImpl, InternalImpl as ERC721ApprovalInternalImpl
};

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

use origami_token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;
use origami_token::components::token::erc721::erc721_burnable::erc721_burnable_component::InternalImpl as ERC721BurnableInternalImpl;

use origami_token::presets::erc721::enumerable_mintable_burnable::{
    ERC721EnumMintBurn, IERC721EnumMintBurnPresetDispatcher,
    IERC721EnumMintBurnPresetDispatcherTrait
};

use origami_token::components::token::erc721::erc721_enumerable::{
    erc_721_enumerable_index_model, erc_721_enumerable_owner_index_model,
    erc_721_enumerable_token_model, erc_721_enumerable_owner_token_model,
    erc_721_enumerable_total_model,
};

use origami_token::components::token::erc721::erc721_owner::erc_721_owner_model;

use origami_token::components::tests::token::erc721::test_erc721_approval::{
    assert_event_approval, assert_only_event_approval
};
use origami_token::components::tests::token::erc721::test_erc721_balance::{
    assert_event_transfer, assert_only_event_transfer
};

use origami_token::components::security::initializable::initializable_model;

//
// Setup
//

fn setup_uninitialized() -> (IWorldDispatcher, IERC721EnumMintBurnPresetDispatcher) {
    let world = spawn_test_world(
        "origami_token",
        array![
            erc_721_token_approval_model::TEST_CLASS_HASH,
            erc_721_balance_model::TEST_CLASS_HASH,
            erc_721_meta_model::TEST_CLASS_HASH,
            erc_721_enumerable_index_model::TEST_CLASS_HASH,
            erc_721_enumerable_owner_index_model::TEST_CLASS_HASH,
            erc_721_enumerable_token_model::TEST_CLASS_HASH,
            erc_721_enumerable_owner_token_model::TEST_CLASS_HASH,
            erc_721_enumerable_total_model::TEST_CLASS_HASH,
            erc_721_owner_model::TEST_CLASS_HASH,
            initializable_model::TEST_CLASS_HASH,
        ]
    );

    // deploy contract
    let mut erc721_enum_mint_burn_dispatcher = IERC721EnumMintBurnPresetDispatcher {
        contract_address: world
            .deploy_contract(
                'salt', ERC721EnumMintBurn::TEST_CLASS_HASH.try_into().unwrap(), array![].span()
            )
    };

    world.grant_owner(starknet::get_contract_address(), dojo::utils::hash(@"origami_token"));
    world.grant_owner(OWNER(), dojo::utils::hash(@"origami_token"));
    world.grant_owner(SPENDER(), dojo::utils::hash(@"origami_token"));

    (world, erc721_enum_mint_burn_dispatcher)
}

fn setup() -> (IWorldDispatcher, IERC721EnumMintBurnPresetDispatcher) {
    let (world, mut enum_mint_burn) = setup_uninitialized();

    // initialize contracts
    enum_mint_burn
        .initializer("NAME", "SYMBOL", "URI", OWNER(), array![TOKEN_ID, TOKEN_ID_2].span());

    // drop all events
    utils::drop_all_events(enum_mint_burn.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, enum_mint_burn)
}

//
// initializer
//

#[test]
fn test_initializer() {
    let (_world, mut enum_mint_burn) = setup();

    assert(enum_mint_burn.balance_of(OWNER()) == 2, 'Should eq 2');
    assert(enum_mint_burn.name() == "NAME", 'Name should be NAME');
    assert(enum_mint_burn.symbol() == "SYMBOL", 'Symbol should be SYMBOL');
    assert(enum_mint_burn.token_uri(TOKEN_ID) == "URI21", 'Uri should be URI21');
}

#[test]
#[should_panic(expected: ('ERC721: caller is not owner', 'ENTRYPOINT_FAILED'))]
fn test_initialize_not_world_owner() {
    let (_world, mut enum_mint_burn) = setup_uninitialized();

    utils::impersonate(OWNER());

    // initialize contracts
    enum_mint_burn
        .initializer("NAME", "SYMBOL", "URI", OWNER(), array![TOKEN_ID, TOKEN_ID_2].span());
}

#[test]
#[should_panic(expected: ('Initializable: is initialized', 'ENTRYPOINT_FAILED'))]
fn test_initialize_multiple() {
    let (_world, mut enum_mint_burn) = setup();

    enum_mint_burn.initializer("NAME", "SYMBOL", "URI", OWNER(), array![TOKEN_ID_3].span());
}

//
// approve
//

#[test]
fn test_approve() {
    let (world, mut enum_mint_burn) = setup();

    utils::impersonate(OWNER());

    enum_mint_burn.approve(SPENDER(), TOKEN_ID);
    assert(enum_mint_burn.get_approved(TOKEN_ID) == SPENDER(), 'Spender not approved correctly');

    // drop StoreSetRecord ERC721TokenApprovalModel
    utils::drop_event(world.contract_address);

    assert_only_event_approval(enum_mint_burn.contract_address, OWNER(), SPENDER(), TOKEN_ID);
    assert_only_event_approval(world.contract_address, OWNER(), SPENDER(), TOKEN_ID);
}

//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let (world, mut enum_mint_burn) = setup();

    utils::impersonate(OWNER());
    enum_mint_burn.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(enum_mint_burn.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(enum_mint_burn.contract_address);

    utils::impersonate(SPENDER());
    enum_mint_burn.transfer_from(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(enum_mint_burn.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    assert(enum_mint_burn.balance_of(RECIPIENT()) == 1, 'Should eq 1');
    assert(enum_mint_burn.balance_of(OWNER()) == 1, 'Should eq 1');
    assert(enum_mint_burn.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
    assert(enum_mint_burn.total_supply() == 2, 'Should eq 2');
    assert(enum_mint_burn.token_by_index(0) == TOKEN_ID, 'Should eq TOKEN_ID');
    assert(
        enum_mint_burn.token_of_owner_by_index(RECIPIENT(), 0) == TOKEN_ID, 'Should eq TOKEN_ID'
    );
}

//
// mint
//

#[test]
fn test_mint() {
    let (_world, mut enum_mint_burn) = setup();

    enum_mint_burn.mint(RECIPIENT(), 3);
    assert(enum_mint_burn.balance_of(RECIPIENT()) == 1, 'invalid balance_of');
    assert(enum_mint_burn.total_supply() == 3, 'invalid total_supply');
    assert(enum_mint_burn.token_by_index(2) == 3, 'invalid token_by_index');
    assert(
        enum_mint_burn.token_of_owner_by_index(RECIPIENT(), 0) == 3,
        'invalid token_of_owner_by_index'
    );
}

//
// burn
//

#[test]
fn test_burn() {
    let (_world, mut enum_mint_burn) = setup();

    enum_mint_burn.burn(TOKEN_ID_2);
    assert(enum_mint_burn.balance_of(OWNER()) == 1, 'invalid balance_of');
    assert(enum_mint_burn.total_supply() == 1, 'invalid total_supply');
    assert(enum_mint_burn.token_by_index(0) == TOKEN_ID, 'invalid token_by_index');
    assert(
        enum_mint_burn.token_of_owner_by_index(OWNER(), 0) == TOKEN_ID,
        'invalid token_of_owner_by_index'
    );
}

