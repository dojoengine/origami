use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;

use token::components::security::initializable::{initializable_model, InitializableModel};
use token::components::security::initializable::initializable_component::{
    InitializableImpl, InternalImpl
};
use token::components::tests::mocks::initializable_mock::InitializableMock;
use token::components::tests::mocks::initializable_mock::InitializableMock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, InitializableMock::ContractState) {
    let world = spawn_test_world(array![initializable_model::TEST_CLASS_HASH,]);

    let mut state = InitializableMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
#[available_gas(5000000)]
fn test_initializable_initialize() {
    let (world, mut state) = STATE();
    assert(!state.initializable.is_initialized(), 'Should not be initialized');
    state.initializable.initialize();
    assert(state.initializable.is_initialized(), 'Should be initialized');
}

#[test]
#[available_gas(5000000)]
#[should_panic(expected: ('Initializable: is initialized',))]
fn test_initializable_initialize_when_initialized() {
    let (world, mut state) = STATE();
    state.initializable.initialize();
    state.initializable.initialize();
}
