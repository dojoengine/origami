use starknet::ContractAddress;

#[starknet::interface]
trait IActions<ContractState> {
    fn move(
        self: @ContractState,
        curr_position: (u32, u32),
        next_position: (u32, u32),
        caller: ContractAddress, //player
        game_id: u32
    );
    fn spawn(
        self: @ContractState, white_address: ContractAddress, black_address: ContractAddress
    ) -> u32;
}

#[dojo::contract]
mod actions {
    use dojo_chess::models::{Color, Piece, PieceType, Game, GameTurn};
    use super::{ContractAddress, IActions};
    use dojo_chess::utils::PieceTrait;

    #[external(v0)]
    impl IActionsImpl of IActions<ContractState> {
        fn spawn(
            self: @ContractState, white_address: ContractAddress, black_address: ContractAddress
        ) -> u32 {
            let world = self.world_dispatcher.read();
            let game_id = world.uuid();
            set!(
                world,
                (
                    Game {
                        game_id, winner: Color::None(()), white: white_address, black: black_address
                    },
                    GameTurn { game_id, turn: Color::White(()) },
                )
            );
            set!(world, (Piece { game_id, x: 0, y: 0, piece_type: PieceType::WhiteRook }));
            set!(world, (Piece { game_id, x: 0, y: 1, piece_type: PieceType::WhitePawn }));
            set!(world, (Piece { game_id, x: 1, y: 6, piece_type: PieceType::BlackPawn }));
            set!(world, (Piece { game_id, x: 1, y: 0, piece_type: PieceType::WhiteKnight }));

            //the rest of the positions on the board goes here....

            game_id
        }
        fn move(
            self: @ContractState,
            curr_position: (u32, u32),
            next_position: (u32, u32),
            caller: ContractAddress, //player
            game_id: u32
        ) {
            let world = self.world_dispatcher.read();
            let (current_x, current_y) = curr_position;
            let (next_x, next_y) = next_position;
            let mut current_piece = get!(world, (game_id, current_x, current_y), (Piece));

            // check if next_position is out of board or not
            assert(PieceTrait::is_out_of_board(next_position), 'Should be inside board');

            // check if this is the right piece type move
            assert(
                current_piece.is_right_piece_move(curr_position, next_position),
                'Should be right piece move'
            );
            let target_piece = current_piece.piece_type;
            // make current_piece piece none and move piece to next_position
            current_piece.piece_type = PieceType::None(());
            let mut piece_next_position = get!(world, (game_id, next_x, next_y), (Piece));

            // check the piece already in next_suqare
            if piece_next_position.piece_type == PieceType::None(()) {
                piece_next_position.piece_type = target_piece;
            } else {
                if piece_next_position.is_mine() {
                    panic(array!['Already same color piece exist'])
                } else {
                    piece_next_position.piece_type = target_piece;
                }
            }
            set!(world, (piece_next_position));
            set!(world, (current_piece));
        }
    }
}

#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use dojo::test_utils::{spawn_test_world, deploy_contract};
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use dojo_chess::models::{Game, game, GameTurn, game_turn, Piece, piece, PieceType};
    use dojo_chess::actions::actions;
    use dojo_chess::actions::{IActionsDispatcher, IActionsDispatcherTrait};

    // helper setup function
    fn setup_world() -> (IWorldDispatcher, IActionsDispatcher) {
        // models
        let mut models = array![
            game::TEST_CLASS_HASH, game_turn::TEST_CLASS_HASH, piece::TEST_CLASS_HASH
        ];
        // deploy world with models
        let world = spawn_test_world(models);

        // deploy systems contract
        let contract_address = world
            .deploy_contract('salt', actions::TEST_CLASS_HASH.try_into().unwrap());
        let actions_system = IActionsDispatcher { contract_address };

        (world, actions_system)
    }

    #[test]
    #[available_gas(3000000000000000)]
    fn test_initiate() {
        let white = starknet::contract_address_const::<0x01>();
        let black = starknet::contract_address_const::<0x02>();

        let (world, actions_system) = setup_world();

        //system calls
        let game_id = actions_system.spawn(white, black);

        //get game
        let game = get!(world, game_id, (Game));
        assert(game.white == white, 'white address is incorrect');
        assert(game.black == black, 'black address is incorrect');

        //get a1 piece
        let a1 = get!(world, (game_id, 0, 0), (Piece));
        assert(a1.piece_type == PieceType::WhiteRook, 'should be White Rook');
        assert(a1.piece_type != PieceType::None, 'should have piece');
    }


    #[test]
    #[available_gas(3000000000000000)]
    fn test_move() {
        let white = starknet::contract_address_const::<0x01>();
        let black = starknet::contract_address_const::<0x02>();

        let (world, actions_system) = setup_world();
        actions_system.spawn(white, black);

        let game_id = world.uuid();
        let a2 = get!(world, (game_id, 0, 1), (Piece));
        assert(a2.piece_type == PieceType::WhitePawn, 'should be White Pawn');
        assert(a2.piece_type != PieceType::None, 'should have piece');

        actions_system.move((0, 1), (0, 2), white.into(), game_id);

        let c3 = get!(world, (game_id, 0, 2), (Piece));
        assert(c3.piece_type == PieceType::WhitePawn, 'should be White Pawn');
        assert(c3.piece_type != PieceType::None, 'should have piece');
    }
}
