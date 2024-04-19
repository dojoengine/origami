mod setup {
    // Core imports

    use core::debug::PrintTrait;

    // Starknet imports

    use starknet::ContractAddress;
    use starknet::testing::{set_contract_address};

    // Dojo imports

    use dojo::world::{IWorldDispatcherTrait, IWorldDispatcher};
    use dojo::test_utils::{spawn_test_world, deploy_contract};

    // Internal imports

    use matchmaker::models::player::Player;
    use matchmaker::models::league::League;
    use matchmaker::models::registry::Registry;
    use matchmaker::models::slot::Slot;
    use matchmaker::systems::maker::{maker, IMakerDispatcher, IMakerDispatcherTrait};

    // Constants

    fn PLAYER() -> ContractAddress {
        starknet::contract_address_const::<'PLAYER'>()
    }

    fn ANYONE() -> ContractAddress {
        starknet::contract_address_const::<'ANYONE'>()
    }

    fn SOMEONE() -> ContractAddress {
        starknet::contract_address_const::<'SOMEONE'>()
    }

    fn NOONE() -> ContractAddress {
        starknet::contract_address_const::<'NOONE'>()
    }

    const REGISTRY_ID: u32 = 0;

    #[derive(Drop)]
    struct Systems {
        maker: IMakerDispatcher,
    }

    #[derive(Drop)]
    struct Context {
        registry_id: u32,
        player_id: ContractAddress,
        someone_id: ContractAddress,
        anyone_id: ContractAddress,
        noone_id: ContractAddress,
    }

    #[inline(always)]
    fn spawn() -> (IWorldDispatcher, Systems, Context) {
        // [Setup] World
        let mut models = core::array::ArrayTrait::new();
        models.append(matchmaker::models::player::player::TEST_CLASS_HASH);
        models.append(matchmaker::models::league::league::TEST_CLASS_HASH);
        models.append(matchmaker::models::registry::registry::TEST_CLASS_HASH);
        models.append(matchmaker::models::slot::slot::TEST_CLASS_HASH);
        let world = spawn_test_world(models);

        // [Setup] Systems
        let maker_address = deploy_contract(maker::TEST_CLASS_HASH, array![].span());
        let systems = Systems { maker: IMakerDispatcher { contract_address: maker_address }, };

        // [Setup] Context
        set_contract_address(SOMEONE());
        systems.maker.create(world);
        systems.maker.subscribe(world);
        set_contract_address(ANYONE());
        systems.maker.create(world);
        systems.maker.subscribe(world);
        set_contract_address(NOONE());
        systems.maker.create(world);
        systems.maker.subscribe(world);
        set_contract_address(PLAYER());
        let context = Context {
            registry_id: REGISTRY_ID,
            player_id: PLAYER(),
            someone_id: SOMEONE(),
            anyone_id: ANYONE(),
            noone_id: NOONE()
        };

        // [Return]
        (world, systems, context)
    }
}
