use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{NAME, SYMBOL, DECIMALS};

use token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20::erc20_metadata::erc20_metadata_component::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl
};
use token::components::tests::mocks::erc20::erc20_metadata_mock::erc20_metadata_mock;
use token::components::tests::mocks::erc20::erc20_metadata_mock::erc20_metadata_mock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, erc20_metadata_mock::ContractState) {
    let world = spawn_test_world(array![erc_20_metadata_model::TEST_CLASS_HASH,]);

    let mut state = erc20_metadata_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
#[available_gas(100000000)]
fn test_erc20_metadata_initialize() {
    let (world, mut state) = STATE();

    state.erc20_metadata.initialize(NAME, SYMBOL, DECIMALS);

    assert(state.erc20_metadata.name() == NAME, 'Should be NAME');
    assert(state.erc20_metadata.symbol() == SYMBOL, 'Should be SYMBOL');
    assert(state.erc20_metadata.decimals() == DECIMALS, 'Should be 18');
    assert(state.erc20_metadata.total_supply() == 0, 'Should be 0');
}

#[test]
#[available_gas(100000000)]
fn test_erc20_metadata_update_total_supply() {
    let (world, mut state) = STATE();

    state.erc20_metadata.update_total_supply(0, 420);
    assert(state.erc20_metadata.total_supply() == 420, 'Should be 420');

    state.erc20_metadata.update_total_supply(0, 1000);
    assert(state.erc20_metadata.total_supply() == 1420, 'Should be 1420');

    state.erc20_metadata.update_total_supply(420, 0);
    assert(state.erc20_metadata.total_supply() == 1000, 'Should be 1000');
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_erc20_metadata_update_total_supply_sub_overflow() {
    let (world, mut state) = STATE();

    state.erc20_metadata.update_total_supply(1, 0);
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('u256_add Overflow',))]
fn test_erc20_metadata_update_total_supply_add_overflow() {
    let (world, mut state) = STATE();

    state.erc20_metadata.update_total_supply(0, BoundedInt::max());
    state.erc20_metadata.update_total_supply(0, 1);
}
