#[dojo::contract]
mod governancetoken {
    use governance::libraries::events::tokenevents;
    use governance::models::token::{
        Allowances, Metadata, TotalSupply, Balances, Delegates, NumCheckpoints, Checkpoints,
        Checkpoint
    };
    use governance::systems::token::interface::IGovernanceToken;
    use integer::BoundedInt;
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address,
        info::{get_block_number, get_execution_info},
    };

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
            let token = get_contract_address();
            let metadata = get!(world, token, Metadata);
            let total_supply = get!(world, token, TotalSupply).amount;
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
                    Metadata { token, name, symbol, decimals },
                    TotalSupply { token, amount: initial_supply },
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
            println!("caller {:?}", get_caller_address());
            transfer_tokens(self.world_dispatcher.read(), get_caller_address(), to, amount);
        }

        fn transfer_from(from: ContractAddress, to: ContractAddress, amount: u128) {
            let world = self.world_dispatcher.read();
            let spender = get_caller_address();
            let spender_allowance = get!(world, (from, spender), Allowances).amount;

            if spender != from && spender_allowance != BoundedInt::max() {
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

        fn get_prior_votes(account: ContractAddress, block_number: u64) -> u128 {
            let world = self.world_dispatcher.read();
            let block_number = get_block_number();
            assert!(block_number < block_number, "Governance Token: not yet determined");
            let n_checkpoints = get!(world, account, NumCheckpoints).count;
            if n_checkpoints.is_zero() {
                return 0;
            }
            let most_recent_checkpoint = get!(world, (account, n_checkpoints - 1), Checkpoints)
                .checkpoint;
            if most_recent_checkpoint.from_block > block_number {
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
                if cp.from_block == block_number {
                    votes = cp.votes;
                    break;
                } else if cp.from_block < block_number {
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
        world: IWorldDispatcher, src_rep: ContractAddress, dst_rep: ContractAddress, amount: u128
    ) {
        println!("amount {}", amount);
        println!("src_rep {:?}", src_rep);
        println!("dst_rep {:?}", dst_rep);
        if src_rep != dst_rep && !amount.is_zero() {
            if !src_rep.is_zero() {
                let src_rep_num = get!(world, src_rep, NumCheckpoints).count;
                let src_rep_old = if !src_rep_num.is_zero() {
                    get!(world, (src_rep, src_rep_num - 1), Checkpoints).checkpoint.votes
                } else {
                    0
                };
                assert!(src_rep_old >= amount, "Governance Token: vote amount underflows");
                let src_rep_new = src_rep_old - amount;
                write_checkpoint(world, src_rep, src_rep_num, src_rep_old, src_rep_new);
            }

            if !dst_rep.is_zero() {
                let dst_rep_num = get!(world, dst_rep, NumCheckpoints).count;
                let dst_rep_old = if !dst_rep_num.is_zero() {
                    get!(world, (dst_rep, dst_rep_num - 1), Checkpoints).checkpoint.votes
                } else {
                    0
                };
                let dst_rep_new = dst_rep_old + amount;
                write_checkpoint(world, dst_rep, dst_rep_num, dst_rep_old, dst_rep_new);
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
        println!("old_votes {}", old_votes);
        println!("new_votes {}", new_votes);
        println!("n_checkpoints {}", n_checkpoints);
        let block_number = get_block_number();
        if !n_checkpoints.is_zero() {
            let mut checkpoint = get!(world, (delegatee, n_checkpoints - 1), Checkpoints)
                .checkpoint;
            if checkpoint.from_block == block_number {
                checkpoint.votes = new_votes;
                set!(
                    world, Checkpoints { account: delegatee, index: n_checkpoints - 1, checkpoint }
                );
            }
        } else {
            let mut checkpoint = Checkpoint { from_block: block_number, votes: new_votes };
            set!(world, Checkpoints { account: delegatee, index: n_checkpoints, checkpoint });
        }
        emit!(
            world,
            tokenevents::DelegateVotesChanged {
                delegatee, prev_balance: old_votes, new_balance: new_votes
            }
        );
    }
}
