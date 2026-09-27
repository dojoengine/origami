//! Spreader: uniform selection of walkable tiles (lot L7).
//!
//! Hash-and-mask with an exact fix-up. Poseidon outputs combined by AND/OR give a Bernoulli mask
//! of density `q / 32`; its intersection with the free walkable tiles is taken in one go. Two
//! rounds (a density in 1/16, then in 1/32 on the remaining deficit) pick most of the tiles,
//! rejection sampling on the board adds the last ones, and an overshoot is trimmed by removing
//! uniformly chosen candidates. Every step only depends on counts and on independent random bits,
//! so the result is invariant under any permutation of the walkable tiles: it is uniform among the
//! subsets of `count` walkable tiles. When `count` exceeds half of the walkable tiles the
//! complement is drawn (the tiles left without an object). Boards of at most 128 bits run on a
//! single `u128` limb. See `GAS.md` (section L7) for the measured alternatives.

// Core imports

use core::poseidon::hades_permutation;
use core::traits::{BitAnd, BitOr};

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, POW128};
use origami_hexmap::helpers::rng::{Rng, RngTrait};

// Constants

/// Smallest number of draws worth a mask round.
const MASK_MIN: u8 = 4;
/// Odd bits mask 0xAAAA... on 128 bits.
const MASK_ODD_BITS: u128 = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
/// Low pairs mask 0x3333... on 128 bits.
const MASK_PAIRS: u128 = 0x33333333333333333333333333333333;
/// Low nibbles mask 0x0F0F... on 128 bits.
const MASK_NIBBLES: u128 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
/// Byte-sum multiplier 0x0101...01 (16 bytes).
const BYTES_ONE: felt252 = 0x01010101010101010101010101010101;
/// 2^120, the byte-sum lands in the top byte of the low limb.
const TWO_POW_120: NonZero<u128> = 0x1000000000000000000000000000000;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// 1/4 in the field.
const INV_4: felt252 = 0x60000000000000cc00000000000000000000000000000000000000000000001;
/// 1/16 in the field.
const INV_16: felt252 = 0x78000000000000ff00000000000000000000000000000000000000000000001;

/// A Poseidon output as a set of random bits.
#[inline]
fn w<T, +BitSetTrait<T>>(word: felt252) -> T {
    BitSetTrait::word(word)
}

/// Errors module.
pub mod errors {
    pub const SPREADER_NOT_ENOUGH_PLACE: felt252 = 'Spreader: not enough place';
    pub const SPREADER_INVALID_GRID: felt252 = 'Spreader: invalid grid';
}

/// Set operations of the draw: `u256` on any board, `u128` on boards of at most 128 bits.
pub trait BitSetTrait<T> {
    /// A Poseidon output as a set of independent random bits.
    fn word(word: felt252) -> T;
    /// The number of set bits.
    fn popcount(self: T) -> u8;
    /// Remove `draws` uniformly chosen set bits by rejection sampling on the board.
    fn reject(self: T, draws: u8, range: NonZero<u128>, ref rng: Rng) -> T;
    /// Remove `count` uniformly chosen set bits by rank: draw a rank, walk the set bits.
    fn walk(self: T, total: u8, count: u8, ref rng: Rng) -> T;
}

pub impl U256BitSet of BitSetTrait<u256> {
    #[inline]
    fn word(word: felt252) -> u256 {
        word.into()
    }

    #[inline]
    fn popcount(self: u256) -> u8 {
        Bits::popcount(self)
    }

    #[inline]
    fn reject(self: u256, draws: u8, range: NonZero<u128>, ref rng: Rng) -> u256 {
        let mut low = self.low;
        let mut high = self.high;
        let mut draws = draws;
        while draws != 0 {
            let index: u32 = rng.draw(range).try_into().unwrap();
            if index < 128 {
                let bit = *POW128.span().at(index);
                if low & bit != 0 {
                    low -= bit;
                    draws -= 1;
                }
            } else {
                let bit = *POW128.span().at(index - 128);
                if high & bit != 0 {
                    high -= bit;
                    draws -= 1;
                }
            }
        }
        u256 { low, high }
    }

