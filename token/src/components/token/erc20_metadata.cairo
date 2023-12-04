use starknet::ContractAddress;

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct ERC20MetadataModel {
    #[key]
    token: ContractAddress,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

///
/// Interface
///

#[starknet::interface]
trait IERC20Metadata<TState> {
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
}


/// ERC20Metadata Component
///
/// TODO: desc
#[starknet::component]
mod ERC20MetadataComponent {
    use super::ERC20MetadataModel;
    use super::IERC20Metadata;
    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    mod Errors {
      //  const INITIALIZED: felt252 = 'Initializable: is initialized';
    }

    #[embeddable_as(ERC20MetadataImpl)]
    impl ERC20Metadata<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of IERC20Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> felt252{
           self.get_metadata().name
        }
        fn symbol(self: @ComponentState<TContractState>) -> felt252{
           self.get_metadata().symbol
        }
        fn decimals(self: @ComponentState<TContractState>) -> u8{
           self.get_metadata().decimals
        }
    }

    #[generate_trait]
    impl ERC20MetadataInternalImpl<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>, name:felt252, symbol: felt252, decimals: u8) {
            set!(
                self.get_contract().world(),
                ERC20MetadataModel { token: get_contract_address(), name, symbol, decimals }
            )
        }

        fn get_metadata(self: @ComponentState<TContractState>) -> ERC20MetadataModel {
            get!(self.get_contract().world(), get_contract_address(),(ERC20MetadataModel))
        }
    }
}
