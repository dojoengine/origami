use core::array::ArrayTrait;
use origami::map::grid::{types::{GridTile, Direction, DirectionIntoFelt252}};

trait IGridTile {
    fn new(col: u32, row: u32) -> GridTile;
    fn neighbor(self: GridTile, direction: Direction) -> GridTile;
    fn neighbors(self: GridTile) -> Array<GridTile>;
    fn is_neighbor(self: GridTile, other: GridTile) -> bool;
    fn tiles_within_range(self: GridTile, range: u32) -> Array<GridTile>;
}

impl ImplGridTile of IGridTile {
    fn new(col: u32, row: u32) -> GridTile {
        GridTile { col, row }
    }

    fn neighbor(self: GridTile, direction: Direction) -> GridTile {
        match direction {
            Direction::East(()) => GridTile { col: self.col + 1, row: self.row },
            Direction::North(()) => GridTile { col: self.col, row: self.row - 1 },
            Direction::West(()) => GridTile { col: self.col - 1, row: self.row },
            Direction::South(()) => GridTile { col: self.col, row: self.row + 1 },
        }
    }

    fn neighbors(self: GridTile) -> Array<GridTile> {
        return array![
            self.neighbor(Direction::East(())),
            self.neighbor(Direction::North(())),
            self.neighbor(Direction::West(())),
            self.neighbor(Direction::South(()))
        ];
    }

    fn is_neighbor(self: GridTile, other: GridTile) -> bool {
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

    fn tiles_within_range(self: GridTile, range: u32) -> Array<GridTile> {
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


// tests ----------------------------------------------------------------------- //

#[cfg(test)]
mod tests {
    use super::{IGridTile, ImplGridTile, Direction, GridTile};
    #[test]
    fn test_row_col() {
        let mut grid_tile = ImplGridTile::new(5, 5);

        assert(grid_tile.col == 5, 'col should be 5');
        assert(grid_tile.row == 5, 'row should be 5');
    }


    #[test]
    fn test_grid_tile_neighbors() {
        let mut grid_tile = ImplGridTile::new(5, 5);

        let east_neighbor = grid_tile.neighbor(Direction::East(()));

        assert(east_neighbor.col == 6, 'col should be 6');
        assert(east_neighbor.row == 5, 'row should be 5');

        let north_neighbor = grid_tile.neighbor(Direction::North(()));

        assert(north_neighbor.col == 5, 'col should be 5');
        assert(north_neighbor.row == 4, 'row should be 4');

        let west_neighbor = grid_tile.neighbor(Direction::West(()));

        assert(west_neighbor.col == 4, 'col should be 4');
        assert(west_neighbor.row == 5, 'row should be 5');

        let south_neighbor = grid_tile.neighbor(Direction::South(()));

        assert(south_neighbor.col == 5, 'col should be 4');
        assert(south_neighbor.row == 6, 'row should be 6');
    }

    #[test]
    fn test_is_neighbor() {
        let mut grid_tile = ImplGridTile::new(5, 5);

        assert(
            grid_tile.is_neighbor(GridTile { col: grid_tile.col + 1, row: grid_tile.row }), 'east'
        );

        assert(
            grid_tile.is_neighbor(GridTile { col: grid_tile.col, row: grid_tile.row + 1 }), 'south'
        );

        assert(
            grid_tile.is_neighbor(GridTile { col: grid_tile.col, row: grid_tile.row - 1 }), 'north'
        );

        assert(
            grid_tile.is_neighbor(GridTile { col: grid_tile.col - 1, row: grid_tile.row }), 'west'
        );
    }

    #[test]
    fn test_tiles_within_range() {
        let grid_tile = ImplGridTile::new(5, 5);
        let tiles_range_one = grid_tile.tiles_within_range(1);
        let tiles_range_two = grid_tile.tiles_within_range(2);
        let tiles_range_three = grid_tile.tiles_within_range(3);
        // Including the center tile 
        assert_eq!(tiles_range_one.len(), 5, "should be 5");
        assert_eq!(tiles_range_two.len(), 13, "should be 13");
        assert_eq!(tiles_range_three.len(), 25, "should be 25");
    }
}
