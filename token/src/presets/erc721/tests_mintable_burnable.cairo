use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, NAME, SYMBOL, URI, TOKEN_ID, TOKEN_ID_2, VALUE};

use token::tests::utils;

use token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel, erc_721_operator_approval_model,
    ERC721OperatorApprovalModel
};
use token::components::token::erc721::erc721_approval::erc721_approval_component;
use token::components::token::erc721::erc721_approval::erc721_approval_component::{
    Approval, ApprovalForAll, ERC721ApprovalImpl, InternalImpl as ERC721ApprovalInternalImpl
};

use token::components::token::erc721::erc721_metadata::{erc_721_meta_model, ERC721MetaModel,};
use token::components::token::erc721::erc721_metadata::erc721_metadata_component::{
    ERC721MetadataImpl, ERC721MetadataCamelImpl, InternalImpl as ERC721MetadataInternalImpl
};

use token::components::token::erc721::erc721_balance::{erc_721_balance_model, ERC721BalanceModel,};
use token::components::token::erc721::erc721_balance::erc721_balance_component::{
    ERC721BalanceImpl, InternalImpl as ERC721BalanceInternalImpl
};

use token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;
use token::components::token::erc721::erc721_burnable::erc721_burnable_component::InternalImpl as ERC721BurnableInternalImpl;

use token::presets::erc721::mintable_burnable::{
    ERC721MintableBurnable, IERC721MintableBurnablePresetDispatcher, IERC721MintableBurnablePresetDispatcherTrait
};
use token::presets::erc721::mintable_burnable::ERC721MintableBurnable::{ERC721InitializerImpl};
use token::presets::erc721::mintable_burnable::ERC721MintableBurnable::world_dispatcherContractMemberStateTrait;

use token::components::tests::token::erc20::test_erc20_allowance::{
    assert_event_approval, assert_only_event_approval
};
use token::components::tests::token::erc20::test_erc20_balance::{
    assert_event_transfer, assert_only_event_transfer
};


//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC721MintableBurnablePresetDispatcher) {
    let world = spawn_test_world(
        array![
            erc_721_token_approval_model::TEST_CLASS_HASH, erc_721_balance_model::TEST_CLASS_HASH, erc_721_meta_model::TEST_CLASS_HASH,
        ]
    );

    // deploy contract
    let mut erc721_mintable_burnable_dispatcher = IERC721MintableBurnablePresetDispatcher {
        contract_address: world
            .deploy_contract('salt', ERC721MintableBurnable::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth
    world.grant_writer('ERC721TokenApprovalModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721BalanceModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721MetadataModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721OwnerModel', erc721_mintable_burnable_dispatcher.contract_address);

    // initialize contracts
    // let tokens = array![TOKEN_ID, TOKEN_ID_2].span()
    erc721_mintable_burnable_dispatcher.initializer(NAME, SYMBOL, URI, OWNER(), array![TOKEN_ID, TOKEN_ID_2].span());

    // drop all events
    utils::drop_all_events(erc721_mintable_burnable_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, erc721_mintable_burnable_dispatcher)
}

//
// initializer 
//

#[test]
fn test_initializer() {
    let (_world, mut erc721_mintable_burnable) = setup();

    assert(erc721_mintable_burnable.balance_of(OWNER()) == 2, 'Should eq 2');
    assert(erc721_mintable_burnable.name() == NAME, 'Name should be NAME');
    assert(erc721_mintable_burnable.symbol() == SYMBOL, 'Symbol should be SYMBOL');
    assert(erc721_mintable_burnable.token_uri(TOKEN_ID) == URI, 'Uri should be URI');
}

//
// approve
//

#[test]
fn test_approve() {
    let (world, mut mintable_burnable) = setup();

    utils::impersonate(OWNER());

    mintable_burnable.approve(SPENDER(), TOKEN_ID);
    assert(
        mintable_burnable.get_approved(TOKEN_ID) == SPENDER(), 'Spender not approved correctly'
    );

    // drop StoreSetRecord ERC721TokenApprovalModel
    utils::drop_event(world.contract_address);

    assert_only_event_approval(mintable_burnable.contract_address, OWNER(), SPENDER(), TOKEN_ID);
    assert_only_event_approval(world.contract_address, OWNER(), SPENDER(), TOKEN_ID);
}

//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let (world, mut mintable_burnable) = setup();

    utils::impersonate(OWNER());

    mintable_burnable.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(mintable_burnable.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    mintable_burnable.transfer_from(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(mintable_burnable.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    // drop StoreSetRecord ERC721TokenApprovalModel
    utils::drop_event(world.contract_address);
    // assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC721BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    assert(mintable_burnable.balance_of(RECIPIENT()) == 1, 'Should eq 1');
    assert(mintable_burnable.balance_of(OWNER()) == 2 - 1, 'Should eq 2 - 1');
    assert(mintable_burnable.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
}

//
// mint
//

#[test]
fn test_mint() {
    let (world, mut mintable_burnable) = setup();

    mintable_burnable.mint(RECIPIENT(), 2);
    assert(mintable_burnable.balance_of(RECIPIENT()) == 1, 'invalid balance_of');
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), 2);
}


//
// burn
//

#[test]
fn test_burn() {
    let (world, mut mintable_burnable) = setup();

    mintable_burnable.burn(TOKEN_ID);
    assert(mintable_burnable.balance_of(OWNER()) == 1, 'invalid balance_of');
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), ZERO(), TOKEN_ID);
}

