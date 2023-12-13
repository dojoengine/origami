#[cfg(test)]
mod tests {
    use chess::models::piece::{Piece, PieceType, Vec2};
    use dojo::world::IWorldDispatcherTrait;
    use chess::tests::units::tests::setup_world;
    use chess::actions::{IActionsDispatcher, IActionsDispatcherTrait};
    use chess::models::player::{Color};

    #[test]
    #[available_gas(3000000000000000)]
    fn integration() {
        let white = starknet::contract_address_const::<0x01>();
        let black = starknet::contract_address_const::<0x02>();

        let (world, actions_system) = setup_world();

        //system calls
        let game_id = actions_system.spawn(white, black);

        //White pawn is setup in (0,1)
        let wp_curr_pos = Vec2 { x: 0, y: 1 };
        let a2 = get!(world, (game_id, wp_curr_pos), (Piece));
        assert(a2.piece_type == PieceType::Pawn, 'should be Pawn in (0,1)');
        assert(a2.color == Color::White, 'should be white color');
        assert(a2.piece_type != PieceType::None, 'should have piece in (0,1)');

        //Black pawn is setup in (1,6)
        let bp_curr_pos = Vec2 { x: 1, y: 6 };
        let b7 = get!(world, (game_id, bp_curr_pos), (Piece));
        assert(b7.piece_type == PieceType::Pawn, 'should be Pawn in (1,6)');
        assert(b7.color == Color::Black, 'should be black color');
        assert(b7.piece_type != PieceType::None, 'should have piece in (1,6)');

        //Move White Pawn to (0,3)
        let wp_next_pos = Vec2 { x: 0, y: 3 };
        actions_system.move(wp_curr_pos, wp_next_pos, white.into(), game_id);

        //White pawn is now in (0,3)
        let wp_curr_pos = wp_next_pos;
        let a4 = get!(world, (game_id, wp_curr_pos), (Piece));
        assert(a4.piece_type == PieceType::Pawn, 'should be Pawn in (0,3)');
        assert(a4.color == Color::White, 'should be white color');
        assert(a4.piece_type != PieceType::None, 'should have piece in (0,3)');

        //Move black Pawn to (1,4)
        let bp_next_pos = Vec2 { x: 1, y: 4 };
        actions_system.move(bp_curr_pos, bp_next_pos, black.into(), game_id);

        //Black pawn is now in (1,4)
        let bp_curr_pos = bp_next_pos;
        let b5 = get!(world, (game_id, bp_curr_pos), (Piece));
        assert(b5.piece_type == PieceType::Pawn, 'should be Pawn in (1,4)');
        assert(b5.color == Color::Black, 'should be black color');
        assert(b5.piece_type != PieceType::None, 'should have piece in (1,4)');

        // Move White Pawn to (1,4) and capture black pawn
        actions_system.move(wp_curr_pos, bp_curr_pos, white.into(), game_id);

        let wp_curr_pos = bp_curr_pos;
        let b5 = get!(world, (game_id, wp_curr_pos), (Piece));
        assert(b5.piece_type == PieceType::Pawn, 'should be Pawn in (1,4)');
        assert(b5.color == Color::White, 'should be white color');
        assert(b5.piece_type != PieceType::None, 'should have piece in (1,4)');
    }
}
