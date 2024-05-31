use starknet::testing;
use starknet::ContractAddress;
use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, VALUE, TOKEN_ID, TOKEN_ID_2};
use token::tests::utils;

use token::components::token::erc721::erc721_balance::{erc_721_balance_model, ERC721BalanceModel};
use token::components::token::erc721::erc721_balance::erc721_balance_component::{
    Transfer, ERC721BalanceImpl, ERC721BalanceCamelImpl, InternalImpl as ERC721BalanceInternalImpl
};

use token::components::token::erc721::erc721_enumerable::{
    erc_721_enumerable_index_model, ERC721EnumerableIndexModel,
    erc_721_enumerable_owner_index_model, ERC721EnumerableOwnerIndexModel,
    erc_721_enumerable_total_model, ERC721EnumerableTotalModel
};
use token::components::token::erc721::erc721_enumerable::erc721_enumerable_component::{
    ERC721EnumerableImpl, InternalImpl as ERC721EnumerableInternalImpl
};
use token::components::tests::mocks::erc721::erc721_enumerable_mock::{
    erc721_enumerable_mock, IERC721EnumerableMockDispatcher, IERC721EnumerableMockDispatcherTrait
};


use starknet::storage::{StorageMemberAccessTrait};

use debug::PrintTrait;

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, erc721_enumerable_mock::ContractState) {
    let world = spawn_test_world(
        array![
            erc_721_enumerable_index_model::TEST_CLASS_HASH,
            erc_721_enumerable_owner_index_model::TEST_CLASS_HASH,
            erc_721_enumerable_total_model::TEST_CLASS_HASH
        ]
    );

    let mut state = erc721_enumerable_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

//
//  set_total_supply
//

#[test]
fn test_erc721_enumerable_total() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_enumerable.set_total_supply(VALUE);
    assert(
        state.erc721_enumerable.get_total_supply().total_supply.into() == VALUE, 'should be VALUE'
    );
}

#[test]
fn test_erc721_enumerable_index() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_enumerable.set_token_by_index(0, TOKEN_ID);
    assert(
        state.erc721_enumerable.get_token_by_index(0).token_id.into() == TOKEN_ID,
        'should be TOKEN_ID'
    );
}

#[test]
fn test_erc721_enumerable_owner_index() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_enumerable.set_token_of_owner_by_index(OWNER(), 0, TOKEN_ID);
    assert(
        state.erc721_enumerable.get_token_of_owner_by_index(OWNER(), 0).token_id.into() == TOKEN_ID,
        'should be TOKEN_ID'
    );
}

#[test]
fn test_erc721_add_token_to_owner_enumeration() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_balance.set_balance(OWNER(), 1);
    state.erc721_enumerable.add_token_to_owner_enumeration(OWNER(), TOKEN_ID);
    assert(
        state.erc721_enumerable.get_token_of_owner_by_index(OWNER(), 0).token_id.into() == TOKEN_ID,
        'should be TOKEN_ID'
    );
    assert(
        state.erc721_enumerable.get_index_of_owner_by_token(OWNER(), TOKEN_ID).index == 0,
        'should be 0'
    );
}

#[test]
fn test_erc721_add_token_to_all_tokens_enumeration() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_enumerable.add_token_to_all_tokens_enumeration(TOKEN_ID);
    assert(
        state.erc721_enumerable.get_token_by_index(0).token_id.into() == TOKEN_ID,
        'should be TOKEN_ID'
    );
    assert(state.erc721_enumerable.get_index_by_token(TOKEN_ID).index == 0, 'should be 0');
}

#[test]
fn test_erc721_remove_token_from_owner_enumeration() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_balance.set_balance(OWNER(), 1);
    state.erc721_enumerable.add_token_to_owner_enumeration(OWNER(), TOKEN_ID);
    state.erc721_balance.set_balance(OWNER(), 2);
    state.erc721_enumerable.add_token_to_owner_enumeration(OWNER(), TOKEN_ID_2);
    state.erc721_balance.set_balance(OWNER(), 1);
    state.erc721_enumerable.remove_token_from_owner_enumeration(OWNER(), TOKEN_ID);
    assert(
        state
            .erc721_enumerable
            .get_token_of_owner_by_index(OWNER(), 0)
            .token_id
            .into() == TOKEN_ID_2,
        'should be TOKEN_ID_2'
    );
    assert(
        state.erc721_enumerable.get_index_of_owner_by_token(OWNER(), TOKEN_ID).index == 0,
        'should be 0'
    );
}

#[test]
fn test_erc721_remove_token_from_all_tokens_enumeration() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_enumerable.add_token_to_all_tokens_enumeration(TOKEN_ID);
    state.erc721_enumerable.set_total_supply(1);
    state.erc721_enumerable.add_token_to_all_tokens_enumeration(TOKEN_ID_2);
    state.erc721_enumerable.set_total_supply(2);
    state.erc721_enumerable.remove_token_from_all_tokens_enumeration(TOKEN_ID);
    assert(
        state.erc721_enumerable.get_token_by_index(0).token_id.into() == TOKEN_ID_2,
        'should be TOKEN_ID_2'
    );
    assert(state.erc721_enumerable.get_index_by_token(TOKEN_ID).index == 0, 'should be 0');
}
