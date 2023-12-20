use starknet::ContractAddress;
use starknet::testing;
use zeroable::Zeroable;

use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{
    ZERO, OWNER, SPENDER, RECIPIENT, BRIDGE, NAME, SYMBOL, DECIMALS, SUPPLY, VALUE
};

use token::tests::utils;

use token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20::erc20_metadata::ERC20MetadataComponent::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::ERC20BalanceComponent::{
    Transfer, ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use token::components::token::erc20::erc20_allowance::{erc_20_allowance_model, ERC20AllowanceModel,};
use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent::{
    Approval, ERC20AllowanceImpl, InternalImpl as ERC20AllownceInternalImpl, ERC20SafeAllowanceImpl,
    ERC20SafeAllowanceCamelImpl
};

use token::components::token::erc20::erc20_bridgeable::{erc_20_bridgeable_model, ERC20BridgeableModel};
use token::components::token::erc20::erc20_bridgeable::ERC20BridgeableComponent::{ERC20BridgeableImpl};

use token::components::token::erc20::erc20_mintable::ERC20MintableComponent::InternalImpl as ERC20MintableInternalImpl;
use token::components::token::erc20::erc20_burnable::ERC20BurnableComponent::InternalImpl as ERC20BurnableInternalImpl;

use token::presets::erc20::bridgeable::ERC20Bridgeable;
use token::presets::erc20::bridgeable::ERC20Bridgeable::{ERC20Impl, ERC20InitializerImpl};
use token::presets::erc20::bridgeable::ERC20Bridgeable::world_dispatcherContractMemberStateTrait;

use debug::PrintTrait;

//
// Setup
//

fn STATE() -> (IWorldDispatcher, ERC20Bridgeable::ContractState) {
    let world = spawn_test_world(
        array![
            erc_20_allowance_model::TEST_CLASS_HASH,
            erc_20_balance_model::TEST_CLASS_HASH,
            erc_20_metadata_model::TEST_CLASS_HASH,
            erc_20_bridgeable_model::TEST_CLASS_HASH,
        ]
    );
    let mut state = ERC20Bridgeable::contract_state_for_testing();
    state.world_dispatcher.write(world);
    (world, state)
}

fn setup() -> ERC20Bridgeable::ContractState {
    let (world, mut state) = STATE();

    state.initializer(NAME, SYMBOL, SUPPLY, OWNER(), BRIDGE());

    utils::drop_event(ZERO());
    state
}

//
// initializer 
//

#[test]
#[available_gas(25000000)]
fn test_initializer() {
    let (world, mut state) = STATE();
    state.initializer(NAME, SYMBOL, SUPPLY, OWNER(), BRIDGE());

    assert_only_event_transfer(ZERO(), OWNER(), SUPPLY);

    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY, 'Should eq inital_supply');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Should eq inital_supply');
    assert(state.name() == NAME, 'Name should be NAME');
    assert(state.symbol() == SYMBOL, 'Symbol should be SYMBOL');
    assert(state.decimals() == DECIMALS, 'Decimals should be 18');
    assert(state.l2_bridge_address() == BRIDGE(), 'Decimals should be BRIDGE');
}

//
// Getters
//

#[test]
#[available_gas(25000000)]
fn test_total_supply() {
    let (world, mut state) = STATE();
    state.erc20_mintable._mint(OWNER(), SUPPLY);
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Should eq SUPPLY');
}

#[test]
#[available_gas(25000000)]
fn test_balance_of() {
    let (world, mut state) = STATE();
    state.erc20_mintable._mint(OWNER(), SUPPLY);
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY, 'Should eq SUPPLY');
}


#[test]
#[available_gas(25000000)]
fn test_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Should eq VALUE');
}

//
// approve & _approve
//

