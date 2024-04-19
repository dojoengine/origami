// Core imports

use core::debug::PrintTrait;

// Starknet imports

use starknet::testing::set_contract_address;

// Dojo imports

use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

// Internal imports

use matchmaker::store::{Store, StoreTrait};
use matchmaker::models::player::{Player, PlayerTrait, PlayerAssert};
use matchmaker::models::registry::{Registry, RegistryTrait, RegistryAssert};
use matchmaker::models::league::{League, LeagueTrait, LeagueAssert};
use matchmaker::models::slot::{Slot, SlotTrait};
use matchmaker::systems::maker::IMakerDispatcherTrait;
use matchmaker::tests::setup::{setup, setup::Systems};

#[test]
fn test_maker_fight() {
    // [Setup]
    let (world, systems, context) = setup::spawn();
    let store = StoreTrait::new(world);

    // [Create]
    systems.maker.create(world);

    // [Subscribe]
    systems.maker.subscribe(world);

    // [Fight]
    let player = store.player(context.registry_id, context.player_id);
    let rating = player.rating;
    systems.maker.fight(world);

    // [Assert] Player
    let player = store.player(context.registry_id, context.player_id);
    assert(player.rating != rating, 'Fight: wrong player rating');
}
