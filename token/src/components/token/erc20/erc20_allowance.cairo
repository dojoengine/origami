use starknet::ContractAddress;

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct ERC20AllowanceModel {
    #[key]
    token: ContractAddress,
    #[key]
    owner: ContractAddress,
    #[key]
    spender: ContractAddress,
    amount: u256,
}

///
/// Interface
///

#[starknet::interface]
trait IERC20Allowance<TState> {
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IERC20SafeAllowance<TState> {
    fn increase_allowance(ref self: TState, spender: ContractAddress, added_value: u256) -> bool;
    fn decrease_allowance(
        ref self: TState, spender: ContractAddress, subtracted_value: u256
    ) -> bool;
}

#[starknet::interface]
trait IERC20SafeAllowanceCamel<TState> {
    fn increaseAllowance(ref self: TState, spender: ContractAddress, addedValue: u256) -> bool;
    fn decreaseAllowance(ref self: TState, spender: ContractAddress, subtractedValue: u256) -> bool;
}

///
/// ERC20Allowance Component
///
#[starknet::component]
mod ERC20AllowanceComponent {
    use super::ERC20AllowanceModel;
    use super::IERC20Allowance;
    use super::IERC20SafeAllowance;
    use super::IERC20SafeAllowanceCamel;
    use integer::BoundedInt;
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
        Approval: Approval
    }

    #[derive(Copy, Drop, Serde, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    mod Errors {
        const APPROVE_FROM_ZERO: felt252 = 'ERC20: approve from 0';
        const APPROVE_TO_ZERO: felt252 = 'ERC20: approve to 0';
    }

    #[embeddable_as(ERC20AllowanceImpl)]
    impl ERC20Allowance<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>
    > of IERC20Allowance<ComponentState<TContractState>> {
        fn allowance(
            self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.get_allowance(owner, spender).amount
        }
        fn approve(
            ref self: ComponentState<TContractState>, spender: ContractAddress, amount: u256
        ) -> bool {
            let owner = get_caller_address();
            self
                .set_allowance(
                    ERC20AllowanceModel { token: get_contract_address(), owner, spender, amount }
                );
            true
        }
    }

    #[embeddable_as(ERC20SafeAllowanceImpl)]
    impl ERC20SafeAllowance<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>
    > of IERC20SafeAllowance<ComponentState<TContractState>> {
        fn increase_allowance(
            ref self: ComponentState<TContractState>, spender: ContractAddress, added_value: u256
        ) -> bool {
            self.update_allowance(get_caller_address(), spender, 0, added_value);
            true
        }

        fn decrease_allowance(
            ref self: ComponentState<TContractState>,
            spender: ContractAddress,
            subtracted_value: u256
        ) -> bool {
            self.update_allowance(get_caller_address(), spender, subtracted_value, 0);
            true
        }
    }

    #[embeddable_as(ERC20SafeAllowanceCamelImpl)]
    impl ERC20SafeAllowanceCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>
    > of IERC20SafeAllowanceCamel<ComponentState<TContractState>> {
        fn increaseAllowance(
            ref self: ComponentState<TContractState>, spender: ContractAddress, addedValue: u256
        ) -> bool {
            self.increase_allowance(spender, addedValue)
        }

        fn decreaseAllowance(
            ref self: ComponentState<TContractState>,
            spender: ContractAddress,
            subtractedValue: u256
        ) -> bool {
            self.decrease_allowance(spender, subtractedValue)
        }
    }

    ///
    /// Internal
    ///

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        // Helper function for allowance model
        fn get_allowance(
            self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress,
        ) -> ERC20AllowanceModel {
            get!(
                self.get_contract().world(),
                (get_contract_address(), owner, spender),
                ERC20AllowanceModel
            )
        }

        fn set_allowance(ref self: ComponentState<TContractState>, allowance: ERC20AllowanceModel) {
            assert(!allowance.owner.is_zero(), Errors::APPROVE_FROM_ZERO);
            assert(!allowance.spender.is_zero(), Errors::APPROVE_TO_ZERO);
            set!(self.get_contract().world(), (allowance));

            let approval_event = Approval {
                owner: allowance.owner, spender: allowance.spender, value: allowance.amount
            };
            self.emit_event(approval_event);
        }

        fn update_allowance(
            ref self: ComponentState<TContractState>,
            owner: ContractAddress,
            spender: ContractAddress,
            subtract: u256,
            add: u256
        ) {
            let mut allowance = self.get_allowance(owner, spender);
            // adding and subtracting is fewer steps than if
            allowance.amount = allowance.amount - subtract;
            allowance.amount = allowance.amount + add;
            self.set_allowance(allowance);
        }

        // use in transfer_from
        fn spend_allowance(
            ref self: ComponentState<TContractState>,
            owner: ContractAddress,
            spender: ContractAddress,
            amount: u256
        ) {
            let current_allowance = self.get_allowance(owner, spender).amount;
            if current_allowance != BoundedInt::max() {
                self.update_allowance(owner, spender, amount, 0);
            }
        }

        fn emit_event<S, +traits::Into<S, Event>, +Drop<S>, +Clone<S>>(
            ref self: ComponentState<TContractState>, event: S
        ) {
            self.emit(event.clone());
            emit!(self.get_contract().world(), event);
        }
    }
}
