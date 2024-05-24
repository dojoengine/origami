use integer::BoundedInt;
use starknet::ContractAddress;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ADMIN, ZERO, OWNER, OTHER, SPENDER, RECIPIENT, VALUE, SUPPLY};

use token::tests::utils;

use token::components::token::erc20::erc20_allowance::{
    erc_20_allowance_model, ERC20AllowanceModel,
};
use token::components::token::erc20::erc20_allowance::erc20_allowance_component::{
    Approval, ERC20AllowanceImpl, InternalImpl as ERC20AllowanceInternalImpl
};
use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::erc20_balance_component::{
    Transfer, ERC20BalanceImpl, ERC20BalanceCamelImpl, InternalImpl as ERC20BalanceInternalImpl
};
use token::components::tests::mocks::erc20::erc20_balance_mock::{
    erc20_balance_mock, IERC20BalanceMockDispatcher, IERC20BalanceMockDispatcherTrait
};
use token::components::tests::mocks::erc20::erc20_balance_mock::erc20_balance_mock::world_dispatcherContractMemberStateTrait;

use token::components::tests::token::erc20::test_erc20_allowance::{
    assert_event_approval, assert_only_event_approval
};

use debug::PrintTrait;
//
// events helpers
//

fn assert_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    let event = utils::pop_log::<Transfer>(emitter).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.value == value, 'Invalid `value`');
}

fn assert_only_event_transfer(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    assert_event_transfer(emitter, from, to, value);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, erc20_balance_mock::ContractState) {
    let world = spawn_test_world(
        array![erc_20_balance_model::TEST_CLASS_HASH, erc_20_allowance_model::TEST_CLASS_HASH,]
    );

    let mut state = erc20_balance_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

#[test]
fn test_erc20_balance_initialize() {
    let (_world, mut state) = STATE();

    assert(state.erc20_balance.balance_of(ADMIN()) == 0, 'Should be 0');
    assert(state.erc20_balance.balance_of(OWNER()) == 0, 'Should be 0');
    assert(state.erc20_balance.balance_of(OTHER()) == 0, 'Should be 0');

    assert(state.erc20_balance.balanceOf(ADMIN()) == 0, 'Should be 0');
    assert(state.erc20_balance.balanceOf(OWNER()) == 0, 'Should be 0');
    assert(state.erc20_balance.balanceOf(OTHER()) == 0, 'Should be 0');
}

//
// update_balance
//

#[test]
fn test_erc20_balance_update_balance() {
    let (_world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 0, 420);
    assert(state.erc20_balance.balance_of(ZERO()) == 420, 'Should be 420');

    state.erc20_balance.update_balance(ZERO(), 0, 1000);
    assert(state.erc20_balance.balance_of(ZERO()) == 1420, 'Should be 1420');

    state.erc20_balance.update_balance(ZERO(), 420, 0);
    assert(state.erc20_balance.balance_of(ZERO()) == 1000, 'Should be 1000');
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_balance_update_balance_sub_overflow() {
    let (_world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 1, 0);
}

#[test]
#[should_panic(expected: ('u256_add Overflow',))]
fn test_erc20_balance_update_balance_add_overflow() {
    let (_world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 0, BoundedInt::max());
    state.erc20_balance.update_balance(ZERO(), 0, 1);
}

//
//  transfer_internal
//

#[test]
fn test_erc20_balance_transfer_internal() {
    let (_world, mut state) = STATE();

    state.erc20_balance.update_balance(ADMIN(), 0, 420);
    state.erc20_balance.update_balance(OTHER(), 0, 1000);

    state.erc20_balance.transfer_internal(ADMIN(), OTHER(), 100);
    assert(state.erc20_balance.balance_of(ADMIN()) == 320, 'Should be 320');
    assert(state.erc20_balance.balance_of(OTHER()) == 1100, 'Should be 1100');
    assert_only_event_transfer(ZERO(), ADMIN(), OTHER(), 100);

    state.erc20_balance.transfer_internal(OTHER(), ADMIN(), 1000);
    assert(state.erc20_balance.balance_of(ADMIN()) == 1320, 'Should be 1320');
    assert(state.erc20_balance.balance_of(OTHER()) == 100, 'Should be 100');
    assert_only_event_transfer(ZERO(), OTHER(), ADMIN(), 1000);
}

#[test]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test_erc20_balance_transfer_internal_from_zero() {
    let (_world, mut state) = STATE();

    state.erc20_balance.transfer_internal(ZERO(), ADMIN(), 420);
}

#[test]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_erc20_balance_transfer_internal_to_zero() {
    let (_world, mut state) = STATE();

    state.erc20_balance.transfer_internal(ADMIN(), ZERO(), 420);
}


