use starknet::ContractAddress;

#[dojo::interface]
trait IGovernanceToken {
    fn spaw(
        name: felt252,
        symbol: felt252,
        decimals: u8,
        initial_supply: u128,
        recipient: ContractAddress
    );
    fn approve(spender: ContractAddress, amount: u128);
    fn transfer(to: ContractAddress, amount: u128);
    fn transfer_from(from: ContractAddress, to: ContractAddress, amount: u128);
    fn delegate(delegatee: ContractAddress);
    fn delegate_by_signature(
        delegatee: ContractAddress, nonce: usize, expiry: u64, pk: felt252, r: felt252, s: felt252
    );
    fn get_current_votes(account: ContractAddress) -> u128;
    fn get_prior_votes(account: ContractAddress, block_number: u64) -> u128;
}
