use starknet::ContractAddress;

#[derive(Serde, Drop, Copy, PartialEq, Introspect)]
enum Color {
    White,
    Black,
    None,
}

#[dojo::model]
#[derive(Drop, Serde)]
struct Player {
    #[key]
    game_id: u32,
    #[key]
    address: ContractAddress,
    color: Color
}

trait PlayerTrait {
    fn is_not_my_piece(self: @Player, piece_color: Color) -> bool;
}

impl PalyerImpl of PlayerTrait {
    fn is_not_my_piece(self: @Player, piece_color: Color) -> bool {
        *self.color != piece_color
    }
}
