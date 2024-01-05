use starknet::{ContractAddress, ClassHash};
use dojo::world::IWorldDispatcher;

#[starknet::interface]
trait IERC20BalanceMock<TState> {
    // IERC20
    fn total_supply(self: @TState,) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // IERC20CamelOnly
    fn totalSupply(self: @TState,) -> u256;
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

     // IWorldProvider
    fn world(self: @TState,) -> IWorldDispatcher;

    fn initializer(
        ref self: TState,
        initial_supply: u256,
        recipient: ContractAddress,
    );
}


#[dojo::contract]
mod ERC20BalanceMock {
    use starknet::ContractAddress;
    use token::components::token::erc20::erc20_allowance::ERC20AllowanceComponent;
    use token::components::token::erc20::erc20_balance::ERC20BalanceComponent;

    component!(path: ERC20AllowanceComponent, storage: erc20_allowance, event: ERC20AllowanceEvent);
    component!(path: ERC20BalanceComponent, storage: erc20_balance, event: ERC20BalanceEvent);

    #[abi(embed_v0)]
    impl ERC20AllowanceImpl = ERC20AllowanceComponent::ERC20AllowanceImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20BalanceImpl = ERC20BalanceComponent::ERC20BalanceImpl<ContractState>;
   
    impl ERC20AllowanceInternalImpl = ERC20AllowanceComponent::InternalImpl<ContractState>;
    impl ERC20BalanceInternalImpl = ERC20BalanceComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20_allowance: ERC20AllowanceComponent::Storage,
        #[substorage(v0)]
        erc20_balance: ERC20BalanceComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC20AllowanceEvent: ERC20AllowanceComponent::Event,
        ERC20BalanceEvent: ERC20BalanceComponent::Event,
    }

    #[external(v0)]
    #[generate_trait]
    impl InitializerImpl of InitializerTrait {
        fn initializer( ref self: ContractState, initial_supply: u256, recipient: ContractAddress, ) {
            // set balance for recipient
            self.erc20_balance.update_balance(recipient,0,initial_supply);
        }
    }

}
