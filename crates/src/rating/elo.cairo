//! Elo struct and rating methods.
//! Source: https://github.com/saucepoint/elo-lib/blob/main/src/Elo.sol

// Core imports

use core::integer::u256_sqrt;

// Constants

const MULTIPLIER: u256 = 10_000;
const SCALER: u256 = 800;

// Errors

mod errors {
    const ELO_DIFFERENCE_TOO_LARGE: felt252 = 'Elo: difference too large';
}

/// Elo implementation..
#[generate_trait]
impl EloImpl of Elo {
    /// Calculates the change in ELO rating, after a given outcome.
    /// # Arguments
    /// * `rating_a` - The ELO rating of the player A.
    /// * `rating_b` - The ELO rating of the player B.
    /// * `score` - The score of the player A, scaled by 100. 100 = win, 50 = draw, 0 = loss.
    /// * `k` - The k-factor or development multiplier used to calculate the change in ELO rating. 20 is the typical value.
    /// # Returns
    /// * `change` - The change in ELO rating of player A.
    /// * `negative` - The directional change of player A's ELO. Opposite sign for player B.
    #[inline(always)]
    fn rating_change(rating_a: u256, rating_b: u256, score: u256, k: u256) -> (u256, bool) {
        let negative = rating_a > rating_b;
        let rating_diff: u256 = if negative {
            rating_a - rating_b
        } else {
            rating_b - rating_a
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
        let powered: u256 = PrivateTrait::pow(10, order);
        let rooted: u256 = u256_sqrt(u256_sqrt(u256_sqrt(u256_sqrt(powered).into()).into()).into())
            .into();

        // [Compute] Change = k * (score - expectedScore)
        let k_expected_score = k * MULTIPLIER / (100 + rooted);
        let k_score = k * score;
        let negative = k_score < k_expected_score;
        let change = if negative {
            k_expected_score - k_score
        } else {
            k_score - k_expected_score
        };

        // [Return] Change rounded and its sign
        (PrivateTrait::round_div(change, 100), negative)
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

    use super::Elo;

    #[test]
    fn test_elo_change_positive_01() {
        let (mag, sign) = Elo::rating_change(1200, 1400, 100, 20);
        assert(mag == 15, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_positive_02() {
        let (mag, sign) = Elo::rating_change(1300, 1200, 100, 20);
        assert(mag == 7, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_positive_03() {
        let (mag, sign) = Elo::rating_change(1900, 2100, 100, 20);
        assert(mag == 15, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_negative_01() {
        let (mag, sign) = Elo::rating_change(1200, 1400, 0, 20);
        assert(mag == 5, 'Elo: wrong change mag');
        assert(sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_negative_02() {
        let (mag, sign) = Elo::rating_change(1300, 1200, 0, 20);
        assert(mag == 13, 'Elo: wrong change mag');
        assert(sign, 'Elo: wrong change sign');
    }

    #[test]
    fn test_elo_change_draw() {
        let (mag, sign) = Elo::rating_change(1200, 1400, 50, 20);
        assert(mag == 5, 'Elo: wrong change mag');
        assert(!sign, 'Elo: wrong change sign');
    }
}
