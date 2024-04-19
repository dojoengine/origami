//! Store struct and component management methods.

// Core imports

use core::debug::PrintTrait;

// Straknet imports

use starknet::ContractAddress;

// Dojo imports

use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

// Models imports

use matchmaker::models::league::{League, LeagueTrait};
use matchmaker::models::player::Player;
use matchmaker::models::registry::Registry;
use matchmaker::models::slot::Slot;


/// Store struct.
#[derive(Copy, Drop)]
struct Store {
    world: IWorldDispatcher,
}

/// Implementation of the `StoreTrait` trait for the `Store` struct.
#[generate_trait]
impl StoreImpl of StoreTrait {
    #[inline(always)]
    fn new(world: IWorldDispatcher) -> Store {
        Store { world: world }
    }

    #[inline(always)]
    fn registry(self: Store, registry_id: u32,) -> Registry {
        get!(self.world, registry_id, (Registry))
    }

    #[inline(always)]
    fn league(self: Store, registry_id: u32, league_id: u8) -> League {
        get!(self.world, (registry_id, league_id), (League))
    }

    #[inline(always)]
    fn slot(self: Store, registry_id: u32, league_id: u8, index: u32) -> Slot {
        get!(self.world, (registry_id, league_id, index), (Slot))
    }

    #[inline(always)]
    fn player(self: Store, registry_id: u32, player_id: ContractAddress) -> Player {
        get!(self.world, (registry_id, player_id), (Player))
    }

    #[inline(always)]
    fn set_registry(self: Store, registry: Registry) {
        set!(self.world, (registry))
    }

    #[inline(always)]
    fn set_league(self: Store, league: League) {
        set!(self.world, (league))
    }

    #[inline(always)]
    fn set_slot(self: Store, slot: Slot) {
        set!(self.world, (slot))
    }

    #[inline(always)]
    fn set_player(self: Store, player: Player) {
        set!(self.world, (player))
    }

    #[inline(always)]
    fn remove_player_slot(self: Store, player: Player) {
        // [Effect] Replace the slot with the last slot if needed
        let mut league = self.league(player.registry_id, player.league_id);
        let mut last_slot = self.slot(league.registry_id, player.league_id, league.size - 1);
        if last_slot.player_id != player.id {
            last_slot.index = player.index;
            self.set_slot(last_slot);
        }
        // [Effect] Remove the last slot
        let mut empty_slot = self.slot(league.registry_id, player.league_id, league.size);
        empty_slot.index = league.size - 1;
        self.set_slot(empty_slot);
    }
}
