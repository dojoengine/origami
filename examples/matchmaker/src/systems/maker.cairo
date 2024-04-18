// Starknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::world::IWorldDispatcher;

// Interface

#[dojo::interface]
trait IMaker {
    fn create();
    fn subscribe();
    fn unsubscribe();
    fn fight();
}

// Contract

#[dojo::contract]
mod maker {
    // Core imports

    use core::array::ArrayTrait;
    use core::debug::PrintTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::info::{get_caller_address, get_tx_info};

    // Internal imports

    use matchmaker::store::{Store, StoreTrait};
    use matchmaker::models::player::{Player, PlayerTrait, PlayerAssert};
    use matchmaker::models::league::{League, LeagueTrait, LeagueAssert};
    use matchmaker::models::registry::{Registry, RegistryTrait, RegistryAssert};
    use matchmaker::models::slot::{Slot, SlotTrait};

    // Local imports

    use super::IMaker;

    // Errors

    mod errors {
        const CHARACTER_DUPLICATE: felt252 = 'Battle: character duplicate';
    }

    // Implementations

    #[abi(embed_v0)]
    impl MakerImpl of IMaker<ContractState> {
        fn create(world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player does not exist
            let caller = get_caller_address();
            let player = store.player(0, caller);
            PlayerAssert::assert_not_exist(player);

            // [Effect] Create one
            let player = PlayerTrait::new(0, caller);
            store.set_player(player);
        }

        fn subscribe(world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player exists
            let caller = get_caller_address();
            let mut player = store.player(0, caller);
            PlayerAssert::assert_does_exist(player);

            // [Effect] Subscribe to Registry
            let league_id = LeagueTrait::compute_id(player.rating);
            let mut league = store.league(0, league_id);
            let mut registry = store.registry(0);
            let slot = registry.subscribe(ref league, ref player);

            // [Effect] Update Slot
            store.set_slot(slot);

            // [Effect] Update Player
            store.set_player(player);

            // [Effect] Update League
            store.set_league(league);

            // [Effect] Update Registry
            store.set_registry(registry);
        }

        fn unsubscribe(world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player exists
            let caller = get_caller_address();
            let mut player = store.player(0, caller);
            PlayerAssert::assert_does_exist(player);

            // [Effect] Unsubscribe to Registry
            let mut league = store.league(0, player.league_id);
            let mut registry = store.registry(0);
            registry.unsubscribe(ref league, ref player);

            // [Effect] Update Player
            store.set_player(player);

            // [Effect] Update League
            store.set_league(league);

            // [Effect] Update Registry
            store.set_registry(registry);
        }

        fn fight(world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player exists
            let caller = get_caller_address();
            let mut player = store.player(0, caller);
            PlayerAssert::assert_does_exist(player);

            // [Compute] Search opponent
            let seed = get_tx_info().unbox().transaction_hash;
            let mut registry = store.registry(0);
            let mut player_league = store.league(0, player.league_id);
            let foe_league_id = registry.search_league(player_league, player);
            let mut foe_league = store.league(0, foe_league_id);
            let foe_slot_id = foe_league.search_player(seed);
            let foe_slot = store.slot(0, foe_league_id, foe_slot_id);
            let mut foe = store.player(0, foe_slot.player_id);

            // [Effect] Fight
            player.fight(ref foe, seed);

            // [Effect] Update Player league and slot
            registry.unsubscribe(ref player_league, ref player);
            let league_id = LeagueTrait::compute_id(player.rating);
            let mut player_league = store.league(0, league_id);
            let player_slot = registry.subscribe(ref player_league, ref player);

            // [Effect] Update Foe league and slot
            registry.unsubscribe(ref foe_league, ref foe);
            let foe_league_id = LeagueTrait::compute_id(foe.rating);
            let mut foe_league = store.league(0, foe_league_id);
            let foe_slot = registry.subscribe(ref foe_league, ref foe);

            // [Effect] Update Slots
            store.set_slot(player_slot);
            store.set_slot(foe_slot);

            // [Effect] Update Players
            store.set_player(player);
            store.set_player(foe);

            // [Effect] Update League
            store.set_league(player_league);
            store.set_league(foe_league);

            // [Effect] Update Registry
            store.set_registry(registry);
        }
    }
}
