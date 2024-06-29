use starknet::{ContractAddress, ClassHash};
use dojo::world::IWorldDispatcher;

#[starknet::interface]
trait IERC721EnumMintBurnPreset<TState> {
    // IERC721
    fn name(self: @TState) -> ByteArray;
    fn symbol(self: @TState) -> ByteArray;
    fn token_uri(self: @TState, token_id: u256) -> ByteArray;
    fn owner_of(self: @TState, account: ContractAddress) -> bool;
    fn get_approved(self: @TState, token_id: u256) -> ContractAddress;
    fn approve(ref self: TState, to: ContractAddress, token_id: u256);
    fn total_supply(self: @TState) -> u256;
    fn token_by_index(self: @TState, index: u256) -> u256;
    fn token_of_owner_by_index(self: @TState, owner: ContractAddress, index: u256) -> u256;

    // IERC721CamelOnly
    fn tokenURI(self: @TState, token_id: u256) -> ByteArray;

    // IWorldProvider
    fn world(self: @TState,) -> IWorldDispatcher;

    fn initializer(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        recipient: ContractAddress,
        token_ids: Span<u256>
    );
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn transfer_from(ref self: TState, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safe_transfer_from(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn mint(ref self: TState, to: ContractAddress, token_id: u256);
    fn burn(ref self: TState, token_id: u256);
}

#[starknet::interface]
trait IERC721EnumInit<TState> {
    fn initializer(
        ref self: TState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        recipient: ContractAddress,
        token_ids: Span<u256>
    );
}

#[starknet::interface]
trait IERC721EnumTransfer<TState> {
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn transfer_from(ref self: TState, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safe_transfer_from(
        ref self: TState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
}

#[starknet::interface]
trait IERC721EnumMintBurn<TState> {
    fn mint(ref self: TState, to: ContractAddress, token_id: u256);
    fn burn(ref self: TState, token_id: u256);
}

#[dojo::contract]
mod ERC721EnumMintBurn {
    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};
    use token::components::security::initializable::initializable_component;
    use token::components::token::erc721::erc721_approval::erc721_approval_component;
    use token::components::token::erc721::erc721_balance::erc721_balance_component;
    use token::components::token::erc721::erc721_burnable::erc721_burnable_component;
    use token::components::token::erc721::erc721_enumerable::erc721_enumerable_component;
    use token::components::token::erc721::erc721_metadata::erc721_metadata_component;
    use token::components::token::erc721::erc721_mintable::erc721_mintable_component;
    use token::components::token::erc721::erc721_owner::erc721_owner_component;

    component!(path: initializable_component, storage: initializable, event: InitializableEvent);

    component!(
        path: erc721_approval_component, storage: erc721_approval, event: ERC721ApprovalEvent
    );
    component!(path: erc721_balance_component, storage: erc721_balance, event: ERC721BalanceEvent);
    component!(
        path: erc721_burnable_component, storage: erc721_burnable, event: ERC721BurnableEvent
    );
    component!(
        path: erc721_enumerable_component, storage: erc721_enumerable, event: ERC721EnumerableEvent
    );
    component!(
        path: erc721_metadata_component, storage: erc721_metadata, event: ERC721MetadataEvent
    );
    component!(
        path: erc721_mintable_component, storage: erc721_mintable, event: ERC721MintableEvent
    );
    component!(path: erc721_owner_component, storage: erc721_owner, event: ERC721OwnerEvent);

    impl InitializableImpl = initializable_component::InitializableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ApprovalImpl =
        erc721_approval_component::ERC721ApprovalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721ApprovalCamelImpl =
        erc721_approval_component::ERC721ApprovalCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        erc721_enumerable_component::ERC721EnumerableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721EnumerableCamelImpl =
        erc721_enumerable_component::ERC721EnumerableCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721MetadataImpl =
        erc721_metadata_component::ERC721MetadataImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721MetadataCamelImpl =
        erc721_metadata_component::ERC721MetadataCamelImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721OwnerImpl = erc721_owner_component::ERC721OwnerImpl<ContractState>;

    impl InitializableInternalImpl = initializable_component::InternalImpl<ContractState>;
    impl ERC721ApprovalInternalImpl = erc721_approval_component::InternalImpl<ContractState>;
    impl ERC721BalanceInternalImpl = erc721_balance_component::InternalImpl<ContractState>;
    impl ERC721BurnableInternalImpl = erc721_burnable_component::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = erc721_enumerable_component::InternalImpl<ContractState>;
    impl ERC721MetadataInternalImpl = erc721_metadata_component::InternalImpl<ContractState>;
    impl ERC721MintableInternalImpl = erc721_mintable_component::InternalImpl<ContractState>;
    impl ERC721OwnerInternalImpl = erc721_owner_component::InternalImpl<ContractState>;

    mod Errors {
        const CALLER_IS_NOT_OWNER: felt252 = 'ERC721: caller is not owner';
        const INVALID_ACCOUNT: felt252 = 'ERC721: invalid account';
        const UNAUTHORIZED: felt252 = 'ERC721: unauthorized caller';
        const INVALID_RECEIVER: felt252 = 'ERC721: invalid receiver';
        const WRONG_SENDER: felt252 = 'ERC721: wrong sender';
        const SAFE_TRANSFER_FAILED: felt252 = 'ERC721: safe transfer failed';
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        initializable: initializable_component::Storage,
        #[substorage(v0)]
        erc721_approval: erc721_approval_component::Storage,
        #[substorage(v0)]
        erc721_balance: erc721_balance_component::Storage,
        #[substorage(v0)]
        erc721_burnable: erc721_burnable_component::Storage,
        #[substorage(v0)]
        erc721_enumerable: erc721_enumerable_component::Storage,
        #[substorage(v0)]
        erc721_metadata: erc721_metadata_component::Storage,
        #[substorage(v0)]
        erc721_mintable: erc721_mintable_component::Storage,
        #[substorage(v0)]
        erc721_owner: erc721_owner_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        InitializableEvent: initializable_component::Event,
        #[flat]
        ERC721ApprovalEvent: erc721_approval_component::Event,
        #[flat]
        ERC721BalanceEvent: erc721_balance_component::Event,
        #[flat]
        ERC721BurnableEvent: erc721_burnable_component::Event,
        #[flat]
        ERC721EnumerableEvent: erc721_enumerable_component::Event,
        #[flat]
        ERC721MetadataEvent: erc721_metadata_component::Event,
        #[flat]
        ERC721MintableEvent: erc721_mintable_component::Event,
        #[flat]
        ERC721OwnerEvent: erc721_owner_component::Event,
    }

    #[abi(embed_v0)]
    impl InitializerImpl of super::IERC721EnumInit<ContractState> {
        fn initializer(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            base_uri: ByteArray,
            recipient: ContractAddress,
            token_ids: Span<u256>
        ) {
            assert(
                self.world().is_owner(get_caller_address(), get_contract_address().into()),
                Errors::CALLER_IS_NOT_OWNER
            );

            self.erc721_metadata.initialize(name, symbol, base_uri);
            self.mint_assets(recipient, token_ids);

            self.initializable.initialize();
        }
    }

    #[abi(embed_v0)]
    impl TransferImpl of super::IERC721EnumTransfer<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc721_balance.get_balance(account).amount.into()
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            assert(
                self.erc721_approval.is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.erc721_balance.transfer_internal(from, to, token_id);
            self.erc721_enumerable.remove_token_from_owner_enumeration(from, token_id);
            self.erc721_enumerable.add_token_to_owner_enumeration(to, token_id);
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            assert(
                self.erc721_approval.is_approved_or_owner(get_caller_address(), token_id),
                Errors::UNAUTHORIZED
            );
            self.erc721_balance.safe_transfer_internal(from, to, token_id, data);
            self.erc721_enumerable.remove_token_from_owner_enumeration(from, token_id);
            self.erc721_enumerable.add_token_to_owner_enumeration(to, token_id);
        }
    }

    #[abi(embed_v0)]
    impl MintBurnImpl of super::IERC721EnumMintBurn<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.erc721_mintable.mint(to, token_id);
            self.erc721_enumerable.add_token_to_all_tokens_enumeration(token_id);
            self.erc721_enumerable.add_token_to_owner_enumeration(to, token_id);
        }

        fn burn(ref self: ContractState, token_id: u256) {
            self.erc721_burnable.burn(token_id);
            self.erc721_enumerable.remove_token_from_all_tokens_enumeration(token_id);
            let owner = self.erc721_owner.owner_of(token_id);
            self.erc721_enumerable.remove_token_from_owner_enumeration(owner, token_id);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn mint_assets(
            ref self: ContractState, recipient: ContractAddress, mut token_ids: Span<u256>
        ) {
            loop {
                if token_ids.len() == 0 {
                    break;
                }
                let id = *token_ids.pop_front().unwrap();

                self.erc721_mintable.mint(recipient, id);
                self.erc721_enumerable.add_token_to_all_tokens_enumeration(id);
                self.erc721_enumerable.add_token_to_owner_enumeration(recipient, id);
            }
        }
    }
}
