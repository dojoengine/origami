use integer::BoundedInt;
use starknet::ContractAddress;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ADMIN, ZERO, OWNER, OTHER, SPENDER, RECIPIENT, VALUE, SUPPLY};

use token::tests::utils;

use token::components::token::erc20::erc20_allowance::{erc_20_allowance_model, ERC20AllowanceModel,};
use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent::{
    Approval, ERC20AllowanceImpl, InternalImpl as ERC20AllowanceInternalImpl
};
use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::ERC20BalanceComponent::{
    Transfer, ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};
use token::components::tests::mocks::erc20::erc20_balance_mock::{ERC20BalanceMock, IERC20BalanceMockDispatcher,IERC20BalanceMockDispatcherTrait };
use token::components::tests::mocks::erc20::erc20_balance_mock::ERC20BalanceMock::world_dispatcherContractMemberStateTrait;

use token::components::tests::token::erc20::test_erc20_allowance::{
    assert_event_approval, assert_only_event_approval
};

use debug::PrintTrait;
//
// events helpers
//

fn assert_eventtransfer_internal(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    let event = utils::pop_log::<Transfer>(emitter).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.value == value, 'Invalid `value`');
}

fn assert_only_eventtransfer_internal(
    emitter: ContractAddress, from: ContractAddress, to: ContractAddress, value: u256
) {
    assert_eventtransfer_internal(emitter, from, to, value);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, ERC20BalanceMock::ContractState) {
    let world = spawn_test_world(array![erc_20_balance_model::TEST_CLASS_HASH,erc_20_allowance_model::TEST_CLASS_HASH,]);

    let mut state = ERC20BalanceMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

#[test]
#[available_gas(100000000)]
fn test_erc20_balance_initialize() {
    let (world, mut state) = STATE();

    assert(state.erc20_balance.balance_of(ADMIN()) == 0, 'Should be 0');
    assert(state.erc20_balance.balance_of(OWNER()) == 0, 'Should be 0');
    assert(state.erc20_balance.balance_of(OTHER()) == 0, 'Should be 0');
}

//
// update_balance
//

#[test]
#[available_gas(100000000)]
fn test_erc20_balance_update_balance() {
    let (world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 0, 420);
    assert(state.erc20_balance.balance_of(ZERO()) == 420, 'Should be 420');

    state.erc20_balance.update_balance(ZERO(), 0, 1000);
    assert(state.erc20_balance.balance_of(ZERO()) == 1420, 'Should be 1420');

    state.erc20_balance.update_balance(ZERO(), 420, 0);
    assert(state.erc20_balance.balance_of(ZERO()) == 1000, 'Should be 1000');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_balance_update_balance_sub_overflow() {
    let (world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 1, 0);
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_add Overflow',))]
fn test_erc20_balance_update_balance_add_overflow() {
    let (world, mut state) = STATE();

    state.erc20_balance.update_balance(ZERO(), 0, BoundedInt::max());
    state.erc20_balance.update_balance(ZERO(), 0, 1);
}

//
//  transfer_internal
//

#[test]
#[available_gas(100000000)]
fn test_erc20_balance_transfer_internal() {
    let (world, mut state) = STATE();

    state.erc20_balance.update_balance(ADMIN(), 0, 420);
    state.erc20_balance.update_balance(OTHER(), 0, 1000);

    state.erc20_balance.transfer_internal(ADMIN(), OTHER(), 100);
    assert(state.erc20_balance.balance_of(ADMIN()) == 320, 'Should be 320');
    assert(state.erc20_balance.balance_of(OTHER()) == 1100, 'Should be 1100');
    assert_only_eventtransfer_internal(ZERO(), ADMIN(), OTHER(), 100);

    state.erc20_balance.transfer_internal(OTHER(), ADMIN(), 1000);
    assert(state.erc20_balance.balance_of(ADMIN()) == 1320, 'Should be 1320');
    assert(state.erc20_balance.balance_of(OTHER()) == 100, 'Should be 100');
    assert_only_eventtransfer_internal(ZERO(), OTHER(), ADMIN(), 1000);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test_erc20_balance_transfer_internal_from_zero() {
    let (world, mut state) = STATE();

    state.erc20_balance.transfer_internal(ZERO(), ADMIN(), 420);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_erc20_balance_transfer_internal_to_zero() {
    let (world, mut state) = STATE();

    state.erc20_balance.transfer_internal(ADMIN(), ZERO(), 420);
}



//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC20BalanceMockDispatcher) {
    let world = spawn_test_world(
        array![
            erc_20_allowance_model::TEST_CLASS_HASH,
            erc_20_balance_model::TEST_CLASS_HASH,
        ]
    );

    // deploy contract
    let mut erc20_balance_mock_dispatcher = IERC20BalanceMockDispatcher {
        contract_address: world
            .deploy_contract('salt', ERC20BalanceMock::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth
    world.grant_writer('ERC20AllowanceModel', erc20_balance_mock_dispatcher.contract_address);
    world.grant_writer('ERC20BalanceModel', erc20_balance_mock_dispatcher.contract_address);

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
#[available_gas(40000000)]
fn testtransfer_internal_from() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::drop_all_events(erc20_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    assert(erc20_balance_mock.transfer_from(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(erc20_balance_mock.contract_address, OWNER(), SPENDER(), 0);
    assert_only_eventtransfer_internal(erc20_balance_mock.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20AllowanceModel 
    utils::drop_event(world.contract_address);
    assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_eventtransfer_internal(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(erc20_balance_mock.balance_of(RECIPIENT()) == VALUE, 'Should eq amount');
    assert(erc20_balance_mock.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(erc20_balance_mock.allowance(OWNER(), SPENDER()) == 0, 'Should eq 0');
    // assert(erc20_balance_mock.total_supply() == SUPPLY, 'Total supply should not change');
}

#[test]
#[available_gas(25000000)]
fn testtransfer_internal_from_doesnt_consume_infinite_allowance() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), BoundedInt::max());

    utils::drop_all_events(erc20_balance_mock.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    erc20_balance_mock.transfer_from(OWNER(), RECIPIENT(), VALUE);

    assert_only_eventtransfer_internal(erc20_balance_mock.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_eventtransfer_internal(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(
        erc20_balance_mock.allowance(OWNER(), SPENDER()) == BoundedInt::max(),
        'Allowance should not change'
    );
}


#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow','ENTRYPOINT_FAILED'))]
fn testtransfer_internal_from_greater_than_allowance() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::impersonate(SPENDER());
    let allowance_plus_one = VALUE + 1;

    erc20_balance_mock.transfer_from(OWNER(), RECIPIENT(), allowance_plus_one);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: transfer to 0','ENTRYPOINT_FAILED'))]
fn testtransfer_internal_from_to_zero_address() {
    let (world, mut erc20_balance_mock) = setup();

    utils::impersonate(OWNER());
    erc20_balance_mock.approve(SPENDER(), VALUE);

    utils::impersonate(SPENDER());
    erc20_balance_mock.transfer_from(OWNER(), ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow','ENTRYPOINT_FAILED'))]
fn testtransfer_internal_from_from_zero_address() {
     let (world, mut erc20_balance_mock) = setup();

    erc20_balance_mock.transfer_from(ZERO(), RECIPIENT(), VALUE);
}