//! Random walk generator (lot L6).

#[generate_trait]
pub impl Walker of WalkerTrait {
    /// Generate a random walk.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `steps` - The number of steps
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    fn generate(width: u8, height: u8, steps: u16, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }
}