    fn walk(self: u256, total: u8, count: u8, ref rng: Rng) -> u256 {
        let mut low = self.low;
        let mut high = self.high;
        let mut total: u128 = total.into();
        let mut count = count;
        while count != 0 {
            let mut rank = rng.draw(total.try_into().unwrap());
            let mut x = low;
            while rank != 0 && x != 0 {
                x = x & (x - 1);
                rank -= 1;
            }
            if x != 0 {
                low -= x - (x & (x - 1));
            } else {
                let mut y = high;
                while rank != 0 {
                    y = y & (y - 1);
                    rank -= 1;
                }
                high -= y - (y & (y - 1));
            }
            total -= 1;
            count -= 1;
        }
        u256 { low, high }
    }
}

pub impl U128BitSet of BitSetTrait<u128> {
    #[inline]
    fn word(word: felt252) -> u128 {
        let word: u256 = word.into();
        word.low
    }

    /// SWAR popcount on one limb, shifts as exact field divisions (see `Bits::popcount`).
    fn popcount(self: u128) -> u8 {
        let value: felt252 = self.into();
        let pairs = value - (self & MASK_ODD_BITS).into() * INV_2;
        let low: felt252 = (pairs.try_into().unwrap() & MASK_PAIRS).into();
        let nibbles = low + (pairs - low) * INV_4;
        let low: felt252 = (nibbles.try_into().unwrap() & MASK_NIBBLES).into();
        let bytes = low + (nibbles - low) * INV_16;
        // [Compute] Each byte is at most 8, byte 15 of the product holds the total
        let total: u256 = (bytes * BYTES_ONE).into();
        let (count, _) = DivRem::div_rem(total.low, TWO_POW_120);
        count.try_into().unwrap()
    }

    #[inline]
    fn reject(self: u128, draws: u8, range: NonZero<u128>, ref rng: Rng) -> u128 {
        let mut set = self;
        let mut draws = draws;
        while draws != 0 {
            let index: u32 = rng.draw(range).try_into().unwrap();
            let bit = *POW128.span().at(index);
            if set & bit != 0 {
                set -= bit;
                draws -= 1;
            }
        }
        set
    }

    fn walk(self: u128, total: u8, count: u8, ref rng: Rng) -> u128 {
        let mut set = self;
        let mut total: u128 = total.into();
        let mut count = count;
        while count != 0 {
            let mut rank = rng.draw(total.try_into().unwrap());
            let mut x = set;
            while rank != 0 {
                x = x & (x - 1);
                rank -= 1;
            }
            set -= x - (x & (x - 1));
            total -= 1;
            count -= 1;
        }
        set
    }
}

#[generate_trait]
pub impl Spreader of SpreaderTrait {
    /// Pick `count` walkable tiles uniformly.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `count` - The number of tiles to pick
    /// * `seed` - The seed
    /// # Returns
    /// * The bitmap of the picked tiles
    /// # Panics
    /// * `Asserter: invalid dimension` if the board is smaller than 3x3 or larger than 251 bits
    /// * `Spreader: invalid grid` if a walkable tile lies outside the board
    /// * `Spreader: not enough place` if `count` exceeds the number of walkable tiles
    fn generate(grid: felt252, width: u8, height: u8, count: u8, seed: felt252) -> felt252 {
        // [Check] Valid dimensions, then no walkable tile outside the board
        Asserter::assert_valid_dimension(width, height);
        let size = width * height;
        let value: u256 = grid.into();
        assert(value < Bits::pow(size).into(), errors::SPREADER_INVALID_GRID);
        // [Check] Enough walkable tiles
        let walkable = Bits::popcount(value);
        assert(count <= walkable, errors::SPREADER_NOT_ENOUGH_PLACE);
        // [Compute] Draw the smaller of the picked set and its complement
        let complement = count > walkable - count;
        let draws = if complement {
            walkable - count
        } else {
            count
        };
        let free: felt252 = if size <= 128 {
            Self::spread(value.low, walkable, draws, size, seed).into()
        } else {
            Bits::to_felt(Self::spread(value, walkable, draws, size, seed))
        };
        // [Return] The drawn tiles, or the tiles left free when the complement was drawn
        if complement {
            free
        } else {
            grid - free
        }
    }

