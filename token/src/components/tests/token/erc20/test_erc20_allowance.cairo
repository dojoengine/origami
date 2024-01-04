use token::components::token::erc20::erc20_allowance::IERC20Allowance;
use starknet::testing;
use starknet::ContractAddress;
use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, VALUE, SUPPLY};
use token::tests::utils;

use token::components::token::erc20::erc20_allowance::{
    erc_20_allowance_model, ERC20AllowanceModel,
};
use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent;
use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent::{
    Approval, ERC20AllowanceImpl, ERC20SafeAllowanceImpl, ERC20SafeAllowanceCamelImpl, InternalImpl
};
use token::components::tests::mocks::erc20::erc20_allowance_mock::ERC20AllowanceMock;
use token::components::tests::mocks::erc20::erc20_allowance_mock::ERC20AllowanceMock::world_dispatcherContractMemberStateTrait;

use debug::PrintTrait;

//
// events helpers
//

fn assert_event_approval(
    emitter: ContractAddress, owner: ContractAddress, spender: ContractAddress, value: u256
) {
    let event = utils::pop_log::<Approval>(emitter).unwrap();
    assert(event.owner == owner, 'Invalid `owner`');
    assert(event.spender == spender, 'Invalid `spender`');
    assert(event.value == value, 'Invalid `value`');
}

fn assert_only_event_approval(
    emitter: ContractAddress, owner: ContractAddress, spender: ContractAddress, value: u256
) {
    assert_event_approval(emitter, owner, spender, value);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, ERC20AllowanceMock::ContractState) {
    let world = spawn_test_world(array![erc_20_allowance_model::TEST_CLASS_HASH,]);

    let mut state = ERC20AllowanceMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

//
//  set_allowance (approve)
//

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance_approve() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), VALUE);
    assert(state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE, 'should be VALUE');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), VALUE);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_erc20_allowance_approve_from_zero() {
    let (world, mut state) = STATE();

    testing::set_caller_address(ZERO());
    state.erc20_allowance.approve(SPENDER(), VALUE);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_erc20_allowance_approve_to_zero() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(ZERO(), VALUE);
}


//
//  update_allowance (increase_allowance, decrease_allowance)
//

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance_update_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    state.erc20_allowance.update_allowance(OWNER(), SPENDER(), 0, SUPPLY);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE + SUPPLY,
        'should be VALUE+SUPPLY'
    );
    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), VALUE + SUPPLY);

    state.erc20_allowance.update_allowance(OWNER(), SPENDER(), VALUE, 0);
    assert(state.erc20_allowance.allowance(OWNER(), SPENDER()) == SUPPLY, 'should be SUPPLY');
    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), SUPPLY);
}


//
//  _spend_allowance 
//

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance__spend_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), SUPPLY);
    utils::drop_event(ZERO());

    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == SUPPLY - VALUE,
        'should be SUPPLY-VALUE'
    );
    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), SUPPLY - VALUE);
}

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance__spend_allowance_with_max_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), BoundedInt::max());
    utils::drop_event(ZERO());

    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == BoundedInt::max(),
        'should be BoundedInt::max()'
    );

    utils::assert_no_events_left(ZERO());
}


//
// increase_allowance & increaseAllowance
//

#[test]
#[available_gas(25000000)]
fn test_erc20_allowance_increase_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.erc20_allowance.increase_allowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), VALUE * 2);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE * 2, 'Should be amount * 2'
    );
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_erc20_allowance_increase_allowance_to_zero_address() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.increase_allowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_erc20_allowance_increase_allowance_from_zero_address() {
    let (world, mut state) = STATE();
    state.erc20_allowance.increase_allowance(SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
fn test_erc20_allowance_increaseAllowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.erc20_allowance.increaseAllowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), 2 * VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE * 2, 'Should be amount * 2'
    );
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_erc20_allowance_increaseAllowance_to_zero_address() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.increaseAllowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_erc20_allowance_increaseAllowance_from_zero_address() {
    let (world, mut state) = STATE();
    state.erc20_allowance.increaseAllowance(SPENDER(), VALUE);
}

//
// decrease_allowance & decreaseAllowance
//

#[test]
#[available_gas(25000000)]
fn test_erc20_allowance_decrease_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.erc20_allowance.decrease_allowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), 0);
    assert(state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE - VALUE, 'Should be 0');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_allowance_decrease_allowance_to_zero_address() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.decrease_allowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_allowance_decrease_allowance_from_zero_address() {
    let (world, mut state) = STATE();
    state.erc20_allowance.decrease_allowance(SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
fn test_erc20_allowance_decreaseAllowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.erc20_allowance.decreaseAllowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), 0);
    assert(state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE - VALUE, 'Should be 0');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_allowance_decreaseAllowance_to_zero_address() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.decreaseAllowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_allowance_decreaseAllowance_from_zero_address() {
    let (world, mut state) = STATE();
    state.erc20_allowance.decreaseAllowance(SPENDER(), VALUE);
}

