use origami_governance::models::governor::{ProposalState, Receipt, Support};
use starknet::{ContractAddress, ClassHash};

#[dojo::interface]
trait IGovernor {
    fn initialize(timelock: felt252, gov_token: felt252, guardian: ContractAddress);
    fn set_proposal_params(
        quorum_votes: u128, threshold: u128, voting_delay: u64, voting_period: u64,
    );
    fn propose(target_selector: felt252, class_hash: ClassHash) -> usize;
    fn queue(proposal_id: usize);
    fn execute(proposal_id: usize);
    fn cancel(proposal_id: usize);
    fn get_action(proposal_id: usize) -> (felt252, ClassHash);
    fn state(proposal_id: usize) -> ProposalState;
    fn cast_vote(proposal_id: usize, support: Support);
}
