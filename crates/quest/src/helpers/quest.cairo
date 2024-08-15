use starknet::ContractAddress;

use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use dojo::utils::selector_from_names;

use origami_quest::models::quest::{
    Quest, QuestStore, QuestType, QuestCounter, QuestCounterStore, QuestRules, QuestClaimed,
    QuestClaimedStore, IQuest, IQuestDispatcher, IQuestDispatcherTrait
};
use origami_quest::components::quest_registry::{
    IQuestRegistryDispatcher, IQuestRegistryDispatcherTrait
};


#[derive(Drop)]
pub struct QuestHelper {
    pub world: IWorldDispatcher,
    pub namespace: ByteArray,
    pub registry: ByteArray,
    pub quest_registry: IQuestRegistryDispatcher,
}

#[generate_trait]
impl QuestHelperImpl of QuestHelperTrait {
    fn new(world: IWorldDispatcher, namespace: ByteArray, registry: ByteArray) -> QuestHelper {
        let (_, quest_registry_address) = world
            .contract(selector_from_names(@namespace, @registry));

        let quest_registry = IQuestRegistryDispatcher { contract_address: quest_registry_address };
        QuestHelper { world, namespace, registry, quest_registry }
    }

    //
    //
    //

    fn register(self: @QuestHelper, new_quest: Quest) {
        (*self.quest_registry).register_quest(new_quest);
    }

    fn progress(self: @QuestHelper, quest_id: felt252, player_id: ContractAddress) {
        // check if quest is is_available
        let quest = QuestStore::get(*self.world, quest_id);
        if quest.is_available(*self.world, player_id) {
            // progress
            // match quest.external {
            //     Option::Some(ext) => {
            //         IQuestDispatcher { contract_address: ext }
            //             .progress(*self.world, quest_id, player_id);
            //     },
            //     Option::None => { (*self.quest_registry).progress(quest_id, player_id); }
            // };

            (*self.quest_registry).progress(quest_id, player_id);
        }
    }
}


#[generate_trait]
impl QuestImpl of QuestTrait {
    fn is_valid(self: @Quest) -> bool {
        !(*self.id).is_zero() && self.name.len() > 0 && self.desc.len() > 0
    }

    fn exists(self: @Quest) -> bool {
        self.name.len() > 0
    }

    //
    //
    //

    fn is_available(self: @Quest, world: IWorldDispatcher, player_id: ContractAddress) -> bool {
        // match self.external {
        //     Option::Some(ext) => IQuestDispatcher { contract_address: *ext }
        //         .is_available(world, *self.id, player_id),
        //     Option::None => Self::check_rules(self.availability, world, player_id)
        // }
        Self::check_rules(self.availability, world, player_id)
    }

    fn is_completed(self: @Quest, world: IWorldDispatcher, player_id: ContractAddress) -> bool {
        // match self.external {
        //     Option::Some(ext) => IQuestDispatcher { contract_address: *ext }
        //         .is_completed(world, *self.id, player_id),
        //     Option::None => Self::check_rules(self.completion, world, player_id)
        // }
        Self::check_rules(self.completion, world, player_id)
    }


    //
    //
    //

    fn claimed(self: @Quest, world: IWorldDispatcher, player_id: ContractAddress) -> bool {
        // match self.external {
        //     Option::Some(ext) => IQuestDispatcher { contract_address: *ext }
        //         .claimed(world, *self.id, player_id),
        //     Option::None => QuestClaimedStore::get(world, *self.id, player_id).claimed
        // }
        QuestClaimedStore::get(world, *self.id, player_id).claimed
    }

    fn claimable(self: @Quest, world: IWorldDispatcher, player_id: ContractAddress) -> bool {
        // match self.external {
        //     Option::Some(ext) => IQuestDispatcher { contract_address: *ext }
        //         .claimable(world, *self.id, player_id),
        //     Option::None => !self.claimed(world, player_id) && self.is_completed(world,
        //     player_id)
        // }
        !self.claimed(world, player_id) && self.is_completed(world, player_id)
    }


    //
    //
    //

    fn check_rules(
        rules: @QuestRules, world: IWorldDispatcher, player_id: ContractAddress
    ) -> bool {
        if rules.all.len() == 0 && rules.any.len() == 0 {
            true
        } else {
            if rules.any.len() > 0 {
                // check rules 'any'
                let mut any_span = rules.any.span();
                let mut completed = false;
                while let Option::Some(rule) = any_span.pop_front() {
                    let quest = QuestStore::get(world, *rule.quest_id);
                    let quest_counter = QuestCounterStore::get(world, quest.id, player_id);
                    if quest_counter.count >= *rule.count {
                        completed = true;
                        break;
                    } else {
                        continue;
                    }
                };

                // OR
                if completed {
                    return true;
                }
            }

            if rules.all.len() > 0 {
                // check rules 'all'
                let mut all_span = rules.all.span();
                let mut completed = true;
                while let Option::Some(rule) = all_span.pop_front() {
                    let quest = QuestStore::get(world, *rule.quest_id);
                    let quest_counter = QuestCounterStore::get(world, quest.id, player_id);
                    if quest_counter.count >= *rule.count {
                        continue;
                    } else {
                        completed = false;
                        break;
                    }
                };

                if completed {
                    return true;
                }
            }
            false
        }
    }
}
