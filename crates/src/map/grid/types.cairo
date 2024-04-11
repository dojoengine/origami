#[derive(Drop, Copy, Serde)]
struct GridTile {
    col: u32,
    row: u32,
}

#[derive(Drop, Copy, Serde)]
enum Direction {
    East: (),
    North: (),
    West: (),
    South: (),
}

impl DirectionIntoFelt252 of Into<Direction, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            Direction::East => 0,
            Direction::North => 1,
            Direction::West => 2,
            Direction::South => 3,
        }
    }
}
