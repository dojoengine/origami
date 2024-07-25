use starknet::ContractAddress;

///
/// Model
///

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ERC20BridgeableModel {
    #[key]
    token: ContractAddress,
    l2_bridge_address: ContractAddress
}

///
/// Interface
///

#[starknet::interface]
trait IERC20Bridgeable<TState> {
    fn l2_bridge_address(self: @TState) -> ContractAddress;
    fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TState, account: ContractAddress, amount: u256);
}

///
/// ERC20Bridgeable Component
///
#[starknet::component]
mod erc20_bridgeable_component {
    use super::IERC20Bridgeable;
    use super::ERC20BridgeableModel;
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use starknet::get_caller_address;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use origami_token::components::token::erc20::erc20_balance::erc20_balance_component as erc20_balance_comp;
    use origami_token::components::token::erc20::erc20_metadata::erc20_metadata_component as erc20_metadata_comp;
    use origami_token::components::token::erc20::erc20_mintable::erc20_mintable_component as erc20_mintable_comp;
    use origami_token::components::token::erc20::erc20_burnable::erc20_burnable_component as erc20_burnable_comp;

    use erc20_balance_comp::InternalImpl as ERC20BalanceInternal;
    use erc20_metadata_comp::InternalImpl as ERC20MetadataInternal;
    use erc20_mintable_comp::InternalImpl as ERC20MintableInternal;
    use erc20_burnable_comp::InternalImpl as ERC20BurnableInternal;

    #[storage]
    struct Storage {}

    mod Errors {
        const CALLER_IS_NOT_BRIDGE: felt252 = 'ERC20: caller not bridge';
    }

    #[embeddable_as(ERC20BridgeableImpl)]
    impl ERC20Bridgeable<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Balance: erc20_balance_comp::HasComponent<TContractState>,
        impl ERC20Metadata: erc20_metadata_comp::HasComponent<TContractState>,
        impl ERC20Mintable: erc20_mintable_comp::HasComponent<TContractState>,
        impl ERC20Burnable: erc20_burnable_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IERC20Bridgeable<ComponentState<TContractState>> {
        fn l2_bridge_address(self: @ComponentState<TContractState>) -> ContractAddress {
            get!(self.get_contract().world(), get_contract_address(), ERC20BridgeableModel)
                .l2_bridge_address
        }

        fn mint(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256
        ) {
            self.assert_is_bridge(get_caller_address());

            let mut erc20_mintable = get_dep_component_mut!(ref self, ERC20Mintable);
            erc20_mintable.mint(recipient, amount);
        }

        fn burn(ref self: ComponentState<TContractState>, account: ContractAddress, amount: u256) {
            self.assert_is_bridge(get_caller_address());

            let mut erc20_burnable = get_dep_component_mut!(ref self, ERC20Burnable);
            erc20_burnable.burn(account, amount);
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl ERC20Balance: erc20_balance_comp::HasComponent<TContractState>,
        impl ERC20Metadata: erc20_metadata_comp::HasComponent<TContractState>,
        impl ERC20Mintable: erc20_mintable_comp::HasComponent<TContractState>,
        impl ERC20Burnable: erc20_burnable_comp::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>, l2_bridge_address: ContractAddress
        ) {
            set!(
                self.get_contract().world(),
                ERC20BridgeableModel { token: get_contract_address(), l2_bridge_address, }
            )
        }

        fn assert_is_bridge(self: @ComponentState<TContractState>, address: ContractAddress) {
            assert(address == self.l2_bridge_address(), Errors::CALLER_IS_NOT_BRIDGE);
        }
    }
}
