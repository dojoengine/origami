use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, VALUE};

use token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20::erc20_metadata::erc20_metadata_component::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::erc20_balance_component::{
    ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use token::components::token::erc20::erc20_mintable::erc20_mintable_component::InternalImpl as ERC20MintableInternalImpl;
use token::components::token::erc20::erc20_burnable::erc20_burnable_component::InternalImpl as ERC20BurnableInternalImpl;

use token::components::tests::mocks::erc20::erc20_mintable_burnable_mock::erc20_mintable_burnable_mock;
use starknet::storage::{StorageMemberAccessTrait};

fn STATE() -> (IWorldDispatcher, erc20_mintable_burnable_mock::ContractState) {
    let world = spawn_test_world(
        array![erc_20_metadata_model::TEST_CLASS_HASH, erc_20_balance_model::TEST_CLASS_HASH,]
    );

    let mut state = erc20_mintable_burnable_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
fn test_erc20_mintable_mint() {
    let (_world, mut state) = STATE();

    let total_supply = state.total_supply();
    state.erc20_mintable.mint(RECIPIENT(), VALUE);
    let total_supply_after = state.total_supply();

    assert(state.balance_of(RECIPIENT()) == VALUE, 'invalid balance_of');
    assert(total_supply_after == total_supply + VALUE, 'invalid total_supply');
}

#[test]
#[should_panic(expected: ('ERC20: mint to 0',))]
fn test_erc20_mintable_mint_to_zero() {
    let (_world, mut state) = STATE();
    state.erc20_mintable.mint(ZERO(), VALUE);
}


#[test]
fn test_erc20_burnable_burn() {
    let (_world, mut state) = STATE();

    let total_supply = state.total_supply();
    state.erc20_mintable.mint(RECIPIENT(), VALUE);
    let total_supply_after_mint = state.total_supply();

    state.erc20_burnable.burn(RECIPIENT(), VALUE);
    let total_supply_after_burn = state.total_supply();

    assert(state.balance_of(RECIPIENT()) == 0, 'invalid balance_of');
    assert(total_supply_after_mint == total_supply + VALUE, 'invalid total_supply');
    assert(total_supply_after_burn == total_supply, 'invalid total_supply');
}


#[test]
#[should_panic(expected: ('ERC20: burn from 0',))]
fn test_erc20_burnable_burn_from_zero() {
    let (_world, mut state) = STATE();
    state.erc20_burnable.burn(ZERO(), VALUE);
}

