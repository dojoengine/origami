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
    total_supply: u256,
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

#[starknet::interface]
trait IERC20MetadataTotalSupply<TState> {
    fn total_supply(self: @TState) -> u256;
}

///
/// ERC20Metadata Component
///
#[starknet::component]
mod ERC20MetadataComponent {
    use super::ERC20MetadataModel;
    use super::IERC20Metadata;
    use super::IERC20MetadataTotalSupply;

    use starknet::get_contract_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    #[storage]
    struct Storage {}

    #[embeddable_as(ERC20MetadataImpl)]
    impl ERC20Metadata<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC20Metadata<ComponentState<TContractState>> {
        fn name(self: @ComponentState<TContractState>) -> felt252 {
            self.get_metadata().name
        }
        fn symbol(self: @ComponentState<TContractState>) -> felt252 {
            self.get_metadata().symbol
        }
        fn decimals(self: @ComponentState<TContractState>) -> u8 {
            self.get_metadata().decimals
        }
    }

    #[embeddable_as(ERC20MetadataTotalSupplyImpl)]
    impl ERC20MetadataTotalSupply<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC20MetadataTotalSupply<ComponentState<TContractState>> {
        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            self.get_metadata().total_supply
        }
    }


    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn get_metadata(self: @ComponentState<TContractState>) -> ERC20MetadataModel {
            get!(self.get_contract().world(), get_contract_address(), (ERC20MetadataModel))
        }

        fn _initialize(
            ref self: ComponentState<TContractState>, name: felt252, symbol: felt252, decimals: u8
        ) {
            set!(
                self.get_contract().world(),
                ERC20MetadataModel {
                    token: get_contract_address(), name, symbol, decimals, total_supply: 0
                }
            )
        }

        // Helper function to update total_supply model
        fn _update_total_supply(
            ref self: ComponentState<TContractState>, subtract: u256, add: u256
        ) {
            let mut meta = self.get_metadata();
            // adding and subtracting is fewer steps than if
            meta.total_supply = meta.total_supply - subtract;
            meta.total_supply = meta.total_supply + add;
            set!(self.get_contract().world(), (meta));
        }
    }
}
