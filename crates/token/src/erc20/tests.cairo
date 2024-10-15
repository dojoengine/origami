use core::num::traits::Bounded;
use integer::u256;
use integer::u256_from_felt252;
use origami_token::tests::utils;
use origami_token::tests::constants::{
    ZERO, OWNER, SPENDER, RECIPIENT, NAME, SYMBOL, DECIMALS, SUPPLY, VALUE
};
use origami_token::erc20::ERC20::Approval;
use origami_token::erc20::ERC20::ERC20Impl;
use origami_token::erc20::ERC20::ERC20MetadataImpl;
use origami_token::erc20::ERC20::InternalImpl;
use origami_token::erc20::ERC20::Transfer;
use origami_token::erc20::ERC20;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing;
use zeroable::Zeroable;
use dojo::test_utils::spawn_test_world;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

use origami_token::erc20::models::{
    ERC20Allowance, erc_20_allowance, ERC20Balance, erc_20_balance, ERC20Meta, erc_20_meta
};
use starknet::storage::{StorageMemberAccessTrait};

use debug::PrintTrait;

//
// Setup
//

fn STATE() -> (IWorldDispatcher, ERC20::ContractState) {
    let world = spawn_test_world(
        [].span(),
        [
            erc_20_allowance::TEST_CLASS_HASH,
            erc_20_balance::TEST_CLASS_HASH,
            erc_20_meta::TEST_CLASS_HASH,
        ]
    );
    let mut state = ERC20::contract_state_for_testing();
    state._world.write(world.contract_address);
    (world, state)
}

fn setup() -> ERC20::ContractState {
    let (world, mut state) = STATE();
    ERC20::constructor(ref state, world.contract_address, NAME, SYMBOL, SUPPLY, OWNER());
    utils::drop_event(ZERO());
    state
}

//
// initializer & constructor
//

#[test]
fn test_initializer() {
    let (_world, mut state) = STATE();
    InternalImpl::initializer(ref state, NAME, SYMBOL);

    assert(ERC20MetadataImpl::nameXXX(@state) == NAME, 'Name should be NAME');
    assert(ERC20MetadataImpl::symbol(@state) == SYMBOL, 'Symbol should be SYMBOL');
    assert(ERC20MetadataImpl::decimals(@state) == DECIMALS, 'Decimals should be 18');
    assert(ERC20Impl::total_supply(@state) == 0, 'Supply should eq 0');
}


#[test]
fn test_constructor() {
    let (world, mut state) = STATE();
    ERC20::constructor(ref state, world.contract_address, NAME, SYMBOL, SUPPLY, OWNER());

    assert_only_event_transfer(ZERO(), OWNER(), SUPPLY);

    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY, 'Should eq inital_supply');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Should eq inital_supply');
    assert(ERC20MetadataImpl::nameXXX(@state) == NAME, 'Name should be NAME');
    assert(ERC20MetadataImpl::symbol(@state) == SYMBOL, 'Symbol should be SYMBOL');
    assert(ERC20MetadataImpl::decimals(@state) == DECIMALS, 'Decimals should be 18');
}

//
// Getters
//

#[test]
fn test_total_supply() {
    let (_world, mut state) = STATE();
    InternalImpl::_mint(ref state, OWNER(), SUPPLY);
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Should eq SUPPLY');
}

#[test]
fn test_balance_of() {
    let (_world, mut state) = STATE();
    InternalImpl::_mint(ref state, OWNER(), SUPPLY);
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY, 'Should eq SUPPLY');
}


#[test]
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
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_approve_from_zero() {
    let mut state = setup();
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
}

#[test]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, Zeroable::zero(), VALUE);
}

#[test]
fn test__approve() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    InternalImpl::_approve(ref state, OWNER(), SPENDER(), VALUE);

    assert_only_event_approval(OWNER(), SPENDER(), VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Spender not approved correctly'
    );
}

