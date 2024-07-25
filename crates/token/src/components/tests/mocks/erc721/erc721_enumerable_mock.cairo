use starknet::{ContractAddress, ClassHash};
use dojo::world::IWorldDispatcher;

#[starknet::interface]
trait IERC721EnumerableMock<TState> {
    // IERC721
    fn total_supply(self: @TState) -> u256;
    fn token_by_index(self: @TState, index: u256) -> u256;
    fn token_of_owner_by_index(ref self: TState, owner: ContractAddress, index: u256,) -> u256;

    // IERC721CamelOnly
    fn totalSupply(self: @TState) -> u256;
    fn tokenByIndex(self: @TState, index: u256) -> u256;
    fn tokenOfOwnerByIndex(ref self: TState, owner: ContractAddress, index: u256,) -> u256;

    // IWorldProvider
    fn world(self: @TState,) -> IWorldDispatcher;
}

#[dojo::contract]
mod erc721_enumerable_mock {
    use starknet::ContractAddress;

    use origami_token::components::token::erc721::erc721_approval::erc721_approval_component;
    use origami_token::components::token::erc721::erc721_balance::erc721_balance_component;
    use origami_token::components::token::erc721::erc721_enumerable::erc721_enumerable_component;
    use origami_token::components::token::erc721::erc721_owner::erc721_owner_component;

    component!(
        path: erc721_approval_component, storage: erc721_approval, event: ERC721ApprovalEvent
    );
    component!(path: erc721_balance_component, storage: erc721_balance, event: ERC721BalanceEvent);
    component!(
        path: erc721_enumerable_component, storage: erc721_enumerable, event: ERC721EnumerableEvent
    );
    component!(path: erc721_owner_component, storage: erc721_owner, event: ERC721OwnerEvent);


    #[abi(embed_v0)]
    impl ERC721ApprovalImpl =
        erc721_approval_component::ERC721ApprovalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ApprovalCamelImpl =
        erc721_approval_component::ERC721ApprovalCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721BalanceImpl =
        erc721_balance_component::ERC721BalanceImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721BalanceCamelImpl =
        erc721_balance_component::ERC721BalanceCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        erc721_enumerable_component::ERC721EnumerableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721EnumerableCamelImpl =
        erc721_enumerable_component::ERC721EnumerableCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721OwnerImpl = erc721_owner_component::ERC721OwnerImpl<ContractState>;

    impl ERC721ApprovalInternalImpl = erc721_approval_component::InternalImpl<ContractState>;
    impl ERC721BalanceInternalImpl = erc721_balance_component::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = erc721_enumerable_component::InternalImpl<ContractState>;
    impl ERC721OwnerInternalImpl = erc721_owner_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_approval: erc721_approval_component::Storage,
        #[substorage(v0)]
        erc721_balance: erc721_balance_component::Storage,
        #[substorage(v0)]
        erc721_enumerable: erc721_enumerable_component::Storage,
        #[substorage(v0)]
        erc721_owner: erc721_owner_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ERC721ApprovalEvent: erc721_approval_component::Event,
        ERC721BalanceEvent: erc721_balance_component::Event,
        ERC721EnumerableEvent: erc721_enumerable_component::Event,
        ERC721OwnerEvent: erc721_owner_component::Event,
    }
}
