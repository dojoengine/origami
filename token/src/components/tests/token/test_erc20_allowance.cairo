use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ADMIN, OWNER, SPENDER};

use token::components::token::erc20_allowance::{erc_20_allowance_model, ERC20AllowanceModel,};
use token::components::token::erc20_allowance::ERC20AllowanceComponent::{
    ERC20AllowanceImpl, InternalImpl
};
use token::components::tests::mocks::erc20_allowance_mock::ERC20AllowanceMock;
use token::components::tests::mocks::erc20_allowance_mock::ERC20AllowanceMock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, ERC20AllowanceMock::ContractState) {
    let world = spawn_test_world(array![erc_20_allowance_model::TEST_CLASS_HASH,]);

    let mut state = ERC20AllowanceMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
#[available_gas(100000000)]
fn test_erc20_allowance_initialize() {
    let (world, mut state) = STATE();
// state.erc20_allowance
}
