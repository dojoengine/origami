use governance::models::governor::{ProposalState, Receipt};
use starknet::{ContractAddress, ClassHash};

#[dojo::interface]
trait IGovernor {
    fn initialize(timelock: ContractAddress, gov_token: ContractAddress, guardian: ContractAddress);
    fn set_proposal_params(
        quorum_votes: u128, threshold: u128, voting_delay: u64, voting_period: u64,
    );
    fn propose(target: ContractAddress, class_hash: ClassHash, description: ByteArray) -> usize;
    fn queue(proposal_id: usize);
    fn execute(proposal_id: usize);
    fn cancel(proposal_id: usize);
    fn get_action(proposal_id: usize) -> (ContractAddress, ClassHash);
    fn state(proposal_id: usize) -> ProposalState;
    fn cast_vote(proposal_id: usize, support: bool);
}
