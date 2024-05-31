# Governance Token

A governance token implementation. It provides functionality for token management, delegation, and voting.

## Contract State

The contract state is managed using the following data structures:

- `Metadata`: Stores the token metadata, including name, symbol, and decimals.
- `TotalSupply`: Keeps track of the total supply of the token.
- `Balances`: Maintains the token balance of each account.
- `Delegates`: Stores the delegate information for each account.
- `NumCheckpoints`: Keeps track of the number of checkpoints for each account.
- `Checkpoints`: Stores the checkpoint data for each account and index.

## Contract Functions

### `initialize`

```rust
fn initialize(
    name: felt252,
    symbol: felt252,
    decimals: u8,
    initial_supply: u128,
    recipient: ContractAddress
)
```

This function initializes the governance token contract with the provided parameters. It sets the token metadata, total supply, and assigns the initial supply to the specified recipient address. It can only be called once during contract deployment.

```rust
fn approve(spender: ContractAddress, amount: u128)
```

This function allows the caller to approve a spender to spend a specified amount of tokens on their behalf. It updates the allowance for the spender and emits an `Approval` event.

```rust
fn transfer(to: ContractAddress, amount: u128)
```

This function transfers a specified amount of tokens from the caller's account to the recipient's account. It updates the balances and emits a `Transfer` event.


```rust
fn transfer_from(from: ContractAddress, to: ContractAddress, amount: u128)
```

This function allows a spender to transfer tokens from one account to another, provided that the spender has sufficient allowance. It updates the balances, allowances, and emits a `Transfer` event.

```rust
fn delegate(delegatee: ContractAddress)
```

This function allows the caller to delegate their voting power to another account. It updates the delegate information and moves the delegated votes accordingly.


```rust
fn get_current_votes(account: ContractAddress) -> u128
```

This function retrieves the current number of votes for a given account. It looks up the most recent checkpoint for the account and returns the corresponding vote count.

```rust
fn get_prior_votes(account: ContractAddress, timestamp: u64) -> u128
```

This function retrieves the number of votes for a given account at a specific timestamp. It performs a binary search on the account's checkpoints to find the checkpoint immediately preceding the given timestamp and returns the corresponding vote count.

## Internal Functions

The contract also includes several internal functions that are used to implement the core functionality:

- `delegate`: Handles the delegation of votes from one account to another.
- `transfer_tokens`: Performs the actual token transfer between accounts.
- `move_delegates`: Updates the vote counts when tokens are transferred or delegated.
- `write_checkpoint`: Writes a new checkpoint for an account's vote count.

## Events

The contract emits the following events:

- `Transfer`: Emitted when tokens are transferred between accounts.
- `Approval`: Emitted when an account approves another account to spend tokens on their behalf.
- `DelegateChanged`: Emitted when an account changes their delegate.
- `DelegateVotesChanged`: Emitted when the vote count for a delegate changes.

Please note that this documentation provides a high-level overview of the governance token smart contract. For more detailed information, refer to the contract code and the associated libraries and models used in the implementation.

# Timelock 

The Timelock is designed to provide a secure way to manage and execute transactions with a time delay. It allows an admin to queue transactions, which can be executed only after a specified time period has passed. This contract is based on the Compound's Timelock contract and is implemented using the Dojo framework.

## Constants

The contract defines the following constants:

- `GRACE_PERIOD`: The grace period (in seconds) after the time lock has passed during which a transaction can be executed. Set to 14 days (1,209,600 seconds).
- `MINIMUM_DELAY`: The minimum delay (in seconds) required before a transaction can be executed. Set to 2 days (172,800 seconds).
- `MAXIMUM_DELAY`: The maximum delay (in seconds) allowed for a transaction. Set to 30 days (2,592,000 seconds).

## Functions

```rust
fn initialize(admin: ContractAddress, delay: u64)
```

This function initializes the Timelock contract with the specified admin address and delay. It can only be called once during the contract's lifetime.

- `admin`: The address of the admin who will have the authority to queue and execute transactions.
- `delay`: The delay (in seconds) required before a queued transaction can be executed. Must be within the `MINIMUM_DELAY` and `MAXIMUM_DELAY` range.

```rust
fn execute_transaction(world: IWorldDispatcher, target: ContractAddress, new_implementation: ClassHash, eta: u64)
```

This function executes a previously queued transaction.

- `world`: The world dispatcher used to interact with the contract state.
- `target`: The address of the contract to be upgraded.
- `new_implementation`: The class hash of the new implementation for the target contract.
- `eta`: The estimated execution time (timestamp) of the transaction.

The function checks that the caller is the admin, the transaction has been queued, the current timestamp is within the allowed execution window (between `eta` and `eta + GRACE_PERIOD`), and then executes the transaction by upgrading the target contract with the new implementation.

```rust
fn que_transaction(world: IWorldDispatcher, target: ContractAddress, new_implementation: ClassHash, eta: u64)
```

This function queues a transaction for future execution.

- `world`: The world dispatcher used to interact with the contract state.
- `target`: The address of the contract to be upgraded.
- `new_implementation`: The class hash of the new implementation for the target contract.
- `eta`: The estimated execution time (timestamp) of the transaction. Must be at least `delay` seconds in the future.

