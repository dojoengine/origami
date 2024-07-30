#[starknet::interface]
trait IDojoFrens<T> {
    fn play_game(self: @T);
    fn secret(self: @T);
    fn spawn_fren(self: @T);
    fn spawn_katana_fren(self: @T);
    fn spawn_sozo_fren(self: @T);
    fn spawn_torii_fren(self: @T);
}

#[dojo::contract]
mod dojo_frens {
    use starknet::{ContractAddress, get_caller_address};

    use dojo::model::Model;

    use dojo_world::models::dojo_fren::{DojoFren, DojoFrenStore, DojoFrenKind};
    use dojo_world::utils::get_random;


    use origami_quest::models::quest::Quest;
    use origami_quest::helpers::quest::{QuestTrait, QuestHelperTrait};


    #[abi(embed_v0)]
    impl DojoFrensImpl of super::IDojoFrens<ContractState> {
        fn play_game(self: @ContractState) {
            let quest_helper = QuestHelperTrait::new(self.world(), "dojo_world", "quest_registry");
            quest_helper.progress('play-game', get_caller_address());
        }

        fn secret(self: @ContractState) {
            let quest_helper = QuestHelperTrait::new(self.world(), "dojo_world", "quest_registry");
            quest_helper.progress('secret', get_caller_address());
        }

        fn spawn_fren(self: @ContractState) {
            let random = get_random('fren?', 3);

            let kind = match random {
                0 => DojoFrenKind::KatanaFren,
                1 => DojoFrenKind::SozoFren,
                _ => DojoFrenKind::ToriiFren,
            };

            self.spawn_fren_by_kind(kind);
        }

        fn spawn_katana_fren(self: @ContractState) {
            self.spawn_fren_by_kind(DojoFrenKind::KatanaFren);
        }
        fn spawn_sozo_fren(self: @ContractState) {
            self.spawn_fren_by_kind(DojoFrenKind::SozoFren);
        }
        fn spawn_torii_fren(self: @ContractState) {
            self.spawn_fren_by_kind(DojoFrenKind::ToriiFren);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_dojo_fren_by_kind(self: @ContractState, kind: DojoFrenKind) -> DojoFren {
            let player_id = get_caller_address();

            DojoFrenStore::get(self.world(), player_id, kind)
        }

        fn spawn_fren_by_kind(self: @ContractState, kind: DojoFrenKind) {
            let mut fren = self.get_dojo_fren_by_kind(kind);
            fren.spawned += 1;
            fren.set(self.world());

            self.handle_quest_progress(@fren);
        }

        fn handle_quest_progress(self: @ContractState, fren: @DojoFren) {
            let player_id = get_caller_address();
            let mut quest_helper = QuestHelperTrait::new(
                self.world(), "dojo_world", "quest_registry"
            );

            match fren.kind {
                DojoFrenKind::KatanaFren(_) => {
                    quest_helper.progress('quest-katana', player_id);
                },
                DojoFrenKind::SozoFren(_) => { quest_helper.progress('quest-sozo', player_id); },
                DojoFrenKind::ToriiFren(_) => { quest_helper.progress('quest-torii', player_id); },
            }

            quest_helper.progress('quest-3-of-each', player_id);
            quest_helper.progress('quest-5-of-one-kind', player_id);
        }
    }
}

