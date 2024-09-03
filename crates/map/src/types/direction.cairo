#[derive(Drop, Copy, Serde)]
pub struct HexTile {
    pub col: u32,
    pub row: u32,
}

#[derive(Drop, Copy, Serde)]
pub enum Direction {
    None,
    NorthWest,
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
}

pub impl DirectionIntoFelt252 of Into<Direction, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            Direction::None => 0,
            Direction::NorthWest => 1,
            Direction::North => 2,
            Direction::NorthEast => 3,
            Direction::East => 4,
            Direction::SouthEast => 5,
            Direction::South => 6,
            Direction::SouthWest => 7,
            Direction::West => 8,
        }
    }
}