#[test]
#[available_gas(25000000)]
fn test_approve() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    assert(ERC20Impl::approve(ref state, SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(OWNER(), SPENDER(), VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Spender not approved correctly'
    );
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_approve_from_zero() {
    let mut state = setup();
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
fn test__approve() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve( SPENDER(), VALUE);

    assert_only_event_approval(OWNER(), SPENDER(), VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Spender not approved correctly'
    );
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test__approve_from_zero() {
    let mut state = setup();
    testing::set_caller_address(ZERO());
    state.erc20_allowance.approve(SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test__approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve(ZERO(), VALUE);
}

//
// transfer & _transfer
//

#[test]
#[available_gas(25000000)]
fn test_transfer() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    assert(ERC20Impl::transfer(ref state, RECIPIENT(), VALUE), 'Should return true');

    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);
    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Balance should eq VALUE');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq supply - VALUE');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Total supply should not change');
}

#[test]
#[available_gas(25000000)]
fn test__transfer() {
    let mut state = setup();

    state.erc20_balance._transfer(OWNER(), RECIPIENT(), VALUE);

    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);
    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Balance should eq amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq supply - amount');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Total supply should not change');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test__transfer_not_enough_balance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());

    let balance_plus_one = SUPPLY + 1;
    state.erc20_balance._transfer(OWNER(), RECIPIENT(), balance_plus_one);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test__transfer_from_zero() {
    let mut state = setup();
    state.erc20_balance._transfer(ZERO(), RECIPIENT(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test__transfer_to_zero() {
    let mut state = setup();
    state.erc20_balance._transfer(OWNER(), ZERO(), VALUE);
}

//
// transfer_from
//

#[test]
#[available_gas(30000000)]
fn test_transfer_from() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    testing::set_caller_address(SPENDER());
    assert(state.transfer_from(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(OWNER(), SPENDER(), 0);
    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);

    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Should eq amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == 0, 'Should eq 0');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Total supply should not change');
}

#[test]
#[available_gas(25000000)]
fn test_transfer_from_doesnt_consume_infinite_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), BoundedInt::max());

    testing::set_caller_address(SPENDER());
    ERC20Impl::transfer_from(ref state, OWNER(), RECIPIENT(), VALUE);

    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == BoundedInt::max(),
        'Allowance should not change'
    );
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_transfer_from_greater_than_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    testing::set_caller_address(SPENDER());
    let allowance_plus_one = VALUE + 1;
    ERC20Impl::transfer_from(ref state, OWNER(), RECIPIENT(), allowance_plus_one);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_transfer_from_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    testing::set_caller_address(SPENDER());
    ERC20Impl::transfer_from(ref state, OWNER(), ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_transfer_from_from_zero_address() {
    let mut state = setup();
    ERC20Impl::transfer_from(ref state, ZERO(), RECIPIENT(), VALUE);
}

//
// increase_allowance & increaseAllowance
//

#[test]
#[available_gas(25000000)]
fn test_increase_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.increase_allowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(OWNER(), SPENDER(), VALUE * 2);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE * 2, 'Should be amount * 2');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_increase_allowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.increase_allowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_increase_allowance_from_zero_address() {
    let mut state = setup();
    state.increase_allowance(SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
fn test_increaseAllowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.increaseAllowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(OWNER(), SPENDER(), 2 * VALUE);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE * 2, 'Should be amount * 2');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_increaseAllowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.increaseAllowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_increaseAllowance_from_zero_address() {
    let mut state = setup();
    state.increaseAllowance(SPENDER(), VALUE);
}

//
// decrease_allowance & decreaseAllowance
//

#[test]
#[available_gas(25000000)]
fn test_decrease_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.decrease_allowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(OWNER(), SPENDER(), 0);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE - VALUE, 'Should be 0');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decrease_allowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.decrease_allowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decrease_allowance_from_zero_address() {
    let mut state = setup();
    state.decrease_allowance(SPENDER(), VALUE);
}

#[test]
#[available_gas(25000000)]
fn test_decreaseAllowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert(state.decreaseAllowance(SPENDER(), VALUE), 'Should return true');

    assert_only_event_approval(OWNER(), SPENDER(), 0);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE - VALUE, 'Should be 0');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decreaseAllowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.decreaseAllowance(ZERO(), VALUE);
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decreaseAllowance_from_zero_address() {
    let mut state = setup();
    state.decreaseAllowance(SPENDER(), VALUE);
}

