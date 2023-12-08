use starknet::ContractAddress;

#[derive(Model, Drop, Serde)]
struct Square {
    #[key]
    game_id: u32,
    #[key]
    x: u32,
    #[key]
    y: u32,
    piece: PieceType,
}

#[derive(Serde, Drop, Copy, PartialEq, Introspect)]
enum PieceType {
    WhitePawn: (),
    WhiteKnight: (),
    WhiteBishop: (),
    WhiteRook: (),
    WhiteQueen: (),
    WhiteKing: (),
    BlackPawn: (),
    BlackKnight: (),
    BlackBishop: (),
    BlackRook: (),
    BlackQueen: (),
    BlackKing: (),
    None: ()
}


#[derive(Serde, Drop, Copy, PartialEq, Introspect)]
enum Color {
    White: (),
    Black: (),
    None: (),
}

#[derive(Model, Drop, Serde)]
struct Game {
    #[key]
    game_id: u32,
    winner: Color,
    white: ContractAddress,
    black: ContractAddress
}

#[derive(Model, Drop, Serde)]
struct GameTurn {
    #[key]
    game_id: u32,
    turn: Color
}
