use integer::BoundedInt;
use starknet::ContractAddress;
use starknet::testing;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use origami_token::tests::constants::{ADMIN, ZERO, OWNER, OTHER, SPENDER, RECIPIENT, TOKEN_ID};

use origami_token::tests::utils;

use origami_token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel,
};
use origami_token::components::token::erc721::erc721_approval::erc721_approval_component::{
    Approval, ERC721ApprovalImpl, InternalImpl as ERC721ApprovalInternalImpl
};
use origami_token::components::token::erc721::erc721_balance::{erc_721_balance_model, ERC721BalanceModel,};
use origami_token::components::token::erc721::erc721_balance::erc721_balance_component::{
    Transfer, ERC721BalanceImpl, ERC721BalanceCamelImpl, InternalImpl as ERC721BalanceInternalImpl
};
use origami_token::components::token::erc721::erc721_owner::{erc_721_owner_model, ERC721OwnerModel,};
use origami_token::components::token::erc721::erc721_owner::erc721_owner_component::{
    ERC721OwnerImpl, ERC721OwnerCamelImpl, InternalImpl as ERC721OwnerInternalImpl
};
use origami_token::components::tests::mocks::erc721::erc721_balance_mock::{
    erc721_balance_mock, IERC721BalanceMockDispatcher, IERC721BalanceMockDispatcherTrait
};

use origami_token::components::token::erc721::erc721_mintable::erc721_mintable_component::InternalImpl as ERC721MintableInternalImpl;
use starknet::storage::{StorageMemberAccessTrait};

use origami_token::components::tests::token::erc721::test_erc721_approval::{
    assert_event_approval, assert_only_event_approval
};

use origami_token::components::introspection::src5::{src_5_model, SRC5Model, ISRC5, ISRC5_ID};
use origami_token::components::introspection::src5::src5_component::{InternalImpl as SRC5InternalImpl};
use origami_token::components::tests::mocks::erc721::erc721_receiver_mock::{
    erc721_receiver_mock, IERC721ReceiverMockDispatcher, IERC721ReceiverMockDispatcherTrait
};

use debug::PrintTrait;
//
// events helpers
//

fn assert_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, token_id: u256
) {
    let event = utils::pop_log::<Transfer>(emitter).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.token_id == token_id, 'Invalid `token_id`');
}

