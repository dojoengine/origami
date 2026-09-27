//! Cave generator: synchronous bit-sliced cellular automaton (lot L4).

#[generate_trait]
pub impl Caver of CaverTrait {
    /// Generate a cave.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The number of generations
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    fn generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
        panic!("unimplemented")
    }
}
