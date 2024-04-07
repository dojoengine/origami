#[dojo::contract]
mod governancetoken {
    use governance::libraries::events::tokenevents;
    use governance::models::token::{
        Allowances, Metadata, TotalSupply, Balances, Delegates, NumCheckpoints, Checkpoints
    };
    use governance::systems::token::interface::IGovernanceToken;
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address,
        info::{get_block_number, get_execution_info},
    };
    use integer::BoundedInt;
    use poseidon::poseidon_hash_span;

    impl GovernanceTokenImpl of IGovernanceToken<ContractState> {
        fn constructor(
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
            let block_number = get_block_number();
            assert!(block_number < block_number, "Governance Token: not yet determined");
            let world = self.world_dispatcher.read();
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


    fn delegate(world: IWorldDispatcher, delegator: ContractAddress, delegatee: ContractAddress) {
        let currentDelegate = get!(world, delegator, Delegates).delegatee;
        let delegatorBalance = get!(world, delegator, Balances).amount;
        set!(world, Delegates { account: delegator, delegatee });
        emit!(
            world, tokenevents::DelegateChanged { delegator, from: currentDelegate, to: delegatee }
        );
        move_delegates(world, currentDelegate, delegatee, delegatorBalance);
    }

    fn transfer_tokens(
        world: IWorldDispatcher, from: ContractAddress, to: ContractAddress, amount: u128
    ) {
        assert!(!from.is_zero(), "Governance Token: transfer from zero address");
        assert!(!to.is_zero(), "Governance Token: transfer to zero address");

        let from_balance = get!(world, from, Balances).amount;
        assert!(from_balance >= amount, "Governance Token: insufficient balance");

        let to_balance = get!(world, to, Balances).amount;
        set!(world, Balances { account: to, amount: to_balance + amount });
        emit!(world, tokenevents::Transfer { from, to, amount });
        let from_rep = get!(world, from, Delegates).delegatee;
        let to_rep = get!(world, to, Delegates).delegatee;

        move_delegates(world, from_rep, to_rep, amount);
    }

    fn move_delegates(
        world: IWorldDispatcher, from_rep: ContractAddress, to_rep: ContractAddress, amount: u128
    ) {
        if from_rep != to_rep && !amount.is_zero() {
            if !from_rep.is_zero() {
                let from_rep_num = get!(world, from_rep, NumCheckpoints).count;
                let from_rep_old = if !from_rep_num.is_zero() {
                    get!(world, (from_rep, from_rep_num - 1), Checkpoints).checkpoint.votes
                } else {
                    0
                };
                assert!(from_rep_old >= amount, "Governance Token: vote amount underflows");
                let from_rep_new = from_rep_old - amount;
                write_checkpoint(world, from_rep, from_rep_num, from_rep_old, from_rep_new);
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
        let block_number = get_block_number();
        let mut checkpoint = get!(world, (delegatee, n_checkpoints - 1), Checkpoints).checkpoint;
        if !n_checkpoints.is_zero() && checkpoint.from_block == n_checkpoints {
            checkpoint.votes = new_votes;
            set!(world, Checkpoints { account: delegatee, index: n_checkpoints - 1, checkpoint });
        } else {
            checkpoint.from_block = block_number;
            checkpoint.votes = new_votes;
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