The function checks that the caller is the admin and the `eta` satisfies the required delay, then marks the transaction as queued.

```rust
fn cancel_transaction(world: IWorldDispatcher, target: ContractAddress, new_implementation: ClassHash, eta: u64)
```

This function cancels a previously queued transaction.

- `world`: The world dispatcher used to interact with the contract state.
- `target`: The address of the contract associated with the transaction to be canceled.
- `new_implementation`: The class hash of the new implementation associated with the transaction to be canceled.
- `eta`: The estimated execution time (timestamp) of the transaction to be canceled.

The function checks that the caller is the admin and then marks the transaction as not queued, effectively canceling it.

## Events

The contract emits the following events:

- `NewAdmin`: Emitted when a new admin is set during contract initialization.
- `NewDelay`: Emitted when a new delay is set during contract initialization.
- `ExecuteTransaction`: Emitted when a transaction is executed.
- `QueueTransaction`: Emitted when a transaction is queued.
- `CancelTransaction`: Emitted when a transaction is canceled.

These events provide transparency and allow off-chain monitoring of the contract's activity.

# Governor 

The Governor is responsible for managing the governance process of a decentralized system.

## Contract Structure

The Governor contract is implemented in the `governor` module and consists of the following main components:

1. `GovernorImpl`: The main implementation of the Governor contract, which defines the core functionality.
2. `governorevents`: A library that defines the events emitted by the Governor contract.
3. `models`: A module that defines the data structures used by the Governor contract, such as `GovernorParams`, `ProposalParams`, `Proposal`, and `Receipt`.
4. `systems`: A module that defines the interfaces and contracts used by the Governor contract, such as `IGovernor`, `ITimelockDispatcher`, and `IGovernanceTokenDispatcher`.

## Contract Functions

### `initialize`

```rust
fn initialize(
    timelock: ContractAddress, gov_token: ContractAddress, guardian: ContractAddress
)
```

- `timelock`: The address of the Timelock contract.
- `gov_token`: The address of the Governance Token contract.
- `guardian`: The address of the guardian account.

The `initialize` function is used to set the initial parameters of the Governor contract. It can only be called once.

### `set_proposal_params`

```rust
fn set_proposal_params(
    quorum_votes: u128, threshold: u128, voting_delay: u64, voting_period: u64,
)
```

- `quorum_votes`: The minimum number of votes required for a proposal to reach quorum.
- `threshold`: The minimum number of votes required for a proposer to create a proposal.
- `voting_delay`: The delay (in blocks) between the proposal's creation and the start of the voting period.
- `voting_period`: The duration (in blocks) of the voting period.

The `set_proposal_params` function allows the guardian to set the parameters for creating and voting on proposals.

### `propose`

```rust
fn propose(target: ContractAddress, class_hash: ClassHash) -> usize
```

- `target`: The address of the contract to be called by the proposal.
- `class_hash`: The class hash of the contract to be called by the proposal.

The `propose` function is used to create a new proposal. It returns the `proposal_id` of the created proposal.

### `queue`

```rust
fn queue(proposal_id: usize)
```

- `proposal_id`: The ID of the proposal to be queued for execution.

The `queue` function is used to queue a succeeded proposal for execution.

### `execute`

```rust
fn execute(proposal_id: usize)
```

- `proposal_id`: The ID of the proposal to be executed.

The `execute` function is used to execute a queued proposal.

### `cancel`

```rust
fn cancel(proposal_id: usize)
```

- `proposal_id`: The ID of the proposal to be canceled.

The `cancel` function is used to cancel a proposal. It can only be called by the guardian or the proposer (if their votes are below the threshold).

### `get_action`

```rust
fn get_action(proposal_id: usize) -> (ContractAddress, ClassHash)
```

- `proposal_id`: The ID of the proposal.

The `get_action` function returns the target contract address and class hash of a proposal.

### `state`

```rust
fn state(proposal_id: usize) -> ProposalState
```

- `proposal_id`: The ID of the proposal.

The `state` function returns the current state of a proposal.

### `cast_vote`

```rust
fn cast_vote(proposal_id: usize, support: Support)
```

- `proposal_id`: The ID of the proposal to vote on.
- `support`: The user's vote, which can be either `For`, `Against`, or `Abstain`.

The `cast_vote` function is used by users to vote on active proposals.

## Internal Function

### `queue_or_revert`

```rust
fn queue_or_revert(
    world: IWorldDispatcher, target: ContractAddress, class_hash: ClassHash, eta: u64
)
```

- `world`: The world dispatcher used to access contract storage.
- `target`: The address of the contract to be called by the proposal.
- `class_hash`: The class hash of the contract to be called by the proposal.
- `eta`: The timestamp at which the proposal can be executed.

The `queue_or_revert` function is an internal function used to queue a proposal for execution or revert if the proposal is already queued.

## Events

The Governor contract emits the following events:

- `ProposalCreated`: Emitted when a new proposal is created.
- `ProposalQueued`: Emitted when a proposal is queued for execution.
- `ProposalExecuted`: Emitted when a proposal is executed.
- `ProposalCanceled`: Emitted when a proposal is canceled.
- `VoteCast`: Emitted when a user casts a vote on a proposal.

These events provide transparency and allow users to track the progress of proposals and the actions taken by the Governor contract.