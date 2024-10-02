use origami_quest::models::quest::{
    Quest, QuestRules, QuestRulesInfos, QuestRulesDefault, QuestType, 
    IQuest, IQuestDispatcher, IQuestDispatcherTrait
};


pub fn play_one_game() -> QuestRules {
    QuestRules { all: array![], any: array![QuestRulesInfos { quest_id: 'play-game', count: 1, },] }
}

pub fn quest_0() -> Quest {
    Quest {
        id: 'play-game',
        name: "Play Game",
        desc: "Play 1 game",
        image_uri: Option::None,
        quest_type: QuestType::Infinite,
        completion: Default::default(),
        availability: Default::default(),
        external: Option::None,
    }
}

pub fn quest_1() -> Quest {
    Quest {
        id: 'quest-katana',
        name: "Katana Frens",
        desc: "Spawn 1 Katana Fren",
        image_uri: Option::None,
        quest_type: QuestType::Infinite,
        completion: Default::default(),
        availability: play_one_game(),
        external: Option::None,
    }
}
pub fn quest_2() -> Quest {
    Quest {
        id: 'quest-sozo',
        name: "Sozo Frens",
        desc: "Spawn 1 Sozo Fren",
        image_uri: Option::None,
        quest_type: QuestType::Infinite,
        completion: Default::default(),
        availability: play_one_game(),
        external: Option::None,
    }
}
pub fn quest_3() -> Quest {
    Quest {
        id: 'quest-torii',
        name: "Torii Frens",
        desc: "Spawn 1 Torii Frens",
        image_uri: Option::Some("www.myimage.com"),
        quest_type: QuestType::Infinite,
        completion: Default::default(),
        availability: play_one_game(),
        external: Option::None,
    }
}

pub fn quest_4() -> Quest {
    Quest {
        id: 'quest-3-of-each',
        name: "Dojo Frens",
        desc: "Spawn 3 Fren of each kind",
        image_uri: Option::None,
        quest_type: QuestType::OneTime,
        completion: QuestRules {
            all: array![
                QuestRulesInfos { quest_id: 'quest-katana', count: 3, },
                QuestRulesInfos { quest_id: 'quest-sozo', count: 3, },
                QuestRulesInfos { quest_id: 'quest-torii', count: 3, },
            ],
            any: array![]
        },
        availability: play_one_game(),
        external: Option::None,
    }
}

pub fn quest_5() -> Quest {
    Quest {
        id: 'quest-5-of-one-kind',
        name: "Dojo Frens",
        desc: "Spawn 5 Frens of a kind",
        image_uri: Option::None,
        quest_type: QuestType::OneTime,
        completion: QuestRules {
            all: array![],
            any: array![
                QuestRulesInfos { quest_id: 'quest-katana', count: 5, },
                QuestRulesInfos { quest_id: 'quest-sozo', count: 5, },
                QuestRulesInfos { quest_id: 'quest-torii', count: 5, },
            ]
        },
        availability: play_one_game(),
        external: Option::None,
    }
}

pub fn quest_6() -> Quest {
    Quest {
        id: 'secret',
        name: "Secret call",
        desc: "Call the secret fn",
        image_uri: Option::None,
        quest_type: QuestType::Infinite,
        completion: Default::default(),
        availability: QuestRules {
            all: array![
                QuestRulesInfos { quest_id: 'quest-3-of-each', count: 1, },
                QuestRulesInfos { quest_id: 'quest-5-of-one-kind', count: 1, }
            ],
            any: array![],
        },
        external: Option::None,
    }
}

