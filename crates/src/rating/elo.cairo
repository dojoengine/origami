//! Elo struct and rating methods.
//! Source: https://github.com/saucepoint/elo-lib/blob/main/src/Elo.sol

// Core imports

use core::integer::{u32_sqrt, u64_sqrt, u128_sqrt, u256_sqrt};

// Constants

const MULTIPLIER: u32 = 10_000;
const SCALER: u256 = 800;

// Errors

mod errors {
    const ELO_DIFFERENCE_TOO_LARGE: felt252 = 'Elo: difference too large';
}

/// Elo implementation..
#[generate_trait]
impl EloImpl of EloTrait {
    /// Calculates the change in ELO rating, after a given outcome.
    /// # Arguments
    /// * `rating_a` - The ELO rating of the player A.
    /// * `rating_b` - The ELO rating of the player B.
    /// * `score` - The score of the player A, scaled by 100. 100 = win, 50 = draw, 0 = loss.
    /// * `k` - The k-factor or development multiplier used to calculate the change in ELO rating. 20 is the typical value.
    /// # Returns
    /// * `change` - The change in ELO rating of player A.
    /// * `negative` - The directional change of player A's ELO. Opposite sign for player B.
    fn rating_change<
        T,
        +Sub<T>,
        +PartialOrd<T>,
        +Into<T, u256>,
        +Drop<T>,
        +Copy<T>,
        S,
        +Into<S, u32>,
        +Drop<S>,
        +Copy<S>,
        K,
        +Into<K, u32>,
        +Drop<K>,
        +Copy<K>,
        C,
        +Into<u32, C>,
    >(
        rating_a: T, rating_b: T, score: S, k: K
    ) -> (C, bool) {
        let negative = rating_a > rating_b;
        let rating_diff: u256 = if negative {
            (rating_a - rating_b).into()
        } else {
            (rating_b - rating_a).into()
        };

        // [Check] Checks against overflow/underflow
        // Large rating diffs leads to 10 ** rating_diff being too large to fit in a u256
        // Large rating diffs when applying the scale factor leads to underflow (800 - rating_diff)
        assert(
            rating_diff < 800 || (!negative && rating_diff < 1126), errors::ELO_DIFFERENCE_TOO_LARGE
        );

        // [Compute] Expected score = 1 / (1 + 10 ^ (rating_diff / 400))
        // Apply offset of 800 to scale the result by 100
        // Divide by 25 to avoid reach u256 max
        // (x / 400) is the same as ((x / 25) / 16)
        // x ^ (1 / 16) is the same as 16th root of x
        let order: u256 = if negative {
            (SCALER - rating_diff) / 25
        } else {
            (SCALER + rating_diff) / 25
        };
        // [Info] Order should be less or equal to 77 to fit a u256
        let powered: u256 = PrivateTrait::pow(10, order);
        let rooted: u16 = u32_sqrt(u64_sqrt(u128_sqrt(u256_sqrt(powered))));

        // [Compute] Change = k * (score - expectedScore)
        let k_expected_score = k.into() * MULTIPLIER / (100 + rooted.into());
        let k_score = k.into() * score.into();
        let negative = k_score < k_expected_score;
        let change = if negative {
            k_expected_score - k_score
        } else {
            k_score - k_expected_score
        };

        // [Return] Change rounded and its sign
        (PrivateTrait::round_div(change, 100).into(), negative)
    }
}

#[generate_trait]
impl Private of PrivateTrait {
    fn pow<T, +Sub<T>, +Mul<T>, +Div<T>, +Rem<T>, +PartialEq<T>, +Into<u8, T>, +Drop<T>, +Copy<T>>(
        base: T, exp: T
    ) -> T {
        if exp == 0_u8.into() {
            1_u8.into()
        } else if exp == 1_u8.into() {
            base
        } else if exp % 2_u8.into() == 0_u8.into() {
            PrivateTrait::pow(base * base, exp / 2_u8.into())
        } else {
            base * PrivateTrait::pow(base * base, exp / 2_u8.into())
        }
    }

    fn round_div<
        T, +Add<T>, +Sub<T>, +Div<T>, +Rem<T>, +PartialOrd<T>, +Into<u8, T>, +Drop<T>, +Copy<T>
    >(
        a: T, b: T
    ) -> T {
        let remained = a % b;
        if b - remained <= remained {
            return a / b + 1_u8.into();
        }
        return a / b;
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use debug::PrintTrait;

    // Local imports

    use super::EloTrait;

    #[test]
    fn test_elo_change_positive_01() {
        let (mag, sign) = EloTrait::rating_change(1200_u128, 1400_u128, 100_u16, 20_u8);
        assert(mag == 15, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_positive_02() {
        let (mag, sign) = EloTrait::rating_change(1300_u128, 1200_u128, 100_u16, 20_u8);
        assert(mag == 7, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_positive_03() {
        let (mag, sign) = EloTrait::rating_change(1900_u256, 2100_u256, 100_u16, 20_u8);
        assert(mag == 15, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_negative_01() {
        let (mag, sign) = EloTrait::rating_change(1200_u128, 1400_u128, 0_u16, 20_u8);
        assert(mag == 5, 'Elo: wrong change mag');
        assert(sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_negative_02() {
        let (mag, sign) = EloTrait::rating_change(1300_u128, 1200_u128, 0_u16, 20_u8);
        assert(mag == 13, 'Elo: wrong change mag');
        assert(sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_draw() {
        let (mag, sign) = EloTrait::rating_change(1200_u128, 1400_u128, 50_u16, 20_u8);
        assert(mag == 5, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }
}
