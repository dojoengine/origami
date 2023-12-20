use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ADMIN, ZERO, OWNER, OTHER};

use token::tests::utils;

use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::ERC20BalanceComponent::{
    ERC20BalanceImpl, InternalImpl
};
use token::components::tests::mocks::erc20::erc20_balance_mock::ERC20BalanceMock;
use token::components::tests::mocks::erc20::erc20_balance_mock::ERC20BalanceMock::world_dispatcherContractMemberStateTrait;



fn STATE() -> (IWorldDispatcher, ERC20BalanceMock::ContractState) {
    let world = spawn_test_world(array![erc_20_balance_model::TEST_CLASS_HASH,]);

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

#[test]
#[available_gas(100000000)]
fn test_erc20_balance__update_balance() {
    let (world, mut state) = STATE();

    state.erc20_balance._update_balance(ZERO(), 0, 420);
    assert(state.erc20_balance.balance_of(ZERO()) == 420, 'Should be 420');

    state.erc20_balance._update_balance(ZERO(), 0, 1000);
    assert(state.erc20_balance.balance_of(ZERO()) == 1420, 'Should be 1420');

    state.erc20_balance._update_balance(ZERO(), 420, 0);
    assert(state.erc20_balance.balance_of(ZERO()) == 1000, 'Should be 1000');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_balance__update_balance_sub_overflow() {
    let (world, mut state) = STATE();

    state.erc20_balance._update_balance(ZERO(), 1, 0);
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_add Overflow',))]
fn test_erc20_balance__update_balance_add_overflow() {
    let (world, mut state) = STATE();

    state.erc20_balance._update_balance(ZERO(), 0, BoundedInt::max());
    state.erc20_balance._update_balance(ZERO(), 0, 1);
}


#[test]
#[available_gas(100000000)]
fn test_erc20_balance__transfer() {
    let (world, mut state) = STATE();

    state.erc20_balance._update_balance(ADMIN(), 0, 420);
    state.erc20_balance._update_balance(OTHER(), 0, 1000);

    state.erc20_balance._transfer(ADMIN(), OTHER(), 100);
    assert(state.erc20_balance.balance_of(ADMIN()) == 320, 'Should be 320');
    assert(state.erc20_balance.balance_of(OTHER()) == 1100, 'Should be 1100');

    state.erc20_balance._transfer(OTHER(), ADMIN(), 1000);
    assert(state.erc20_balance.balance_of(ADMIN()) == 1320, 'Should be 1320');
    assert(state.erc20_balance.balance_of(OTHER()) == 100, 'Should be 100');
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test_erc20_balance__transfer_from_zero() {
    let (world, mut state) = STATE();

    state.erc20_balance._transfer(ZERO(), ADMIN(), 420);
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_erc20_balance__transfer_to_zero() {
    let (world, mut state) = STATE();

    state.erc20_balance._transfer(ADMIN(), ZERO(), 420);
}
