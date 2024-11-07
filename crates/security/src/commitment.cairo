use core::poseidon::poseidon_hash_span;
use core::num::traits::Zero;

#[derive(Copy, Drop, Default, Serde)]
pub struct Commitment {
    pub hash: felt252
}

/// Errors module.
pub mod errors {
    pub const COMMITMENT_INVALID_HASH: felt252 = 'Commitment: can not commit zero';
}

pub trait CommitmentTrait {
    fn new() -> Commitment;
    fn commit(ref self: Commitment, hash: felt252);
    fn reveal<T, impl TSerde: Serde<T>, impl TDrop: Drop<T>>(self: @Commitment, reveal: T) -> bool;
}

pub impl CommitmentImpl of CommitmentTrait {
    fn new() -> Commitment {
        Commitment { hash: 0 }
    }

    fn commit(ref self: Commitment, hash: felt252) {
        assert(hash.is_non_zero(), errors::COMMITMENT_INVALID_HASH);
        self.hash = hash;
    }

    fn reveal<T, impl TSerde: Serde<T>, impl TDrop: Drop<T>>(self: @Commitment, reveal: T) -> bool {
        let mut serialized = array![];
        reveal.serialize(ref serialized);
        let hash = poseidon_hash_span(serialized.span());
        return hash == *self.hash;
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::poseidon::poseidon_hash_span;

    // Local imports

    use super::CommitmentTrait;

    #[test]
    fn test_security_commit_reveal() {
        let mut commitment = CommitmentTrait::new();
        let value = array!['ohayo'].span();
        let hash = poseidon_hash_span(value);
        commitment.commit(hash);
        let valid = commitment.reveal('ohayo');
        assert(valid, 'invalid reveal for commitment')
    }

    #[test]
    #[should_panic(expected: ('Commitment: can not commit zero',))]
    fn test_security_commit_revert_zero() {
        let mut commitment = CommitmentTrait::new();
        commitment.commit(0);
    }
}
