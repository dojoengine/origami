//! Spreader: uniform selection of walkable tiles (lot L7).
//!
//! Radix select on random keys. Every walkable tile gets a random key, one bit per Poseidon word;
//! the `count` tiles with the smallest keys are chosen, ties broken uniformly. The keys are never
//! materialised: level after level, one word splits the current class `S` (`n` tiles, `k` to
//! choose) in two, `Z = S & word` and `S - Z`, with one AND and one popcount `z`: if `k <= z` the
//! choice continues in `Z`, otherwise `Z` is chosen whole and the choice continues in `S - Z` for
//! `k - z` tiles. A class of at most 8 tiles is finished in one step: a uniform subset of the right
//! size from a table of all masks of up to 8 bits, deposited on the class by a walk of at most 8
//! steps. The number of levels is about `log2(n / 8)`, whatever the seed.
//! Small counts, when `count` picks cost less than the levels (`prefer_picks`), are picked one by
//! one instead:
//! at most `TRIALS` rejection trials on the board when the set is dense, a walk to a random rank
//! on small sets, and otherwise a select of the set bit of a random rank from byte counts.
//! Every loop has a fixed iteration bound, stated in the comments: the work is bounded.
//!
//! Every decision depends only on counts and on random bits, so the result is invariant under any
//! permutation of the walkable tiles: it is uniform among the subsets of `count` walkable tiles, up
//! to the imperfections of the random sources, bounded in the doc of `generate`. Boards of at most
//! 128 bits run on a single `u128` limb. See `GAS.md` (section L7) for the measured alternatives.

// Core imports

use core::poseidon::hades_permutation;
use core::traits::{BitAnd, BitOr};

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, POW128, TWO_POW_128};
use origami_hexmap::helpers::rng::{Rng, RngTrait};

// Constants

