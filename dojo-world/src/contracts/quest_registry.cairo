use starknet::ContractAddress;
use origami_quest::models::quest::Quest;


#[dojo::contract]
mod quest_registry {
    use starknet::{ContractAddress, get_caller_address};
    use origami_quest::models::quest::{Quest};
    use origami_quest::components::quest_registry::{quest_registry_comp, IQuestRegistry};


    component!(path: quest_registry_comp, storage: quest_registry, event: QuestRegistryEvent);

    #[storage]
    struct Storage {
        #[substorage(v0)]
        quest_registry: quest_registry_comp::Storage,
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        #[flat]
        QuestRegistryEvent: quest_registry_comp::Event,
    }

    mod Errors {
        const NOT_NS_WRITER: felt252 = 'not namespace writer!';
    }


    #[abi(embed_v0)]
    impl ImplQuestRegistry<ContractState> of IQuestRegistry<ContractState> {
        fn register_quest(ref self: ContractState, new_quest: Quest) -> felt252 {
            // no check on who can register quest
            quest_registry_comp::InternalTrait::register_quest(ref self.quest_registry, new_quest)
        }

        fn progress(ref self: ContractState, quest_id: felt252, player_id: ContractAddress) {
            quest_registry_comp::InternalTrait::progress(
                ref self.quest_registry, quest_id, player_id
            )
        }
    }
}

