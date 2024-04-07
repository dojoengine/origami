use starknet::ContractAddress;

#[dojo::interface]
trait IGovernanceToken {
    fn constructor(
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
    fn get_current_votes(account: ContractAddress) -> u128;
    fn get_prior_votes(account: ContractAddress, block_number: u64) -> u128;
}
