use dojo::world::IWorldDispatcherTrait;
use governance::utils::{
    mock_contract_upgraded::{
        hellostarknetupgraded, IHelloStarknetUgradedDispatcher, IHelloStarknetUgradedDispatcherTrait
    },
    mock_contract::{IHelloStarknetDispatcherTrait}, testing
};
use governance::models::governor::{ProposalParams, Proposals, ProposalCount, Support};
use governance::systems::governor::interface::IGovernorDispatcherTrait;
use governance::systems::token::interface::IGovernanceTokenDispatcherTrait;
use governance::systems::timelock::interface::ITimelockDispatcherTrait;
use starknet::testing::{set_contract_address, set_block_timestamp};

const QUORUM: u128 = 5;
const THRESHOLD: u128 = 10;
const DELAY: u64 = 172_801; // 2 days;;
const PERIOD: u64 = 20;

#[test]
fn test_set_proposal_params() {
    let (systems, world) = testing::setup();

    set_contract_address(testing::GOVERNOR());
    systems.governor.set_proposal_params(QUORUM, THRESHOLD, DELAY, PERIOD);

    let new_proposal_params = get!(world, systems.governor.contract_address, ProposalParams);
    assert!(new_proposal_params.quorum_votes == QUORUM);
    assert!(new_proposal_params.threshold == THRESHOLD);
    assert!(new_proposal_params.voting_delay == DELAY);
    assert!(new_proposal_params.voting_period == PERIOD);
}

#[test]
fn test_propose() {
    let (systems, world) = testing::setup();

    set_contract_address(testing::GOVERNOR());
    systems.governor.set_proposal_params(QUORUM, THRESHOLD, DELAY, PERIOD);
    systems.token.delegate(testing::ACCOUNT_1());

    let proposal_target: starknet::ContractAddress = 'target'.try_into().unwrap();
    let proposal_class_hash: starknet::ClassHash = 'new_class_hash'.try_into().unwrap();

    set_contract_address(testing::ACCOUNT_1());

    set_block_timestamp('ts1');
    systems.governor.propose(proposal_target, proposal_class_hash);

    assert!(get!(world, systems.governor.contract_address, ProposalCount).count == 1);
    let proposal = get!(world, 1, Proposals).proposal;
    assert!(proposal.proposer == testing::ACCOUNT_1(), "proposer is not correct");
    assert!(proposal.target == proposal_target, "target is not correct");
    assert!(proposal.class_hash == proposal_class_hash, "class_hash is not correct");
    assert!(proposal.start_block == 'ts1' + DELAY, "start_block is not correct");
    assert!(proposal.end_block == 'ts1' + DELAY + PERIOD, "end_block is not correct");
}

#[test]
fn test_cast_vote() {
    let (systems, world) = testing::setup();
    let proposal_target: starknet::ContractAddress = 'target'.try_into().unwrap();
    let proposal_class_hash: starknet::ClassHash = 'new_class_hash'.try_into().unwrap();

    set_contract_address(testing::GOVERNOR());
    systems.governor.set_proposal_params(QUORUM, THRESHOLD, DELAY, PERIOD);

    systems.token.transfer(testing::ACCOUNT_1(), 200);
    systems.token.transfer(testing::ACCOUNT_2(), 100);

    set_contract_address(testing::ACCOUNT_2());
    systems.token.delegate(testing::ACCOUNT_2());
    set_contract_address(testing::ACCOUNT_1());
    systems.token.delegate(testing::ACCOUNT_1());
    set_block_timestamp('ts1');
    systems.governor.propose(proposal_target, proposal_class_hash);
    set_block_timestamp('ts1' + DELAY + 1);
    systems.governor.cast_vote(1, Support::For);

    set_contract_address(testing::ACCOUNT_2());
    systems.governor.cast_vote(1, Support::For);

    let proposal = get!(world, 1, Proposals).proposal;
    println!("proposal: {:?}", proposal);
    let one_voting_power = systems.token.get_current_votes(testing::ACCOUNT_1());
    let two_voting_power = systems.token.get_current_votes(testing::ACCOUNT_2());
    assert!(proposal.for_votes == one_voting_power + two_voting_power, "for_votes is not correct");
    assert!(proposal.against_votes == 0, "against_votes is not correct");
    assert!(proposal.abstain_votes == 0, "abstain_votes is not correct");
}

#[test]
fn test_queue_proposal() {
    let (systems, world) = testing::setup();
    let proposal_target: starknet::ContractAddress = 'target'.try_into().unwrap();
    let proposal_class_hash: starknet::ClassHash = 'new_class_hash'.try_into().unwrap();

    set_contract_address(testing::GOVERNOR());
    systems.governor.set_proposal_params(QUORUM, THRESHOLD, DELAY, PERIOD);

    systems.token.transfer(testing::ACCOUNT_1(), 200);
    systems.token.transfer(testing::ACCOUNT_2(), 100);

    set_contract_address(testing::ACCOUNT_2());
    systems.token.delegate(testing::ACCOUNT_2());
    set_contract_address(testing::ACCOUNT_1());
    systems.token.delegate(testing::ACCOUNT_1());
    set_block_timestamp('ts1');
    systems.governor.propose(proposal_target, proposal_class_hash);
    set_block_timestamp('ts1' + DELAY + 1);
    systems.governor.cast_vote(1, Support::For);
    set_contract_address(testing::ACCOUNT_2());
    systems.governor.cast_vote(1, Support::For);
    set_block_timestamp('ts1' + DELAY + PERIOD + 1);
    systems.governor.queue(1);

    let proposal = get!(world, 1, Proposals).proposal;
    assert!(proposal.eta == 'ts1' + DELAY * 2 + PERIOD + 1, "eta is not correct");
}

#[test]
fn test_execute_proposal() {
    let (systems, world) = testing::setup();
    systems.mock.increase_balance(1000);
    let proposal_class_hash = hellostarknetupgraded::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(testing::GOVERNOR());
    systems.governor.set_proposal_params(QUORUM, THRESHOLD, DELAY, PERIOD);

    systems.token.transfer(testing::ACCOUNT_1(), 200);
    systems.token.transfer(testing::ACCOUNT_2(), 100);

    set_contract_address(testing::ACCOUNT_2());
    systems.token.delegate(testing::ACCOUNT_2());
    set_contract_address(testing::ACCOUNT_1());
    systems.token.delegate(testing::ACCOUNT_1());
    set_block_timestamp('ts1');
    systems.governor.propose(systems.mock.contract_address, proposal_class_hash);
    set_block_timestamp('ts1' + DELAY + 1);
    systems.governor.cast_vote(1, Support::For);
    set_contract_address(testing::ACCOUNT_2());
    systems.governor.cast_vote(1, Support::For);
    set_block_timestamp('ts1' + DELAY + PERIOD + 1);
    systems.governor.queue(1);

    set_block_timestamp('ts1' + DELAY * 2 + PERIOD + 1);
    systems.governor.execute(1);

    let proposal = get!(world, 1, Proposals).proposal;
    assert!(proposal.executed == true, "executed is not correct");

    IHelloStarknetUgradedDispatcher { contract_address: systems.mock.contract_address }
        .decrease_balance(1000);
}
