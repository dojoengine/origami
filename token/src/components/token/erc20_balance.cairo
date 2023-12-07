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
}


/// ERC20Balance Component
///
/// TODO: desc
#[starknet::component]
mod ERC20BalanceComponent {
    use super::ERC20BalanceModel;
    use super::IERC20Balance;
    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

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
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>,
    > of IERC20Balance<ComponentState<TContractState>> {
        fn balance_of(self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
            self.get_balance(account).amount
        }
        fn transfer(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256
        ) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_balance(
            self: @ComponentState<TContractState>, account: ContractAddress
        ) -> ERC20BalanceModel {
            get!(
                self.get_contract().world(), (get_contract_address(), account), (ERC20BalanceModel)
            )
        }

        fn _update_balance(
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

        fn _transfer(
            ref self: ComponentState<TContractState>,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), Errors::TRANSFER_FROM_ZERO);
            assert(!recipient.is_zero(), Errors::TRANSFER_TO_ZERO);
            self._update_balance(sender, amount, 0);
            self._update_balance(recipient, 0, amount);

            let transfer_event = Transfer { from: sender, to: recipient, value: amount };
            self.emit(transfer_event.clone());
            emit!(self.get_contract().world(), transfer_event);
        }
    }
}
