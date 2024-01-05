/// adaptation of https://github.com/OpenZeppelin/cairo-contracts/blob/main/src/introspection/src5.cairo for dojo

use starknet::ContractAddress;

const ISRC5_ID: felt252 = 0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055;

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct SRC5Model {
    #[key]
    token: ContractAddress,
    #[key]
    interface_id: felt252,
    supports: bool,
}

///
/// Interface
///

#[starknet::interface]
trait ISRC5<TState> {
    fn supports_interface(self: @TState, interface_id: felt252) -> bool;
}

#[starknet::interface]
trait ISRC5Camel<TState> {
    fn supportsInterface(self: @TState, interfaceId: felt252) -> bool;
}

/// # SRC5 Component
///
/// The SRC5 component allows contracts to expose the interfaces they implement.
#[starknet::component]
mod SRC5Component {
    use super::{SRC5Model, ISRC5, ISRC5Camel, ISRC5_ID};
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    mod Errors {
        const INVALID_ID: felt252 = 'SRC5: invalid id';
    }

    #[embeddable_as(SRC5Impl)]
    impl SRC5<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of ISRC5<ComponentState<TContractState>> {
        /// Returns whether the contract implements the given interface.
        fn supports_interface(
            self: @ComponentState<TContractState>, interface_id: felt252
        ) -> bool {
            if interface_id == ISRC5_ID {
                return true;
            }
            self.supports_interface_internal(interface_id)
        }
    }

    #[embeddable_as(SRC5CamelImpl)]
    impl SRC5Camel<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of ISRC5Camel<ComponentState<TContractState>> {
        fn supportsInterface(self: @ComponentState<TContractState>, interfaceId: felt252) -> bool {
            self.supports_interface(interfaceId)
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of InternalTrait<TContractState> {
        /// Registers the given interface as supported by the contract.
        fn register_interface(ref self: ComponentState<TContractState>, interface_id: felt252) {
            set!(
                self.get_contract().world(),
                SRC5Model { token: get_contract_address(), interface_id, supports: true }
            );
        }

        /// Deregisters the given interface as supported by the contract.
        ///
        /// Requirements:
        ///
        /// - `interface_id` is not `ISRC5_ID`
        fn deregister_interface(ref self: ComponentState<TContractState>, interface_id: felt252) {
            assert(interface_id != ISRC5_ID, Errors::INVALID_ID);
            set!(
                self.get_contract().world(),
                SRC5Model { token: get_contract_address(), interface_id, supports: false }
            );
        }

        fn supports_interface_internal(
            self: @ComponentState<TContractState>, interface_id: felt252
        ) -> bool {
            get!(self.get_contract().world(), (get_contract_address(), interface_id), (SRC5Model))
                .supports
        }
    }
}
