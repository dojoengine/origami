//! Digger: open a corridor or a maze from an edge tile (lot L5).

#[generate_trait]
pub impl Digger of DiggerTrait {
    /// Dig a maze from an edge tile.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `seed` - The seed
    /// # Returns
    /// * The grid with the maze
    fn maze(width: u8, height: u8, order: u8, start: u8, grid: felt252, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }

    /// Dig a corridor from an edge tile until it reaches an open tile.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the corridor, 0 or 1
    /// * `start` - The edge tile, not a corner
    /// * `grid` - The original grid
    /// * `seed` - The seed
    /// # Returns
    /// * The grid with the corridor
    fn corridor(
        width: u8, height: u8, order: u8, start: u8, grid: felt252, seed: felt252,
    ) -> felt252 {
        panic!("unimplemented")
    }
}
