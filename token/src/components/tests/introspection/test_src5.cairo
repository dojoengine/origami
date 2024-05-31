use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;

use token::components::introspection::src5::{src_5_model, SRC5Model, ISRC5, ISRC5_ID};
use token::components::introspection::src5::src5_component::{InternalImpl};
use token::components::tests::mocks::src5_mock::SRC5Mock;
use starknet::storage::{StorageMemberAccessTrait};
use token::tests::constants::{OTHER_ID};


fn STATE() -> (IWorldDispatcher, SRC5Mock::ContractState) {
    let world = spawn_test_world(array![src_5_model::TEST_CLASS_HASH,]);

    let mut state = SRC5Mock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}


#[test]
fn test_src5_default_behavior() {
    let (_world, mut state) = STATE();
    let supports_default_interface = state.supports_interface(ISRC5_ID);
    assert(supports_default_interface, 'Should support base interface');
}

#[test]
fn test_src5_not_registered_interface() {
    let (_world, mut state) = STATE();
    let supports_unregistered_interface = state.supports_interface(OTHER_ID);
    assert(!supports_unregistered_interface, 'Should not support unregistered');
}

#[test]
fn test_src5_register_interface() {
    let (_world, mut state) = STATE();
    state.src5.register_interface(OTHER_ID);
    let supports_new_interface = state.supports_interface(OTHER_ID);
    assert(supports_new_interface, 'Should support new interface');
}

#[test]
fn test_src5_deregister_interface() {
    let (_world, mut state) = STATE();
    state.src5.register_interface(OTHER_ID);
    state.src5.deregister_interface(OTHER_ID);
    let supports_old_interface = state.supports_interface(OTHER_ID);
    assert(!supports_old_interface, 'Should not support interface');
}

#[test]
#[should_panic(expected: ('SRC5: invalid id',))]
fn test_src5_deregister_default_interface() {
    let (_world, mut state) = STATE();
    state.src5.deregister_interface(ISRC5_ID);
}