/// Measured costs (thousands of gas) choosing between picks and the radix select: one pick on a
/// set covering at least 2/3, at least 1/2, less than 1/2 of the board; one radix level on `u256`
/// and on `u128`; the subset table (see `GAS.md`, "Radix or picks").
const PICK_VERY_DENSE: u16 = 30;
const PICK_DENSE: u16 = 38;
const PICK_SPARSE: u16 = 42;
const LEVEL_WIDE: u16 = 25;
const LEVEL_SMALL: u16 = 16;
const TABLE: u16 = 30;
/// Largest count worth comparing: `6 * PICK_VERY_DENSE > 5 * LEVEL_WIDE + TABLE`.
const PICKS_MAX: u8 = 5;
/// Largest number of radix levels (random words).
const LEVELS: u8 = 12;
/// Largest class finished by the subset table.
const TABLE_MAX: u8 = 8;
/// Largest set picked by a walk to a random rank (before the byte counts exist).
const WALK_MAX: u8 = 8;
/// Largest number of rejection trials of a pick, before the select.
const TRIALS: u8 = 2;
/// Odd bits mask 0xAAAA... on 128 bits.
const MASK_ODD_BITS: u128 = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
/// Low pairs mask 0x3333... on 128 bits.
const MASK_PAIRS: u128 = 0x33333333333333333333333333333333;
/// Low nibbles mask 0x0F0F... on 128 bits.
const MASK_NIBBLES: u128 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
/// High bit of every byte, 0x8080... on 128 bits.
const MASK_BYTE_HIGH: u128 = 0x80808080808080808080808080808080;
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
/// 1/128 in the field.
const INV_128: felt252 = 0x7f0000000000010de0000000000000000000000000000000000000000000001;
/// 1/255 in the field.
const INV_255: felt252 = 0x18989898989898ccdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdce;
/// Number of set bits of a nibble.
const NIBBLE_COUNT: [u8; 16] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4];
/// Bit of rank `r` of nibble `v`, at `4 * v + r` (0 when the rank does not exist).
const NIBBLE_SELECT: [felt252; 64] = [
    0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 2, 0, 0, 4, 0, 0, 0, 1, 4, 0, 0, 2, 4, 0, 0, 1, 2, 4, 0,
    8, 0, 0, 0, 1, 8, 0, 0, 2, 8, 0, 0, 1, 2, 8, 0, 4, 8, 0, 0, 1, 4, 8, 0, 2, 4, 8, 0, 1, 2, 4, 8,
];
/// Start of the masks of `d` bits with `j` set bits in `SUBSETS`, at `10 * d + j`; the next
/// entry is their end, so `C(d, j)` is the difference.
const SUBSET_OFFSETS: [u16; 90] = [
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 6, 7, 7, 7, 7, 7, 7, 7, 7, 8,
    11, 14, 15, 15, 15, 15, 15, 15, 15, 16, 20, 26, 30, 31, 31, 31, 31, 31, 31, 32, 37, 47, 57, 62,
    63, 63, 63, 63, 63, 64, 70, 85, 105, 120, 126, 127, 127, 127, 127, 128, 135, 156, 191, 226, 247,
    254, 255, 255, 255, 256, 264, 292, 348, 418, 474, 502, 510, 511,
];
/// Every mask of `d <= 8` bits, grouped by `d`, then by number of set bits, increasing.
const SUBSETS: [u8; 511] = [
    0, 0, 1, 0, 1, 2, 3, 0, 1, 2, 4, 3, 5, 6, 7, 0, 1, 2, 4, 8, 3, 5, 6, 9, 10, 12, 7, 11, 13, 14,
    15, 0, 1, 2, 4, 8, 16, 3, 5, 6, 9, 10, 12, 17, 18, 20, 24, 7, 11, 13, 14, 19, 21, 22, 25, 26,
    28, 15, 23, 27, 29, 30, 31, 0, 1, 2, 4, 8, 16, 32, 3, 5, 6, 9, 10, 12, 17, 18, 20, 24, 33, 34,
    36, 40, 48, 7, 11, 13, 14, 19, 21, 22, 25, 26, 28, 35, 37, 38, 41, 42, 44, 49, 50, 52, 56, 15,
    23, 27, 29, 30, 39, 43, 45, 46, 51, 53, 54, 57, 58, 60, 31, 47, 55, 59, 61, 62, 63, 0, 1, 2, 4,
    8, 16, 32, 64, 3, 5, 6, 9, 10, 12, 17, 18, 20, 24, 33, 34, 36, 40, 48, 65, 66, 68, 72, 80, 96,
    7, 11, 13, 14, 19, 21, 22, 25, 26, 28, 35, 37, 38, 41, 42, 44, 49, 50, 52, 56, 67, 69, 70, 73,
    74, 76, 81, 82, 84, 88, 97, 98, 100, 104, 112, 15, 23, 27, 29, 30, 39, 43, 45, 46, 51, 53, 54,
    57, 58, 60, 71, 75, 77, 78, 83, 85, 86, 89, 90, 92, 99, 101, 102, 105, 106, 108, 113, 114, 116,
    120, 31, 47, 55, 59, 61, 62, 79, 87, 91, 93, 94, 103, 107, 109, 110, 115, 117, 118, 121, 122,
    124, 63, 95, 111, 119, 123, 125, 126, 127, 0, 1, 2, 4, 8, 16, 32, 64, 128, 3, 5, 6, 9, 10, 12,
    17, 18, 20, 24, 33, 34, 36, 40, 48, 65, 66, 68, 72, 80, 96, 129, 130, 132, 136, 144, 160, 192,
    7, 11, 13, 14, 19, 21, 22, 25, 26, 28, 35, 37, 38, 41, 42, 44, 49, 50, 52, 56, 67, 69, 70, 73,
    74, 76, 81, 82, 84, 88, 97, 98, 100, 104, 112, 131, 133, 134, 137, 138, 140, 145, 146, 148, 152,
    161, 162, 164, 168, 176, 193, 194, 196, 200, 208, 224, 15, 23, 27, 29, 30, 39, 43, 45, 46, 51,
    53, 54, 57, 58, 60, 71, 75, 77, 78, 83, 85, 86, 89, 90, 92, 99, 101, 102, 105, 106, 108, 113,
    114, 116, 120, 135, 139, 141, 142, 147, 149, 150, 153, 154, 156, 163, 165, 166, 169, 170, 172,
    177, 178, 180, 184, 195, 197, 198, 201, 202, 204, 209, 210, 212, 216, 225, 226, 228, 232, 240,
    31, 47, 55, 59, 61, 62, 79, 87, 91, 93, 94, 103, 107, 109, 110, 115, 117, 118, 121, 122, 124,
    143, 151, 155, 157, 158, 167, 171, 173, 174, 179, 181, 182, 185, 186, 188, 199, 203, 205, 206,
    211, 213, 214, 217, 218, 220, 227, 229, 230, 233, 234, 236, 241, 242, 244, 248, 63, 95, 111,
    119, 123, 125, 126, 159, 175, 183, 187, 189, 190, 207, 215, 219, 221, 222, 231, 235, 237, 238,
    243, 245, 246, 249, 250, 252, 127, 191, 223, 239, 247, 251, 253, 254, 255,
];
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

/// Byte counts of a set, per `u128` limb, kept up to date across removals.
#[derive(Copy, Drop)]
pub struct Counts {
    /// Byte `j` holds the number of set bits in bytes `0..=j` of the low limb.
    pub low_prefix: u128,
    /// Byte `j` holds the number of set bits of byte `j` of the low limb.
    pub low_bytes: u128,
    pub high_prefix: u128,
    pub high_bytes: u128,
    /// The number of set bits of the low limb.
    pub low_count: u8,
}

/// Set operations of the draw: `u256` on any board, `u128` on boards of at most 128 bits.
pub trait BitSetTrait<T> {
    /// The set as a felt bitmap.
    fn to_felt(self: T) -> felt252;
    /// A Poseidon output as a set of random bits.
    fn word(word: felt252) -> T;
    /// The number of set bits.
    fn popcount(self: T) -> u8;
    /// The bit at `index` (below the board size) if it is set, as a set.
    fn probe(self: T, index: u32) -> Option<T>;
    /// The set bit of rank `rank` (from the lowest), by a walk of `rank` steps.
    fn walk(self: T, rank: u8) -> T;
    /// The set bits whose rank (from the lowest) is set in `mask`, as a felt: at most 8 steps,
    /// the set has at most 8 bits.
    fn deposit(self: T, mask: u8) -> felt252;
    /// The byte counts of the set.
    fn counts(self: T) -> Counts;
    /// The set bit of rank `rank`, from the byte counts (no loop); the counts are updated for
    /// its removal.
    fn select(self: T, ref counts: Counts, rank: u8) -> T;
    /// Update the byte counts for the removal of the set bit at `index`.
    fn forget(ref counts: Counts, index: u32);
}

