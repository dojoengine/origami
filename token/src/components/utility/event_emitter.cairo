// /// Event emitter Component
// ///
// /// Emit an event for both token contract & dojo world
// #[starknet::component]
// mod EventEmitterComponent {
//     //use super::IEventEmitter;
//     use starknet::get_contract_address;
//     use starknet::event::EventEmitter;
//     use dojo::world::{
//         IWorldProvider, IWorldProviderDispatcher, IWorldDispatcher, IWorldDispatcherTrait
//     };

//     #[storage]
//     struct Storage {}

//     #[event]
//     #[derive(Drop, Copy, Serde, starknet::Event)]
//     enum Event {}

//     #[generate_trait]
//     impl InternalImpl<
//         TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>,
//     > of InternalTrait<TContractState> {
//         fn emit_event<S,E, +traits::Into<S, E>, +Drop<S>>(
//             ref self: ComponentState<TContractState>, event: S
//         ) {
//             // not ok :(
//             //let mut contract_mut = self.get_contract_mut();
//             //starknet::event::EventEmitter::emit(ref contract_mut, event);
//             //contract_mut.emit(event);
//             self.emit(event);
//             emit!(self.get_contract().world(), event);
//         }
//     }
// }

