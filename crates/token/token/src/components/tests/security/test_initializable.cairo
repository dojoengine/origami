use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;

use origami_token::components::security::initializable::{initializable_model, InitializableModel};
use origami_token::components::security::initializable::initializable_component::{
    InitializableImpl, InternalImpl
};
use origami_token::components::tests::mocks::initializable_mock::InitializableMock;

fn STATE() -> (IWorldDispatcher, InitializableMock::ContractState) {
    let world = spawn_test_world("origami_token", array![initializable_model::TEST_CLASS_HASH,]);

    let mut state = InitializableMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
fn test_initializable_initialize() {
    let (_world, mut state) = STATE();
    assert(!state.initializable.is_initialized(), 'Should not be initialized');
    state.initializable.initialize();
    assert(state.initializable.is_initialized(), 'Should be initialized');
}

#[test]
#[should_panic(expected: ('Initializable: is initialized',))]
fn test_initializable_initialize_when_initialized() {
    let (_world, mut state) = STATE();
    state.initializable.initialize();
    state.initializable.initialize();
}
