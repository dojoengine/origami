use core::array::SpanTrait;
use starknet::ContractAddress;
use starknet::testing;
use zeroable::Zeroable;

use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{
    ZERO, OWNER, SPENDER, RECIPIENT, BRIDGE, NAME, SYMBOL, DECIMALS, SUPPLY, VALUE
};

use token::tests::utils;

use token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20::erc20_metadata::erc20_metadata_component::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::erc20_balance_component::{
    Transfer, ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use token::components::token::erc20::erc20_allowance::{
    erc_20_allowance_model, ERC20AllowanceModel,
};
use token::components::token::erc20::erc20_allowance::erc20_allowance_component::{
    Approval, ERC20AllowanceImpl, InternalImpl as ERC20AllownceInternalImpl, ERC20SafeAllowanceImpl,
    ERC20SafeAllowanceCamelImpl
};

use token::components::token::erc20::erc20_bridgeable::{
    erc_20_bridgeable_model, ERC20BridgeableModel
};
use token::components::token::erc20::erc20_bridgeable::erc20_bridgeable_component::{
    ERC20BridgeableImpl
};

use token::components::token::erc20::erc20_mintable::erc20_mintable_component::InternalImpl as ERC20MintableInternalImpl;
use token::components::token::erc20::erc20_burnable::erc20_burnable_component::InternalImpl as ERC20BurnableInternalImpl;

use bridge::dojo_token::{
    dojo_token, IDojoToken, IDojoTokenDispatcher, IDojoTokenDispatcherTrait
};
use bridge::dojo_bridge::{
    dojo_bridge_model, dojo_bridge, IDojoBridge, IDojoBridgeDispatcher, IDojoBridgeDispatcherTrait
};

use token::components::tests::token::erc20::test_erc20_allowance::{
    assert_event_approval, assert_only_event_approval
};
use token::components::tests::token::erc20::test_erc20_balance::{
    assert_event_transfer, assert_only_event_transfer
};


const L1BRIDGE: felt252 = 'L1BRIDGE';

//
// Setup
//

fn setup() -> (IWorldDispatcher, IDojoTokenDispatcher, IDojoBridgeDispatcher) {
    let world = spawn_test_world(
        array![
            erc_20_allowance_model::TEST_CLASS_HASH,
            erc_20_balance_model::TEST_CLASS_HASH,
            erc_20_metadata_model::TEST_CLASS_HASH,
            erc_20_bridgeable_model::TEST_CLASS_HASH,
            dojo_bridge_model::TEST_CLASS_HASH,
        ]
    );

    // deploy token
    let mut dojo_token_dispatcher = IDojoTokenDispatcher {
        contract_address: world
            .deploy_contract('salt', dojo_token::TEST_CLASS_HASH.try_into().unwrap())
    };

     // deploy bridge
    let mut dojo_bridge_dispatcher = IDojoBridgeDispatcher {
        contract_address: world
            .deploy_contract('salt', dojo_bridge::TEST_CLASS_HASH.try_into().unwrap())
    };

    // setup auth for dojo_token
    world.grant_writer('ERC20AllowanceModel', dojo_token_dispatcher.contract_address);
    world.grant_writer('ERC20BalanceModel', dojo_token_dispatcher.contract_address);
    world.grant_writer('ERC20MetadataModel', dojo_token_dispatcher.contract_address);
    world.grant_writer('ERC20BridgeableModel', dojo_token_dispatcher.contract_address);
   
    // setup auth for dojo_bridge
    world.grant_writer('DojoBridgeModel', dojo_bridge_dispatcher.contract_address);


    // initialize dojo_token
    dojo_token_dispatcher.initializer(NAME, SYMBOL, dojo_bridge_dispatcher.contract_address);
    
    // initialize dojo_bridge
    dojo_bridge_dispatcher.initializer( L1BRIDGE, dojo_token_dispatcher.contract_address);
    dojo_bridge_dispatcher.initializer( L1BRIDGE, dojo_token_dispatcher.contract_address);

    // drop all events
    utils::drop_all_events(dojo_token_dispatcher.contract_address);
    utils::drop_all_events(dojo_bridge_dispatcher.contract_address);
    utils::drop_all_events(world.contract_address);

    (world, dojo_token_dispatcher, dojo_bridge_dispatcher)
}


//
// initializer 
//

#[test]
#[available_gas(30000000)]
fn test_initializers() {
    let (world, mut dojo_token, mut dojo_bridge) = setup();

    assert(dojo_token.total_supply() == 0, 'Should eq 0');
    assert(dojo_token.name() == NAME, 'Name should be NAME');
    assert(dojo_token.symbol() == SYMBOL, 'Symbol should be SYMBOL');
    assert(dojo_token.decimals() == DECIMALS, 'Decimals should be 18');

    assert(dojo_token.l2_bridge_address() == dojo_bridge.contract_address, 'invalid l2_bridge_address');

    assert(dojo_bridge.get_l1_bridge() == L1BRIDGE, 'Should be L1BRIDGE');
    assert(dojo_bridge.get_token() == dojo_token.contract_address, 'Invalid get_token');

}
