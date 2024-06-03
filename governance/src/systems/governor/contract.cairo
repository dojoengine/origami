#[dojo::contract]
mod governor {
    use governance::libraries::events::governorevents;
    use governance::models::{
        governor::{
            GovernorParams, ProposalParams, ProposalCount, Proposals, Proposal, Receipt,
            ProposalState, LatestProposalIds, Receipts, Support
        },
        timelock::{QueuedTransactions, TimelockParams}
    };
    use governance::systems::{
        governor::interface::IGovernor,
        timelock::{contract::timelock, interface::{ITimelockDispatcher, ITimelockDispatcherTrait}},
        token::interface::{IGovernanceTokenDispatcher, IGovernanceTokenDispatcherTrait}
    };
    use starknet::{
        ContractAddress, ClassHash, get_contract_address, get_caller_address,
        info::get_block_timestamp
    };

    #[abi(embed_v0)]
    impl GovernorImpl of IGovernor<ContractState> {
        fn initialize(
            timelock: ContractAddress, gov_token: ContractAddress, guardian: ContractAddress
        ) {
            let world = self.world_dispatcher.read();
            let contract = get_contract_address();
            let curr_params = get!(world, contract, GovernorParams);
            assert!(
                curr_params.timelock == Zeroable::zero()
                    && curr_params.gov_token == Zeroable::zero()
                    && curr_params.guardian == Zeroable::zero()
                    && curr_params.guardian == Zeroable::zero(),
                "Governor::initialize: already initialized"
            );
            set!(world, GovernorParams { contract, timelock, gov_token, guardian });
        }

        fn set_proposal_params(
            quorum_votes: u128, threshold: u128, voting_delay: u64, voting_period: u64,
        ) {
            let world = self.world_dispatcher.read();
            let params = get!(world, get_contract_address(), GovernorParams);
            assert!(
                params.guardian == get_caller_address(),
                "Governor::set_proposal_params: only guardian can set proposal params"
            );
            ITimelockDispatcher { contract_address: params.timelock }
                .initialize(get_contract_address(), voting_delay);
            set!(
                world,
                ProposalParams {
                    contract: get_contract_address(),
                    quorum_votes,
                    threshold,
                    voting_delay,
                    voting_period
                }
            );
        }

        fn propose(target: ContractAddress, class_hash: ClassHash,) -> usize {
            let world = self.world_dispatcher.read();
            let contract = get_contract_address();
            let caller = get_caller_address();
            let params = get!(world, contract, ProposalParams);
            let time_now = get_block_timestamp();
            let gov_token = IGovernanceTokenDispatcher {
                contract_address: get!(world, contract, GovernorParams).gov_token
            };
            let prior_votes = gov_token.get_prior_votes(caller, time_now - 1);
            assert!(
                prior_votes > params.threshold,
                "Governor::propose: proposer votes below proposal threshold"
            );

            let latest_proposal_id = get!(world, caller, LatestProposalIds).id;
            if !latest_proposal_id.is_zero() {
                let state = self.state(latest_proposal_id);
                match state {
                    ProposalState::Active(()) => {
                        panic!(
                            "Governor::propose: one live proposal per proposer, found an already active proposal"
                        );
                    },
                    ProposalState::Pending(()) => {
                        panic!(
                            "Governor::propose: one live proposal per proposer, found an already pending proposal"
                        );
                    },
                    _ => {}
                }
            }

            let start_block = time_now + params.voting_delay;
            let end_block = start_block + params.voting_period;
            let curr_proposal_count = get!(world, contract, ProposalCount).count;
            set!(world, ProposalCount { contract, count: curr_proposal_count + 1 });
            let proposal_id = curr_proposal_count + 1;

            let mut new_proposal: Proposal = Default::default();
            new_proposal.id = proposal_id;
            new_proposal.class_hash = class_hash;
            new_proposal.proposer = caller;
            new_proposal.target = target;
            new_proposal.start_block = start_block;
            new_proposal.end_block = end_block;

            set!(world, LatestProposalIds { address: caller, id: proposal_id });
            set!(world, Proposals { id: proposal_id, proposal: new_proposal });

            emit!(
                world,
                governorevents::ProposalCreated {
                    id: proposal_id, proposer: caller, target, class_hash, start_block, end_block,
                }
            );
            new_proposal.id
        }

        fn queue(proposal_id: usize) {
            let world = self.world_dispatcher.read();
            let state = self.state(proposal_id);
            match state {
                ProposalState::Succeeded(()) => {},
                _ => { panic!("Governor::queue: proposal can only be queued if it is succeeded"); }
            }
            let mut proposal = get!(world, proposal_id, Proposals).proposal;
            let timelock_addr = get!(world, get_contract_address(), GovernorParams).timelock;
            let timelock_delay = get!(world, timelock_addr, TimelockParams).delay;
            let eta = get_block_timestamp() + timelock_delay;
            queue_or_revert(world, proposal.target, proposal.class_hash, eta);
            proposal.eta = eta;
            set!(world, Proposals { id: proposal_id, proposal });
            emit!(world, governorevents::ProposalQueued { id: proposal_id, eta });
        }