    /// Remove `draws` uniformly chosen tiles from a set.
    /// # Arguments
    /// * `free` - The set, below 2^251
    /// * `total` - The number of set bits, at least `2 * draws`
    /// * `draws` - The number of tiles to remove
    /// * `size` - The board size, every set bit is below it
    /// * `seed` - The seed
    /// # Returns
    /// * The set without the removed tiles
    fn spread<T, +BitSetTrait<T>, +BitAnd<T>, +BitOr<T>, +Sub<T>, +Copy<T>, +Drop<T>>(
        mut free: T, mut total: u8, mut draws: u8, size: u8, seed: felt252,
    ) -> T {
        let range: u128 = size.into();
        let range: NonZero<u128> = range.try_into().unwrap();
        let mut state = seed;
        // [Compute] Mask rounds: density q / 16, then q / 32 on the remaining deficit
        let mut round: u8 = 0;
        while round != 2 && draws >= MASK_MIN {
            let draws_u16: u16 = draws.into();
            let q: u16 = if round == 0 {
                draws_u16 * 16 / total.into() * 2
            } else {
                draws_u16 * 32 / total.into()
            };
            round += 1;
            if q == 0 {
                continue;
            }
            let (mask, next) = Self::bernoulli(q.try_into().unwrap(), state);
            state = next;
            let candidates = free & mask;
            let picked = candidates.popcount();
            if picked > draws {
                // [Compute] Overshoot: keep `draws` candidates, the round ends the draw
                let mut rng = RngTrait::new(state);
                let kept = Self::trim(candidates, picked, picked - draws, size, range, ref rng);
                return free - kept;
            }
            free = free - candidates;
            draws -= picked;
            total -= picked;
        }
        // [Compute] Last tiles by rejection sampling
        let mut rng = RngTrait::new(state);
        free.reject(draws, range, ref rng)
    }

    /// Bernoulli mask: every bit is set with probability `q / 32`, independently.
    /// The bits of `q` are read from the lowest over 5 random words `a..e`: a set bit ORs the
    /// next word (`p = 1/2 + p/2`), a cleared bit ANDs it (`p = p/2`), and the words below the
    /// lowest set bit are skipped. Unrolled: a loop over the bits costs 2.4x more (`GAS.md`).
    /// A Poseidon output is uniform below the field prime, so its bits below 251 are fair up to a
    /// bias under 2^-55.
    /// # Arguments
    /// * `q` - The numerator, in `1..=16`
    /// * `seed` - The seed
    /// # Returns
    /// * The mask, and the next seed
    fn bernoulli<T, +BitSetTrait<T>, +BitAnd<T>, +BitOr<T>, +Copy<T>, +Drop<T>>(
        q: u8, seed: felt252,
    ) -> (T, felt252) {
        let (a, b, c) = hades_permutation(seed, 0, 2);
        let (d, e, next) = hades_permutation(seed, 1, 2);
        // [Compute] Only the words used by `q` are converted
        let mask: T = match q {
            1 => w(e) & (w(d) & (w(c) & (w(b) & w(a)))),
            2 => w(e) & (w(d) & (w(c) & w(b))),
            3 => w(e) & (w(d) & (w(c) & (w(b) | w(a)))),
            4 => w(e) & (w(d) & w(c)),
            5 => w(e) & (w(d) & (w(c) | (w(b) & w(a)))),
            6 => w(e) & (w(d) & (w(c) | w(b))),
            7 => w(e) & (w(d) & (w(c) | (w(b) | w(a)))),
            8 => w(e) & w(d),
            9 => w(e) & (w(d) | (w(c) & (w(b) & w(a)))),
            10 => w(e) & (w(d) | (w(c) & w(b))),
            11 => w(e) & (w(d) | (w(c) & (w(b) | w(a)))),
            12 => w(e) & (w(d) | w(c)),
            13 => w(e) & (w(d) | (w(c) | (w(b) & w(a)))),
            14 => w(e) & (w(d) | (w(c) | w(b))),
            15 => w(e) & (w(d) | (w(c) | (w(b) | w(a)))),
            _ => w(e),
        };
        (mask, next)
    }

