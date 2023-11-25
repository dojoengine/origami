use origami::map::hex::{types::{HexTile, Direction, DirectionIntoFelt252}};

trait IHexTile {
    fn new(col: u32, row: u32) -> HexTile;
    fn neighbor(self: HexTile, direction: Direction) -> HexTile;
    fn neighbors(self: HexTile) -> Array<HexTile>;
    fn is_neighbor(self: HexTile, other: HexTile) -> bool;
}

impl ImplHexTile of IHexTile {
    fn new(col: u32, row: u32) -> HexTile {
        HexTile { col, row }
    }

    fn neighbor(self: HexTile, direction: Direction) -> HexTile {
        match direction {
            Direction::East(()) => HexTile { col: self.col + 1, row: self.row },
            Direction::NorthEast(()) => HexTile { col: self.col + 1, row: self.row - 1 },
            Direction::NorthWest(()) => HexTile { col: self.col, row: self.row - 1 },
            Direction::West(()) => HexTile { col: self.col - 1, row: self.row },
            Direction::SouthWest(()) => HexTile { col: self.col, row: self.row + 1 },
            Direction::SouthEast(()) => HexTile { col: self.col + 1, row: self.row + 1 },
        }
    }

    fn neighbors(self: HexTile) -> Array<HexTile> {
        array![
            self.neighbor(Direction::East(())),
            self.neighbor(Direction::NorthEast(())),
            self.neighbor(Direction::NorthWest(())),
            self.neighbor(Direction::West(())),
            self.neighbor(Direction::SouthWest(())),
            self.neighbor(Direction::SouthEast(()))
        ]
    }

    fn is_neighbor(self: HexTile, other: HexTile) -> bool {
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
}


// tests ----------------------------------------------------------------------- //

#[cfg(test)]
mod tests {
    use super::{IHexTile, ImplHexTile, Direction, HexTile};
    #[test]
    #[available_gas(500000)]
    fn test_row_col() {
        let mut hex_tile = ImplHexTile::new(5, 5);

        assert(hex_tile.col == 5, 'col should be 5');
        assert(hex_tile.row == 5, 'row should be 5');
    }


    #[test]
    #[available_gas(500000)]
    fn test_hex_tile_neighbors() {
        let mut hex_tile = ImplHexTile::new(5, 5);

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
    #[available_gas(501230000)]
    fn test_is_neighbor() {
        let mut hex_tile = ImplHexTile::new(5, 5);

        assert(hex_tile.is_neighbor(HexTile { col: hex_tile.col + 1, row: hex_tile.row }), 'east');

        assert(
            hex_tile.is_neighbor(HexTile { col: hex_tile.col, row: hex_tile.row + 1 }), 'north east'
        );

        assert(
            hex_tile.is_neighbor(HexTile { col: hex_tile.col, row: hex_tile.row - 1 }), 'north west'
        );

        assert(hex_tile.is_neighbor(HexTile { col: hex_tile.col - 1, row: hex_tile.row }), 'west');

        assert(
            hex_tile.is_neighbor(HexTile { col: hex_tile.col, row: hex_tile.row - 1 }), 'south west'
        );

        assert(
            hex_tile.is_neighbor(HexTile { col: hex_tile.col + 1, row: hex_tile.row - 1 }),
            'south east'
        );
    }
}
