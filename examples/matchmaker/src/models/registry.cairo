// Starknet imports

use starknet::ContractAddress;

// Internal imports

use matchmaker::constants::{LEAGUE_SIZE, DEFAULT_RATING};
use matchmaker::store::{Store, StoreTrait};
use matchmaker::models::league::{League, LeagueTrait};
use matchmaker::models::player::{Player, PlayerTrait, PlayerAssert};
use matchmaker::models::slot::{Slot, SlotTrait};
use matchmaker::helpers::bitmap::Bitmap;

// Errors

mod errors {
    const REGISTRY_INVALID_INDEX: felt252 = 'Registry: invalid bitmap index';
    const REGISTRY_IS_EMPTY: felt252 = 'Registry: is empty';
    const REGISTRY_LEAGUE_NOT_FOUND: felt252 = 'Registry: league not found';
}

#[derive(Model, Copy, Drop, Serde)]
struct Registry {
    #[key]
    id: u32,
    leagues: felt252,
}

#[generate_trait]
impl RegistryImpl of RegistryTrait {
    #[inline(always)]
    fn new(id: u32) -> Registry {
        Registry { id, leagues: 0 }
    }

    #[inline(always)]
    fn subscribe(ref self: Registry, ref league: League, ref player: Player) -> Slot {
        let slot = league.subscribe(ref player);
        Private::update(ref self, league.id, league.size);
        slot
    }

    #[inline(always)]
    fn unsubscribe(ref self: Registry, ref league: League, ref player: Player) {
        league.unsubscribe(ref player);
        Private::update(ref self, league.id, league.size);
    }

    #[inline(always)]
    fn search_league(ref self: Registry, ref league: League, ref player: Player) -> u8 {
        // [Check] Player has subscribed
        PlayerAssert::assert_subscribed(player);
        // [Effect] Unsubcribe player from his league
        self.unsubscribe(ref league, ref player);
        // [Check] Registry is not empty
        RegistryAssert::assert_not_empty(self);
        // [Compute] Loop over the bitmap to find the nearest league with at least 1 player
        match Bitmap::nearest_significant_bit(self.leagues.into(), league.id) {
            Option::Some(bit) => bit,
            Option::None => {
                panic(array![errors::REGISTRY_LEAGUE_NOT_FOUND]);
                0
            },
        }
    }
}

#[generate_trait]
impl Private of PrivateTrait {
    #[inline(always)]
    fn update(ref registry: Registry, index: u8, count: u32,) {
        let bit = Bitmap::get_bit_at(registry.leagues.into(), index.into());
        let new_bit = count != 0;
        if bit != new_bit {
            let leagues = Bitmap::set_bit_at(registry.leagues.into(), index.into(), new_bit);
            registry.leagues = leagues.try_into().expect(errors::REGISTRY_INVALID_INDEX);
        }
    }
}

#[generate_trait]
impl RegistryAssert of AssertTrait {
    #[inline(always)]
    fn assert_not_empty(registry: Registry) {
        // [Check] Registry is not empty
        assert(registry.leagues.into() > 0_u256, errors::REGISTRY_IS_EMPTY);
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::debug::PrintTrait;

    // Local imports

    use super::{
        Registry, RegistryTrait, PrivateTrait, League, LeagueTrait, Slot, SlotTrait, Player,
        PlayerTrait, ContractAddress
    };

    // Constants

    fn PLAYER() -> ContractAddress {
        starknet::contract_address_const::<'PLAYER'>()
    }

    fn TARGET() -> ContractAddress {
        starknet::contract_address_const::<'TARGET'>()
    }

    const PLAYER_NAME: felt252 = 'NAME';
    const REGISTRY_ID: u32 = 1;
    const LEAGUE_ID: u8 = 1;
    const CLOSEST_LEAGUE_ID: u8 = 2;
    const TARGET_LEAGUE_ID: u8 = 100;
    const FAREST_LEAGUE_ID: u8 = 251;
    const INDEX: u8 = 3;

    #[test]
    fn test_new() {
        let registry = RegistryTrait::new(REGISTRY_ID);
        assert_eq!(registry.id, REGISTRY_ID);
        assert_eq!(registry.leagues, 0);
    }

    #[test]
    fn test_subscribe() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        registry.subscribe(ref league, ref player);
        // [Assert] Registry
        assert(registry.leagues.into() > 0_u256, 'Registry: wrong leagues value');
    }

    #[test]
    fn test_unsubscribe() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        registry.subscribe(ref league, ref player);
        registry.unsubscribe(ref league, ref player);
        // [Assert] Registry
        assert_eq!(registry.leagues, 0);
    }

    #[test]
    fn test_search_league_same() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        let mut foe = PlayerTrait::new(REGISTRY_ID, TARGET(), PLAYER_NAME);
        registry.subscribe(ref league, ref foe);
        let league_id = registry.search_league(ref league, ref player);
        // [Assert] Registry
        assert(league_id == LEAGUE_ID, 'Registry: wrong search league');
    }

    #[test]
    fn test_search_league_close() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        let mut foe_league = LeagueTrait::new(REGISTRY_ID, CLOSEST_LEAGUE_ID);
        let mut foe = PlayerTrait::new(REGISTRY_ID, TARGET(), PLAYER_NAME);
        registry.subscribe(ref foe_league, ref foe);
        let league_id = registry.search_league(ref league, ref player);
        // [Assert] Registry
        assert(league_id == CLOSEST_LEAGUE_ID, 'Registry: wrong search league');
    }

    #[test]
    fn test_search_league_target() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        let mut foe_league = LeagueTrait::new(REGISTRY_ID, TARGET_LEAGUE_ID);
        let mut foe = PlayerTrait::new(REGISTRY_ID, TARGET(), PLAYER_NAME);
        registry.subscribe(ref foe_league, ref foe);
        let league_id = registry.search_league(ref league, ref player);
        // [Assert] Registry
        assert(league_id == TARGET_LEAGUE_ID, 'Registry: wrong search league');
    }

    #[test]
    fn test_search_league_far_down_top() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        let mut foe_league = LeagueTrait::new(REGISTRY_ID, FAREST_LEAGUE_ID);
        let mut foe = PlayerTrait::new(REGISTRY_ID, TARGET(), PLAYER_NAME);
        registry.subscribe(ref foe_league, ref foe);
        let league_id = registry.search_league(ref league, ref player);
        // [Assert] Registry
        assert(league_id == FAREST_LEAGUE_ID, 'Registry: wrong search league');
    }

    #[test]
    fn test_search_league_far_top_down() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, FAREST_LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        let mut foe_league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut foe = PlayerTrait::new(REGISTRY_ID, TARGET(), PLAYER_NAME);
        registry.subscribe(ref foe_league, ref foe);
        let league_id = registry.search_league(ref league, ref player);
        // [Assert] Registry
        assert(league_id == LEAGUE_ID, 'Registry: wrong search league');
    }

    #[test]
    #[should_panic(expected: ('Registry: is empty',))]
    fn test_search_league_revert_empty() {
        let mut registry = RegistryTrait::new(REGISTRY_ID);
        let mut league = LeagueTrait::new(REGISTRY_ID, LEAGUE_ID);
        let mut player = PlayerTrait::new(REGISTRY_ID, PLAYER(), PLAYER_NAME);
        registry.subscribe(ref league, ref player);
        registry.search_league(ref league, ref player);
    }
}