    /// Remove `count` uniformly chosen tiles from a set: by rank on sparse sets, by rejection
    /// sampling on the board otherwise.
    /// # Arguments
    /// * `set` - The set
    /// * `total` - The number of set bits, more than `count`
    /// * `count` - The number of tiles to remove
    /// * `size` - The board size
    /// * `range` - The board size, as a divisor
    /// * `rng` - The generator
    /// # Returns
    /// * The set without the removed tiles
    #[inline]
    fn trim<T, +BitSetTrait<T>, +Drop<T>>(
        set: T, total: u8, count: u8, size: u8, range: NonZero<u128>, ref rng: Rng,
    ) -> T {
        // [Check] Cost model: a rank walk visits half the set on average (~3.5k per step), a
        // rejection trial costs ~10k and succeeds with probability `total / size`
        let total_u16: u16 = total.into();
        let size: u16 = size.into();
        if total_u16 * (total_u16 + 3) >= 6 * size {
            set.reject(count, range, ref rng)
        } else {
            set.walk(total, count, ref rng)
        }
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::dict::Felt252Dict;

    // Internal imports

    use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
    use origami_hexmap::tests::fixtures::*;

    // Local imports

    use super::{BitSetTrait, Spreader};

    // Constants

    const SEED: felt252 = 'SEED';

    /// Draw and assert the invariants: `count` bits, all on walkable tiles.
    fn check(grid: felt252, width: u8, height: u8, count: u8, seed: felt252) -> felt252 {
        let objects = Spreader::generate(grid, width, height, count, seed);
        let objects_u256: u256 = objects.into();
        let grid_u256: u256 = grid.into();
        assert!(objects_u256 & grid_u256 == objects_u256);
        assert!(Bits::popcount(objects_u256) == count);
        objects
    }

    /// The set bits of a bitmap, as bit values `2^i`.
    fn bits(set: felt252) -> Array<felt252> {
        let set: u256 = set.into();
        let mut keys: Array<felt252> = array![];
        let mut low = set.low;
        while low != 0 {
            let rest = low & (low - 1);
            keys.append((low - rest).into());
            low = rest;
        }
        let mut high = set.high;
        while high != 0 {
            let rest = high & (high - 1);
            keys.append((high - rest).into() * TWO_POW_128);
            high = rest;
        }
        keys
    }

    /// Draw `runs` times and assert that every walkable tile is picked `E = runs * count /
    /// walkable` times within `margin`, and that the sum of the squared deviations stays below
    /// twice its expectation under uniformity, `walkable * E * (1 - count / walkable)`.
    fn assert_uniform(grid: felt252, width: u8, height: u8, count: u8, runs: u32, margin: u32) {
        let mut counts: Felt252Dict<u32> = Default::default();
        let mut seed: felt252 = SEED;
        let mut run = runs;
        while run != 0 {
            let objects = check(grid, width, height, count, seed);
            for key in bits(objects) {
                counts.insert(key, counts.get(key) + 1);
            }
            seed += 1;
            run -= 1;
        }
        // [Check] Every walkable tile
        let walkable: u32 = Bits::popcount(grid.into()).into();
        let expected = runs * count.into() / walkable;
        let mut squares: u32 = 0;
        for key in bits(grid) {
            let hits = counts.get(key);
            assert!(hits + margin >= expected && hits <= expected + margin, "tile {}", key);
            let deviation = if hits > expected {
                hits - expected
            } else {
                expected - hits
            };
            squares += deviation * deviation;
        }
        let variance = expected * (walkable - count.into()) / walkable;
        assert!(squares <= 2 * walkable * variance, "squares {} {}", squares, variance);
    }

    #[test]
    fn test_spreader_cave_7x7() {
        //  0 0 0 0 0 0 0
        // 0 1 0 0 0 0 0
        //  0 0 1 0 1 0 0
        // 0 0 0 0 1 0 0
        //  0 0 0 0 0 0 0
        // 0 0 0 1 0 0 0
        //  0 0 0 0 0 0 0
        let objects = check(CAVE_7X7, 7, 7, 5, SEED);
        assert!(objects == 0x10140800400);
    }

    #[test]
    fn test_spreader_cave_17x14() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 1 0 1 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0
        // 0 0 1 0 0 0 1 0 0 0 1 0 1 0 0 0 0
        //  0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0
        // 0 0 0 1 0 0 0 0 1 0 0 0 0 0 0 0 0
        //  0 1 0 1 0 1 0 0 1 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let objects = check(CAVE_17X14, 17, 14, 20, SEED);
        assert!(objects == 0xa0002000008088a020000000002080008000610802a40000000000);
    }

