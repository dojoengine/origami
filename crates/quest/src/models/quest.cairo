use starknet::ContractAddress;
use dojo::world::IWorldDispatcher;

#[starknet::interface]
pub trait IQuest<T> {
    fn is_available(
        self: @T, world: IWorldDispatcher, quest_id: felt252, player_id: ContractAddress
    ) -> bool;
    fn is_completed(
        self: @T, world: IWorldDispatcher, quest_id: felt252, player_id: ContractAddress
    ) -> bool;
    fn claimed(
        self: @T, world: IWorldDispatcher, quest_id: felt252, player_id: ContractAddress
    ) -> bool;
    fn claimable(
        self: @T, world: IWorldDispatcher, quest_id: felt252, player_id: ContractAddress
    ) -> bool;
    fn progress(
        self: @T, world: IWorldDispatcher, quest_id: felt252, player_id: ContractAddress
    ) ;
}


//
//  Quest
//

#[derive(Drop, Serde, Introspect)]
#[dojo::model(namespace = "origami_quest")]
pub struct Quest {
    #[key]
    id: felt252,
    name: ByteArray,
    desc: ByteArray,
    image_uri: Option<ByteArray>,
    quest_type: QuestType,
    //
    completion: QuestRules,
    //
    availability: QuestRules,
    //
    external: Option<ContractAddress>
// data: Array<felt252>
}

#[derive(Drop, Serde, Introspect)]
pub struct QuestRules {
    all: Array<QuestRulesInfos>,
    any: Array<QuestRulesInfos>,
}

#[derive(Drop, Serde, Introspect)]
pub struct QuestRulesInfos {
    quest_id: felt252,
    count: u64,
}


#[derive(Drop, Serde, Copy, Introspect)]
pub enum QuestType {
    Infinite,
    OneTime
}


//
// Quest counter
//

#[derive(Drop, Serde, Introspect)]
#[dojo::model(namespace = "origami_quest")]
#[dojo::event]
pub struct QuestCounter {
    #[key]
    quest_id: felt252,
    #[key]
    player_id: ContractAddress,
    count: u64,
}

//
// Quest claimed
//

#[derive(Drop, Serde, Introspect)]
#[dojo::model(namespace = "origami_quest")]
#[dojo::event]
pub struct QuestClaimed {
    #[key]
    quest_id: felt252,
    #[key]
    player_id: ContractAddress,
    claimed: bool,
}


//
//
//

impl QuestRulesDefault of Default<QuestRules> {
    fn default() -> QuestRules {
        QuestRules { all: array![], any: array![], }
    }
}