//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC20BalanceMockDispatcher) {
    let world = spawn_test_world(
        array![erc_20_allowance_model::TEST_CLASS_HASH, erc_20_balance_model::TEST_CLASS_HASH,]
    );

    // deploy contract
    let mut erc20_balance_mock_dispatcher = IERC20BalanceMockDispatcher {
        contract_address: world
            .deploy_contract('salt', erc20_balance_mock::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth
    world
        .grant_writer(
            selector!("ERC20AllowanceModel"), erc20_balance_mock_dispatcher.contract_address
        );
    world
        .grant_writer(
            selector!("ERC20BalanceModel"), erc20_balance_mock_dispatcher.contract_address
        );

    // initialize contracts
    erc20_balance_mock_dispatcher.initializer(SUPPLY, OWNER());

    // drop all events
    utils::drop_all_events(erc20_balance_mock_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, erc20_balance_mock_dispatcher)
}


//
// transfer_from  (need deployed contracts)
//

#[test]
fn test_transfer_from() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::drop_all_events(erc20_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    assert(erc20_balance_mock.transfer_from(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(erc20_balance_mock.contract_address, OWNER(), SPENDER(), 0);
    assert_only_event_transfer(erc20_balance_mock.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20AllowanceModel 
    utils::drop_event(world.contract_address);
    assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(erc20_balance_mock.balance_of(RECIPIENT()) == VALUE, 'Should eq amount');
    assert(erc20_balance_mock.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(erc20_balance_mock.allowance(OWNER(), SPENDER()) == 0, 'Should eq 0');
// assert(erc20_balance_mock.total_supply() == SUPPLY, 'Total supply should not change');
}

#[test]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_greater_than_allowance() {
    let (_world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::impersonate(SPENDER());
    let allowance_plus_one = VALUE + 1;

    erc20_balance_mock.transfer_from(OWNER(), RECIPIENT(), allowance_plus_one);
}

#[test]
#[should_panic(expected: ('ERC20: transfer to 0', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_to_zero_address() {
    let (_world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::impersonate(SPENDER());
    erc20_balance_mock.transfer_from(OWNER(), ZERO(), VALUE);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED'))]
fn test_transfer_from_from_zero_address() {
    let (_world, mut erc20_balance_mock) = setup();

    erc20_balance_mock.transfer_from(ZERO(), RECIPIENT(), VALUE);
}


//
// transferFrom 
//

#[test]
fn test_transferFrom() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::drop_all_events(erc20_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    assert(erc20_balance_mock.transferFrom(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(erc20_balance_mock.contract_address, OWNER(), SPENDER(), 0);
    assert_only_event_transfer(erc20_balance_mock.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20AllowanceModel 
    utils::drop_event(world.contract_address);
    assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(erc20_balance_mock.balance_of(RECIPIENT()) == VALUE, 'Should eq amount');
    assert(erc20_balance_mock.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(erc20_balance_mock.allowance(OWNER(), SPENDER()) == 0, 'Should eq 0');
// assert(erc20_balance_mock.total_supply() == SUPPLY, 'Total supply should not change');
}
