/// adaptation of https://github.com/OpenZeppelin/cairo-contracts/blob/main/src/security/initializable.cairo for dojo

use starknet::ContractAddress;

///
/// Model
///

#[derive(Copy, Drop, Serde)]
#[dojo::model]
struct InitializableModel {
    #[key]
    token: ContractAddress,
    initialized: bool,
}

///
/// Interface
///

#[starknet::interface]
trait IInitializable<TState> {
    fn is_initialized(self: @TState) -> bool;
}


/// Initializable Component
///
/// The Initializable component provides a simple mechanism that executes
/// logic once and only once. This can be useful for setting a contract's
/// initial state in scenarios where a constructor cannot be used.
#[starknet::component]
mod initializable_component {
    use super::InitializableModel;
    use super::IInitializable;
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    mod Errors {
        const INITIALIZED: felt252 = 'Initializable: is initialized';
    }

    #[embeddable_as(InitializableImpl)]
    impl Initializable<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of IInitializable<ComponentState<TContractState>> {
        /// Returns true if the using contract executed `initialize`.
        fn is_initialized(self: @ComponentState<TContractState>) -> bool {
            get!(self.get_contract().world(), get_contract_address(), (InitializableModel))
                .initialized
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of InternalTrait<TContractState> {
        /// Ensures the calling function can only be called once.
        fn initialize(ref self: ComponentState<TContractState>) {
            assert(!self.is_initialized(), Errors::INITIALIZED);
            set!(
                self.get_contract().world(),
                InitializableModel { token: get_contract_address(), initialized: true }
            )
        }
    }
}
