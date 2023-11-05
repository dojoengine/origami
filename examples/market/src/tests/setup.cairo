// Starknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::world::{IWorldDispatcherTrait, IWorldDispatcher};
use dojo::test_utils::{spawn_test_world, deploy_contract};

// Internal imports

use market::models::cash::{cash, Cash};
use market::models::item::{item, Item};
use market::models::liquidity::{liquidity, Liquidity};
use market::models::market::{market as market_model, Market};
use market::systems::liquidity::{Liquidity as liquidity_actions};
use market::systems::trade::{Trade as trade_actions};

#[derive(Drop)]
struct Systems {
    liquidity: ContractAddress,
    trade: ContractAddress,
}

fn spawn_market() -> (IWorldDispatcher, Systems) {
    // [Setup] World
    let mut models = array::ArrayTrait::new();
    models.append(cash::TEST_CLASS_HASH);
    models.append(item::TEST_CLASS_HASH);
    models.append(liquidity::TEST_CLASS_HASH);
    models.append(market_model::TEST_CLASS_HASH);
    let world = spawn_test_world(models);

    // [Setup] Systems
    let liquidity_address = deploy_contract(liquidity_actions::TEST_CLASS_HASH, array![].span());
    let trade_address = deploy_contract(trade_actions::TEST_CLASS_HASH, array![].span());
    let systems = Systems { liquidity: liquidity_address, trade: trade_address, };

    // [Return]
    (world, systems)
}
