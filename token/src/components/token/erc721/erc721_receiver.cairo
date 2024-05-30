use starknet::ContractAddress;

///
/// Interface
///

#[starknet::interface]
trait IERC721Receiver<TState> {
    fn on_erc721_received(self: @TState, operator: ContractAddress, from: ContractAddress, token_id: u256, data: Span<felt252>) -> felt252;
}

#[starknet::interface]
trait IERC721ReceiverCamel<TState> {
    fn onERC721Received(self: @TState, operator: ContractAddress, from: ContractAddress, tokenId: u256, data: Span<felt252>) -> felt252;
}

///
/// ERC721Receiver Component
///
#[starknet::component]
mod erc721_receiver_component {
    use super::IERC721Receiver;
    use super::IERC721ReceiverCamel;
    use starknet::ContractAddress;
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
    };

    use token::components::introspection::src5::src5_component as src5_comp;
    use src5_comp::InternalImpl as SRC5Internal;

    use token::components::token::erc721::interface::IERC721_RECEIVER_ID;


    #[storage]
    struct Storage {}

    #[embeddable_as(ERC721ReceiverImpl)]
    impl ERC721Receiver<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721Receiver<ComponentState<TContractState>> {
        fn on_erc721_received(self: @ComponentState<TContractState>, operator: ContractAddress, from: ContractAddress, token_id: u256, data: Span<felt252>) -> felt252 {
            IERC721_RECEIVER_ID
        }
    }

    #[embeddable_as(ERC721ReceiverCamelImpl)]
    impl ERC721ReceiverCamel<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +Drop<TContractState>,
    > of IERC721ReceiverCamel<ComponentState<TContractState>> {
        fn onERC721Received(self: @ComponentState<TContractState>, operator: ContractAddress, from: ContractAddress, tokenId: u256, data: Span<felt252>) -> felt252 {
            IERC721_RECEIVER_ID
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        impl SRC5: src5_comp::HasComponent<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        /// Initializes the contract by registering the IERC721Receiver interface ID.
        /// This should be used inside the contract's constructor.
        fn initializer(ref self: ComponentState<TContractState>) {
            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(IERC721_RECEIVER_ID);
        }
    }
}