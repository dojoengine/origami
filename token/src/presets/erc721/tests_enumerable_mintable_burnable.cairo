use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, TOKEN_ID};

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


//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC20BridgeablePresetDispatcher) {
    let world = spawn_test_world(
        array![
            erc_721_token_approval_model::TEST_CLASS_HASH, erc_721_balance_model::TEST_CLASS_HASH, erc_721_metadata_model::TEST_CLASS_HASH,
        ]
    );

    // deploy contract
    let mut erc721_mintable_burnable_dispatcher = IERC721MintableBurnableDispatcher {
        contract_address: world
            .deploy_contract('salt', ERC721MintableBurnable::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth
    world.grant_writer('ERC721TokenApprovalModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721BalanceModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721MetadataModel', erc721_mintable_burnable_dispatcher.contract_address);
    world.grant_writer('ERC721OwnerModel', erc721_mintable_burnable_dispatcher.contract_address);

    // initialize contracts
    erc721_mintable_burnable_dispatcher.initializer(NAME, SYMBOL, URI, OWNER(), Span<TOKEN_ID, TOKEN_ID_2>);

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
    assert(erc721_mintable_burnable.token_uri() == URI, 'Uri should be URI');
}

//
// approve
//

#[test]
fn test_approve() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(OWNER());

    assert(erc20_bridgeable.approve(SPENDER(), VALUE), 'Should eq VALUE');
    assert(
        erc20_bridgeable.allowance(OWNER(), SPENDER()) == VALUE, 'Spender not approved correctly'
    );

    // drop StoreSetRecord ERC20AllowanceModel
    utils::drop_event(world.contract_address);

    assert_only_event_approval(erc20_bridgeable.contract_address, OWNER(), SPENDER(), VALUE);
    assert_only_event_approval(world.contract_address, OWNER(), SPENDER(), VALUE);
}

//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(OWNER());

    erc20_bridgeable.approve(SPENDER(), VALUE);

    utils::drop_all_events(erc20_bridgeable.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    assert(erc20_bridgeable.transfer_from(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(erc20_bridgeable.contract_address, OWNER(), SPENDER(), 0);
    assert_only_event_transfer(erc20_bridgeable.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20AllowanceModel 
    utils::drop_event(world.contract_address);
    assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(erc20_bridgeable.balance_of(RECIPIENT()) == VALUE, 'Should eq amount');
    assert(erc20_bridgeable.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(erc20_bridgeable.allowance(OWNER(), SPENDER()) == 0, 'Should eq 0');
    assert(erc20_bridgeable.total_supply() == SUPPLY, 'Total supply should not change');
}

//
// mint
//

#[test]
fn test_mint() {
}


//
// burn
//

#[test]
fn test_burn() {
}

