use starknet::ContractAddress;

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct ERC20BalanceModel {
    #[key]
    token: ContractAddress,
    #[key]
    account: ContractAddress,
    amount: u256,
}

///
/// Interface
///

#[starknet::interface]
trait IERC20Balance<TState> {
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

#[starknet::interface]
trait IERC20BalanceCamel<TState> {
    fn balanceOf(self: @TState, account: ContractAddress) -> u256;
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

///
/// ERC20Balance Component
///
#[starknet::component]
mod erc20_balance_component {
    use super::ERC20BalanceModel;
    use super::IERC20Balance;
    use super::IERC20BalanceCamel;

    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::token::erc20::erc20_allowance::erc20_allowance_component as erc20_allowance_comp;
    use erc20_allowance_comp::InternalImpl as ERC20AllowanceInternal;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Copy, Drop, Serde, starknet::Event)]
    enum Event {
        Transfer: Transfer
    }

    #[derive(Copy, Drop, Serde, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    mod Errors {
        const TRANSFER_FROM_ZERO: felt252 = 'ERC20: transfer from 0';
        const TRANSFER_TO_ZERO: felt252 = 'ERC20: transfer to 0';
    }

    #[embeddable_as(ERC20BalanceImpl)]
    impl ERC20Balance<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Allowance: erc20_allowance_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IERC20Balance<ComponentState<TContractState>> {
        fn balance_of(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.get_balance(account).amount
        }

        fn transfer(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256
        ) -> bool {
            let sender = get_caller_address();
            self.transfer_internal(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let mut erc20_allowance = get_dep_component_mut!(ref self, ERC20Allowance);
            erc20_allowance.spend_allowance(sender, caller, amount);
            self.transfer_internal(sender, recipient, amount);
            true
        }
    }

    #[embeddable_as(ERC20BalanceCamelImpl)]
    impl ERC20BalanceCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Allowance: erc20_allowance_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IERC20BalanceCamel<ComponentState<TContractState>> {
        fn balanceOf(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_balance(
            self: @ComponentState<TContractState>, account: ContractAddress
        ) -> ERC20BalanceModel {
            get!(
                self.get_contract().world(), (get_contract_address(), account), (ERC20BalanceModel)
            )
        }

        fn update_balance(
            ref self: ComponentState<TContractState>,
            account: ContractAddress,
            subtract: u256,
            add: u256
        ) {
            let mut balance = self.get_balance(account);
            // adding and subtracting is fewer steps than if
            balance.amount = balance.amount - subtract;
            balance.amount = balance.amount + add;
            set!(self.get_contract().world(), (balance));
        }

        fn transfer_internal(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            self.update_balance(sender, amount, 0);
            self.update_balance(recipient, 0, amount);

            let transfer_event = Transfer { from: sender, to: recipient, value: amount };

            self.emit(transfer_event.clone());
            emit!(self.get_contract().world(), (Event::Transfer(transfer_event)));
        }
    }
}
