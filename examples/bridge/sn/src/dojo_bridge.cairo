use starknet::{ContractAddress, ClassHash};
use dojo::world::IWorldDispatcher;

#[starknet::interface]
trait IDojoBridge<TState> {
    // IWorldProvider
    fn world(self: @TState, ) -> IWorldDispatcher;

    // IUpgradeable
    fn upgrade(ref self: TState, new_class_hash: ClassHash);

    // WITHOUT INTERFACE !!!
    fn initializer(ref self: TState, l1_bridge: felt252, l2_token: ContractAddress);
    fn initiate_withdrawal(ref self: TState, l1_recipient: felt252, amount: u256);
    fn get_l1_bridge(self: @TState, ) -> felt252;
    fn get_token(self: @TState, ) -> ContractAddress;
    fn dojo_resource(self: @TState, ) -> felt252;
}

///
/// Model
///

#[derive(Model, Copy, Drop, Serde)]
struct DojoBridgeModel {
    #[key]
    bridge: ContractAddress,
    // address L1 bridge contract address, the L1 counterpart to this contract
    l1_bridge: felt252,
    // Dojo ERC20 token on Starknet
    l2_token: ContractAddress
}


#[starknet::interface]
trait IDojoBridgeTrait<TState> { 
    fn initiate_withdrawal(ref self: TState, l1_recipient: felt252, amount: u256);
    fn get_l1_bridge(self: @TState, ) -> felt252;
    fn get_token(self: @TState, ) -> ContractAddress;
}

#[starknet::interface]
trait IDojoBridgeInitializerTrait<TState> { 
    fn initializer(ref self: TState, l1_bridge: felt252, l2_token: ContractAddress);
}


#[dojo::contract]
mod dojo_bridge {
    use super::DojoBridgeModel;
    use starknet::ContractAddress;
    use starknet::{get_contract_address, get_caller_address};

    use token::components::token::erc20::erc20_bridgeable::{
        IERC20Bridgeable, IERC20BridgeableDispatcher, IERC20BridgeableDispatcherTrait
    };

    use token::components::security::initializable::initializable_component;

    component!(path: initializable_component, storage: initializable, event: InitializableEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        initializable: initializable_component::Storage,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        InitializableEvent: initializable_component::Event,
        DepositHandled: DepositHandled,
        WithdrawalInitiated: WithdrawalInitiated,
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct DepositHandled {
        recipient: ContractAddress,
        amount: u256
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct WithdrawalInitiated {
        #[key]
        sender: ContractAddress,
        recipient: felt252,
        amount: u256
    }

    mod Errors {
        const CALLER_IS_NOT_OWNER: felt252 = 'Bridge: caller is not owner';
        const INVALID_L1_ORIGIN: felt252 = 'Bridge: invalid L1 origin';

        const L1_ADDRESS_CANNOT_BE_ZERO: felt252 = 'Bridge: L1 address cannot be 0';
        const L1_ADDRESS_OUT_OF_BOUNDS: felt252 = 'Bridge: L1 addr out of bounds';
        const INVALID_RECIPIENT: felt252 = 'Bridge: invalid recipient';
    }


    // operation ID sent in the message payload to L1
    const PROCESS_WITHDRAWAL: felt252 = 1;

    // Ethereum addresses are bound to 2**160
    const ETH_ADDRESS_BOUND: u256 = 0x10000000000000000000000000000000000000000_u256;

    impl InitializableImpl = initializable_component::InitializableImpl<ContractState>;
    impl InitializableInternalImpl = initializable_component::InternalImpl<ContractState>;

    //
    // Initializer
    //

    #[abi(embed_v0)]
    impl DojoBridgeInitializerImpl of super::IDojoBridgeInitializerTrait<ContractState> {
        fn initializer(ref self: ContractState, l1_bridge: felt252, l2_token: ContractAddress) {
            assert(
                self.world().is_owner(get_caller_address(), get_contract_address().into()),
                Errors::CALLER_IS_NOT_OWNER
            );

            // one time bridge initialization
            set!(
                self.world(), DojoBridgeModel { bridge: get_contract_address(), l1_bridge, l2_token }
            );

            // reverts if already initialized
            self.initializable.initialize();
        }
    }

    //
    // L1 Handler
    //

    #[l1_handler]
    fn handle_deposit(
        ref self: ContractState, from_address: felt252, recipient: ContractAddress, amount: u256
    ) {
        let data = self.get_data();
        assert(from_address == data.l1_bridge, Errors::INVALID_L1_ORIGIN);

        // mint token
        let token_dispatcher = IERC20BridgeableDispatcher { contract_address: data.l2_token };
        token_dispatcher.mint(recipient, amount);

        let event = DepositHandled { recipient, amount };

        self.emit(event.clone());
        emit!(self.world(), (Event::DepositHandled(event)));
    }

    //
    // Impls
    //

    #[abi(embed_v0)]
    impl DojoBridgeImpl of super::IDojoBridgeTrait<ContractState> {
        fn initiate_withdrawal(ref self: ContractState, l1_recipient: felt252, amount: u256) {
            let data = self.get_data();
            let caller = get_caller_address();

            assert(l1_recipient.is_non_zero(), Errors::L1_ADDRESS_CANNOT_BE_ZERO);
            assert(l1_recipient.into() < ETH_ADDRESS_BOUND, Errors::L1_ADDRESS_OUT_OF_BOUNDS);
            assert(l1_recipient != data.l1_bridge, Errors::INVALID_RECIPIENT);

            // burn token
            let token_dispatcher = IERC20BridgeableDispatcher { contract_address: data.l2_token };
            token_dispatcher.burn(caller, amount);

            let message: Array<felt252> = array![
                PROCESS_WITHDRAWAL, l1_recipient, amount.low.into(), amount.high.into()
            ];

            // send msg to L1
            starknet::syscalls::send_message_to_l1_syscall(data.l1_bridge, message.span()).unwrap();

            let event = WithdrawalInitiated { sender: caller, recipient: l1_recipient, amount };
           
            self.emit(event.clone());
            emit!(self.world(), (Event::WithdrawalInitiated(event)));
        }

        fn get_l1_bridge(self: @ContractState) -> felt252 {
            self.get_data().l1_bridge
        }

        fn get_token(self: @ContractState) -> ContractAddress {
            self.get_data().l2_token
        }
    }


    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_data(self: @ContractState) -> DojoBridgeModel {
            get!(self.world(), get_contract_address(), (DojoBridgeModel))
        }

    }
}

