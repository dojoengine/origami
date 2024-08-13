use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use starknet::{ClassHash, ContractAddress};

pub fn get_contract_infos(
    world: IWorldDispatcher, resource: felt252
) -> (ClassHash, ContractAddress) {
    let (class_hash, contract_address) = match world.resource(resource) {
        dojo::world::Resource::Contract((
            class_hash, contract_address
        )) => (class_hash, contract_address),
        _ => (0.try_into().unwrap(), 0.try_into().unwrap())
    };

    if class_hash.is_zero() || contract_address.is_zero() {
        panic!("Invalid resource!");
    }

    (class_hash, contract_address)
}


pub fn grant_writer(
    world: IWorldDispatcher, selectors: Span<felt252>, contract_addresses: Span<ContractAddress>
) {
    let mut selectors = selectors;
    while let Option::Some(selector) = selectors.pop_front() {
        let mut contract_addresses = contract_addresses.clone();

        while let Option::Some(contract_address) = contract_addresses.pop_front() {
            world.grant_writer(*selector, *contract_address);
        }
    }
}
