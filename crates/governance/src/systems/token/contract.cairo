#[dojo::contract]
mod governancetoken {
    use core::num::traits::Bounded;
    use origami_governance::libraries::events::tokenevents;
    use origami_governance::models::token::{
        Allowances, Metadata, TotalSupply, Balances, Delegates, NumCheckpoints, Checkpoints,
        Checkpoint
    };
    use origami_governance::systems::token::interface::IGovernanceToken;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp,};

    #[abi(embed_v0)]
    impl GovernanceTokenImpl of IGovernanceToken<ContractState> {
        fn initialize(
            name: felt252,
            symbol: felt252,
            decimals: u8,
            initial_supply: u128,
            recipient: ContractAddress
        ) {
            let world = self.world_dispatcher.read();
            let token_selector = self.selector();
            let metadata = get!(world, token_selector, Metadata);
            let total_supply = get!(world, token_selector, TotalSupply).amount;
            assert!(
                metadata.name.is_zero()
                    && metadata.symbol.is_zero()
                    && metadata.decimals.is_zero()
                    && total_supply.is_zero(),
                "Governance Token: already initialized"
            );
            set!(
                world,
                (
                    Metadata { token_selector, name, symbol, decimals },
                    TotalSupply { token_selector, amount: initial_supply },
                    Balances { account: recipient, amount: initial_supply }
                )
            );
            emit!(
                world,
                tokenevents::Transfer {
                    from: Zeroable::zero(), to: recipient, amount: initial_supply
                }
            )
        }

        fn approve(spender: ContractAddress, amount: u128) {
            let world = self.world_dispatcher.read();
            let caller = get_caller_address();
            set!(world, (Allowances { delegator: caller, delegatee: spender, amount }));
            emit!(world, tokenevents::Approval { owner: caller, spender, amount })
        }

        fn transfer(to: ContractAddress, amount: u128) {
            transfer_tokens(self.world_dispatcher.read(), get_caller_address(), to, amount);
        }

        fn transfer_from(from: ContractAddress, to: ContractAddress, amount: u128) {
            let world = self.world_dispatcher.read();
            let spender = get_caller_address();
            let spender_allowance = get!(world, (from, spender), Allowances).amount;

            if spender != from && spender_allowance != Bounded::<u128>::MAX {
                assert!(
                    spender_allowance >= amount,
                    "Governance Token: transfer amount exceeds spender allowance"
                );
                let new_allowance = spender_allowance - amount;
                set!(
                    world, Allowances { delegator: from, delegatee: spender, amount: new_allowance }
                );
                emit!(world, tokenevents::Approval { owner: from, spender, amount: new_allowance });
            }
            transfer_tokens(world, from, to, amount);
        }

        fn delegate(delegatee: ContractAddress) {
            delegate(self.world_dispatcher.read(), get_caller_address(), delegatee);
        }

        fn get_current_votes(account: ContractAddress) -> u128 {
            let world = self.world_dispatcher.read();
            let n_checkpoints = get!(world, account, NumCheckpoints).count;
            if n_checkpoints > 0 {
                get!(world, (account, n_checkpoints - 1), Checkpoints).checkpoint.votes
            } else {
                0
            }
        }

        fn get_prior_votes(account: ContractAddress, timestamp: u64) -> u128 {
            let world = self.world_dispatcher.read();
            let time_now = get_block_timestamp();
            assert!(time_now > timestamp, "Governance Token: not yet determined");
            let n_checkpoints = get!(world, account, NumCheckpoints).count;
            if n_checkpoints.is_zero() {
                return 0;
            }
            let most_recent_checkpoint = get!(world, (account, n_checkpoints - 1), Checkpoints)
                .checkpoint;
            if most_recent_checkpoint.from_block > timestamp {
                return 0;
            }
            let mut lower = 0;
            let mut upper = n_checkpoints - 1;
            let mut votes = 0;
            loop {
                if lower == upper {
                    votes = get!(world, (account, lower), Checkpoints).checkpoint.votes;
                    break;
                }
                let center = upper - (upper - lower) / 2;
                let cp = get!(world, (account, center), Checkpoints).checkpoint;
                if cp.from_block == timestamp {
                    votes = cp.votes;
                    break;
                } else if cp.from_block < timestamp {
                    lower = center;
                } else {
                    upper = center - 1;
                }
            };
            votes
        }
    }


    // function _delegate(address delegator, address delegatee) internal {
    //     address currentDelegate = delegates[delegator];
    //     uint96 delegatorBalance = balances[delegator];
    //     delegates[delegator] = delegatee;

    //     emit DelegateChanged(delegator, currentDelegate, delegatee);

    //     _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    // }

    fn delegate(world: IWorldDispatcher, delegator: ContractAddress, delegatee: ContractAddress) {
        let current_delegate = get!(world, delegator, Delegates).address;
        let delegator_balance = get!(world, delegator, Balances).amount;
        set!(world, Delegates { account: delegator, address: delegatee });
        emit!(
            world, tokenevents::DelegateChanged { delegator, from: current_delegate, to: delegatee }
        );
        move_delegates(world, current_delegate, delegatee, delegator_balance);
    }

    fn transfer_tokens(
        world: IWorldDispatcher, from: ContractAddress, to: ContractAddress, amount: u128
    ) {
        assert!(!from.is_zero(), "Governance Token: transfer from zero address");
        assert!(!to.is_zero(), "Governance Token: transfer to zero address");

        let from_balance = get!(world, from, Balances).amount;
        assert!(from_balance >= amount, "Governance Token: insufficient balance");

        let to_balance = get!(world, to, Balances).amount;
        set!(
            world,
            (
                Balances { account: to, amount: to_balance + amount },
                Balances { account: from, amount: from_balance - amount }
            )
        );
        emit!(world, tokenevents::Transfer { from, to, amount });
        let from_rep = get!(world, from, Delegates).address;
        let to_rep = get!(world, to, Delegates).address;

        move_delegates(world, from_rep, to_rep, amount);
    }

    fn move_delegates(
        world: IWorldDispatcher, from: ContractAddress, to: ContractAddress, amount: u128
    ) {
        if from != to && !amount.is_zero() {
            if !from.is_zero() {
                let from_num = get!(world, from, NumCheckpoints).count;
                let from_old = if !from_num.is_zero() {
                    get!(world, (from, from_num - 1), Checkpoints).checkpoint.votes
                } else {
                    0
                };
                assert!(from_old >= amount, "Governance Token: vote amount underflows");
                let from_new = from_old - amount;
                write_checkpoint(world, from, from_num, from_old, from_new);
            }

            if !to.is_zero() {
                let to_num = get!(world, to, NumCheckpoints).count;
                let to_old = if !to_num.is_zero() {
                    get!(world, (to, to_num - 1), Checkpoints).checkpoint.votes
                } else {
                    0
                };
                let to_new = to_old + amount;
                write_checkpoint(world, to, to_num, to_old, to_new);
            }
        }
    }

    fn write_checkpoint(
        world: IWorldDispatcher,
        delegatee: ContractAddress,
        n_checkpoints: u64,
        old_votes: u128,
        new_votes: u128
    ) {
        let timestamp = get_block_timestamp();
        if !n_checkpoints.is_zero() {
            let mut checkpoint = get!(world, (delegatee, n_checkpoints - 1), Checkpoints)
                .checkpoint;
            if checkpoint.from_block == timestamp {
                checkpoint.votes = new_votes;
                set!(
                    world, Checkpoints { account: delegatee, index: n_checkpoints - 1, checkpoint }
                );
            }
        } else {
            let mut checkpoint = Checkpoint { from_block: timestamp, votes: new_votes };
            set!(world, Checkpoints { account: delegatee, index: n_checkpoints, checkpoint });
            set!(world, NumCheckpoints { account: delegatee, count: n_checkpoints + 1 });
        }
        emit!(
            world,
            tokenevents::DelegateVotesChanged {
                delegatee, prev_balance: old_votes, new_balance: new_votes
            }
        );
    }
}
