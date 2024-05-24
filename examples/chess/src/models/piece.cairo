use chess::models::player::Color;
use starknet::ContractAddress;

#[dojo::model]
#[derive(Drop, Serde)]
struct Piece {
    #[key]
    game_id: u32,
    #[key]
    position: Vec2,
    color: Color,
    piece_type: PieceType,
}

#[derive(Copy, Drop, Serde, Introspect)]
struct Vec2 {
    x: u32,
    y: u32
}

trait PieceTrait {
    fn is_out_of_board(next_position: Vec2) -> bool;
    fn is_right_piece_move(self: @Piece, next_position: Vec2) -> bool;
}

impl PieceImpl of PieceTrait {
    fn is_out_of_board(next_position: Vec2) -> bool {
        next_position.x > 7 || next_position.y > 7
    }

    fn is_right_piece_move(self: @Piece, next_position: Vec2) -> bool {
        let n_x = next_position.x;
        let n_y = next_position.y;
        assert!(
            !(n_x == *self.position.x && n_y == *self.position.y), "Cannot move same position "
        );
        match self.piece_type {
            PieceType::Pawn => {
                match self.color {
                    Color::White => {
                        (n_x == *self.position.x && n_y == *self.position.y + 1)
                            || (n_x == *self.position.x && n_y == *self.position.y + 2)
                            || (n_x == *self.position.x + 1 && n_y == *self.position.y + 1)
                            || (n_x == *self.position.x - 1 && n_y == *self.position.y + 1)
                    },
                    Color::Black => {
                        (n_x == *self.position.x && n_y == *self.position.y - 1)
                            || (n_x == *self.position.x && n_y == *self.position.y - 2)
                            || (n_x == *self.position.x + 1 && n_y == *self.position.y - 1)
                            || (n_x == *self.position.x - 1 && n_y == *self.position.y - 1)
                    },
                    Color::None => panic(array!['Should not move empty piece']),
                }
            },
            PieceType::Knight => { n_x == *self.position.x + 2 && n_y == *self.position.y + 1 },
            PieceType::Bishop => {
                (n_x <= *self.position.x && n_y <= *self.position.y && *self.position.y
                    - n_y == *self.position.x
                    - n_x)
                    || (n_x <= *self.position.x && n_y >= *self.position.y && *self.position.y
                        - n_y == *self.position.x
                        - n_x)
                    || (n_x >= *self.position.x && n_y <= *self.position.y && *self.position.y
                        - n_y == *self.position.x
                        - n_x)
                    || (n_x >= *self.position.x && n_y >= *self.position.y && *self.position.y
                        - n_y == *self.position.x
                        - n_x)
            },
            PieceType::Rook => {
                (n_x == *self.position.x || n_y != *self.position.y)
                    || (n_x != *self.position.x || n_y == *self.position.y)
            },
            PieceType::Queen => {
                (n_x == *self.position.x || n_y != *self.position.y)
                    || (n_x != *self.position.x || n_y == *self.position.y)
                    || (n_x != *self.position.x || n_y != *self.position.y)
            },
            PieceType::King => {
                (n_x <= *self.position.x + 1 && n_y <= *self.position.y + 1)
                    || (n_x <= *self.position.x + 1 && n_y <= *self.position.y - 1)
                    || (n_x <= *self.position.x - 1 && n_y <= *self.position.y + 1)
                    || (n_x <= *self.position.x - 1 && n_y <= *self.position.y - 1)
            },
            PieceType::None => panic(array!['Should not move empty piece']),
        }
    }
}

#[derive(Serde, Drop, Copy, PartialEq, Introspect)]
enum PieceType {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
    None,
}

