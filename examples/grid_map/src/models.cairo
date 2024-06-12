use starknet::ContractAddress;
use origami::map::grid::{
    grid::{GridTile},
    types::{Direction}
};

#[derive(Copy, Drop, Serde, Introspect, PartialEq)]
struct Vec2 {
    x: u32,
    y: u32
}

#[dojo::model]
#[derive(Copy, Drop, Serde, Introspect, PartialEq)]
struct Position {
    #[key]
    player: ContractAddress,
    vec: Vec2,
}

#[dojo::model]
#[derive(Drop, Serde)]
struct Map {
    #[key]
    game_id: u32,
    max_x: u32,
    max_y: u32,
    players: Array<Position>,
}


trait Vec2Trait {
    fn is_zero(self: Vec2) -> bool;
    fn is_equal(self: Vec2, b: Vec2) -> bool;
}

impl Vec2Impl of Vec2Trait {
    fn is_zero(self: Vec2) -> bool {
        if self.x - self.y == 0 {
            return true;
        }
        false
    }

    fn is_equal(self: Vec2, b: Vec2) -> bool {
        self.x == b.x && self.y == b.y
    }
}
// #[cfg(test)]
// mod tests {
//     use super::{Position, Vec2, Vec2Trait};

//     #[test]
//     fn test_vec_is_zero() {
//         assert(Vec2Trait::is_zero(Vec2 { x: 0, y: 0 }), 'not zero');
//     }

//     #[test]
//     fn test_vec_is_equal() {
//         let position = Vec2 { x: 420, y: 0 };
//         assert(position.is_equal(Vec2 { x: 420, y: 0 }), 'not equal');
//     }
// }


