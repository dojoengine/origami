// internal imports
use core::Into;
use origami::map::hex::{types::Direction};

// define the interface
#[starknet::interface]
trait IActions<TContractState> {
    fn spawn(self: @TContractState);
    fn move(self: @TContractState, direction: Direction);
}

// dojo decorator
#[dojo::contract]
mod actions {
    use starknet::{ContractAddress, get_caller_address};
    use origami::map::hex::{hex::{IHexTile}, types::{Direction, DirectionIntoFelt252}};

    use hex_map::models::{Position, Vec2};
    use hex_map::noise::{ITile};

    use super::IActions;

    // declaring custom event struct
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Moved: Moved,
    }

    // declaring custom event struct
    #[derive(Drop, starknet::Event)]
    struct Moved {
        player: ContractAddress,
        direction: Direction
    }

    fn next_position(position: Position, direction: Direction) -> Position {
        let mut new_position = position;

        // convert to Hex
        let hex_tile = IHexTile::new(position.vec.x, position.vec.y);

        // get next next tile
        let next_hex = hex_tile.neighbor(direction);

        // check movable
        ITile::check_moveable(next_hex);

        // convert back to Position
        new_position.vec = Vec2 { x: next_hex.col, y: next_hex.row };

        new_position
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        // ContractState is defined by system decorator expansion
        fn spawn(self: @ContractState) { // Access the world dispatcher for reading.
            let world = self.world_dispatcher.read();

            set!(world, (Position { player: get_caller_address(), vec: Vec2 { x: 10, y: 10 } }));
        }
        // Moves player in the provided direction.
        fn move(self: @ContractState, direction: Direction) {
            // Access the world dispatcher for reading.
            let world = self.world_dispatcher.read();

            // Get the address of the current caller, possibly the player's address.
            let player = get_caller_address();

            // Retrieve the player's current position and moves data from the world.
            let mut position = get!(world, player, (Position));

            // // Calculate the player's next position based on the provided direction.
            let next = next_position(position, direction);

            // Update the world state with the new moves data and position.
            set!(world, (next));

            // Emit an event to the world to notify about the player's move.
            emit!(world, Moved { player, direction });
        }
    }
}
#[cfg(test)]
mod tests {
    use debug::PrintTrait;
    use starknet::class_hash::Felt252TryIntoClassHash;

    // import world dispatcher
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};

    // import test utils
    use dojo::test_utils::{spawn_test_world, deploy_contract};

    // import models
    use hex_map::models::{position};
    use hex_map::models::{Position, Direction, Vec2};

    // import actions
    use super::{actions, IActionsDispatcher, IActionsDispatcherTrait};

    fn setup_world() -> (IWorldDispatcher, IActionsDispatcher) {
        // models
        let mut models = array![position::TEST_CLASS_HASH];

        // deploy world with models
        let world = spawn_test_world(models);

        // deploy systems contract
        let contract_address = world
            .deploy_contract('salt', actions::TEST_CLASS_HASH.try_into().unwrap());
        let actions_system = IActionsDispatcher { contract_address };

        (world, actions_system)
    }

    #[test]
    #[available_gas(30000000)]
    fn test_east() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::East(()));

        // get new_position
        let new_position = get!(world, caller, Position);

        // check new position x
        assert(new_position.vec.x == 11, 'position x is wrong');

        // check new position y
        assert(new_position.vec.y == 10, 'position y is wrong');
    }


    #[test]
    #[should_panic(expected: ('Cannot walk on water', 'ENTRYPOINT_FAILED'))]
    #[available_gas(30000000)]
    fn test_south_east() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::SouthEast(()));

        // get new_position
        let new_position = get!(world, caller, Position);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_south() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::SouthWest(()));

        // get new_position
        let new_position = get!(world, caller, Position);

        // check new position x
        assert(new_position.vec.x == 10, 'position x is wrong');

        // check new position y
        assert(new_position.vec.y == 11, 'position y is wrong');
    }
    #[test]
    #[should_panic(expected: ('Cannot walk on water', 'ENTRYPOINT_FAILED'))]
    #[available_gas(30000000)]
    fn test_north() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::West(()));

        // get new_position
        let new_position = get!(world, caller, Position);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_north_west() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::NorthWest(()));

        // get new_position
        let new_position = get!(world, caller, Position);

        // check new position x
        assert(new_position.vec.x == 10, 'position x is wrong');

        // check new position y
        assert(new_position.vec.y == 9, 'position y is wrong');
    }

    #[test]
    #[should_panic(expected: ('Cannot walk on water', 'ENTRYPOINT_FAILED'))]
    #[available_gas(30000000)]
    fn test_north_east() {
        // caller
        let caller = starknet::contract_address_const::<0x0>();

        let (world, actions_system) = setup_world();

        // call spawn()
        actions_system.spawn();

        // call move with direction right
        actions_system.move(Direction::NorthEast(()));

        // get new_position
        let new_position = get!(world, caller, Position);
    }
}

