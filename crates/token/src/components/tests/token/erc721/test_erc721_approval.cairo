use origami_token::components::token::erc721::erc721_approval::IERC721Approval;
use starknet::testing;
use starknet::ContractAddress;
use core::num::traits::Bounded;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::utils::test::spawn_test_world;
use origami_token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, TOKEN_ID};
use origami_token::tests::utils;

use origami_token::components::token::erc721::erc721_approval::{
    erc_721_token_approval_model, ERC721TokenApprovalModel, erc_721_operator_approval_model,
    ERC721OperatorApprovalModel
};
use origami_token::components::token::erc721::erc721_owner::{
    erc_721_owner_model, ERC721OwnerModel,
};
use origami_token::components::token::erc721::erc721_approval::erc721_approval_component;
use origami_token::components::token::erc721::erc721_approval::erc721_approval_component::{
    Approval, ApprovalForAll, ERC721ApprovalImpl, InternalImpl as ERC721ApprovalInternalImpl
};

use origami_token::components::token::erc721::erc721_owner::erc721_owner_component;
use origami_token::components::token::erc721::erc721_owner::erc721_owner_component::{
    ERC721OwnerImpl, InternalImpl as ERC721OwnerInternalImpl
};

use origami_token::components::tests::mocks::erc721::erc721_approval_mock::erc721_approval_mock;

use debug::PrintTrait;

//
// events helpers
//

fn assert_event_approval(
    emitter: ContractAddress, owner: ContractAddress, spender: ContractAddress, token_id: u256
) {
    let event = utils::pop_log::<Approval>(emitter).unwrap();
    assert(event.owner == owner, 'Invalid `owner`');
    assert(event.spender == spender, 'Invalid `spender`');
    assert(event.token_id == token_id, 'Invalid `token_id`');
}

fn assert_only_event_approval(
    emitter: ContractAddress, owner: ContractAddress, spender: ContractAddress, token_id: u256
) {
    assert_event_approval(emitter, owner, spender, token_id);
    utils::assert_no_events_left(emitter);
}

fn assert_event_approval_for_all(
    emitter: ContractAddress, owner: ContractAddress, operator: ContractAddress, approved: bool
) {
    let event = utils::pop_log::<ApprovalForAll>(emitter).unwrap();
    assert(event.owner == owner, 'Invalid `owner`');
    assert(event.operator == operator, 'Invalid `operator`');
    assert(event.approved == approved, 'Invalid `approved`');
}

fn assert_only_event_approval_for_all(
    emitter: ContractAddress, owner: ContractAddress, operator: ContractAddress, approved: bool
) {
    assert_event_approval_for_all(emitter, owner, operator, approved);
    utils::assert_no_events_left(emitter);
}

//
// initialize STATE
//

fn STATE() -> (IWorldDispatcher, erc721_approval_mock::ContractState) {
    let world = spawn_test_world(
        "origami_token",
        array![
            erc_721_token_approval_model::TEST_CLASS_HASH,
            erc_721_operator_approval_model::TEST_CLASS_HASH,
            erc_721_owner_model::TEST_CLASS_HASH
        ]
    );

    let mut state = erc721_approval_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    utils::drop_event(ZERO());

    (world, state)
}

//
//  set_approval (approve)
//

#[test]
fn test_erc721_approval_approve() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_approval.approve(SPENDER(), TOKEN_ID);
    assert(state.erc721_approval.get_approved(TOKEN_ID) == SPENDER(), 'should be SPENDER');

    assert_only_event_approval(ZERO(), OWNER(), SPENDER(), TOKEN_ID);
}

#[test]
fn test_erc721_approval_approve_for_all() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_approval.set_approval_for_all(SPENDER(), true);
    assert(
        state.erc721_approval.is_approved_for_all(OWNER(), SPENDER()) == true, 'should be approved'
    );

    assert_only_event_approval_for_all(ZERO(), OWNER(), SPENDER(), true);
}

#[test]
#[should_panic(expected: ('ERC721: unauthorized caller',))]
fn test_erc721_approval_unauthorized_caller() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(ZERO());

    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_approval.approve(SPENDER(), TOKEN_ID);
}

#[test]
#[should_panic(expected: ('ERC721: approval to owner',))]
fn test_erc721_approval_approval_to_owner() {
    let (_world, mut state) = STATE();

    testing::set_caller_address(OWNER());

    state.erc721_owner.set_owner(TOKEN_ID, OWNER());
    state.erc721_approval.approve(OWNER(), TOKEN_ID);
}
