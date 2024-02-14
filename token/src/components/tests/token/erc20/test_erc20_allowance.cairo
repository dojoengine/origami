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
use token::components::token::erc20::erc20_allowance::erc20_allowance_component;
use token::components::token::erc20::erc20_allowance::erc20_allowance_component::{
    Approval, ERC20AllowanceImpl, InternalImpl
};
use token::components::tests::mocks::erc20::erc20_allowance_mock::erc20_allowance_mock;
use token::components::tests::mocks::erc20::erc20_allowance_mock::erc20_allowance_mock::world_dispatcherContractMemberStateTrait;

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

fn STATE() -> (IWorldDispatcher, erc20_allowance_mock::ContractState) {
    let world = spawn_test_world(array![erc_20_allowance_model::TEST_CLASS_HASH,]);

    let mut state = erc20_allowance_mock::contract_state_for_testing();
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
//  spend_allowance 
//

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance_spend_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), SUPPLY);
    utils::drop_event(ZERO());

    state.erc20_allowance.spend_allowance(OWNER(), SPENDER(), VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == SUPPLY - VALUE,
        'should be SUPPLY-VALUE'
    );
    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), SUPPLY - VALUE);
}
