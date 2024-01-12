use starknet::ContractAddress;
use chess::models::piece::Vec2;
#[starknet::interface]
trait IActions<ContractState> {
    fn move(
        self: @ContractState,
        curr_position: Vec2,
        next_position: Vec2,
        caller: ContractAddress, //player
        game_id: u32
    );
    fn spawn(
        self: @ContractState, white_address: ContractAddress, black_address: ContractAddress
    ) -> u32;
}

#[dojo::contract]
mod actions {
    use chess::models::player::{Player, Color, PlayerTrait};
    use chess::models::piece::{Piece, PieceType, PieceTrait};
    use chess::models::game::{Game, GameTurn, GameTurnTrait};
    use super::{ContractAddress, IActions, Vec2};

    #[abi(embed_v0)]
    impl IActionsImpl of IActions<ContractState> {
        fn spawn(
            self: @ContractState, white_address: ContractAddress, black_address: ContractAddress
        ) -> u32 {
            let world = self.world_dispatcher.read();
            let game_id = world.uuid();

            // set Players
            set!(
                world,
                (
                    Player { game_id, address: black_address, color: Color::Black },
                    Player { game_id, address: white_address, color: Color::White },
                )
            );

            // set Game and GameTurn    
            set!(
                world,
                (
                    Game {
                        game_id, winner: Color::None, white: white_address, black: black_address
                    },
                    GameTurn { game_id, player_color: Color::White },
                )
            );

            // set Pieces
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::White,
                    position: Vec2 { x: 0, y: 0 },
                    piece_type: PieceType::Rook
                })
            );
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::White,
                    position: Vec2 { x: 0, y: 1 },
                    piece_type: PieceType::Pawn
                })
            );
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::Black,
                    position: Vec2 { x: 1, y: 6 },
                    piece_type: PieceType::Pawn
                })
            );
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::White,
                    position: Vec2 { x: 1, y: 0 },
                    piece_type: PieceType::Knight
                })
            );
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::None,
                    position: Vec2 { x: 0, y: 2 },
                    piece_type: PieceType::None
                })
            );

            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::None,
                    position: Vec2 { x: 0, y: 3 },
                    piece_type: PieceType::None
                })
            );
            set!(
                world,
                (Piece {
                    game_id,
                    color: Color::None,
                    position: Vec2 { x: 1, y: 4 },
                    piece_type: PieceType::None
                })
            );

            //the rest of the positions on the board goes here....

            game_id
        }
        fn move(
            self: @ContractState,
            curr_position: Vec2,
            next_position: Vec2,
            caller: ContractAddress, //player
            game_id: u32
        ) {
            let world = self.world_dispatcher.read();
            let mut current_piece = get!(world, (game_id, curr_position), (Piece));
            // check if next_position is out of board or not
            assert(!PieceTrait::is_out_of_board(next_position), 'Should be inside board');

            // check if this is the right move for this piece type
            assert(
                current_piece.is_right_piece_move(next_position), 'Illegal move for type of piece'
            );
            // Get piece data from to next_position in the board
            let mut next_position_piece = get!(world, (game_id, next_position), (Piece));

            let player = get!(world, (game_id, caller), (Player));
            // check if there is already a piece in next_position
            assert(
                next_position_piece.piece_type == PieceType::None
                    || player.is_not_my_piece(next_position_piece.color),
                'Already same color piece exist'
            );

            next_position_piece.piece_type = current_piece.piece_type;
            next_position_piece.color = player.color;
            // make current_piece piece none 
            current_piece.piece_type = PieceType::None;
            current_piece.color = Color::None;
            set!(world, (next_position_piece));
            set!(world, (current_piece));

            // change turn
            let mut game_turn = get!(world, game_id, (GameTurn));
            game_turn.player_color = game_turn.next_turn();
            set!(world, (game_turn));
        }
    }
}
