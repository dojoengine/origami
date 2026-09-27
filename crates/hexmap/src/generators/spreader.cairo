//! Spreader: uniform selection of walkable tiles (lot L7).

#[generate_trait]
pub impl Spreader of SpreaderTrait {
    /// Pick `count` walkable tiles uniformly.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `count` - The number of tiles to pick
    /// * `seed` - The seed
    /// # Returns
    /// * The bitmap of the picked tiles
    fn generate(grid: felt252, width: u8, height: u8, count: u8, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }
}
