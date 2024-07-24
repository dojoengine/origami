use starknet::testing;
use starknet::ContractAddress;

use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::contract::{IContractDispatcherTrait, IContractDispatcher};
use dojo::test_utils::spawn_test_world;
use origami_token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, BRIDGE, DECIMALS, SUPPLY, VALUE};

use origami_token::components::token::erc20::erc20_allowance::{erc_20_allowance_model, ERC20AllowanceModel};
use origami_token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use origami_token::components::token::erc20::erc20_metadata::erc20_metadata_component::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use origami_token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use origami_token::components::token::erc20::erc20_balance::erc20_balance_component::{
    ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use origami_token::components::token::erc20::erc20_mintable::erc20_mintable_component::InternalImpl as ERC20MintableInternalImpl;
use origami_token::components::token::erc20::erc20_burnable::erc20_burnable_component::InternalImpl as ERC20BurnableInternalImpl;

use origami_token::components::token::erc20::erc20_bridgeable::{
    erc_20_bridgeable_model, ERC20BridgeableModel
};
use origami_token::components::token::erc20::erc20_bridgeable::erc20_bridgeable_component::{
    ERC20BridgeableImpl
};

use origami_token::components::tests::mocks::erc20::erc20_bridgeable_mock::erc20_bridgeable_mock;
use origami_token::components::tests::mocks::erc20::erc20_bridgeable_mock::erc20_bridgeable_mock::{
    ERC20InitializerImpl
};

use origami_token::components::security::initializable::initializable_model;

fn STATE() -> (IWorldDispatcher, erc20_bridgeable_mock::ContractState) {
    let world = spawn_test_world(
        "origami_token",
        array![
            erc_20_metadata_model::TEST_CLASS_HASH,
            erc_20_balance_model::TEST_CLASS_HASH,
            erc_20_bridgeable_model::TEST_CLASS_HASH,
            erc_20_allowance_model::TEST_CLASS_HASH,
            initializable_model::TEST_CLASS_HASH,
        ]
    );

    // Deploy the contract to ensure the selector is a known resource.
    world
        .deploy_contract(
            'salt', erc20_bridgeable_mock::TEST_CLASS_HASH.try_into().unwrap(), array![].span(),
        );

    let mut state = erc20_bridgeable_mock::contract_state_for_testing();
    state.world_dispatcher.write(world);
    world
        .grant_owner(starknet::get_contract_address(), dojo::contract::IContract::selector(@state));

    (world, state)
}


fn setup() -> erc20_bridgeable_mock::ContractState {
    let (_world, mut state) = STATE();
    state.initializer("NAME", "SYMBOL", SUPPLY, OWNER(), BRIDGE());
    state
}

//
// initializer
//

#[test]
fn test_erc20_bridgeable_initializer() {
    let (_world, mut state) = STATE();
    state.initializer("NAME", "SYMBOL", SUPPLY, OWNER(), BRIDGE());

    assert(state.l2_bridge_address() == BRIDGE(), 'should be BRIDGE');
}

//
//  bridgeable
//

#[test]
fn test_erc20_bridgeable_bridge_can_mint() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());

    state.mint(RECIPIENT(), VALUE);

    assert(state.balance_of(RECIPIENT()) == VALUE, 'Should eq VALUE');
}

#[test]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_erc20_bridgeable_bridge_only_can_mint() {
    let mut state = setup();

    testing::set_caller_address(RECIPIENT());
    state.erc20_bridgeable.mint(RECIPIENT(), VALUE);
}

#[test]
fn test_erc20_bridgeable_bridge_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);
    state.burn(RECIPIENT(), 1);

    assert(state.balance_of(RECIPIENT()) == VALUE - 1, 'Should eq VALUE-1');
}

#[test]
#[should_panic(expected: ('ERC20: caller not bridge',))]
fn test_erc20_bridgeable_bridge_only_can_burn() {
    let mut state = setup();

    testing::set_caller_address(BRIDGE());
    state.mint(RECIPIENT(), VALUE);

    testing::set_caller_address(RECIPIENT());
    state.burn(RECIPIENT(), VALUE);
}
