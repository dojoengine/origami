use core::result::ResultTrait;
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::ContractAddress;
use starknet::testing;

fn impersonate(address: ContractAddress) {
    testing::set_contract_address(address);
    testing::set_account_contract_address(address);
}

fn deploy(contract_class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (address, _) = starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap();
    address
}

/// Pop the earliest unpopped logged event for the contract as the requested type
/// and checks there's no more data left on the event, preventing unaccounted params.
/// Indexed event members are currently not supported, so they are ignored.
fn pop_log<T, impl TDrop: Drop<T>, impl TEvent: starknet::Event<T>>(
    address: ContractAddress
) -> Option<T> {
    let (mut keys, mut data) = testing::pop_log_raw(address)?;
    let ret = starknet::Event::deserialize(ref keys, ref data);
    assert(data.is_empty(), 'Event has extra data');
    ret
}

fn assert_no_events_left(address: ContractAddress) {
    assert(testing::pop_log_raw(address).is_none(), 'Events remaining on queue');
}

fn drop_event(address: ContractAddress) {
    testing::pop_log_raw(address);
}

fn drop_all_events(address: ContractAddress) {
    loop {
        match testing::pop_log_raw(address) {
            option::Option::Some(_) => {},
            option::Option::None => { break; },
        };
    }
}
