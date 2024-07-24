use core::array::SpanTrait;
use starknet::ContractAddress;
use starknet::testing;
use zeroable::Zeroable;

use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use origami_token::tests::constants::{
    ZERO, OWNER, SPENDER, RECIPIENT, BRIDGE, DECIMALS, SUPPLY, VALUE
};

use origami_token::tests::utils;

use origami_token::components::token::erc20::erc20_metadata::{
    erc_20_metadata_model, ERC20MetadataModel,
};
use origami_token::components::token::erc20::erc20_metadata::erc20_metadata_component::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use origami_token::components::token::erc20::erc20_balance::{
    erc_20_balance_model, ERC20BalanceModel,
};
use origami_token::components::token::erc20::erc20_balance::erc20_balance_component::{
    Transfer, ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use origami_token::components::token::erc20::erc20_allowance::{
    erc_20_allowance_model, ERC20AllowanceModel,
};
use origami_token::components::token::erc20::erc20_allowance::erc20_allowance_component::{
    Approval, ERC20AllowanceImpl, InternalImpl as ERC20AllownceInternalImpl,
};

use origami_token::components::token::erc20::erc20_bridgeable::{
    erc_20_bridgeable_model, ERC20BridgeableModel
};
use origami_token::components::token::erc20::erc20_bridgeable::erc20_bridgeable_component::{
    ERC20BridgeableImpl
};

use origami_token::components::token::erc20::erc20_mintable::erc20_mintable_component::InternalImpl as ERC20MintableInternalImpl;
use origami_token::components::token::erc20::erc20_burnable::erc20_burnable_component::InternalImpl as ERC20BurnableInternalImpl;

use origami_token::presets::erc20::bridgeable::{
    ERC20Bridgeable, IERC20BridgeablePresetDispatcher, IERC20BridgeablePresetDispatcherTrait
};
use origami_token::presets::erc20::bridgeable::ERC20Bridgeable::{ERC20InitializerImpl};

use origami_token::components::tests::token::erc20::test_erc20_allowance::{
    assert_event_approval, assert_only_event_approval
};
use origami_token::components::tests::token::erc20::test_erc20_balance::{
    assert_event_transfer, assert_only_event_transfer
};

use origami_token::components::security::initializable::initializable_model;

//
// Setup
//

fn setup() -> (IWorldDispatcher, IERC20BridgeablePresetDispatcher) {
    let world = spawn_test_world(
        "origami_token",
        array![
            erc_20_allowance_model::TEST_CLASS_HASH,
            erc_20_balance_model::TEST_CLASS_HASH,
            erc_20_metadata_model::TEST_CLASS_HASH,
            erc_20_bridgeable_model::TEST_CLASS_HASH,
            initializable_model::TEST_CLASS_HASH,
        ]
    );

    // deploy contract
    let mut erc20_bridgeable_dispatcher = IERC20BridgeablePresetDispatcher {
        contract_address: world
            .deploy_contract(
                'salt', ERC20Bridgeable::TEST_CLASS_HASH.try_into().unwrap(), array![].span()
            )
    };

    world.grant_owner(starknet::get_contract_address(), dojo::utils::hash(@"origami_token"));
    world.grant_owner(OWNER(), dojo::utils::hash(@"origami_token"));
    world.grant_owner(BRIDGE(), dojo::utils::hash(@"origami_token"));
    world.grant_owner(SPENDER(), dojo::utils::hash(@"origami_token"));

    // initialize contracts
    erc20_bridgeable_dispatcher.initializer("NAME", "SYMBOL", SUPPLY, OWNER(), BRIDGE());

    // drop all events
    utils::drop_all_events(erc20_bridgeable_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, erc20_bridgeable_dispatcher)
}


//
// initializer
//

#[test]
fn test_initializer() {
    let (_world, mut erc20_bridgeable) = setup();

    assert(erc20_bridgeable.balance_of(OWNER()) == SUPPLY, 'Should eq inital_supply');
    assert(erc20_bridgeable.total_supply() == SUPPLY, 'Should eq inital_supply');
    assert(erc20_bridgeable.name() == "NAME", 'Name should be NAME');
    assert(erc20_bridgeable.symbol() == "SYMBOL", 'Symbol should be SYMBOL');
    assert(erc20_bridgeable.decimals() == DECIMALS, 'Decimals should be 18');
    assert(erc20_bridgeable.l2_bridge_address() == BRIDGE(), 'Decimals should be BRIDGE');
}


//
// approve
//

#[test]
fn test_approve() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(OWNER());

    assert(erc20_bridgeable.approve(SPENDER(), VALUE), 'Should eq VALUE');
    assert(
        erc20_bridgeable.allowance(OWNER(), SPENDER()) == VALUE, 'Spender not approved correctly'
    );

    // drop StoreSetRecord ERC20AllowanceModel
    utils::drop_event(world.contract_address);

    assert_only_event_approval(erc20_bridgeable.contract_address, OWNER(), SPENDER(), VALUE);
    assert_only_event_approval(world.contract_address, OWNER(), SPENDER(), VALUE);
}


