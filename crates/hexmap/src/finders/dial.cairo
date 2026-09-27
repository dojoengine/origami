//! Weighted bit-parallel Dial search with cost classes (lot L3).

#[generate_trait]
pub impl Dial of DialTrait {
    /// Search the cheapest path between two tiles, entry costs in `{1, 2, 3, 4}`.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// * `costs` - `costs[k]` is the bitmap of the tiles of cost `k + 2`, at most 3 items,
    /// the other walkable tiles cost 1
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    fn search(
        grid: felt252, width: u8, height: u8, from: u8, to: u8, costs: Span<felt252>,
    ) -> Span<u8> {
        panic!("unimplemented")
    }
}