//
// _spend_allowance
//

#[test]
#[available_gas(25000000)]
fn test__spend_allowance_not_unlimited() {
    let mut state = setup();

    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve( SPENDER(), SUPPLY);
    utils::drop_event(ZERO());

    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), VALUE);

    assert_only_event_approval(OWNER(), SPENDER(), SUPPLY - VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == SUPPLY - VALUE,
        'Should eq supply - amount'
    );
}

#[test]
#[available_gas(25000000)]
fn test__spend_allowance_unlimited() {
    let mut state = setup();
   
    testing::set_caller_address(OWNER());
    state.erc20_allowance.approve( SPENDER(), BoundedInt::max());

    let max_minus_one: u256 = BoundedInt::max() - 1;
    state.erc20_allowance._spend_allowance(OWNER(), SPENDER(), max_minus_one);

    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == BoundedInt::max(),
        'Allowance should not change'
    );
}

//
// _mint
//

#[test]
#[available_gas(25000000)]
fn test__mint() {
    let (world, mut state) = STATE();
    state.erc20_mintable._mint(OWNER(), VALUE);
    assert_only_event_transfer(ZERO(), OWNER(), VALUE);
    assert(ERC20Impl::balance_of(@state, OWNER()) == VALUE, 'Should eq amount');
    assert(ERC20Impl::total_supply(@state) == VALUE, 'Should eq total supply');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: mint to 0',))]
fn test__mint_to_zero() {
    let (world, mut state) = STATE();
    state.erc20_mintable._mint(ZERO(), VALUE);
}

//
// _burn
//

#[test]
#[available_gas(25000000)]
fn test__burn() {
    let mut state = setup();
    state.erc20_burnable._burn(OWNER(), VALUE);

    assert_only_event_transfer(OWNER(), ZERO(), VALUE);
    assert(ERC20Impl::total_supply(@state) == SUPPLY - VALUE, 'Should eq supply - amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq supply - amount');
}

#[test]
#[available_gas(25000000)]
#[should_panic(expected: ('ERC20: burn from 0',))]
fn test__burn_from_zero() {
    let mut state = setup();
    state.erc20_burnable._burn(ZERO(), VALUE);
}


//
//  bridgeable
//

#[test]
#[available_gas(30000000)]
fn test_bridge_can_mint() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);

    assert_only_event_transfer(ZERO(), RECIPIENT(), VALUE);

    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Should eq VALUE');
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_bridge_only_can_mint() {
    let mut state = setup();

    testing::set_caller_address(RECIPIENT());
    state.erc20_bridgeable.mint(RECIPIENT(), VALUE);
}

#[test]
#[available_gas(30000000)]
fn test_bridge_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);
    assert_only_event_transfer(ZERO(), RECIPIENT(), VALUE);

    state.burn(RECIPIENT(), 1);
    assert_only_event_transfer(RECIPIENT(), ZERO(), 1);

    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE - 1, 'Should eq VALUE-1');
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_bridge_only_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);

    testing::set_caller_address(RECIPIENT());
    state.burn(RECIPIENT(), VALUE);
}


//
// Helpers
//

fn assert_event_approval(owner: ContractAddress, spender: ContractAddress, value: u256) {
    let event = utils::pop_log::<Approval>(ZERO()).unwrap();
    assert(event.owner == owner, 'Invalid `owner`');
    assert(event.spender == spender, 'Invalid `spender`');
    assert(event.value == value, 'Invalid `value`');
}

fn assert_only_event_approval(owner: ContractAddress, spender: ContractAddress, value: u256) {
    assert_event_approval(owner, spender, value);
    utils::assert_no_events_left(ZERO());
}

fn assert_event_transfer(from: ContractAddress, to: ContractAddress, value: u256) {
    let event = utils::pop_log::<Transfer>(ZERO()).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.value == value, 'Invalid `value`');
}

fn assert_only_event_transfer(from: ContractAddress, to: ContractAddress, value: u256) {
    assert_event_transfer(from, to, value);
    utils::assert_no_events_left(ZERO());
}
