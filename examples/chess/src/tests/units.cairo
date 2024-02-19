#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use dojo::test_utils::{spawn_test_world, deploy_contract};
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use chess::models::player::{Player, Color, player};
    use chess::models::piece::{Piece, PieceType, Vec2, piece};
    use chess::models::game::{Game, GameTurn, game, game_turn};
    use chess::actions::{actions, IActionsDispatcher, IActionsDispatcherTrait};

    // helper setup function
    fn setup_world() -> (IWorldDispatcher, IActionsDispatcher) {
        // models
        let mut models = array![
            game::TEST_CLASS_HASH,
            player::TEST_CLASS_HASH,
            game_turn::TEST_CLASS_HASH,
            piece::TEST_CLASS_HASH
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
    fn test_spawn() {
        let white = starknet::contract_address_const::<0x01>();
        let black = starknet::contract_address_const::<0x02>();
        let (world, actions_system) = setup_world();

        //system calls
        let game_id = actions_system.spawn(white, black);

        //get game
        let game = get!(world, game_id, (Game));
        let game_turn = get!(world, game_id, (GameTurn));
        assert(game_turn.player_color == Color::White, 'should be white turn');
        assert(game.white == white, 'white address is incorrect');
        assert(game.black == black, 'black address is incorrect');

        //get a1 piece
        let curr_pos = Vec2 { x: 0, y: 0 };
        let a1 = get!(world, (game_id, curr_pos), (Piece));
        assert(a1.piece_type == PieceType::Rook, 'should be Rook');
        assert(a1.color == Color::White, 'should be white color');
        assert(a1.piece_type != PieceType::None, 'should have piece');
    }
    #[test]
    fn test_move() {
        let white = starknet::contract_address_const::<0x01>();
        let black = starknet::contract_address_const::<0x02>();

        let (world, actions_system) = setup_world();
        let game_id = actions_system.spawn(white, black);
        let curr_pos = Vec2 { x: 0, y: 1 };
        let a2 = get!(world, (game_id, curr_pos), (Piece));
        assert(a2.piece_type == PieceType::Pawn, 'should be Pawn');
        assert(a2.color == Color::White, 'should be white color piece 1');
        assert(a2.piece_type != PieceType::None, 'should have piece');

        let next_pos = Vec2 { x: 0, y: 2 };
        let game_turn = get!(world, game_id, (GameTurn));
        assert(game_turn.player_color == Color::White, 'should be white player turn');
        actions_system.move(curr_pos, next_pos, white.into(), game_id);

        let curr_pos = next_pos;
        let c3 = get!(world, (game_id, curr_pos), (Piece));
        assert(c3.piece_type == PieceType::Pawn, 'should be Pawn');
        assert(c3.color == Color::White, 'should be white color piece 2');
        assert(c3.piece_type != PieceType::None, 'should have piece');

        let game_turn = get!(world, game_id, (GameTurn));
        assert(game_turn.player_color == Color::Black, 'should be black player turn');
    }
}
