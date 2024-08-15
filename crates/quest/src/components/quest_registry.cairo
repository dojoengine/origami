use starknet::ContractAddress;
use origami_quest::models::quest::Quest;

#[starknet::interface]
trait IQuestRegistry<T> {
    fn register_quest(ref self: T, new_quest: Quest) -> felt252;
    fn progress(ref self: T, quest_id: felt252, player_id: ContractAddress);
}

#[starknet::component]
mod quest_registry_comp {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use dojo::world::{
        IWorldProvider, IWorldProviderDispatcher, IWorldProviderDispatcherTrait, IWorldDispatcher,
        IWorldDispatcherTrait
    };
    use dojo::model::Model;
    use dojo::contract::{IContract, IContractDispatcher, IContractDispatcherTrait};

    use origami_quest::models::quest::{
        Quest, QuestStore, QuestCounter, QuestCounterStore, QuestType
    };
    use origami_quest::helpers::quest::{QuestTrait, QuestHelperTrait};
    use origami_quest::utils::get_contract_infos;

    #[storage]
    struct Storage {}

    mod Errors {
        const NOT_NS_WRITER: felt252 = 'not namespace writer!';
        const QUEST_ID_ALREADY_REGISTERED: felt252 = 'quest id already registered!';
        const INVALID_QUEST_ID: felt252 = 'invalid quest id';
        const INVALID_QUEST: felt252 = 'invalid quest';
        const INVALID_CALLER: felt252 = 'invalid caller';
        const INVALID_CROSS_NS: felt252 = 'invalid cross ns';
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        QuestRegistered: QuestRegistered,
        QuestProgress: QuestProgress,
    }

    #[derive(Drop, Serde, starknet::Event)]
    struct QuestRegistered {
        #[key]
        id: felt252,
        quest: Quest,
    }

    #[derive(Drop, Serde, starknet::Event)]
    struct QuestProgress {
        #[key]
        quest_id: felt252,
        #[key]
        player_id: ContractAddress,
        count: u64,
    }

    #[embeddable_as(ImplQuestRegistry)]
    impl QuestRegistryImpl<
        TContractState,
        +HasComponent<TContractState>,
        +IWorldProvider<TContractState>,
        +IContract<TContractState>
    > of super::IQuestRegistry<ComponentState<TContractState>> {
        fn register_quest(ref self: ComponentState<TContractState>, new_quest: Quest) -> felt252 {
            let world = self.get_contract().world();

            // retrieve caller account
            let caller_account = starknet::get_tx_info().unbox().account_contract_address;

            // retrieve current namespace_hash
            let namespace_hash = self.get_contract().namespace_hash();

            // check caller account is writer for namespace
            let is_writer = world.is_writer(namespace_hash, caller_account);
            assert(is_writer, Errors::NOT_NS_WRITER);

            InternalTrait::register_quest(ref self, new_quest)
        }


        fn progress(
            ref self: ComponentState<TContractState>, quest_id: felt252, player_id: ContractAddress
        ) {
            let world = self.get_contract().world();

            // get caller
            let caller = get_caller_address();
            let caller_disp = IContractDispatcher { contract_address: caller };

            let caller_namespace = caller_disp.namespace_hash();
            let registry_namespace = IContractDispatcher {
                contract_address: get_contract_address()
            }
                .namespace_hash();
            // check same namespace
            assert(caller_namespace == registry_namespace, Errors::INVALID_CROSS_NS);

            // check caller is a contract registered in world / for selector
            let caller_selector = caller_disp.selector();
            // panic if not exists
            let (_, caller_selector_address) = get_contract_infos(world, caller_selector);
            // check retrieved address == caller address
            assert(caller_selector_address == caller, Errors::INVALID_CALLER);

            InternalTrait::progress(ref self, quest_id, player_id)
        }
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IWorldProvider<TContractState>
    > of InternalTrait<TContractState> {
        fn register_quest(ref self: ComponentState<TContractState>, new_quest: Quest) -> felt252 {
            let world = self.get_contract().world();

            // get / init quest
            let mut quest = QuestStore::get(world, new_quest.id);

            // check quest not already registered
            assert(!quest.exists(), Errors::QUEST_ID_ALREADY_REGISTERED);

            // check quest is valid
            assert(new_quest.is_valid(), Errors::INVALID_QUEST);

            // create quest
            new_quest.set(world);

            // // emit event
            let id = quest.entity_id();
            emit!(world, (Event::QuestRegistered(QuestRegistered { id, quest: new_quest })));

            id
        }


        fn progress(
            ref self: ComponentState<TContractState>, quest_id: felt252, player_id: ContractAddress
        ) {
            let world = self.get_contract().world();

            // get quest
            let mut quest = QuestStore::get(world, quest_id);

            // check valid quest
            assert(quest.exists(), Errors::INVALID_QUEST_ID);

            let mut counter = QuestCounterStore::get(world, quest_id, player_id);

            match quest.quest_type {
                QuestType::Infinite => {
                    // increase counter on completion
                    if quest.is_completed(world, player_id) {
                        counter.count = counter.count + 1;
                        counter.set(world);
                    }
                },
                QuestType::OneTime => {
                    // set count to 1
                    if counter.count < 1 && quest.is_completed(world, player_id) {
                        counter.count = 1;
                        counter.set(world);
                    }
                }
            };
            // // emit QuestProgress
            emit!(
                world,
                (Event::QuestProgress(QuestProgress { quest_id, player_id, count: counter.count }))
            );
        }
    }
}

