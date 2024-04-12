use integer::BoundedInt;
use starknet::ContractAddress;
use starknet::testing;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ADMIN, ZERO, OWNER, OTHER, SPENDER, RECIPIENT, TOKEN_ID};

use token::tests::utils;

use token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel,
};
use token::components::token::erc721::erc721_approval::erc721_approval_component::{
    Approval, ERC721ApprovalImpl, InternalImpl as ERC721ApprovalInternalImpl
};
use token::components::token::erc721::erc721_balance::{erc_721_balance_model, ERC721BalanceModel,};
use token::components::token::erc721::erc721_balance::erc721_balance_component::{
    Transfer, ERC721BalanceImpl, ERC721BalanceCamelImpl, InternalImpl as ERC721BalanceInternalImpl
};
use token::components::token::erc721::erc721_owner::{erc_721_owner_model, ERC721OwnerModel,};
use token::components::token::erc721::erc721_owner::erc721_owner_component::{
    ERC721OwnerImpl, ERC721OwnerCamelImpl, InternalImpl as ERC721OwnerInternalImpl
};
use token::components::tests::mocks::erc721::erc721_balance_mock::{
    erc721_balance_mock, IERC721BalanceMockDispatcher, IERC721BalanceMockDispatcherTrait
};

use token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;
use token::components::tests::mocks::erc721::erc721_balance_mock::erc721_balance_mock::world_dispatcherContractMemberStateTrait;

use token::components::tests::token::erc721::test_erc721_approval::{
    assert_event_approval, assert_only_event_approval
};

use debug::PrintTrait;
//
// events helpers
//

fn assert_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, token_id: u128
) {
    let event = utils::pop_log::<Transfer>(emitter).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.token_id == token_id, 'Invalid `token_id`');
}

fn assert_only_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, token_id: u128
) {
    assert_event_transfer(emitter, from, to, token_id);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, erc721_balance_mock::ContractState) {
    let world = spawn_test_world(
        array![erc_721_balance_model::TEST_CLASS_HASH, erc_721_token_approval_model::TEST_CLASS_HASH,]
    );

    let mut state = erc721_balance_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

#[test]
fn test_erc721_balance_initialize() {
    let (_world, mut state) = STATE();

    assert(state.erc721_balance.balance_of(ADMIN()) == 0, 'Should be 0');
    assert(state.erc721_balance.balance_of(OWNER()) == 0, 'Should be 0');
    assert(state.erc721_balance.balance_of(OTHER()) == 0, 'Should be 0');

    assert(state.erc721_balance.balanceOf(ADMIN()) == 0, 'Should be 0');
    assert(state.erc721_balance.balanceOf(OWNER()) == 0, 'Should be 0');
    assert(state.erc721_balance.balanceOf(OTHER()) == 0, 'Should be 0');
}

//
// update_balance
//

#[test]
fn test_erc721_balance_set_balances() {
    let (_world, mut state) = STATE();

    state.erc721_balance.set_balance(OTHER(), 1);
    assert(state.erc721_balance.balance_of(OTHER()) == 1, 'Should be 1');
}

//
//  transfer_internal
//

#[test]
fn test_erc721_balance_transfer_internal() {
    let (_world, mut state) = STATE();

    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_balance.set_balance(OWNER(), 1);
    state.erc721_balance.set_balance(OTHER(), 0);

    state.erc721_balance.transfer_internal(OWNER(), OTHER(), TOKEN_ID);
    assert(state.erc721_balance.balance_of(OTHER()) == 1, 'Should be 1');
    assert_only_event_transfer(ZERO(), OWNER(), OTHER(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: invalid account',))]
fn test_erc721_balance_invalid_account() {
    let (_world, mut state) = STATE();

    state.erc721_balance.balance_of(ZERO());
}

#[test]
#[should_panic(expected: ('ERC721: invalid receiver',))]
fn test_erc721_balance_invalid_receiver() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_balance.transfer_from(OWNER(), ZERO(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: wrong sender',))]
fn test_erc721_balance_wrong_sender() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_balance.transfer_from(RECIPIENT(), OTHER(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: unauthorized caller',))]
fn test_erc721_balance_unauthorized() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(RECIPIENT());
    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_balance.transfer_from(RECIPIENT(), OTHER(), TOKEN_ID);
}


// //
// Setup
//

fn setup() -> (IWorldDispatcher, IERC721BalanceMockDispatcher) {
    let world = spawn_test_world(
        array![erc_721_token_approval_model::TEST_CLASS_HASH, erc_721_balance_model::TEST_CLASS_HASH,]
    );

    // deploy contract
    let mut erc721_balance_mock_dispatcher = IERC721BalanceMockDispatcher {
        contract_address: world
            .deploy_contract('salt', erc721_balance_mock::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth
    world.grant_writer('ERC721TokenApprovalModel', erc721_balance_mock_dispatcher.contract_address);
    world.grant_writer('ERC721BalanceModel', erc721_balance_mock_dispatcher.contract_address);
    world.grant_writer('ERC721OwnerModel', erc721_balance_mock_dispatcher.contract_address);

    // initialize contracts
    erc721_balance_mock_dispatcher.initializer(OWNER(), TOKEN_ID);

    // drop all events
    utils::drop_all_events(erc721_balance_mock_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, erc721_balance_mock_dispatcher)
}


//
// transfer_from  (need deployed contracts)
//

#[test]
fn test_transfer_from() {
    let (world, mut erc721_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transfer_from(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(erc721_balance_mock.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    // // drop StoreSetRecord ERC721TokenApprovalModel 
    utils::drop_event(world.contract_address);
    // // drop StoreSetRecord ERC721BalanceModel x3 - incl mint
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    assert(erc721_balance_mock.balance_of(RECIPIENT()) == 1, 'Should eq 1');
    assert(erc721_balance_mock.balance_of(OWNER()) == 0, 'Should eq 0');
    assert(erc721_balance_mock.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
}

#[test]
#[should_panic(expected: ('ERC721: invalid receiver', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_to_zero_address() {
    let (_world, mut erc721_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transfer_from(OWNER(), ZERO(), TOKEN_ID);
}

// //
// // transferFrom 
// //

#[test]
fn test_transferFrom() {
    let (world, mut erc721_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transferFrom(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(erc721_balance_mock.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    // // drop StoreSetRecord ERC721TokenApprovalModel 
    utils::drop_event(world.contract_address);
    // // drop StoreSetRecord ERC721BalanceModel x3 - incl mint
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), TOKEN_ID);

    assert(erc721_balance_mock.balance_of(RECIPIENT()) == 1, 'Should eq 1');
    assert(erc721_balance_mock.balance_of(OWNER()) == 0, 'Should eq 0');
    assert(erc721_balance_mock.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
// assert(erc721_balance_mock.total_supply() == SUPPLY, 'Total supply should not change');
}
