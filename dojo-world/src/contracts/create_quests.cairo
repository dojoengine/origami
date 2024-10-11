#[dojo::contract]
mod xxx_create_quests {
    use starknet::{ContractAddress, get_caller_address};

    use dojo::model::Model;

    use dojo_world::utils::get_random;


    use origami_quest::models::quest::Quest;
    use origami_quest::helpers::quest::QuestHelperTrait;

    use dojo_world::quests::quests::{quest_0, quest_1, quest_2, quest_3, quest_4, quest_5, quest_6};


    #[abi(embed_v0)]
    fn dojo_init(ref self: ContractState) {
        let quest_helper = QuestHelperTrait::new(self.world(), "dojo_world", "quest_registry");

        quest_helper.register(quest_0());
        quest_helper.register(quest_1());
        quest_helper.register(quest_2());
        quest_helper.register(quest_3());
        quest_helper.register(quest_4());
        quest_helper.register(quest_5());
        quest_helper.register(quest_6());
    }

}