    #[test]
    fn test_spreader_maze_17x14_complement() {
        // 60 of 92 walkable tiles: the 32 tiles left free are drawn
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 1 1 0 0 1 0 1 0 0 1 0 0 0 1 0
        // 0 1 1 0 0 0 1 0 0 0 1 0 0 0 0 1 0
        //  0 0 1 1 1 0 1 1 0 1 0 0 1 0 0 0 0
        // 0 0 1 0 0 0 0 0 0 0 0 1 0 0 1 1 0
        //  0 0 0 0 1 0 0 0 0 1 1 0 0 0 0 1 0
        // 0 0 1 0 0 0 0 1 1 0 0 0 1 1 0 1 0
        //  0 0 1 0 0 0 0 0 0 0 0 0 0 1 0 0 0
        // 0 0 0 1 0 1 0 0 0 1 0 1 0 0 0 1 0
        //  0 0 0 0 0 1 1 0 0 0 1 0 1 0 0 0 0
        // 0 1 1 0 0 0 0 1 0 1 0 0 0 0 0 1 0
        //  0 0 0 0 1 0 0 0 0 1 0 0 0 1 0 1 0
        // 0 0 1 0 0 0 1 1 1 1 0 0 1 1 0 1 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let objects = check(MAZE_17X14, 17, 14, 60, SEED);
        assert!(objects == 0x652262211da40804c10c2218d1002051440c506141042288f340000);
    }

    #[test]
    fn test_spreader_invariants() {
        let counts = array![0_u8, 1, 3, 4, 5, 20, 60, 65, 66, 100, 130, 131].span();
        for count in counts {
            check(CAVE_17X14, 17, 14, *count, SEED);
        }
        let counts = array![0_u8, 1, 4, 5, 8, 9, 12, 16].span();
        for count in counts {
            check(MAZE_7X7, 7, 7, *count, SEED);
        }
        check(EMPTY_17X14, 17, 14, 180, SEED);
        check(EMPTY_17X14, 17, 14, 90, SEED);
        check(MAZE_17X14, 17, 14, 60, SEED);
        check(SERPENTINE_17X14, 17, 14, 47, SEED);
        check(UNREACHABLE_7X7, 7, 7, 10, SEED);
    }

    #[test]
    fn test_spreader_all_or_nothing() {
        assert!(Spreader::generate(CAVE_17X14, 17, 14, 131, SEED) == CAVE_17X14);
        assert!(Spreader::generate(CAVE_17X14, 17, 14, 0, SEED) == 0);
        assert!(Spreader::generate(CAVE_7X7, 7, 7, 23, SEED) == CAVE_7X7);
        assert!(Spreader::generate(CAVE_7X7, 7, 7, 0, SEED) == 0);
        assert!(Spreader::generate(0, 7, 7, 0, SEED) == 0);
    }