        fn execute(proposal_id: usize) {
            let world = self.world_dispatcher.read();
            let state = self.state(proposal_id);
            match state {
                ProposalState::Queued(()) => {},
                _ => { panic!("Governor::execute: proposal can only be executed if it is queued"); }
            }

            let mut proposal = get!(world, proposal_id, Proposals).proposal;
            proposal.executed = true;

            let timelock = ITimelockDispatcher {
                contract_address: get!(world, get_contract_address(), GovernorParams).timelock
            };
            timelock.execute_transaction(proposal.target, proposal.class_hash, proposal.eta);
            set!(world, Proposals { id: proposal_id, proposal });

            emit!(world, governorevents::ProposalExecuted { id: proposal_id, executed: true });
        }

        fn cancel(proposal_id: usize) {
            let world = self.world_dispatcher.read();
            let state = self.state(proposal_id);
            let contract = get_contract_address();

            match state {
                ProposalState::Executed(()) => {
                    panic!("Governor::cancel: cannot cancel executed proposal");
                },
                _ => {}
            }

            let mut proposal = get!(world, proposal_id, Proposals).proposal;
            let guardian = get!(world, contract, GovernorParams).guardian;
            let threshold = get!(world, contract, ProposalParams).threshold;
            let gov_token = IGovernanceTokenDispatcher {
                contract_address: get!(world, contract, GovernorParams).gov_token
            };
            let prior_votes = gov_token
                .get_prior_votes(proposal.proposer, get_block_timestamp() - 1);
            assert!(
                guardian == get_caller_address() || prior_votes < threshold,
                "Governor::cancel: proposer above threshold"
            );

            proposal.canceled = true;

            let timelock = ITimelockDispatcher {
                contract_address: get!(world, contract, GovernorParams).timelock
            };
            timelock.cancel_transaction(proposal.target, proposal.class_hash, proposal.eta);

            emit!(world, governorevents::ProposalCanceled { id: proposal_id, cancelled: true });
        }

        fn get_action(proposal_id: usize) -> (ContractAddress, ClassHash) {
            let world = self.world_dispatcher.read();
            let proposal = get!(world, proposal_id, Proposals).proposal;
            (proposal.target, proposal.class_hash)
        }

        fn state(proposal_id: usize) -> ProposalState {
            let world = self.world_dispatcher.read();
            let contract = get_contract_address();
            let proposal_count = get!(world, contract, ProposalCount).count;
            assert!(
                proposal_id <= proposal_count && !proposal_id.is_zero(),
                "Governor::state: invalid proposal id"
            );

            let proposal = get!(world, proposal_id, Proposals).proposal;
            let quorum_votes = get!(world, contract, ProposalParams).quorum_votes;
            let block_number = get_block_timestamp();

            if proposal.canceled {
                return ProposalState::Canceled(());
            } else if block_number <= proposal.start_block {
                return ProposalState::Pending(());
            } else if block_number <= proposal.end_block {
                return ProposalState::Active(());
            } else if proposal.for_votes <= proposal.against_votes
                || proposal.for_votes < quorum_votes {
                return ProposalState::Defeated(());
            } else if proposal.eta == 0 {
                return ProposalState::Succeeded(());
            } else if proposal.executed {
                return ProposalState::Executed(());
            } else if block_number >= proposal.eta + timelock::GRACE_PERIOD {
                return ProposalState::Expired(());
            } else {
                return ProposalState::Queued(());
            }
        }

        fn cast_vote(proposal_id: usize, support: Support) {
            let world = self.world_dispatcher.read();
            let state = self.state(proposal_id);
            match state {
                ProposalState::Active(()) => {},
                _ => { panic!("Governor::cast_vote: voting is closed"); }
            }

            let mut proposal = get!(world, proposal_id, Proposals).proposal;
            let caller = get_caller_address();
            let mut receipt = get!(world, (proposal_id, caller), Receipts).receipt;
            assert!(!receipt.has_voted, "Governor::cast_vote: voter already voted");

            let gov_token = IGovernanceTokenDispatcher {
                contract_address: get!(world, get_contract_address(), GovernorParams).gov_token
            };
            let votes = gov_token.get_prior_votes(caller, proposal.start_block);
            match support {
                Support::For => { proposal.for_votes += votes; },
                Support::Against => { proposal.against_votes += votes; },
                Support::Abstain => { proposal.abstain_votes += votes; }
            }
            set!(world, Proposals { id: proposal_id, proposal });

            receipt.has_voted = true;
            receipt.support = support;
            receipt.votes = votes;
            emit!(world, governorevents::VoteCast { voter: caller, proposal_id, support, votes });
        }
    }

    fn queue_or_revert(
        world: IWorldDispatcher, target: ContractAddress, class_hash: ClassHash, eta: u64
    ) {
        let queued_tx = get!(world, (target, class_hash), QueuedTransactions).queued;
        assert!(!queued_tx, "Governor::queue_or_revert: proposal action already queued at eta");

        let timelock = ITimelockDispatcher {
            contract_address: get!(world, get_contract_address(), GovernorParams).timelock
        };
        timelock.que_transaction(target, class_hash, eta);
    }
}
