// Core imports

use debug::PrintTrait;

// Dojo imports

use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

// Internal imports

use market::models::cash::Cash;
use market::models::item::Item;
use market::models::liquidity::Liquidity;
use market::models::market::{Market, MarketTrait};
use market::tests::{setup, setup::Systems};

#[test]
fn test_market_spawn() {
    // [Setup]
    let (_world, _systems) = setup::spawn_market();
}
