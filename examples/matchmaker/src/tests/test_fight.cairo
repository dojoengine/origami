// Core imports

use core::debug::PrintTrait;

// Starknet imports

use starknet::testing::{set_contract_address, set_transaction_hash};

// Dojo imports

use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

// Internal imports

use matchmaker::constants::DEFAULT_RATING;
use matchmaker::store::{Store, StoreTrait};
use matchmaker::models::player::{Player, PlayerTrait, PlayerAssert};
use matchmaker::models::registry::{Registry, RegistryTrait, RegistryAssert};
use matchmaker::models::league::{League, LeagueTrait, LeagueAssert};
use matchmaker::models::slot::{Slot, SlotTrait};
use matchmaker::systems::maker::IMakerDispatcherTrait;
use matchmaker::tests::setup::{setup, setup::Systems};

#[test]
fn test_maker_fight_lose() {
    // [Setup]
    let (world, systems, context) = setup::spawn();
    let store = StoreTrait::new(world);

    // [Create]
    systems.maker.create(world, context.player_name);

    // [Subscribe]
    systems.maker.subscribe(world);

    // [Fight]
    set_transaction_hash(0);
    systems.maker.fight(world);

    // [Assert] Player
    let player = store.player(context.registry_id, context.player_id);
    assert(player.rating != DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Someone
    let someone = store.player(context.registry_id, context.someone_id);
    assert(someone.rating != DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Global rating
    let total = 2 * DEFAULT_RATING;
    assert(player.rating + someone.rating == total, 'Fight: wrong global rating');
}

#[test]
fn test_maker_fight_draw() {
    // [Setup]
    let (world, systems, context) = setup::spawn();
    let store = StoreTrait::new(world);

    // [Create]
    systems.maker.create(world, context.player_name);

    // [Subscribe]
    systems.maker.subscribe(world);

    // [Fight]
    set_transaction_hash(1);
    systems.maker.fight(world);

    // [Assert] Player
    let player = store.player(context.registry_id, context.player_id);
    assert(player.rating == DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Someone
    let someone = store.player(context.registry_id, context.someone_id);
    assert(someone.rating == DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Global rating
    let total = 2 * DEFAULT_RATING;
    assert(player.rating + someone.rating == total, 'Fight: wrong global rating');
}

#[test]
fn test_maker_fight_win() {
    // [Setup]
    let (world, systems, context) = setup::spawn();
    let store = StoreTrait::new(world);

    // [Create]
    systems.maker.create(world, context.player_name);

    // [Subscribe]
    systems.maker.subscribe(world);

    // [Fight]
    set_transaction_hash(2);
    systems.maker.fight(world);

    // [Assert] Player
    let player = store.player(context.registry_id, context.player_id);
    assert(player.rating != DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Someone
    let someone = store.player(context.registry_id, context.someone_id);
    assert(someone.rating != DEFAULT_RATING, 'Fight: wrong player rating');

    // [Assert] Global rating
    let total = 2 * DEFAULT_RATING;
    assert(player.rating + someone.rating == total, 'Fight: wrong global rating');
}

#[test]
fn test_maker_fight_several_times() {
    // [Setup]
    let (world, systems, context) = setup::spawn();
    let store = StoreTrait::new(world);

    // [Create]
    systems.maker.create(world, context.player_name);

    // [Subscribe]
    systems.maker.subscribe(world);

    // [Fight]
    let mut iter = 2;
    loop {
        if iter == 0 {
            break;
        }
        systems.maker.fight(world);
        iter -= 1;
    };

    // [Assert] Global rating
    let total = 2 * DEFAULT_RATING;
    let player = store.player(context.registry_id, context.player_id);
    let someone = store.player(context.registry_id, context.someone_id);
    assert(player.rating + someone.rating == total, 'Fight: wrong global rating');
}
