use starknet::{ContractAddress, ClassHash};

#[dojo::interface]
trait ITimelock {
    fn initialize(ref world: IWorldDispatcher, admin: ContractAddress, delay: u64);
    fn execute_transaction(
        ref world: IWorldDispatcher,
        target: ContractAddress,
        new_implementation: ClassHash,
        eta: u64
    );
    fn que_transaction(
        ref world: IWorldDispatcher,
        target: ContractAddress,
        new_implementation: ClassHash,
        eta: u64
    );
    fn cancel_transaction(
        ref world: IWorldDispatcher,
        target: ContractAddress,
        new_implementation: ClassHash,
        eta: u64
    );
}