fn assert_only_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, token_id: u256
) {
    assert_event_transfer(emitter, from, to, token_id);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, erc721_balance_mock::ContractState) {
    let world = spawn_test_world(
        array![
            erc_721_balance_model::TEST_CLASS_HASH, erc_721_token_approval_model::TEST_CLASS_HASH,
        ]
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


//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC721BalanceMockDispatcher, IERC721ReceiverMockDispatcher) {
    let world = spawn_test_world(
        array![
            erc_721_token_approval_model::TEST_CLASS_HASH,
            erc_721_balance_model::TEST_CLASS_HASH,
            src_5_model::TEST_CLASS_HASH
        ]
    );

    // deploy balance mock contract
    let mut erc721_balance_mock_dispatcher = IERC721BalanceMockDispatcher {
        contract_address: world
            .deploy_contract(
                'salt', erc721_balance_mock::TEST_CLASS_HASH.try_into().unwrap(), array![].span()
            )
    };

    // setup balance auth
    world
        .grant_writer(
            selector!("ERC721TokenApprovalModel"), erc721_balance_mock_dispatcher.contract_address
        );
    world
        .grant_writer(
            selector!("ERC721BalanceModel"), erc721_balance_mock_dispatcher.contract_address
        );
    world
        .grant_writer(
            selector!("ERC721OwnerModel"), erc721_balance_mock_dispatcher.contract_address
        );

    // initialize balance contracts
    erc721_balance_mock_dispatcher.initializer(OWNER(), TOKEN_ID);

    // drop balance events
    utils::drop_all_events(erc721_balance_mock_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    // deploy erc721 receiver contract
    let mut erc721_receiver_mock_dispatcher = IERC721ReceiverMockDispatcher {
        contract_address: world
            .deploy_contract(
                'salt2', erc721_receiver_mock::TEST_CLASS_HASH.try_into().unwrap(), array![].span()
            )
    };

    // setup erc721 receiver auth
    world.grant_writer(selector!("SRC5Model"), erc721_receiver_mock_dispatcher.contract_address);

    // register balance contracts
    erc721_receiver_mock_dispatcher.initializer();

    (world, erc721_balance_mock_dispatcher, erc721_receiver_mock_dispatcher)
}


//
// transfer_from  (need deployed contracts)
//

#[test]
fn test_transfer_from() {
    let (world, mut erc721_balance_mock, _) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transfer_from(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(
        erc721_balance_mock.contract_address, OWNER(), RECIPIENT(), TOKEN_ID
    );

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
    let (_world, mut erc721_balance_mock, _) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transfer_from(OWNER(), ZERO(), TOKEN_ID);
}

#[test]
fn test_safe_transfer_from() {
    let (world, mut erc721_balance_mock, mut erc721_receiver_mock) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    let DATA: Span<felt252> = array!['DATA'].span();
    erc721_balance_mock
        .safe_transfer_from(OWNER(), erc721_receiver_mock.contract_address, TOKEN_ID, DATA);

    assert_only_event_transfer(
        erc721_balance_mock.contract_address,
        OWNER(),
        erc721_receiver_mock.contract_address,
        TOKEN_ID
    );

    // // drop StoreSetRecord ERC721TokenApprovalModel
    utils::drop_event(world.contract_address);
    // // drop StoreSetRecord ERC721BalanceModel x3 - incl mint
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(
        world.contract_address, OWNER(), erc721_receiver_mock.contract_address, TOKEN_ID
    );

    assert(
        erc721_balance_mock.balance_of(erc721_receiver_mock.contract_address) == 1, 'Should eq 1'
    );
    assert(erc721_balance_mock.balance_of(OWNER()) == 0, 'Should eq 0');
    assert(erc721_balance_mock.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
}

//
// transferFrom
//

#[test]
fn test_transferFrom() {
    let (world, mut erc721_balance_mock, _) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    erc721_balance_mock.transferFrom(OWNER(), RECIPIENT(), TOKEN_ID);

    assert_only_event_transfer(
        erc721_balance_mock.contract_address, OWNER(), RECIPIENT(), TOKEN_ID
    );

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
fn test_safeTransferFrom() {
    let (world, mut erc721_balance_mock, mut erc721_receiver_mock) = setup();

    utils::impersonate(OWNER());
    erc721_balance_mock.approve(SPENDER(), TOKEN_ID);

    utils::drop_all_events(erc721_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);
    utils::assert_no_events_left(erc721_balance_mock.contract_address);

    utils::impersonate(SPENDER());
    let DATA: Span<felt252> = array!['DATA'].span();
    erc721_balance_mock
        .safeTransferFrom(OWNER(), erc721_receiver_mock.contract_address, TOKEN_ID, DATA);

    assert_only_event_transfer(
        erc721_balance_mock.contract_address,
        OWNER(),
        erc721_receiver_mock.contract_address,
        TOKEN_ID
    );

    // // drop StoreSetRecord ERC721TokenApprovalModel
    utils::drop_event(world.contract_address);
    // // drop StoreSetRecord ERC721BalanceModel x3 - incl mint
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(
        world.contract_address, OWNER(), erc721_receiver_mock.contract_address, TOKEN_ID
    );

    assert(
        erc721_balance_mock.balance_of(erc721_receiver_mock.contract_address) == 1, 'Should eq 1'
    );
    assert(erc721_balance_mock.balance_of(OWNER()) == 0, 'Should eq 0');
    assert(erc721_balance_mock.get_approved(TOKEN_ID) == ZERO(), 'Should eq 0');
}