//
// transfer
//

#[test]
fn test_transfer() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(OWNER());

    assert(erc20_bridgeable.transfer(RECIPIENT(), VALUE), 'Should return true');

    assert(erc20_bridgeable.balance_of(RECIPIENT()) == VALUE, 'Balance should eq VALUE');
    assert(erc20_bridgeable.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq supply - VALUE');
    assert(erc20_bridgeable.total_supply() == SUPPLY, 'Total supply should not change');

    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);

    assert_only_event_transfer(erc20_bridgeable.contract_address, OWNER(), RECIPIENT(), VALUE);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), VALUE);
}


//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(OWNER());

    erc20_bridgeable.approve(SPENDER(), VALUE);

    utils::drop_all_events(erc20_bridgeable.contract_address);
    utils::drop_all_events(world.contract_address);

    utils::impersonate(SPENDER());
    assert(erc20_bridgeable.transfer_from(OWNER(), RECIPIENT(), VALUE), 'Should return true');

    assert_event_approval(erc20_bridgeable.contract_address, OWNER(), SPENDER(), 0);
    assert_only_event_transfer(erc20_bridgeable.contract_address, OWNER(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20AllowanceModel
    utils::drop_event(world.contract_address);
    assert_event_approval(world.contract_address, OWNER(), SPENDER(), 0);
    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, OWNER(), RECIPIENT(), VALUE);

    assert(erc20_bridgeable.balance_of(RECIPIENT()) == VALUE, 'Should eq amount');
    assert(erc20_bridgeable.balance_of(OWNER()) == SUPPLY - VALUE, 'Should eq suppy - amount');
    assert(erc20_bridgeable.allowance(OWNER(), SPENDER()) == 0, 'Should eq 0');
    assert(erc20_bridgeable.total_supply() == SUPPLY, 'Total supply should not change');
}

//
//  bridgeable
//

#[test]
fn test_bridge_can_mint() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(BRIDGE());
    erc20_bridgeable.mint(RECIPIENT(), VALUE);

    assert_only_event_transfer(erc20_bridgeable.contract_address, ZERO(), RECIPIENT(), VALUE);

    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);

    assert_only_event_transfer(world.contract_address, ZERO(), RECIPIENT(), VALUE);

    assert(erc20_bridgeable.balance_of(RECIPIENT()) == VALUE, 'Should eq VALUE');
}

#[test]
#[should_panic(expected: ('ERC20: caller not bridge', 'ENTRYPOINT_FAILED'))]
fn test_bridge_only_can_mint() {
    let (_world, mut erc20_bridgeable) = setup();

    utils::impersonate(RECIPIENT());
    erc20_bridgeable.mint(RECIPIENT(), VALUE);
}

#[test]
fn test_bridge_can_burn() {
    let (world, mut erc20_bridgeable) = setup();

    utils::impersonate(BRIDGE());
    erc20_bridgeable.mint(RECIPIENT(), VALUE);
    assert_only_event_transfer(erc20_bridgeable.contract_address, ZERO(), RECIPIENT(), VALUE);

    utils::drop_all_events(erc20_bridgeable.contract_address);
    utils::drop_all_events(world.contract_address);

    erc20_bridgeable.burn(RECIPIENT(), 1);

    assert_only_event_transfer(erc20_bridgeable.contract_address, RECIPIENT(), ZERO(), 1);

    // drop StoreSetRecord ERC20BalanceModel x2
    utils::drop_event(world.contract_address);
    utils::drop_event(world.contract_address);
    assert_only_event_transfer(world.contract_address, RECIPIENT(), ZERO(), 1);

    assert(erc20_bridgeable.balance_of(RECIPIENT()) == VALUE - 1, 'Should eq VALUE-1');
}

#[test]
#[should_panic(expected: ('ERC20: caller not bridge', 'ENTRYPOINT_FAILED'))]
fn test_bridge_only_can_burn() {
    let (_world, mut erc20_bridgeable) = setup();

    utils::impersonate(BRIDGE());
    erc20_bridgeable.mint(RECIPIENT(), VALUE);

    utils::impersonate(RECIPIENT());
    erc20_bridgeable.burn(RECIPIENT(), VALUE);
}