pub impl U256BitSet of BitSetTrait<u256> {
    #[inline]
    fn to_felt(self: u256) -> felt252 {
        Bits::to_felt(self)
    }

    #[inline]
    fn word(word: felt252) -> u256 {
        word.into()
    }

    /// Byte counts of both limbs summed, then one byte-sum (cheaper than `Bits::popcount`).
    fn popcount(self: u256) -> u8 {
        let bytes = byte_counts(self.low) + byte_counts(self.high);
        // [Compute] Every byte of the sum is at most 16, every prefix sum at most 251
        let total: u256 = (bytes * BYTES_ONE).into();
        let (count, _) = DivRem::div_rem(total.low, TWO_POW_120);
        count.try_into().unwrap()
    }

    #[inline]
    fn probe(self: u256, index: u32) -> Option<u256> {
        if index < 128 {
            let bit = *POW128.span().at(index);
            if self.low & bit != 0 {
                return Option::Some(u256 { low: bit, high: 0 });
            }
        } else {
            let bit = *POW128.span().at(index - 128);
            if self.high & bit != 0 {
                return Option::Some(u256 { low: 0, high: bit });
            }
        }
        Option::None
    }

    fn walk(self: u256, rank: u8) -> u256 {
        // [Compute] At most `rank` steps over both limbs
        let mut rank = rank;
        let mut x = self.low;
        while rank != 0 && x != 0 {
            x = x & (x - 1);
            rank -= 1;
        }
        if x != 0 {
            return u256 { low: x - (x & (x - 1)), high: 0 };
        }
        let mut y = self.high;
        while rank != 0 {
            y = y & (y - 1);
            rank -= 1;
        }
        u256 { low: 0, high: y - (y & (y - 1)) }
    }

    fn deposit(self: u256, mask: u8) -> felt252 {
        // [Compute] At most 8 steps over both limbs: one per set bit of the class
        let mut mask = mask;
        let mut chosen: felt252 = 0;
        let mut x = self.low;
        while mask != 0 && x != 0 {
            let rest = x & (x - 1);
            let (next, keep) = DivRem::div_rem(mask, 2);
            if keep != 0 {
                chosen += (x - rest).into();
            }
            mask = next;
            x = rest;
        }
        let mut y = self.high;
        while mask != 0 {
            let rest = y & (y - 1);
            let (next, keep) = DivRem::div_rem(mask, 2);
            if keep != 0 {
                chosen += (y - rest).into() * TWO_POW_128;
            }
            mask = next;
            y = rest;
        }
        chosen
    }

    fn counts(self: u256) -> Counts {
        let (low_prefix, low_bytes) = prefix_counts(self.low);
        let (high_prefix, high_bytes) = prefix_counts(self.high);
        let (low_count, _) = DivRem::div_rem(low_prefix, TWO_POW_120);
        Counts {
            low_prefix,
            low_bytes,
            high_prefix,
            high_bytes,
            low_count: low_count.try_into().unwrap(),
        }
    }

    fn select(self: u256, ref counts: Counts, rank: u8) -> u256 {
        if rank < counts.low_count {
            let (bit, base) = select_in(self.low, counts.low_prefix, counts.low_bytes, rank);
            drop_bit(ref counts.low_prefix, ref counts.low_bytes, base);
            counts.low_count -= 1;
            return u256 { low: bit, high: 0 };
        }
        let rank = rank - counts.low_count;
        let (bit, base) = select_in(self.high, counts.high_prefix, counts.high_bytes, rank);
        drop_bit(ref counts.high_prefix, ref counts.high_bytes, base);
        u256 { low: 0, high: bit }
    }

    fn forget(ref counts: Counts, index: u32) {
        if index < 128 {
            drop_bit(ref counts.low_prefix, ref counts.low_bytes, byte_base(index));
            counts.low_count -= 1;
        } else {
            drop_bit(ref counts.high_prefix, ref counts.high_bytes, byte_base(index - 128));
        }
    }
}

pub impl U128BitSet of BitSetTrait<u128> {
    #[inline]
    fn to_felt(self: u128) -> felt252 {
        self.into()
    }

    #[inline]
    fn word(word: felt252) -> u128 {
        let word: u256 = word.into();
        word.low
    }

    fn popcount(self: u128) -> u8 {
        let total: u256 = (byte_counts(self) * BYTES_ONE).into();
        let (count, _) = DivRem::div_rem(total.low, TWO_POW_120);
        count.try_into().unwrap()
    }

    #[inline]
    fn probe(self: u128, index: u32) -> Option<u128> {
        let bit = *POW128.span().at(index);
        if self & bit != 0 {
            Option::Some(bit)
        } else {
            Option::None
        }
    }

    fn walk(self: u128, rank: u8) -> u128 {
        // [Compute] At most `rank` steps
        let mut rank = rank;
        let mut x = self;
        while rank != 0 {
            x = x & (x - 1);
            rank -= 1;
        }
        x - (x & (x - 1))
    }

    fn deposit(self: u128, mask: u8) -> felt252 {
        // [Compute] At most 8 steps: one per set bit of the class
        let mut mask = mask;
        let mut chosen: felt252 = 0;
        let mut x = self;
        while mask != 0 {
            let rest = x & (x - 1);
            let (next, keep) = DivRem::div_rem(mask, 2);
            if keep != 0 {
                chosen += (x - rest).into();
            }
            mask = next;
            x = rest;
        }
        chosen
    }

