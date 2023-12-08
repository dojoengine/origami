use starknet::testing;
use starknet::ContractAddress;

use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{
     ZERO, OWNER, SPENDER, RECIPIENT, BRIDGE, NAME, SYMBOL, DECIMALS, SUPPLY, VALUE
};

use token::components::token::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20_metadata::ERC20MetadataComponent::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use token::components::token::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20_balance::ERC20BalanceComponent::{
    ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use token::components::token::erc20_mintable::ERC20MintableComponent::InternalImpl as ERC20MintableInternalImpl;
use token::components::token::erc20_burnable::ERC20BurnableComponent::InternalImpl as ERC20BurnableInternalImpl;

use token::components::token::erc20_bridgeable::{erc_20_bridgeable_model, ERC20BridgeableModel};
use token::components::token::erc20_bridgeable::ERC20BridgeableComponent::{ERC20BridgeableImpl};

use token::components::tests::mocks::erc20_bridgeable_mock::ERC20BridgeableMock;
use token::components::tests::mocks::erc20_bridgeable_mock::ERC20BridgeableMock::{
    ERC20InitializerImpl
};
use token::components::tests::mocks::erc20_bridgeable_mock::ERC20BridgeableMock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, ERC20BridgeableMock::ContractState) {
    let world = spawn_test_world(
        array![erc_20_metadata_model::TEST_CLASS_HASH, erc_20_balance_model::TEST_CLASS_HASH,
        erc_20_bridgeable_model::TEST_CLASS_HASH]
    );

    let mut state = ERC20BridgeableMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}


fn setup() -> ERC20BridgeableMock::ContractState {
    let (world, mut state) = STATE();
    state.initializer(NAME, SYMBOL, SUPPLY, OWNER(), BRIDGE());
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

    assert(state.l2_bridge_address() == BRIDGE(), 'Decimals should be BRIDGE');
}

//
//  bridgeable
//

#[test]
#[available_gas(30000000)]
fn test_erc20_bridgeable_bridge_can_mint() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);

    assert(state.balance_of(RECIPIENT()) == VALUE, 'Should eq VALUE');
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_erc20_bridgeable_bridge_only_can_mint() {
    let mut state = setup();

    testing::set_caller_address(RECIPIENT());
    state.erc20_bridgeable.mint(RECIPIENT(), VALUE);
}

#[test]
#[available_gas(30000000)]
fn test_erc20_bridgeable_bridge_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);
    state.burn(RECIPIENT(), 1);

    assert(state.balance_of(RECIPIENT()) == VALUE - 1, 'Should eq VALUE-1');
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_erc20_bridgeable_bridge_only_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);

    testing::set_caller_address(RECIPIENT());
    state.burn(RECIPIENT(), VALUE);
}