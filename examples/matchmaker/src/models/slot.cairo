// Starknet imports

use starknet::ContractAddress;

// Internal imports

use matchmaker::models::player::{Player, PlayerTrait};

#[derive(Model, Copy, Drop, Serde)]
struct Slot {
    #[key]
    registry_id: u32,
    #[key]
    league_id: u8,
    #[key]
    index: u32,
    player_id: ContractAddress,
}

#[generate_trait]
impl SlotImpl of SlotTrait {
    #[inline(always)]
    fn new(player: Player) -> Slot {
        Slot {
            registry_id: player.registry_id,
            league_id: player.league_id,
            index: player.index,
            player_id: player.id,
        }
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::debug::PrintTrait;

    // Local imports

    use super::{Slot, SlotTrait, Player, PlayerTrait, ContractAddress};

    // Constants

    fn PLAYER() -> ContractAddress {
        starknet::contract_address_const::<'PLAYER'>()
    }

    const REGISTER_ID: u32 = 1;
    const LEAGUE_ID: u8 = 2;
    const INDEX: u32 = 3;

    #[test]
    fn test_new() {
        let player_id = PLAYER();
        let mut player = PlayerTrait::new(REGISTER_ID, player_id);
        player.league_id = LEAGUE_ID;
        player.index = INDEX;
        let slot = SlotTrait::new(player);
        assert_eq!(slot.registry_id, REGISTER_ID);
        assert_eq!(slot.league_id, LEAGUE_ID);
        assert_eq!(slot.index, INDEX);
        assert_eq!(slot.player_id, player_id);
    }
}