    fn counts(self: u128) -> Counts {
        let (low_prefix, low_bytes) = prefix_counts(self);
        Counts { low_prefix, low_bytes, high_prefix: 0, high_bytes: 0, low_count: 0 }
    }

    #[inline]
    fn select(self: u128, ref counts: Counts, rank: u8) -> u128 {
        let (bit, base) = select_in(self, counts.low_prefix, counts.low_bytes, rank);
        drop_bit(ref counts.low_prefix, ref counts.low_bytes, base);
        bit
    }

    #[inline]
    fn forget(ref counts: Counts, index: u32) {
        drop_bit(ref counts.low_prefix, ref counts.low_bytes, byte_base(index));
    }
}

/// Byte counts of a limb (SWAR, shifts as exact field divisions).
/// # Arguments
/// * `value` - The limb
/// # Returns
/// * Byte `j` holds the number of set bits of byte `j` (at most 8), below 2^128
fn byte_counts(value: u128) -> felt252 {
    let felt: felt252 = value.into();
    let pairs = felt - (value & MASK_ODD_BITS).into() * INV_2;
    let low: felt252 = (pairs.try_into().unwrap() & MASK_PAIRS).into();
    let nibbles = low + (pairs - low) * INV_4;
    let low: felt252 = (nibbles.try_into().unwrap() & MASK_NIBBLES).into();
    low + (nibbles - low) * INV_16
}

/// Byte counts of a limb and their inclusive prefix sums.
/// # Arguments
/// * `value` - The limb
/// # Returns
/// * The prefix sums, byte `j` holds the number of set bits in bytes `0..=j` (at most 128)
/// * The byte counts, byte `j` holds the number of set bits of byte `j` (at most 8)
fn prefix_counts(value: u128) -> (u128, u128) {
    let bytes = byte_counts(value);
    // [Compute] No carry between bytes: every prefix sum is at most 128
    let prefix: u256 = (bytes * BYTES_ONE).into();
    (prefix.low, bytes.try_into().unwrap())
}

/// `2^(8j)`, `j` the byte of a bit index of a limb.
#[inline]
fn byte_base(index: u32) -> u128 {
    let (_, offset) = DivRem::div_rem(index, 8);
    *POW128.span().at(index - offset)
}

/// Update the byte counts of a limb for the removal of a set bit of the byte `2^(8j) = base`:
/// the count of byte `j` and the prefix sums of bytes `j..16` decrease by one.
#[inline]
fn drop_bit(ref prefix: u128, ref bytes: u128, base: u128) {
    // [Compute] sum(2^(8i), i = j..16) = (2^128 - 2^(8j)) / 255, exact in the field
    let ones: felt252 = (TWO_POW_128 - base.into()) * INV_255;
    prefix -= ones.try_into().unwrap();
    bytes -= base;
}

/// The set bit of rank `rank` of a limb, from its byte counts: no loop.
/// # Arguments
/// * `value` - The limb
/// * `prefix` - The inclusive prefix counts of its bytes (`prefix_counts`)
/// * `bytes` - The counts of its bytes
/// * `rank` - The rank, below the number of set bits
/// # Returns
/// * The bit `2^i`, and the base `2^(8j)` of its byte
fn select_in(value: u128, prefix: u128, bytes: u128, rank: u8) -> (u128, u128) {
    // [Compute] Byte j is flagged when prefix_j > rank, i.e. prefix_j + 127 - rank >= 128; the
    // prefix sums grow with j, so the lowest flagged byte holds the bit (field arithmetic: no
    // carry between bytes, every byte stays at most 255)
    let rank_felt: felt252 = rank.into();
    let shifted: felt252 = prefix.into() + (127 - rank_felt) * BYTES_ONE;
    let shifted: u128 = shifted.try_into().unwrap();
    let flags = shifted & MASK_BYTE_HIGH;
    let lowest = flags - (flags & (flags - 1));
    // [Compute] base = 2^(8j) = lowest / 128, exact
    let base: felt252 = lowest.into() * INV_128;
    let base: u128 = base.try_into().unwrap();
    let base_nz: NonZero<u128> = base.try_into().unwrap();
    // [Compute] The byte and the number of set bits below it
    let (above, _) = DivRem::div_rem(value, base_nz);
    let (_, byte) = DivRem::div_rem(above, 256);
    let (above, _) = DivRem::div_rem(prefix - bytes, base_nz);
    let (_, below) = DivRem::div_rem(above, 256);
    let byte: u8 = byte.try_into().unwrap();
    let rank: u8 = rank - below.try_into().unwrap();
    // [Compute] The nibble, then a table
    let (high, low) = DivRem::div_rem(byte, 16);
    let low_count = *NIBBLE_COUNT.span().at(low.into());
    let bit: felt252 = if rank < low_count {
        let index: u32 = (low * 4 + rank).into();
        *NIBBLE_SELECT.span().at(index)
    } else {
        let index: u32 = (high * 4 + rank - low_count).into();
        *NIBBLE_SELECT.span().at(index) * 16
    };
    ((base.into() * bit).try_into().unwrap(), base)
}