    #[test]
    fn test_spreader_deterministic() {
        let lhs = Spreader::generate(CAVE_17X14, 17, 14, 20, SEED);
        assert!(lhs == Spreader::generate(CAVE_17X14, 17, 14, 20, SEED));
        assert!(lhs != Spreader::generate(CAVE_17X14, 17, 14, 20, SEED + 1));
        let lhs = Spreader::generate(CAVE_7X7, 7, 7, 5, SEED);
        assert!(lhs == Spreader::generate(CAVE_7X7, 7, 7, 5, SEED));
        assert!(lhs != Spreader::generate(CAVE_7X7, 7, 7, 5, SEED + 1));
    }

    #[test]
    fn test_spreader_dimensions() {
        // Every tile walkable, border included: the draw does not need the border ring
        let full_3x3: felt252 = 0x1ff;
        assert!(check(full_3x3, 3, 3, 9, SEED) == full_3x3);
        check(full_3x3, 3, 3, 4, SEED);
        assert!(check(0x10, 3, 3, 1, SEED) == 0x10);
        let full_16x8: felt252 = Bits::pow(128) - 1;
        check(full_16x8, 16, 8, 1, SEED);
        check(full_16x8, 16, 8, 40, SEED);
        check(full_16x8, 16, 8, 100, SEED);
        let full_19x13: felt252 = Bits::pow(247) - 1;
        check(full_19x13, 19, 13, 30, SEED);
        check(full_19x13, 19, 13, 123, SEED);
        check(full_19x13, 19, 13, 200, SEED);
        // A single walkable tile, in the first and the last corner
        assert!(check(1, 19, 13, 1, SEED) == 1);
        assert!(check(Bits::pow(246), 19, 13, 1, SEED) == Bits::pow(246));
        assert!(check(Bits::pow(127), 16, 8, 1, SEED) == Bits::pow(127));
    }

    #[test]
    fn test_spreader_uniform_small_mask() {
        // u128 path, complement (12 > 23 - 12), mask rounds on 11 draws; expected 120 per tile
        assert_uniform(CAVE_7X7, 7, 7, 12, 230, 40);
    }

    #[test]
    fn test_spreader_uniform_small_reject() {
        // u128 path, rejection only (3 draws); expected 60 per tile
        assert_uniform(CAVE_7X7, 7, 7, 3, 460, 30);
    }

    #[test]
    fn test_spreader_uniform_large_mask() {
        // u256 path, mask rounds on 45 draws; expected 45 per tile
        assert_uniform(EMPTY_17X14, 17, 14, 45, 180, 30);
    }

    #[test]
    fn test_spreader_uniform_large_complement() {
        // u256 path, complement (75 > 92 - 75), mask rounds on 17 draws; expected 163 per tile
        assert_uniform(MAZE_17X14, 17, 14, 75, 200, 30);
    }

    #[test]
    fn test_spreader_bitset_popcount_small() {
        assert!(BitSetTrait::<u128>::popcount(0) == 0);
        assert!(BitSetTrait::<u128>::popcount(1) == 1);
        assert!(BitSetTrait::<u128>::popcount(0xffffffffffffffffffffffffffffffff) == 128);
        assert!(BitSetTrait::<u128>::popcount(0x80000000000000000000000000000001) == 2);
        let value: u256 = CAVE_7X7.into();
        assert!(BitSetTrait::<u128>::popcount(value.low) == 23);
    }

    #[test]
    #[should_panic(expected: 'Spreader: not enough place')]
    fn test_spreader_revert_not_enough_place() {
        Spreader::generate(CAVE_7X7, 7, 7, 24, SEED);
    }

    #[test]
    #[should_panic(expected: 'Spreader: not enough place')]
    fn test_spreader_revert_not_enough_place_large() {
        Spreader::generate(CAVE_17X14, 17, 14, 132, SEED);
    }

    #[test]
    #[should_panic(expected: 'Spreader: invalid grid')]
    fn test_spreader_revert_invalid_grid() {
        Spreader::generate(Bits::pow(49), 7, 7, 1, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_spreader_revert_invalid_dimension() {
        Spreader::generate(1, 2, 7, 1, SEED);
    }
}
