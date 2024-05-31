// Core imports

use core::zeroable::Zeroable;

// Starknet imports

use starknet::ContractAddress;

// External imports

use origami::rating::elo::EloTrait;

// Internal imports

use matchmaker::constants::{ZERO, DEFAULT_RATING, DEFAULT_K_FACTOR};

// Errors

mod errors {
    const PLAYER_DOES_NOT_EXIST: felt252 = 'Player: does not exist';
    const PLAYER_ALREADY_EXIST: felt252 = 'Player: already exist';
    const PLAYER_NOT_SUBSCRIBABLE: felt252 = 'Player: not subscribable';
    const PLAYER_NOT_SUBSCRIBED: felt252 = 'Player: not subscribed';
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Player {
    #[key]
    registry_id: u32,
    #[key]
    id: ContractAddress,
    name: felt252,
    league_id: u8,
    index: u32,
    rating: u32,
}

#[generate_trait]
impl PlayerImpl of PlayerTrait {
    #[inline(always)]
    fn new(registry_id: u32, id: ContractAddress, name: felt252) -> Player {
        Player { registry_id, id, name, league_id: 0, index: 0, rating: DEFAULT_RATING, }
    }

    #[inline(always)]
    fn fight(ref self: Player, ref foe: Player, seed: felt252) {
        let win: u8 = (seed.into() % 3_u256).try_into().unwrap();
        let score: u16 = match win {
            0 => 0, // Lose
            1 => 50, // Draw
            2 => 100, // Win
            _ => 0,
        };
        let (change, negative) = EloTrait::rating_change(
            self.rating, foe.rating, score, DEFAULT_K_FACTOR
        );
        if negative {
            self.rating -= change;
            foe.rating += change;
        } else {
            self.rating += change;
            foe.rating -= change;
        };
    }
}

#[generate_trait]
impl PlayerAssert of AssertTrait {
    #[inline(always)]
    fn assert_does_exist(player: Player) {
        assert(player.is_non_zero(), errors::PLAYER_DOES_NOT_EXIST);
    }

    #[inline(always)]
    fn assert_not_exist(player: Player) {
        assert(player.is_zero(), errors::PLAYER_ALREADY_EXIST);
    }

    #[inline(always)]
    fn assert_subscribable(player: Player) {
        assert(player.league_id == 0, errors::PLAYER_NOT_SUBSCRIBABLE);
    }

    #[inline(always)]
    fn assert_subscribed(player: Player) {
        assert(player.league_id != 0, errors::PLAYER_NOT_SUBSCRIBED);
    }
}

impl PlayerZeroable of Zeroable<Player> {
    #[inline(always)]
    fn zero() -> Player {
        Player { registry_id: 0, id: ZERO(), name: 0, league_id: 0, index: 0, rating: 0, }
    }

    #[inline(always)]
    fn is_zero(self: Player) -> bool {
        self.league_id == 0 && self.index == 0 && self.rating == 0
    }

    #[inline(always)]
    fn is_non_zero(self: Player) -> bool {
        !self.is_zero()
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::debug::PrintTrait;

    // Local imports

    use super::{Player, PlayerTrait, DEFAULT_RATING, ContractAddress, AssertTrait};

    // Constants

    fn PLAYER() -> ContractAddress {
        starknet::contract_address_const::<'PLAYER'>()
    }

    const PLAYER_NAME: felt252 = 'NAME';
    const REGISTRY_ID: u32 = 1;

    #[test]
    fn test_new() {
        let player_id = PLAYER();
        let player = PlayerTrait::new(REGISTRY_ID, player_id, PLAYER_NAME);
        assert_eq!(player.registry_id, REGISTRY_ID);
        assert_eq!(player.id, player_id);
        assert_eq!(player.league_id, 0);
        assert_eq!(player.index, 0);
        assert_eq!(player.rating, DEFAULT_RATING);
    }

    #[test]
    fn test_subscribable() {
        let player_id = PLAYER();
        let player = PlayerTrait::new(REGISTRY_ID, player_id, PLAYER_NAME);
        AssertTrait::assert_subscribable(player);
    }

    #[test]
    #[should_panic(expected: ('Player: not subscribable',))]
    fn test_subscribable_revert_not_subscribable() {
        let player_id = PLAYER();
        let mut player = PlayerTrait::new(REGISTRY_ID, player_id, PLAYER_NAME);
        player.league_id = 1;
        AssertTrait::assert_subscribable(player);
    }

    #[test]
    fn test_subscribed() {
        let player_id = PLAYER();
        let mut player = PlayerTrait::new(REGISTRY_ID, player_id, PLAYER_NAME);
        player.league_id = 1;
        AssertTrait::assert_subscribed(player);
    }

    #[test]
    #[should_panic(expected: ('Player: not subscribed',))]
    fn test_subscribed_revert_not_subscribed() {
        let player_id = PLAYER();
        let player = PlayerTrait::new(REGISTRY_ID, player_id, PLAYER_NAME);
        AssertTrait::assert_subscribed(player);
    }
}
