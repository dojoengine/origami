// Starknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::world::IWorldDispatcher;

// Interface

#[starknet::interface]
trait IMaker<TContractState> {
    fn create(self: @TContractState, world: IWorldDispatcher, name: felt252);
    fn subscribe(self: @TContractState, world: IWorldDispatcher);
    fn unsubscribe(self: @TContractState, world: IWorldDispatcher);
    fn fight(self: @TContractState, world: IWorldDispatcher);
}

// Contract

#[starknet::contract]
mod maker {
    // Core imports

    use core::array::ArrayTrait;
    use core::debug::PrintTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::info::{get_caller_address, get_tx_info};

    // Dojo imports

    use dojo::world;
    use dojo::world::IWorldDispatcher;
    use dojo::world::IWorldDispatcherTrait;
    use dojo::world::IWorldProvider;
    use dojo::world::IDojoResourceProvider;

    // Internal imports

    use matchmaker::constants::WORLD;
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

    // Storage

    #[storage]
    struct Storage {}

    // Implementations

    #[abi(embed_v0)]
    impl DojoResourceProviderImpl of IDojoResourceProvider<ContractState> {
        fn dojo_resource(self: @ContractState) -> felt252 {
            'account'
        }
    }

    #[abi(embed_v0)]
    impl WorldProviderImpl of IWorldProvider<ContractState> {
        fn world(self: @ContractState) -> IWorldDispatcher {
            IWorldDispatcher { contract_address: WORLD() }
        }
    }

    #[abi(embed_v0)]
    impl MakerImpl of IMaker<ContractState> {
        fn create(self: @ContractState, world: IWorldDispatcher, name: felt252) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player does not exist
            let caller = get_caller_address();
            let player = store.player(0, caller);
            PlayerAssert::assert_not_exist(player);

            // [Effect] Create one
            let player = PlayerTrait::new(0, caller, name);
            store.set_player(player);
        }

        fn subscribe(self: @ContractState, world: IWorldDispatcher) {
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

        fn unsubscribe(self: @ContractState, world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player exists
            let caller = get_caller_address();
            let mut player = store.player(0, caller);
            PlayerAssert::assert_does_exist(player);

            // [Effect] Remove slot
            store.remove_player_slot(player);

            // [Effect] Unsubscribe to Registry
            let mut league = store.league(player.registry_id, player.league_id);
            let mut registry = store.registry(player.registry_id);
            registry.unsubscribe(ref league, ref player);

            // [Effect] Update Player
            store.set_player(player);

            // [Effect] Update League
            store.set_league(league);

            // [Effect] Update Registry
            store.set_registry(registry);
        }

        fn fight(self: @ContractState, world: IWorldDispatcher) {
            // [Setup] Datastore
            let mut store: Store = StoreTrait::new(world);

            // [Check] Player exists
            let caller = get_caller_address();
            let mut player = store.player(0, caller);
            PlayerAssert::assert_does_exist(player);

            // [Effect] Remove slot
            store.remove_player_slot(player);

            // [Effect] Search opponent which unsubscribe, then update league
            let seed = get_tx_info().unbox().transaction_hash;
            let mut registry = store.registry(0);
            let mut player_league = store.league(0, player.league_id);
            let foe_league_id = registry.search_league(ref player_league, ref player);
            store.set_league(player_league);

            // [Compute] Foe
            let mut foe_league = store.league(0, foe_league_id);
            let foe_slot_id = foe_league.search_player(seed);
            let foe_slot = store.slot(0, foe_league_id, foe_slot_id);
            let mut foe = store.player(0, foe_slot.player_id);

            // [Effect] Remove foe slot, unsubscribe and update league
            store.remove_player_slot(foe);
            registry.unsubscribe(ref foe_league, ref foe);
            store.set_league(foe_league);

            // [Effect] Fight and update players
            player.fight(ref foe, seed);

            // [Effect] Update player, league and slot
            let league_id = LeagueTrait::compute_id(player.rating);
            let mut league = store.league(0, league_id);
            let slot = registry.subscribe(ref league, ref player);
            store.set_league(league);
            store.set_slot(slot);
            store.set_player(player);

            // [Effect] Update Foe, league and slot
            let league_id = LeagueTrait::compute_id(foe.rating);
            let mut league = store.league(0, league_id);
            let slot = registry.subscribe(ref league, ref foe);
            store.set_league(league);
            store.set_slot(slot);
            store.set_player(foe);

            // [Effect] Update Registry
            store.set_registry(registry);
        }
    }
}
