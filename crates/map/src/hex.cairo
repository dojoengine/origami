/// Internal imports.

use origami_map::types::direction::Direction;

/// Types.

#[derive(Drop, Copy, Serde)]
pub struct Hex {
    pub col: u32,
    pub row: u32,
}

/// Implementation of the `HexTrait` trait for the `Hex` struct.
#[generate_trait]
pub impl HexImpl of HexTrait {
    #[inline]
    fn new(col: u32, row: u32) -> Hex {
        Hex { col, row }
    }

    #[inline]
    fn neighbor(self: Hex, direction: Direction) -> Hex {
        match direction {
            Direction::East(()) => Hex { col: self.col + 1, row: self.row },
            Direction::NorthEast(()) => Hex { col: self.col + 1, row: self.row - 1 },
            Direction::NorthWest(()) => Hex { col: self.col, row: self.row - 1 },
            Direction::West(()) => Hex { col: self.col - 1, row: self.row },
            Direction::SouthWest(()) => Hex { col: self.col, row: self.row + 1 },
            Direction::SouthEast(()) => Hex { col: self.col + 1, row: self.row + 1 },
            _ => self,
        }
    }

    #[inline]
    fn neighbor_even_y(self: Hex, direction: Direction) -> Hex {
        match direction {
            Direction::East(()) => Hex { col: self.col + 1, row: self.row },
            Direction::NorthEast(()) => Hex { col: self.col, row: self.row + 1 },
            Direction::NorthWest(()) => Hex { col: self.col - 1, row: self.row + 1 },
            Direction::West(()) => Hex { col: self.col - 1, row: self.row },
            Direction::SouthWest(()) => Hex { col: self.col - 1, row: self.row - 1 },
            Direction::SouthEast(()) => Hex { col: self.col, row: self.row - 1 },
            _ => self,
        }
    }

    #[inline]
    fn neighbors(self: Hex) -> Array<Hex> {
        if (self.row % 2 == 0) {
            return array![
                self.neighbor_even_y(Direction::East(())),
                self.neighbor_even_y(Direction::NorthEast(())),
                self.neighbor_even_y(Direction::NorthWest(())),
                self.neighbor_even_y(Direction::West(())),
                self.neighbor_even_y(Direction::SouthWest(())),
                self.neighbor_even_y(Direction::SouthEast(())),
            ];
        }
        return array![
            self.neighbor(Direction::East(())),
            self.neighbor(Direction::NorthEast(())),
            self.neighbor(Direction::NorthWest(())),
            self.neighbor(Direction::West(())),
            self.neighbor(Direction::SouthWest(())),
            self.neighbor(Direction::SouthEast(())),
        ];
    }

    fn is_neighbor(self: Hex, other: Hex) -> bool {
        let mut neighbors = self.neighbors();

        loop {
            if (neighbors.len() == 0) {
                break false;
            }

            let curent_neighbor = neighbors.pop_front().unwrap();

            if (curent_neighbor.col == other.col) {
                if (curent_neighbor.row == other.row) {
                    break true;
                }
            };
        }
    }

    fn tiles_within_range(self: Hex, range: u32) -> Array<Hex> {
        let mut queue = array![self];
        let mut visited = array![self];
        let mut moves = 0;

        loop {
            if moves == range {
                break;
            }
            let mut next_queue = array![];
            loop {
                if queue.len() == 0 {
                    break;
                }
                let tile = queue.pop_front().unwrap();
                let mut neighbors = tile.neighbors();

                loop {
                    if neighbors.len() == 0 {
                        break;
                    }
                    let neighbor = neighbors.pop_front().unwrap();
                    let mut is_visited = false;
                    let mut index = 0;
                    let visited_span = visited.span();

                    loop {
                        if index == visited_span.len() || is_visited == true {
                            break;
                        }
                        let curr = *visited_span.at(index);
                        if (curr.col == neighbor.col && curr.row == neighbor.row) {
                            is_visited = true;
                        }
                        index = index + 1;
                    };
                    if !is_visited {
                        next_queue.append(neighbor);
                        visited.append(neighbor);
                    }
                };
            };
            queue = next_queue.clone();
            moves = moves + 1;
        };
        return visited;
    }
}


/// Tests.

#[cfg(test)]
mod tests {
    use super::{HexTrait, Direction, Hex};
    #[test]
    fn test_row_col() {
        let mut hex_tile = HexTrait::new(5, 5);

        assert(hex_tile.col == 5, 'col should be 5');
        assert(hex_tile.row == 5, 'row should be 5');
    }


    #[test]
    fn test_hex_tile_neighbors() {
        let mut hex_tile = HexTrait::new(5, 5);

        let east_neighbor = hex_tile.neighbor(Direction::East(()));

        assert(east_neighbor.col == 6, 'col should be 7');
        assert(east_neighbor.row == 5, 'row should be 5');

        let north_east_neighbor = hex_tile.neighbor(Direction::NorthEast(()));

        assert(north_east_neighbor.col == 6, 'col should be 6');
        assert(north_east_neighbor.row == 4, 'row should be 4');

        let north_west_neighbor = hex_tile.neighbor(Direction::NorthWest(()));

        assert(north_west_neighbor.col == 5, 'col should be 5');
        assert(north_west_neighbor.row == 4, 'row should be 4');

        let west_neighbor = hex_tile.neighbor(Direction::West(()));

        assert(west_neighbor.col == 4, 'col should be 3');
        assert(west_neighbor.row == 5, 'row should be 5');

        let south_west_neighbor = hex_tile.neighbor(Direction::SouthWest(()));

        assert(south_west_neighbor.col == 5, 'col should be 4');
        assert(south_west_neighbor.row == 6, 'row should be 6');

        let south_east_neighbor = hex_tile.neighbor(Direction::SouthEast(()));

        assert(south_east_neighbor.col == 6, 'col should be 5');
        assert(south_east_neighbor.row == 6, 'row should be 6');
    }

    #[test]
    fn test_is_neighbor() {
        let mut hex_tile = HexTrait::new(5, 5);

        assert(hex_tile.is_neighbor(Hex { col: hex_tile.col + 1, row: hex_tile.row }), 'east');

        assert(
            hex_tile.is_neighbor(Hex { col: hex_tile.col, row: hex_tile.row + 1 }), 'north east',
        );

        assert(
            hex_tile.is_neighbor(Hex { col: hex_tile.col, row: hex_tile.row - 1 }), 'north west',
        );

        assert(hex_tile.is_neighbor(Hex { col: hex_tile.col - 1, row: hex_tile.row }), 'west');

        assert(
            hex_tile.is_neighbor(Hex { col: hex_tile.col, row: hex_tile.row - 1 }), 'south west',
        );

        assert(
            hex_tile.is_neighbor(Hex { col: hex_tile.col + 1, row: hex_tile.row - 1 }),
            'south east',
        );
    }

    #[test]
    fn test_tiles_within_range() {
        let mut hex_tile = HexTrait::new(5, 5);

        let tiles_range_one = hex_tile.tiles_within_range(1);
        let tiles_range_two = hex_tile.tiles_within_range(2);
        let tiles_range_three = hex_tile.tiles_within_range(3);

        assert(tiles_range_one.len() == 7, 'should be 7');
        assert(tiles_range_two.len() == 19, 'should be 19');
        assert(tiles_range_three.len() == 37, 'should be 37');
    }
}
