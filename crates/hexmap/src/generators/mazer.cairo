//! Maze generator: recursive backtracker over 6 directions (lot L5).

#[generate_trait]
pub impl Mazer of MazerTrait {
    /// Generate a maze.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The order of the maze, 0 or 1, the higher the less dense
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    fn generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }
}
