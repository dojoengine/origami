#[dojo::contract]
mod timelock {
    use governance::libraries::events::timelockevents;
    use governance::models::timelock::{PendingAdmin, QueuedTransactions, TimelockParams};
    use governance::systems::timelock::interface::ITimelock;
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_block_timestamp, get_contract_address,
        Zeroable
    };

    // The following constants are defined is seconds based on the Compounds Timelock contract,
    // but can be adjusted to fit the needs of the project.
    const GRACE_PERIOD: u64 = 1_209_600; // 14 days
    const MINIMUM_DELAY: u64 = 172_800; // 2 days;
    const MAXIMUM_DELAY: u64 = 2_592_000; // 30 days;

    impl TimelockImpl of ITimelock<ContractState> {
        fn initialize(admin: ContractAddress, delay: u64) {
            assert!(!admin.is_zero(), "Timelock::constructor: Admin address cannot be zero.");
            assert!(
                delay >= MINIMUM_DELAY, "Timelock::constructor: Delay must exceed minimum delay."
            );
            assert!(
                delay <= MAXIMUM_DELAY,
                "Timelock::constructor: Delay must not exceed maximum delay."
            );
            let world = self.world_dispatcher.read();
            let contract = get_contract_address();
            let curr_params = get!(world, contract, TimelockParams);
            assert!(
                curr_params.admin == Zeroable::zero(), "Timelock::constructor: Already initialized."
            );
            set!(world, TimelockParams { contract, admin, delay });
            emit!(
                world,
                timelockevents::NewAdmin { contract, address: admin },
                timelockevents::NewDelay { contract, value: delay }
            );
        }

        fn execute_transaction(
            world: IWorldDispatcher,
            target: ContractAddress,
            new_implementation: ClassHash,
            eta: u64
        ) {
            let params = get!(world, get_contract_address(), TimelockParams);
            assert!(
                get_caller_address() == params.admin,
                "Timelock::execute_transaction: Call must come from admin."
            );
            let queued_tx = get!(world, (target, new_implementation), QueuedTransactions);
            assert!(
                queued_tx.queued, "Timelock::execute_transaction: Transaction hasn't been queued."
            );
            let timestamp = get_block_timestamp();
            assert!(
                timestamp >= eta,
                "Timelock::execute_transaction: Transaction hasn't surpassed time lock."
            );
            assert!(
                timestamp <= eta + GRACE_PERIOD,
                "Timelock::execute_transaction: Transaction is stale."
            );
            set!(
                world,
                QueuedTransactions {
                    contract: target, class_hash: new_implementation, queued: false
                }
            );
            let upgraded_class_hash = world.upgrade_contract(target, new_implementation);
            emit!(
                world,
                timelockevents::ExecuteTransaction { target, class_hash: upgraded_class_hash, eta }
            );
        }

        fn que_transaction(
            world: IWorldDispatcher,
            target: ContractAddress,
            new_implementation: ClassHash,
            eta: u64
        ) {
            let params = get!(world, get_contract_address(), TimelockParams);
            assert!(
                get_caller_address() == params.admin,
                "Timelock::queue_transaction: Call must come from admin."
            );
            assert!(
                eta >= get_block_timestamp() + params.delay,
                "Timelock::queue_transaction: Estimated execution block must satisfy delay."
            );
            set!(
                world,
                QueuedTransactions {
                    contract: target, class_hash: new_implementation, queued: true
                }
            );
            emit!(
                world,
                timelockevents::QueueTransaction { target, class_hash: new_implementation, eta }
            );
        }

        fn cancel_transaction(
            world: IWorldDispatcher,
            target: ContractAddress,
            new_implementation: ClassHash,
            eta: u64
        ) {
            let params = get!(world, get_contract_address(), TimelockParams);
            assert!(
                get_caller_address() == params.admin,
                "Timelock::cancel_transaction: Call must come from admin."
            );
            set!(
                world,
                QueuedTransactions {
                    contract: target, class_hash: new_implementation, queued: false
                }
            );
            emit!(
                world,
                timelockevents::CancelTransaction { target, class_hash: new_implementation, eta }
            );
        }
    }
}
