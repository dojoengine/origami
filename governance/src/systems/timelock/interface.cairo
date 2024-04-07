use starknet::{ContractAddress, ClassHash};

#[dojo::interface]
trait ITimelock {
    fn constructor(admin: ContractAddress, delay: u64);
    fn que_transaction(target: ContractAddress, new_implementation: ClassHash, eta: u64);
    fn cancel_transaction(target: ContractAddress, new_implementation: ClassHash, eta: u64);
    fn execute_transaction(
        target: ContractAddress, new_implementation: ClassHash, eta: u64
    ) -> ClassHash;
}
