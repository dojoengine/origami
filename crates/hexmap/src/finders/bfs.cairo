//! Bit-parallel breadth-first search with layer backtracking (lot L1).

#[generate_trait]
pub impl Bfs of BfsTrait {
    /// Search the shortest path between two tiles.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        panic!("unimplemented")
    }

    /// Flood fill: every tile reachable from a position.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// # Returns
    /// * The bitmap of the reachable tiles
    fn reachable(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
        panic!("unimplemented")
    }

    /// Every walkable tile reachable within `range` steps of a position.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The centre position
    /// * `range` - The number of steps
    /// # Returns
    /// * The bitmap of the tiles in range
    fn tiles_within_range(
        grid: felt252, width: u8, height: u8, position: u8, range: u8,
    ) -> felt252 {
        panic!("unimplemented")
    }
}
