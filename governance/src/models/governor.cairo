use governance::libraries::traits::{ContractAddressDefault, ClassHashDefault};
use starknet::{ContractAddress, ClassHash};

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct GovernorParams {
    #[key]
    contract: ContractAddress,
    timelock: ContractAddress,
    gov_token: ContractAddress,
    guardian: ContractAddress,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ProposalParams {
    #[key]
    contract: ContractAddress,
    quorum_votes: u128,
    threshold: u128,
    voting_delay: u64,
    voting_period: u64,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct ProposalCount {
    #[key]
    contract: ContractAddress,
    count: usize,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Proposals {
    #[key]
    id: usize,
    proposal: Proposal,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct Receipts {
    #[key]
    proposal_id: usize,
    #[key]
    voter: ContractAddress,
    receipt: Receipt,
}

#[dojo::model]
#[derive(Copy, Drop, Serde)]
struct LatestProposalIds {
    #[key]
    address: ContractAddress,
    id: usize,
}

#[derive(Copy, Debug, Drop, Default, Introspect, Serde)]
struct Proposal {
    id: usize,
    proposer: ContractAddress,
    eta: u64,
    target: ContractAddress,
    class_hash: ClassHash,
    start_block: u64,
    end_block: u64,
    for_votes: u128,
    abstain_votes: u128,
    against_votes: u128,
    canceled: bool,
    executed: bool,
}

#[derive(Copy, Default, Drop, Introspect, Serde)]
struct Receipt {
    has_voted: bool,
    support: Support,
    votes: u128
}

#[derive(Copy, Drop, Serde)]
enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
}

#[derive(Copy, Default, Drop, Introspect, Serde)]
enum Support {
    For,
    Against,
    #[default]
    Abstain,
}
