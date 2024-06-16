// internal imports
use origami::map::grid::{types::Direction};
use grid_map::models::Position;

// define the interface
#[dojo::interface]
trait IActions {
    fn init_map(game_id: u32, max_x: u32, max_y: u32);
    fn spawn(game_id: u32, x: u32, y: u32);
    fn move(game_id: u32, direction: Direction);
}

#[dojo::interface]
trait IActionsComputed {
    fn next_position(position: Position, direction: Direction) -> Position;
}

// dojo decorator
#[dojo::contract]
mod actions {
    use starknet::{ContractAddress, get_caller_address};
    use origami::map::grid::{grid::{IGridTile}, types::{Direction, DirectionIntoFelt252}};

    use grid_map::models::{Position, Vec2, Map};

    use super::{IActions, IActionsComputed};

    // declaring custom event struct
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Moved: Moved,
        Spawned: Spawned
    }

    // declaring custom event struct
    #[derive(Drop, starknet::Event)]
    struct Moved {
        player: ContractAddress,
        direction: Direction
    }

    #[derive(Drop, starknet::Event)]
    struct Spawned {
        player: ContractAddress,
        vec: Vec2
    }

    #[abi(embed_v0)]
    impl ActionsComputedImpl of IActionsComputed<ContractState> {
        #[computed(Position)]
        fn next_position(position: Position, direction: Direction) -> Position {
            let mut new_position = position;

            // convert to Grid
            let grid_tile = IGridTile::new(position.vec.x, position.vec.y);

            // get next tile
            let next_grid = grid_tile.neighbor(direction);

            // convert back to Position
            new_position.vec = Vec2 { x: next_grid.col, y: next_grid.row };

            new_position
        }
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        // Init the map
        fn init_map(game_id: u32, max_x: u32, max_y: u32) {
            // Access the world dispatcher for reading.
            let world = self.world_dispatcher.read();

            let player = get_caller_address();

            let mut players: Array<Position> = ArrayTrait::new();

            let map = Map { game_id, max_x, max_y, players, };

            // Update the world state with the new moves data and position.
            set!(world, (map));
        }

        // ContractState is defined by system decorator expansion
        fn spawn(game_id: u32, x: u32, y: u32) {
            // Access the world dispatcher for reading.
            let world = self.world_dispatcher.read();
            let player = get_caller_address();

            // Predefined position for later use
            let player_position = Position { player, vec: Vec2 { x, y }, };

            let mut map = get!(world, game_id, (Map));
            assert!(map.max_x >= x, "Position x is out of bounds");
            assert!(map.max_y >= y, "Position y is out of bounds");
            let mut players = map.players;
            if players.len() == 0 {
                players.append(player_position);
            } else {
                let player_snapshot = @players;
                let mut i = 0;
                while i < players.len() {
                    let current_player: Position = *player_snapshot[i];
                    assert!(current_player.player != player, "Player already exists");
                    assert!(current_player.vec != player_position.vec, "Position already taken");
                    if i == players.len() - 1 {
                        players.append(player_position);
                    }
                    i += 1;
                }
            }

            let mut map = get!(world, game_id, (Map));
            let mut new_map = map;
            new_map.players = players;
            set!(world, (player_position));
            set!(world, (new_map));
            emit!(world, (Event::Spawned(Spawned { player, vec: player_position.vec })));
        }

        // Moves player in the provided direction.
        fn move(game_id: u32, direction: Direction) {
            let world = self.world_dispatcher.read();
            let player = get_caller_address();
            let current_position = get!(world, player, (Position));
            let new_vec: Vec2 = {
                match direction {
                    Direction::East => Vec2 {
                        x: current_position.vec.x + 1, y: current_position.vec.y
                    },
                    Direction::North => Vec2 {
                        x: current_position.vec.x, y: current_position.vec.y - 1
                    },
                    Direction::West => Vec2 {
                        x: current_position.vec.x - 1, y: current_position.vec.y
                    },
                    Direction::South => Vec2 {
                        x: current_position.vec.x, y: current_position.vec.y + 1
                    },
                }
            };

            // Predefined position for later use
            let player_position = Position { player, vec: new_vec };
            let mut new_players = array![player_position];

            let mut map = get!(world, game_id, (Map));
            let mut players = map.players;
            assert!(players.len() > 0, "No players in the game");
            let player_snapshot = @players;
            let mut i = 0;
            while i < players.len() {
                let current_player: Position = *player_snapshot[i];
                assert!(current_player.vec != new_vec, "Position already taken");
                // when the code reach this line, it means that the new position is valid
                new_players.append(current_player);
                i += 1;
            };

            map.players = new_players;
            set!(world, (map));
            delete!(world, (current_position));
            set!(world, (player_position));
            emit!(world, (Event::Spawned(Spawned { player, vec: player_position.vec })));
        }
    }
}

// will write test later