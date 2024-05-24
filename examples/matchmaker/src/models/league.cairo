use core::option::OptionTrait;
// Starknet imports

use starknet::ContractAddress;

// Internal imports

use matchmaker::constants::{LEAGUE_SIZE, LEAGUE_COUNT, LEAGUE_MIN_THRESHOLD};
use matchmaker::models::player::{Player, PlayerTrait, PlayerAssert};
use matchmaker::models::slot::{Slot, SlotTrait};

// Errors

mod errors {
    const LEAGUE_NOT_SUBSCRIBED: felt252 = 'League: player not subscribed';
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct League {
    #[key]
    registry_id: u32,
    #[key]
    id: u8,
    size: u32,
}

#[generate_trait]
impl LeagueImpl of LeagueTrait {
    #[inline(always)]
    fn new(registry_id: u32, league_id: u8) -> League {
        League { registry_id, id: league_id, size: 0, }
    }

    #[inline(always)]
    fn compute_id(rating: u32) -> u8 {
        if rating <= LEAGUE_MIN_THRESHOLD {
            return 1;
        }
        let max_rating = LEAGUE_MIN_THRESHOLD + LEAGUE_SIZE.into() * LEAGUE_COUNT.into();
        if rating >= max_rating {
            return LEAGUE_COUNT;
        }
        let id = 1 + (rating - LEAGUE_MIN_THRESHOLD) / LEAGUE_SIZE.into();
        if id > 251 {
            251
        } else if id < 1 {
            1
        } else {
            id.try_into().unwrap()
        }
    }

    #[inline(always)]
    fn subscribe(ref self: League, ref player: Player) -> Slot {
        // [Check] Player can subscribe
        PlayerAssert::assert_subscribable(player);
        // [Effect] Update
        let index = self.size;
        self.size += 1;
        player.league_id = self.id;
        player.index = index;
        // [Return] Corresponding slot
        SlotTrait::new(player)
    }

    #[inline(always)]
    fn unsubscribe(ref self: League, ref player: Player) {
        // [Check] Player belongs to the league
        LeagueAssert::assert_subscribed(self, player);
        // [Effect] Update
        self.size -= 1;
        player.league_id = 0;
        player.index = 0;
    }

    #[inline(always)]
    fn search_player(self: League, seed: felt252) -> u32 {
        let seed: u256 = seed.into();
        let index = seed % self.size.into();
        index.try_into().unwrap()
    }
}

#[generate_trait]
impl LeagueAssert of AssertTrait {
    #[inline(always)]
    fn assert_subscribed(self: League, player: Player) {
        assert(player.league_id == self.id, errors::LEAGUE_NOT_SUBSCRIBED);
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::debug::PrintTrait;

    // Local imports

    use super::{
        League, LeagueTrait, Player, PlayerTrait, ContractAddress, LEAGUE_SIZE, LEAGUE_COUNT,
        LEAGUE_MIN_THRESHOLD
    };

    // Constants

    fn PLAYER() -> ContractAddress {
        starknet::contract_address_const::<'PLAYER'>()
    }

    const PLAYER_NAME: felt252 = 'NAME';
    const REGISTRY_ID: u32 = 1;
    const LEAGUE_ID: u8 = 1;

    #[test]
    fn test_new() {
        let league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        assert_eq!(league.registry_id, REGISTRY_ID);
        assert_eq!(league.id, LEAGUE_ID);
        assert_eq!(league.size, 0);
    }

    #[test]
    fn test_compute_id() {
        let rating = LEAGUE_MIN_THRESHOLD - 1;
        let league_id = LeagueTrait::compute_id(rating);
        assert_eq!(league_id, 1);
    }

    #[test]
    fn test_compute_id_overflow() {
        let max_rating = LEAGUE_MIN_THRESHOLD + LEAGUE_SIZE.into() * LEAGUE_COUNT.into() + 1;
        let league_id = LeagueTrait::compute_id(max_rating);
        assert_eq!(league_id, LEAGUE_COUNT);
    }

    #[test]
    fn test_compute_id_underflow() {
        let rating = 0;
        let league_id = LeagueTrait::compute_id(rating);
        assert_eq!(league_id, 1);
    }

    #[test]
    fn test_subscribe_once() {
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let slot = LeagueTrait::subscribe(ref league, ref player);
        // [Assert] League
        assert_eq!(league.size, 1);
        // [Assert] Player
        assert_eq!(player.league_id, LEAGUE_ID);
        assert_eq!(player.index, 0);
        // [Assert] Slot
        assert_eq!(slot.player_id, player.id);
    }

    #[test]
    #[should_panic(expected: ('Player: not subscribable',))]
    fn test_subscribe_twice() {
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        LeagueTrait::subscribe(ref league, ref player);
        LeagueTrait::subscribe(ref league, ref player);
    }

    #[test]
    fn test_unsubscribe_once() {
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        LeagueTrait::subscribe(ref league, ref player);
        LeagueTrait::unsubscribe(ref league, ref player);
        // [Assert] League
        assert_eq!(league.size, 0);
        // [Assert] Player
        assert_eq!(player.league_id, 0);
        assert_eq!(player.index, 0);
    }

    #[test]
    #[should_panic(expected: ('League: player not subscribed',))]
    fn test_unsubscribe_twice() {
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        LeagueTrait::subscribe(ref league, ref player);
        LeagueTrait::unsubscribe(ref league, ref player);
        LeagueTrait::unsubscribe(ref league, ref player);
    }
}
