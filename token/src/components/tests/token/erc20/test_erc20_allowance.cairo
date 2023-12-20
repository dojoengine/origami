use token::components::token::erc20::erc20_allowance::IERC20Allowance;
use starknet::testing;
use starknet::ContractAddress;
use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, VALUE, SUPPLY};

use token::components::token::erc20::erc20_allowance::{
    erc_20_allowance_model, ERC20AllowanceModel,
};
use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent::{
    ERC20AllowanceImpl, InternalImpl
};
use token::components::tests::mocks::erc20::erc20_allowance_mock::ERC20AllowanceMock;
use token::components::tests::mocks::erc20::erc20_allowance_mock::ERC20AllowanceMock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, ERC20AllowanceMock::ContractState) {
    let world = spawn_test_world(array![erc_20_allowance_model::TEST_CLASS_HASH,]);

    let mut state = ERC20AllowanceMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

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
//todo test event
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

    state.erc20_allowance.update_allowance(OWNER(), SPENDER(), 0, SUPPLY);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == VALUE + SUPPLY,
        'should be VALUE+SUPPLY'
    );

    state.erc20_allowance.update_allowance(OWNER(), SPENDER(), VALUE, 0);
    assert(state.erc20_allowance.allowance(OWNER(), SPENDER()) == SUPPLY, 'should be SUPPLY');
//todo test event
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

    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == SUPPLY - VALUE,
        'should be SUPPLY-VALUE'
    );
//todo test event
}

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance__spend_allowance_with_max_allowance() {
    let (world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc20_allowance.approve(SPENDER(), BoundedInt::max());

    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), VALUE);
    assert(
        state.erc20_allowance.allowance(OWNER(), SPENDER()) == BoundedInt::max(),
        'should be BoundedInt::max()'
    );
}
