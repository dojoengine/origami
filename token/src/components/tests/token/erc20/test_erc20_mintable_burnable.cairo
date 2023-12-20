use integer::BoundedInt;
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::test_utils::spawn_test_world;
use token::tests::constants::{ZERO, OWNER, SPENDER, RECIPIENT, VALUE};

use token::components::token::erc20::erc20_metadata::{erc_20_metadata_model, ERC20MetadataModel,};
use token::components::token::erc20::erc20_metadata::ERC20MetadataComponent::{
    ERC20MetadataImpl, ERC20MetadataTotalSupplyImpl, InternalImpl as ERC20MetadataInternalImpl
};

use token::components::token::erc20::erc20_balance::{erc_20_balance_model, ERC20BalanceModel,};
use token::components::token::erc20::erc20_balance::ERC20BalanceComponent::{
    ERC20BalanceImpl, InternalImpl as ERC20BalanceInternalImpl
};

use token::components::token::erc20::erc20_mintable::ERC20MintableComponent::InternalImpl as ERC20MintableInternalImpl;
use token::components::token::erc20::erc20_burnable::ERC20BurnableComponent::InternalImpl as ERC20BurnableInternalImpl;

use token::components::tests::mocks::erc20::erc20_mintable_burnable_mock::ERC20MintableBurnableMock;
use token::components::tests::mocks::erc20::erc20_mintable_burnable_mock::ERC20MintableBurnableMock::world_dispatcherContractMemberStateTrait;


fn STATE() -> (IWorldDispatcher, ERC20MintableBurnableMock::ContractState) {
    let world = spawn_test_world(
        array![erc_20_metadata_model::TEST_CLASS_HASH, erc_20_balance_model::TEST_CLASS_HASH,]
    );

    let mut state = ERC20MintableBurnableMock::contract_state_for_testing();
    state.world_dispatcher.write(world);

    (world, state)
}

#[test]
#[available_gas(100000000)]
fn test_erc20_mintable__mint() {
    let (world, mut state) = STATE();

    let total_supply = state.total_supply();
    state.erc20_mintable._mint(RECIPIENT(), VALUE);
    let total_supply_after = state.total_supply();

    assert(state.balance_of(RECIPIENT()) == VALUE, 'invalid balance_of');
    assert(total_supply_after == total_supply + VALUE, 'invalid total_supply');
}

#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: mint to 0',))]
fn test_erc20_mintable__mint_to_zero() {
    let (world, mut state) = STATE();
    state.erc20_mintable._mint(ZERO(), VALUE);
}


#[test]
#[available_gas(100000000)]
fn test_erc20_burnable__burn() {
    let (world, mut state) = STATE();

    let total_supply = state.total_supply();
    state.erc20_mintable._mint(RECIPIENT(), VALUE);
    let total_supply_after_mint = state.total_supply();

    state.erc20_burnable._burn(RECIPIENT(), VALUE);
    let total_supply_after_burn = state.total_supply();

    assert(state.balance_of(RECIPIENT()) == 0, 'invalid balance_of');
    assert(total_supply_after_mint == total_supply + VALUE, 'invalid total_supply');
    assert(total_supply_after_burn == total_supply, 'invalid total_supply');
}


#[test]
#[available_gas(100000000)]
#[should_panic(expected: ('ERC20: burn from 0',))]
fn test_erc20_burnable__burn_from_zero() {
    let (world, mut state) = STATE();
    state.erc20_burnable._burn(ZERO(), VALUE);
}
// TODO test events


