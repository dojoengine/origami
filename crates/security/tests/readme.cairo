//! The examples of `README.md`, compiled against the public API.

use core::poseidon::poseidon_hash_span;
use origami_security::commitment::{Commitment, CommitmentTrait};

#[test]
fn test_readme_commit_reveal() {
    // Create a new commitment
    let mut commitment: Commitment = CommitmentTrait::new();
    // Commit to a value (in this case, a string)
    let value = 'secret';
    let mut serialized = array![];
    value.serialize(ref serialized);
    let hash = poseidon_hash_span(serialized.span());
    commitment.commit(hash);
    // Later, reveal and verify the commitment
    let is_valid = commitment.reveal('secret');
    assert(is_valid, 'Invalid reveal for commitment');
}
