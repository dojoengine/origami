use dojo::test_utils::{spawn_test_world};
use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use governance::models::{
    governor::{
        GovernorParams, ProposalParams, ProposalCount, LatestProposalIds, governor_params,
        proposal_params, proposal_count, latest_proposal_ids
    },
    timelock::{
        TimelockParams, PendingAdmin, QueuedTransactions, timelock_params, pending_admin,
        queued_transactions
    },
    token::{
        Metadata, TotalSupply, Allowances, Balances, Delegates, Checkpoints, NumCheckpoints, Nonces,
        metadata, total_supply, allowances, balances, delegates, checkpoints, num_checkpoints,
        nonces
    }
};
use governance::systems::{
    governor::{contract::governor, interface::{IGovernorDispatcher, IGovernorDispatcherTrait}},
    timelock::{contract::timelock, interface::{ITimelockDispatcher, ITimelockDispatcherTrait}},
    token::{
        contract::governancetoken,
        interface::{IGovernanceTokenDispatcher, IGovernanceTokenDispatcherTrait}
    }
};
use governance::utils::mock_contract::{
    hellostarknet, IHelloStarknetDispatcher, mock_balances, MockBalances
};
use starknet::{ContractAddress, contract_address_const};

const DAY: u64 = 86400;
const E18: u128 = 1_000_000_000_000_000_000;
const INITIAL_SUPPLY: u128 = 100_000_000_000_000_000_000_000_000;

fn GOVERNOR() -> ContractAddress {
    contract_address_const::<'governor'>()
}
fn ACCOUNT_1() -> ContractAddress {
    contract_address_const::<0x1>()
}
fn ACCOUNT_2() -> ContractAddress {
    contract_address_const::<0x2>()
}
fn ACCOUNT_3() -> ContractAddress {
    contract_address_const::<0x3>()
}
fn ACCOUNT_4() -> ContractAddress {
    contract_address_const::<0x4>()
}
fn ACCOUNT_5() -> ContractAddress {
    contract_address_const::<0x5>()
}

#[derive(Clone, Copy, Drop, Serde)]
struct Systems {
    governor: IGovernorDispatcher,
    timelock: ITimelockDispatcher,
    token: IGovernanceTokenDispatcher,
    mock: IHelloStarknetDispatcher,
}

fn setup() -> (Systems, IWorldDispatcher) {
    let models = array![
        governor_params::TEST_CLASS_HASH,
        proposal_params::TEST_CLASS_HASH,
        proposal_count::TEST_CLASS_HASH,
        latest_proposal_ids::TEST_CLASS_HASH,
        timelock_params::TEST_CLASS_HASH,
        pending_admin::TEST_CLASS_HASH,
        queued_transactions::TEST_CLASS_HASH,
        metadata::TEST_CLASS_HASH,
        total_supply::TEST_CLASS_HASH,
        allowances::TEST_CLASS_HASH,
        balances::TEST_CLASS_HASH,
        delegates::TEST_CLASS_HASH,
        checkpoints::TEST_CLASS_HASH,
        num_checkpoints::TEST_CLASS_HASH,
        nonces::TEST_CLASS_HASH,
        mock_balances::TEST_CLASS_HASH
    ];
    let world = spawn_test_world(models);

    let contract_address = world
        .deploy_contract(1, governor::TEST_CLASS_HASH.try_into().unwrap(), array![].span());
    let governor = IGovernorDispatcher { contract_address };

    let contract_address = world
        .deploy_contract(2, timelock::TEST_CLASS_HASH.try_into().unwrap(), array![].span());
    let timelock = ITimelockDispatcher { contract_address };

    let contract_address = world
        .deploy_contract(3, governancetoken::TEST_CLASS_HASH.try_into().unwrap(), array![].span());
    let token = IGovernanceTokenDispatcher { contract_address };

    let contract_address = world
        .deploy_contract(4, hellostarknet::TEST_CLASS_HASH.try_into().unwrap(), array![].span());
    let mock = IHelloStarknetDispatcher { contract_address };

    let systems = Systems { governor, timelock, token, mock };

    // should use constructor now
    systems.governor.initialize(timelock.contract_address, token.contract_address, GOVERNOR());
    systems.token.initialize('Gov Token', 'GOV', 18, INITIAL_SUPPLY, GOVERNOR());
    // systems.timelock.initialize(systems.governor.contract_address, DAY * 2);
    (systems, world)
}

#[test]
fn test_deploy() {
    let (_systems, _world) = setup();
}
