use chess::models::{PieceType, Piece};
use starknet::ContractAddress;

trait PieceTrait {
    fn is_mine(self: @Piece) -> bool;
    fn is_out_of_board(next_position: (u32, u32)) -> bool;
    fn is_right_piece_move(
        self: @Piece, curr_position: (u32, u32), next_position: (u32, u32)
    ) -> bool;
}

impl PieceImpl of PieceTrait {
    fn is_mine(self: @Piece) -> bool {
        false
    }

    fn is_out_of_board(next_position: (u32, u32)) -> bool {
        let (n_x, n_y) = next_position;
        if n_x > 7 || n_y > 7 {
            return false;
        }
        true
    }

    fn is_right_piece_move(
        self: @Piece, curr_position: (u32, u32), next_position: (u32, u32)
    ) -> bool {
        let (c_x, c_y) = curr_position;
        let (n_x, n_y) = next_position;
        match self.piece_type {
            PieceType::WhitePawn => { true },
            PieceType::WhiteKnight => {
                if n_x == c_x + 2 && n_y == c_x + 1 {
                    return true;
                }
                panic(array!['Knight illegal move'])
            },
            PieceType::WhiteBishop => { true },
            PieceType::WhiteRook => { true },
            PieceType::WhiteQueen => { true },
            PieceType::WhiteKing => { true },
            PieceType::BlackPawn => { true },
            PieceType::BlackKnight => { true },
            PieceType::BlackBishop => { true },
            PieceType::BlackRook => { true },
            PieceType::BlackQueen => { true },
            PieceType::BlackKing => { true },
            PieceType::None(_) => panic(array!['Should not move empty piece']),
        }
    }
}
