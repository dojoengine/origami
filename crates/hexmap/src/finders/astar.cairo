//! Scalar A* with a heap, benchmark baseline for the bit-parallel BFS (lot L2).

#[generate_trait]
pub impl Astar of AstarTrait {
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
}