#[test]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test__approve_from_zero() {
    let mut state = setup();
    InternalImpl::_approve(ref state, Zeroable::zero(), SPENDER(), VALUE);
}

#[test]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test__approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    InternalImpl::_approve(ref state, OWNER(), Zeroable::zero(), VALUE);
}

//
// transfer & _transfer
//

#[test]
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
fn test__transfer() {
    let mut state = setup();

    InternalImpl::_transfer(ref state, OWNER(), RECIPIENT(), VALUE);

    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);
    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Balance should eq amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq supply - amount');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Total supply should not change');
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test__transfer_not_enough_balance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());

    let balance_plus_one = SUPPLY + 1;
    InternalImpl::_transfer(ref state, OWNER(), RECIPIENT(), balance_plus_one);
}

#[test]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test__transfer_from_zero() {
    let mut state = setup();
    InternalImpl::_transfer(ref state, Zeroable::zero(), RECIPIENT(), VALUE);
}

#[test]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test__transfer_to_zero() {
    let mut state = setup();
    InternalImpl::_transfer(ref state, OWNER(), Zeroable::zero(), VALUE);
}

//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    utils::drop_event(ZERO());

    testing::set_caller_address(SPENDER());
    assert(ERC20Impl::transfer_from(ref state, OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(OWNER(), SPENDER(), 0);
    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);

    assert(ERC20Impl::balance_of(@state, RECIPIENT()) == VALUE, 'Should eq amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == 0, 'Should eq 0');
    assert(ERC20Impl::total_supply(@state) == SUPPLY, 'Total supply should not change');
}

#[test]
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
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_transfer_from_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    testing::set_caller_address(SPENDER());
    ERC20Impl::transfer_from(ref state, OWNER(), Zeroable::zero(), VALUE);
}

#[test]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_transfer_from_from_zero_address() {
    let mut state = setup();
    ERC20Impl::transfer_from(ref state, Zeroable::zero(), RECIPIENT(), VALUE);
}

//
// _spend_allowance
//

#[test]
fn test__spend_allowance_not_unlimited() {
    let mut state = setup();

    InternalImpl::_approve(ref state, OWNER(), SPENDER(), SUPPLY);
    utils::drop_event(ZERO());

    InternalImpl::_spend_allowance(ref state, OWNER(), SPENDER(), VALUE);

    assert_only_event_approval(OWNER(), SPENDER(), SUPPLY - VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == SUPPLY - VALUE,
        'Should eq supply - amount'
    );
}

//
// _mint
//

#[test]
fn test__mint() {
    let (_world, mut state) = STATE();
    InternalImpl::_mint(ref state, OWNER(), VALUE);
    assert_only_event_transfer(ZERO(), OWNER(), VALUE);
    assert(ERC20Impl::balance_of(@state, OWNER()) == VALUE, 'Should eq amount');
    assert(ERC20Impl::total_supply(@state) == VALUE, 'Should eq total supply');
}

#[test]
#[should_panic(expected: ('ERC20: mint to 0',))]
fn test__mint_to_zero() {
    let (_world, mut state) = STATE();
    InternalImpl::_mint(ref state, Zeroable::zero(), VALUE);
}

//
// _burn
//

#[test]
fn test__burn() {
    let mut state = setup();
    InternalImpl::_burn(ref state, OWNER(), VALUE);

    assert_only_event_transfer(OWNER(), ZERO(), VALUE);
    assert(ERC20Impl::total_supply(@state) == SUPPLY - VALUE, 'Should eq supply - amount');
    assert(ERC20Impl::balance_of(@state, OWNER()) == SUPPLY - VALUE, 'Should eq supply - amount');
}

#[test]
#[should_panic(expected: ('ERC20: burn from 0',))]
fn test__burn_from_zero() {
    let mut state = setup();
    InternalImpl::_burn(ref state, Zeroable::zero(), VALUE);
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
