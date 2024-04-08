use starknet::{ContractAddress, ClassHash};

#[dojo::interface]
trait ITimelock {
    fn initialize(admin: ContractAddress, delay: u64);
}