#[generate_trait]
pub impl Spreader of SpreaderTrait {
    /// Pick `count` walkable tiles uniformly.
    ///
    /// Uniform up to a total variation below `2^-15` in the worst case and `2^-23` in practice,
    /// from the two random sources (every other step is exact):
    /// * a key word is a Poseidon output, uniform below the prime `P = 2^251 + 17 * 2^192 + 1`;
    ///   its 251 low bits are within `(17 * 2^192 + 1) / P < 2^-54.9` of 251 fair coins
    ///   (`test_spreader_bias_field_bits`), and a call uses at most `LEVELS = 12` words:
    ///   `< 2^-51.3`;
    /// * `Rng` draws by mixed radix from 128-bit pools refilled below 2^32: a draw from a pool
    ///   holding at least 2^32 means the bounds already drawn from it multiply to less than 2^96,
    ///   so the bounds of all the draws of one pool multiply to less than `2^96 * 251 < 2^104`,
    ///   and these draws, digits of a uniform 128-bit integer, are within `2^104 / 2^128 = 2^-24`
    ///   of independent uniform draws (`test_spreader_bias_pool`). One pool serves the whole call
    ///   in practice (at most 3 draws per pick, 1 for the table); the worst case is one pool per
    ///   draw, at most `3 * 125 = 375` draws (see the loop bounds): `< 2^-15.4`.
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
        // [Return] The chosen tiles
        if size <= 128 {
            Self::choose(value.low, count, size, seed)
        } else {
            Self::choose(value, count, size, seed)
        }
    }

    /// Choose `count` tiles uniformly in a set.
    /// # Arguments
    /// * `set` - The set, below 2^251
    /// * `count` - The number of tiles to choose
    /// * `size` - The board size, every set bit is below it
    /// * `seed` - The seed
    /// # Returns
    /// * The chosen tiles
    /// # Panics
    /// * `Spreader: not enough place` if `count` exceeds the size of the set
    fn choose<T, +BitSetTrait<T>, +BitAnd<T>, +BitOr<T>, +Sub<T>, +Copy<T>, +Drop<T>>(
        set: T, count: u8, size: u8, seed: felt252,
    ) -> felt252 {
        // [Check] Enough tiles
        let total = set.popcount();
        assert(count <= total, errors::SPREADER_NOT_ENOUGH_PLACE);
        // [Compute] Choose the smaller of the chosen set and its complement
        let (k, negate) = if count > total - count {
            (total - count, true)
        } else {
            (count, false)
        };
        // [Compute] Radix select, unless k picks are cheaper (never above PICKS_MAX)
        let chosen = if k <= PICKS_MAX && Self::prefer_picks(total, k, size) {
            Self::picks(set, total, k, size, seed)
        } else {
            Self::radix(set, total, k, size, seed)
        };
        if negate {
            set.to_felt() - chosen
        } else {
            chosen
        }
    }

    /// Whether `k` picks cost less than the radix select on a set of `total` tiles, from the
    /// measured costs: `k * pick < levels * level + table`, `levels = ceil(log2(total / 8))`.
    /// # Arguments
    /// * `total` - The number of tiles of the set
    /// * `k` - The number of tiles to choose
    /// * `size` - The board size
    /// # Returns
    /// * `true` to pick
    #[inline]
    fn prefer_picks(total: u8, k: u8, size: u8) -> bool {
        // [Check] At most 8 tiles: the subset table finishes at once
        if total <= TABLE_MAX {
            return false;
        }
        let levels: u8 = if total <= 16 {
            1
        } else if total <= 32 {
            2
        } else if total <= 64 {
            3
        } else if total <= 128 {
            4
        } else {
            5
        };
        let levels: u16 = levels.into();
        let level = if size <= 128 {
            LEVEL_SMALL
        } else {
            LEVEL_WIDE
        };
        let total: u16 = total.into();
        let size: u16 = size.into();
        let pick = if 3 * total >= 2 * size {
            PICK_VERY_DENSE
        } else if 2 * total >= size {
            PICK_DENSE
        } else {
            PICK_SPARSE
        };
        let k: u16 = k.into();
        k * pick < levels * level + TABLE
    }

    /// Choose `k` tiles by radix select on random keys (see the module doc).
    /// # Arguments
    /// * `set` - The set
    /// * `total` - The number of set bits
    /// * `k` - The number of tiles to choose, at most `total`
    /// * `size` - The board size
    /// * `seed` - The seed
    /// # Returns
    /// * The chosen tiles
    fn radix<T, +BitSetTrait<T>, +BitAnd<T>, +BitOr<T>, +Sub<T>, +Copy<T>, +Drop<T>>(
        set: T, total: u8, k: u8, size: u8, seed: felt252,
    ) -> felt252 {
        // Invariant: result = base + X, X uniform among the k-subsets of set, base disjoint
        let mut base: felt252 = 0;
        let mut set = set;
        let mut n = total;
        let mut k = k;
        // [Compute] At most LEVELS iterations, one word each; a class halves in expectation, so
        // about log2(n / 8) levels (4 to 5 on 17x14)
        let mut level: u8 = 0;
        while n > TABLE_MAX && k != 0 && k != n && level != LEVELS {
            let (word, _, _) = hades_permutation(seed, level.into(), 2);
            let first = set & w(word);
            let z = first.popcount();
            if k <= z {
                set = first;
                n = z;
            } else {
                base += first.to_felt();
                set = set - first;
                n -= z;
                k -= z;
            }
            level += 1;
        }
        // [Return] Trivial classes
        if k == 0 {
            return base;
        }
        if k == n {
            return base + set.to_felt();
        }
        // [Compute] Class of at most 8 tiles: a uniform k-subset of the ranks from the table
        let (rng_seed, _, _) = hades_permutation(seed, LEVELS.into(), 2);
        if n <= TABLE_MAX {
            let mut rng = RngTrait::new(rng_seed);
            let row: u32 = (n * 10 + k).into();
            let start = *SUBSET_OFFSETS.span().at(row);
            let end = *SUBSET_OFFSETS.span().at(row + 1);
            let range: u128 = (end - start).into();
            let index: u32 = rng.draw(range.try_into().unwrap()).try_into().unwrap();
            let mask = *SUBSETS.span().at(start.into() + index);
            return base + set.deposit(mask);
        }
        // [Compute] Still more than 8 tiles after LEVELS words, probability below
        // `4096 * C(251, 9) * 2^-108 < 2^-42` on any board: picks, with the complement
        if k > n - k {
            base + set.to_felt() - Self::picks(set, n, n - k, size, rng_seed)
        } else {
            base + Self::picks(set, n, k, size, rng_seed)
        }
    }

    /// Choose `k` tiles by picking them one by one.
    /// # Arguments
    /// * `set` - The set
    /// * `total` - The number of set bits
    /// * `k` - The number of tiles to choose, at most `total`
    /// * `size` - The board size
    /// * `seed` - The seed
    /// # Returns
    /// * The chosen tiles
    fn picks<T, +BitSetTrait<T>, +Sub<T>, +Copy<T>, +Drop<T>>(
        set: T, total: u8, k: u8, size: u8, seed: felt252,
    ) -> felt252 {
        // [Compute] At most k <= 125 iterations, each bounded (see `pick`)
        let range: u128 = size.into();
        let range: NonZero<u128> = range.try_into().unwrap();
        let mut rng = RngTrait::new(seed);
        let mut counts: Option<Counts> = Option::None;
        let mut set = set;
        let mut n = total;
        let mut k = k;
        let mut picked: felt252 = 0;
        while k != 0 {
            let bit = Self::pick(set, n, size, range, ref counts, ref rng);
            set = set - bit;
            picked += bit.to_felt();
            n -= 1;
            k -= 1;
        }
        picked
    }

    /// Pick one tile uniformly in a set, in a bounded number of operations: at most 3 draws.
    /// # Arguments
    /// * `set` - The set
    /// * `total` - The number of set bits, not zero
    /// * `size` - The board size
    /// * `range` - The board size, as a divisor
    /// * `counts` - The byte counts of the set once built, kept up to date
    /// * `rng` - The generator
    /// # Returns
    /// * The picked tile, as a set
    #[inline]
    fn pick<T, +BitSetTrait<T>, +Copy<T>, +Drop<T>>(
        set: T, total: u8, size: u8, range: NonZero<u128>, ref counts: Option<Counts>, ref rng: Rng,
    ) -> T {
        // [Compute] Small set, byte counts not built: a walk of at most WALK_MAX - 1 steps
        if total <= WALK_MAX && counts.is_none() {
            return set.walk(rng.next_below(total));
        }
        // [Compute] Hit rate at least 30 %: at most TRIALS rejection trials
        let total_u16: u16 = total.into();
        let size_u16: u16 = size.into();
        if 10 * total_u16 >= 3 * size_u16 {
            let mut trials = TRIALS;
            while trials != 0 {
                let index: u32 = rng.draw(range).try_into().unwrap();
                if let Option::Some(bit) = set.probe(index) {
                    if let Option::Some(mut built) = counts {
                        BitSetTrait::<T>::forget(ref built, index);
                        counts = Option::Some(built);
                    }
                    return bit;
                }
                trials -= 1;
            }
        }
        // [Compute] Otherwise, or after TRIALS misses: select a random rank, no loop
        let mut built = match counts {
            Option::Some(built) => built,
            Option::None => set.counts(),
        };
        let bit = set.select(ref built, rng.next_below(total));
        counts = Option::Some(built);
        bit
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::dict::Felt252Dict;

    // Internal imports

    use origami_hexmap::helpers::bits::{Bits, TWO_POW_128, TWO_POW_32};
    use origami_hexmap::tests::fixtures::*;

    // Local imports

    use super::{BitSetTrait, Counts, SUBSETS, SUBSET_OFFSETS, Spreader};

    // Constants

    const SEED: felt252 = 'SEED';
    /// 10x25 board (250 bits), 2 walkable tiles in opposite corners (audit A2, finding 1).
    const SPARSE2_10X25: felt252 =
        0x200000000000000000000000000000000000000000000000000000000000001;
    /// 17x14 board, 5 walkable tiles (20, 77, 130, 185, 218) of 238.
    const SPARSE5_17X14: felt252 = 0x4000000020000000000000400000000000020000000000000100000;
    /// 17x14 board, 71 interior tiles drawn at random (30 % of the board, maze-like density).
    const D30_17X14: felt252 = 0xb10c5a483196889444060584021da123f42200343911d60c7180000;

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
    /// `(2 * walkable + 12) * V`, `V = E * (1 - count / walkable)` the variance of one tile: its
    /// expectation is about `walkable * V`, and the `+ 12` keeps sets of a few tiles (a
    /// chi-square with 1 or 2 degrees of freedom) from failing by chance.
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
        assert!(squares <= (2 * walkable + 12) * variance, "squares {} {}", squares, variance);
    }

    #[test]
    fn test_spreader_cave_7x7() {
        // u128, 5 of 23 tiles: radix select (2 levels), then the subset table
        //  0 0 0 0 0 0 0
        // 0 0 0 1 0 0 0
        //  0 0 0 0 0 0 0
        // 0 0 1 0 0 1 0
        //  0 0 0 1 0 0 0
        // 0 1 0 0 0 0 0
        //  0 0 0 0 0 0 0
        let objects = check(CAVE_7X7, 7, 7, 5, SEED);
        assert!(objects == 0x4002421000);
    }

    #[test]
    fn test_spreader_cave_17x14() {
        // u256, 20 of 131 tiles: radix select
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 1 0 0 0 1 0 0 1 0 1 0 0 0 0 0 0
        // 0 1 0 0 1 0 1 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0
        //  0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 1 0 1 0 0 0 0 0 0 1 0 0 0 0 0 0
        //  0 1 0 1 0 0 0 0 0 0 0 0 1 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let objects = check(CAVE_17X14, 17, 14, 20, SEED);
        assert!(objects == 0x200000022501280000080004040080004000050202804000400000);
    }

    #[test]
    fn test_spreader_maze_17x14_complement() {
        // 60 of 92 walkable tiles: the 32 tiles left free are chosen
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 1 0 0 1 0 1 0 0 1 1 0 0 0 0
        // 0 1 0 0 0 1 1 0 0 0 1 0 0 0 1 0 0
        //  0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 0 0
        // 0 0 1 0 0 0 0 0 0 0 0 1 1 0 1 0 0
        //  0 1 0 1 1 0 1 0 1 1 1 0 0 0 0 1 0
        // 0 0 1 0 0 1 0 1 1 0 0 1 0 0 0 1 0
        //  0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 0 0
        // 0 0 0 0 0 1 0 0 1 0 0 1 0 0 0 0 0
        //  0 0 0 1 0 1 1 0 0 1 1 0 0 0 1 0 0
        // 0 0 0 0 0 0 0 1 0 1 0 0 0 1 0 0 0
        //  0 0 0 0 1 0 0 0 0 1 0 1 0 1 0 0 0
        // 0 1 1 1 0 1 0 0 0 1 0 0 1 1 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let objects = check(MAZE_17X14, 17, 14, 60, SEED);
        assert!(objects == 0x253046220da408068b5c225911022012402cc40144042a1d1300000);
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
    fn test_spreader_uniform_small_radix() {
        // u128 radix, complement (12 > 23 - 12, 11 chosen); expected 120 per tile
        assert_uniform(CAVE_7X7, 7, 7, 12, 230, 40);
    }

    #[test]
    fn test_spreader_uniform_small_picks() {
        // u128 picks on a set of 47 % of the board (2 trials, then select); expected 20 per tile
        assert_uniform(CAVE_7X7, 7, 7, 1, 460, 20);
    }

    #[test]
    fn test_spreader_uniform_large_radix() {
        // u256 radix, 45 tiles; expected 45 per tile
        assert_uniform(EMPTY_17X14, 17, 14, 45, 180, 30);
    }

    #[test]
    fn test_spreader_uniform_large_complement() {
        // u256 radix, complement (75 > 92 - 75, 17 left out); expected 163 per tile
        assert_uniform(MAZE_17X14, 17, 14, 75, 200, 30);
    }

    #[test]
    fn test_spreader_uniform_large_picks() {
        // u256 picks on a dense set (rejection trials, then select); expected 10 per tile
        assert_uniform(EMPTY_17X14, 17, 14, 4, 450, 15);
    }

    #[test]
    fn test_spreader_uniform_sparse_two() {
        // 2 walkable tiles on 250 bits (audit A2): subset table; expected 500 per tile
        assert_uniform(SPARSE2_10X25, 10, 25, 1, 1000, 80);
    }

    #[test]
    fn test_spreader_uniform_sparse_five() {
        // 5 walkable tiles of 238: subset table; expected 100 per tile
        assert_uniform(SPARSE5_17X14, 17, 14, 2, 250, 40);
    }

    #[test]
    fn test_spreader_uniform_density_30_radix() {
        // 71 walkable tiles of 238 (30 %), u256 radix on a sparse set; expected 50 per tile
        assert_uniform(D30_17X14, 17, 14, 20, 180, 30);
    }

    #[test]
    fn test_spreader_uniform_density_30_picks() {
        // 71 walkable tiles of 238, 2 picks by select; expected 10 per tile
        assert_uniform(D30_17X14, 17, 14, 2, 355, 15);
    }

    /// Compare the byte counts of a set with the ones built from scratch.
    fn assert_counts<T, +BitSetTrait<T>, +Copy<T>, +Drop<T>>(set: T, counts: Counts) {
        let fresh = set.counts();
        assert!(counts.low_prefix == fresh.low_prefix);
        assert!(counts.low_bytes == fresh.low_bytes);
        assert!(counts.high_prefix == fresh.high_prefix);
        assert!(counts.high_bytes == fresh.high_bytes);
        assert!(counts.low_count == fresh.low_count);
    }

    #[test]
    fn test_spreader_select_wide() {
        // select(rank) == walk(rank) for every rank, and the counts follow every removal
        let grids = array![CAVE_17X14, EMPTY_17X14, MAZE_17X14, D30_17X14, SPARSE2_10X25].span();
        for grid in grids {
            let set: u256 = (*grid).into();
            let total = set.popcount();
            let mut rank: u8 = 0;
            while rank != total {
                let mut counts = set.counts();
                let bit = set.select(ref counts, rank);
                assert!(bit == set.walk(rank));
                assert_counts(set - bit, counts);
                rank += 1;
            }
            // Removals in sequence, alternating select and forget (after a probe)
            let mut rest = set;
            let mut counts = rest.counts();
            let mut left = total;
            while left > 1 {
                let bit = rest.select(ref counts, left / 2);
                rest = rest - bit;
                left -= 1;
                let lowest = rest.walk(0);
                let index: u32 = if lowest.low != 0 {
                    Bits::popcount((lowest.low - 1).into()).into()
                } else {
                    128 + Bits::popcount((lowest.high - 1).into()).into()
                };
                assert!(rest.probe(index) == Option::Some(lowest));
                BitSetTrait::<u256>::forget(ref counts, index);
                rest = rest - lowest;
                left -= 1;
                assert_counts(rest, counts);
            }
        }
    }

    #[test]
    fn test_spreader_select_small() {
        let grids = array![CAVE_7X7, EMPTY_7X7, MAZE_7X7, 0xffffffffffffffffffffffffffffffff]
            .span();
        for grid in grids {
            let set: u256 = (*grid).into();
            let set = set.low;
            let total = set.popcount();
            let mut rank: u8 = 0;
            while rank != total {
                let mut counts = set.counts();
                let bit = set.select(ref counts, rank);
                assert!(bit == set.walk(rank));
                assert_counts(set - bit, counts);
                rank += 1;
            }
        }
    }

    #[test]
    fn test_spreader_deposit() {
        // The table masks land on the right tiles, in increasing order of the tiles
        let set: u256 = SPARSE5_17X14.into();
        assert!(set.deposit(0b00001) == Bits::pow(20));
        assert!(set.deposit(0b10100) == Bits::pow(218) + Bits::pow(130));
        assert!(set.deposit(0b11111) == SPARSE5_17X14);
        let small: u128 = 0b101101;
        assert!(small.deposit(0b0110) == 0b001100);
    }

    #[test]
    fn test_spreader_subset_table() {
        // Group (d, j) holds the C(d, j) masks of d bits with j set bits, increasing
        let mut d: u32 = 0;
        while d != 9 {
            let mut j: u32 = 0;
            let mut binomial: u16 = 1;
            while j <= d {
                let start = *SUBSET_OFFSETS.span().at(10 * d + j);
                let end = *SUBSET_OFFSETS.span().at(10 * d + j + 1);
                assert!(end - start == binomial);
                let mut index = start;
                let mut previous: u16 = 0;
                while index != end {
                    let mask = *SUBSETS.span().at(index.into());
                    let mask_u128: u128 = mask.into();
                    assert!(mask_u128.popcount().into() == j);
                    let limit: u16 = Bits::pow(d.try_into().unwrap()).try_into().unwrap();
                    let mask_u16: u16 = mask.into();
                    assert!(mask_u16 < limit);
                    assert!(index == start || mask_u16 > previous);
                    previous = mask_u16;
                    index += 1;
                }
                // C(d, j + 1) = C(d, j) * (d - j) / (j + 1)
                let d_u16: u16 = d.try_into().unwrap();
                let j_u16: u16 = j.try_into().unwrap();
                binomial = binomial * (d_u16 - j_u16) / (j_u16 + 1);
                j += 1;
            }
            d += 1;
        }
    }

    #[test]
    fn test_spreader_bias_field_bits() {
        // P - 1 = 2^251 + 17 * 2^192: the values of [2^251, P) put a double weight on the 251 low
        // bits of 17 * 2^192 + 1 values out of P, a total variation (17 * 2^192 + 1) / P
        let p_minus_one: u256 = (0 - 1).into();
        let two_192: u256 = Bits::pow(192).into();
        assert!(p_minus_one == Bits::pow(251).into() + 17 * two_192);
        // (17 * 2^192 + 1) / P < 2^-54 (precisely 2^-54.9: log2(17) - 59)
        let excess = 17 * two_192 + 1;
        assert!(excess * Bits::pow(54).into() < p_minus_one + 1);
        assert!(excess * Bits::pow(55).into() > p_minus_one + 1);
    }

    #[test]
    fn test_spreader_bias_pool() {
        // `Rng` refills below 2^32: a pool holding at least 2^32 has served bounds multiplying
        // to at most 2^128 / 2^32 = 2^96
        assert!(TWO_POW_32 == 0x100000000);
        // Every bound drawn here is at most 251: the board size, a set size, or C(d, j) <= 70
        let mut row: u32 = 0;
        while row != 89 {
            let start = *SUBSET_OFFSETS.span().at(row);
            let end = *SUBSET_OFFSETS.span().at(row + 1);
            assert!(end - start <= 70);
            row += 1;
        }
        // So the bounds of one pool multiply to less than 2^96 * 251 < 2^104, and its draws are
        // within 2^104 / 2^128 = 2^-24 of independent uniform draws
        let two_96: u256 = Bits::pow(96).into();
        assert!(two_96 * 251 < Bits::pow(104).into());
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
