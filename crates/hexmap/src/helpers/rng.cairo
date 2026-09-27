//! Pooled random number generator.
//!
//! One Poseidon permutation yields a 128-bit pool (the low limb of its second output; the first
//! output is the next seed). Bounded integers are drawn from it by mixed radix
//! (`(pool, r) = DivRem(pool, n)`), and the pool is refilled when it drops below 2^64. The
//! divisions by the constant bounds 6, 216 and 720 use `bounded_int::div_rem` (see `GAS.md`).
//!
//! Bias: while the pool holds at least 2^64, the bounds already drawn from it multiply to less
//! than `2^128 / 2^64`, so the bounds of all the draws of one pool multiply to less than
//! `2^64 * B` (`B` the largest bound): these draws, digits of one uniform 128-bit integer, are
//! within `2^64 * B / 2^128` of independent uniform draws: `2^-56` per pool for `B <= 251` (every
//! bound of the generators), `2^-54.5` for `shuffle6` (`B = 720`). The low limb of a Poseidon
//! output is within `2^-123` of uniform.
//!
//! The other outputs of the permutation are not kept: a spare pool in the generator (one more
//! field carried through the recursions of `Mazer` and `Digger`) costs 2 % per carved tile, more
//! than the permutations it saves (see `GAS.md`, P1). `Walker`, which keeps its pool in locals,
//! uses both limbs.

// Core imports

#[feature("bounded-int-utils")]
use core::internal::bounded_int::{BoundedInt, DivRemHelper, UnitInt, div_rem, upcast};
use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::helpers::bits::TWO_POW_64;

// Constants

/// Number of permutations of the 6 directions.
const PERMUTATION_COUNT: NonZero<u128> = 720;

/// `DivRem` of a pool by 6, with the ranges of the quotient and the remainder.
impl DivRem6 of DivRemHelper<u128, UnitInt<6>> {
    type DivT = BoundedInt<0, 0x2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>;
    type RemT = BoundedInt<0, 5>;
}

/// `DivRem` of a pool by 216.
impl DivRem216 of DivRemHelper<u128, UnitInt<216>> {
    type DivT = BoundedInt<0, 0x12f684bda12f684bda12f684bda12f6>;
    type RemT = BoundedInt<0, 215>;
}

/// `DivRem` of a pool by 720.
impl DivRem720 of DivRemHelper<u128, UnitInt<720>> {
    type DivT = BoundedInt<0, 0x5b05b05b05b05b05b05b05b05b05b0>;
    type RemT = BoundedInt<0, 719>;
}

/// Types.
#[derive(Copy, Drop)]
pub struct Rng {
    pub seed: felt252,
    pub pool: u128,
}

#[generate_trait]
pub impl RngImpl of RngTrait {
    /// Create a generator, the pool is filled on the first draw.
    /// # Arguments
    /// * `seed` - The seed
    /// # Returns
    /// * The generator
    #[inline]
    fn new(seed: felt252) -> Rng {
        Rng { seed, pool: 0 }
    }

    /// Starknet Poseidon hash of two values, a single permutation.
    /// # Arguments
    /// * `lhs` - The left value
    /// * `rhs` - The right value
    /// # Returns
    /// * The hash
    #[inline]
    fn mix(lhs: felt252, rhs: felt252) -> felt252 {
        let (hash, _, _) = hades_permutation(lhs, rhs, 2);
        hash
    }

    /// Draw an integer in `[0, bound)`.
    /// # Arguments
    /// * `self` - The generator
    /// * `bound` - The exclusive upper bound
    /// # Returns
    /// * The drawn integer
    /// # Effects
    /// * The pool is consumed, and refilled when it runs low
    #[inline]
    fn draw(ref self: Rng, bound: NonZero<u128>) -> u128 {
        if self.pool < TWO_POW_64 {
            self.refill();
        }
        let (pool, value) = DivRem::div_rem(self.pool, bound);
        self.pool = pool;
        value
    }

    /// Draw an integer in `[0, 6)`: a division by a constant (`bounded_int`, see `GAS.md`).
    /// # Arguments
    /// * `self` - The generator
    /// # Returns
    /// * The drawn integer
    #[feature("bounded-int-utils")]
    #[inline]
    fn draw6(ref self: Rng) -> u128 {
        if self.pool < TWO_POW_64 {
            self.refill();
        }
        let (pool, value) = div_rem::<_, _, DivRem6>(self.pool, 6);
        self.pool = upcast(pool);
        upcast(value)
    }

    /// Draw an integer in `[0, bound)`.
    /// # Arguments
    /// * `self` - The generator
    /// * `bound` - The exclusive upper bound, not zero
    /// # Returns
    /// * The drawn integer
    #[inline]
    fn next_below(ref self: Rng, bound: u8) -> u8 {
        let bound: u128 = bound.into();
        let value = self.draw(bound.try_into().unwrap());
        // [Return] value < bound <= 255
        value.try_into().unwrap()
    }

    /// Draw a uniform permutation of the 6 directions, packed 4 bits per direction (first in the
    /// lowest nibble, see `DirectionTrait::pop_front`). One draw and one table lookup.
    /// # Arguments
    /// * `self` - The generator
    /// # Returns
    /// * The packed permutation
    #[feature("bounded-int-utils")]
    #[inline]
    fn shuffle6(ref self: Rng) -> u32 {
        if self.pool < TWO_POW_64 {
            self.refill();
        }
        let (pool, index) = div_rem::<_, _, DivRem720>(self.pool, 720);
        self.pool = upcast(pool);
        let index: felt252 = upcast(index);
        *PERMUTATIONS.span().at(index.try_into().unwrap())
    }

    /// Divide a pool by 216: three base-6 digits (`Walker`).
    /// # Arguments
    /// * `pool` - The pool
    /// # Returns
    /// * The quotient and the remainder
    #[feature("bounded-int-utils")]
    #[inline(always)]
    fn split216(pool: u128) -> (u128, u128) {
        let (quotient, remainder) = div_rem::<_, _, DivRem216>(pool, 216);
        (upcast(quotient), upcast(remainder))
    }

    /// Refill the pool from the next seed.
    /// # Arguments
    /// * `self` - The generator
    /// # Effects
    /// * The seed and the pool are replaced
    #[inline]
    fn refill(ref self: Rng) {
        let (seed, word, _) = hades_permutation(self.seed, 0, 2);
        let word: u256 = word.into();
        self.seed = seed;
        self.pool = word.low;
    }
}

// Table of the 720 permutations of `0..6`, lexicographic order, generated offline.

pub const PERMUTATIONS: [u32; 720] = [
    0x543210, 0x453210, 0x534210, 0x354210, 0x435210, 0x345210, 0x542310, 0x452310, 0x524310,
    0x254310, 0x425310, 0x245310, 0x532410, 0x352410, 0x523410, 0x253410, 0x325410, 0x235410,
    0x432510, 0x342510, 0x423510, 0x243510, 0x324510, 0x234510, 0x543120, 0x453120, 0x534120,
    0x354120, 0x435120, 0x345120, 0x541320, 0x451320, 0x514320, 0x154320, 0x415320, 0x145320,
    0x531420, 0x351420, 0x513420, 0x153420, 0x315420, 0x135420, 0x431520, 0x341520, 0x413520,
    0x143520, 0x314520, 0x134520, 0x542130, 0x452130, 0x524130, 0x254130, 0x425130, 0x245130,
    0x541230, 0x451230, 0x514230, 0x154230, 0x415230, 0x145230, 0x521430, 0x251430, 0x512430,
    0x152430, 0x215430, 0x125430, 0x421530, 0x241530, 0x412530, 0x142530, 0x214530, 0x124530,
    0x532140, 0x352140, 0x523140, 0x253140, 0x325140, 0x235140, 0x531240, 0x351240, 0x513240,
    0x153240, 0x315240, 0x135240, 0x521340, 0x251340, 0x512340, 0x152340, 0x215340, 0x125340,
    0x321540, 0x231540, 0x312540, 0x132540, 0x213540, 0x123540, 0x432150, 0x342150, 0x423150,
    0x243150, 0x324150, 0x234150, 0x431250, 0x341250, 0x413250, 0x143250, 0x314250, 0x134250,
    0x421350, 0x241350, 0x412350, 0x142350, 0x214350, 0x124350, 0x321450, 0x231450, 0x312450,
    0x132450, 0x213450, 0x123450, 0x543201, 0x453201, 0x534201, 0x354201, 0x435201, 0x345201,
    0x542301, 0x452301, 0x524301, 0x254301, 0x425301, 0x245301, 0x532401, 0x352401, 0x523401,
    0x253401, 0x325401, 0x235401, 0x432501, 0x342501, 0x423501, 0x243501, 0x324501, 0x234501,
    0x543021, 0x453021, 0x534021, 0x354021, 0x435021, 0x345021, 0x540321, 0x450321, 0x504321,
    0x54321, 0x405321, 0x45321, 0x530421, 0x350421, 0x503421, 0x53421, 0x305421, 0x35421, 0x430521,
    0x340521, 0x403521, 0x43521, 0x304521, 0x34521, 0x542031, 0x452031, 0x524031, 0x254031,
    0x425031, 0x245031, 0x540231, 0x450231, 0x504231, 0x54231, 0x405231, 0x45231, 0x520431,
    0x250431, 0x502431, 0x52431, 0x205431, 0x25431, 0x420531, 0x240531, 0x402531, 0x42531, 0x204531,
    0x24531, 0x532041, 0x352041, 0x523041, 0x253041, 0x325041, 0x235041, 0x530241, 0x350241,
    0x503241, 0x53241, 0x305241, 0x35241, 0x520341, 0x250341, 0x502341, 0x52341, 0x205341, 0x25341,
    0x320541, 0x230541, 0x302541, 0x32541, 0x203541, 0x23541, 0x432051, 0x342051, 0x423051,
    0x243051, 0x324051, 0x234051, 0x430251, 0x340251, 0x403251, 0x43251, 0x304251, 0x34251,
    0x420351, 0x240351, 0x402351, 0x42351, 0x204351, 0x24351, 0x320451, 0x230451, 0x302451, 0x32451,
    0x203451, 0x23451, 0x543102, 0x453102, 0x534102, 0x354102, 0x435102, 0x345102, 0x541302,
    0x451302, 0x514302, 0x154302, 0x415302, 0x145302, 0x531402, 0x351402, 0x513402, 0x153402,
    0x315402, 0x135402, 0x431502, 0x341502, 0x413502, 0x143502, 0x314502, 0x134502, 0x543012,
    0x453012, 0x534012, 0x354012, 0x435012, 0x345012, 0x540312, 0x450312, 0x504312, 0x54312,
    0x405312, 0x45312, 0x530412, 0x350412, 0x503412, 0x53412, 0x305412, 0x35412, 0x430512, 0x340512,
    0x403512, 0x43512, 0x304512, 0x34512, 0x541032, 0x451032, 0x514032, 0x154032, 0x415032,
    0x145032, 0x540132, 0x450132, 0x504132, 0x54132, 0x405132, 0x45132, 0x510432, 0x150432,
    0x501432, 0x51432, 0x105432, 0x15432, 0x410532, 0x140532, 0x401532, 0x41532, 0x104532, 0x14532,
    0x531042, 0x351042, 0x513042, 0x153042, 0x315042, 0x135042, 0x530142, 0x350142, 0x503142,
    0x53142, 0x305142, 0x35142, 0x510342, 0x150342, 0x501342, 0x51342, 0x105342, 0x15342, 0x310542,
    0x130542, 0x301542, 0x31542, 0x103542, 0x13542, 0x431052, 0x341052, 0x413052, 0x143052,
    0x314052, 0x134052, 0x430152, 0x340152, 0x403152, 0x43152, 0x304152, 0x34152, 0x410352,
    0x140352, 0x401352, 0x41352, 0x104352, 0x14352, 0x310452, 0x130452, 0x301452, 0x31452, 0x103452,
    0x13452, 0x542103, 0x452103, 0x524103, 0x254103, 0x425103, 0x245103, 0x541203, 0x451203,
    0x514203, 0x154203, 0x415203, 0x145203, 0x521403, 0x251403, 0x512403, 0x152403, 0x215403,
    0x125403, 0x421503, 0x241503, 0x412503, 0x142503, 0x214503, 0x124503, 0x542013, 0x452013,
    0x524013, 0x254013, 0x425013, 0x245013, 0x540213, 0x450213, 0x504213, 0x54213, 0x405213,
    0x45213, 0x520413, 0x250413, 0x502413, 0x52413, 0x205413, 0x25413, 0x420513, 0x240513, 0x402513,
    0x42513, 0x204513, 0x24513, 0x541023, 0x451023, 0x514023, 0x154023, 0x415023, 0x145023,
    0x540123, 0x450123, 0x504123, 0x54123, 0x405123, 0x45123, 0x510423, 0x150423, 0x501423, 0x51423,
    0x105423, 0x15423, 0x410523, 0x140523, 0x401523, 0x41523, 0x104523, 0x14523, 0x521043, 0x251043,
    0x512043, 0x152043, 0x215043, 0x125043, 0x520143, 0x250143, 0x502143, 0x52143, 0x205143,
    0x25143, 0x510243, 0x150243, 0x501243, 0x51243, 0x105243, 0x15243, 0x210543, 0x120543, 0x201543,
    0x21543, 0x102543, 0x12543, 0x421053, 0x241053, 0x412053, 0x142053, 0x214053, 0x124053,
    0x420153, 0x240153, 0x402153, 0x42153, 0x204153, 0x24153, 0x410253, 0x140253, 0x401253, 0x41253,
    0x104253, 0x14253, 0x210453, 0x120453, 0x201453, 0x21453, 0x102453, 0x12453, 0x532104, 0x352104,
    0x523104, 0x253104, 0x325104, 0x235104, 0x531204, 0x351204, 0x513204, 0x153204, 0x315204,
    0x135204, 0x521304, 0x251304, 0x512304, 0x152304, 0x215304, 0x125304, 0x321504, 0x231504,
    0x312504, 0x132504, 0x213504, 0x123504, 0x532014, 0x352014, 0x523014, 0x253014, 0x325014,
    0x235014, 0x530214, 0x350214, 0x503214, 0x53214, 0x305214, 0x35214, 0x520314, 0x250314,
    0x502314, 0x52314, 0x205314, 0x25314, 0x320514, 0x230514, 0x302514, 0x32514, 0x203514, 0x23514,
    0x531024, 0x351024, 0x513024, 0x153024, 0x315024, 0x135024, 0x530124, 0x350124, 0x503124,
    0x53124, 0x305124, 0x35124, 0x510324, 0x150324, 0x501324, 0x51324, 0x105324, 0x15324, 0x310524,
    0x130524, 0x301524, 0x31524, 0x103524, 0x13524, 0x521034, 0x251034, 0x512034, 0x152034,
    0x215034, 0x125034, 0x520134, 0x250134, 0x502134, 0x52134, 0x205134, 0x25134, 0x510234,
    0x150234, 0x501234, 0x51234, 0x105234, 0x15234, 0x210534, 0x120534, 0x201534, 0x21534, 0x102534,
    0x12534, 0x321054, 0x231054, 0x312054, 0x132054, 0x213054, 0x123054, 0x320154, 0x230154,
    0x302154, 0x32154, 0x203154, 0x23154, 0x310254, 0x130254, 0x301254, 0x31254, 0x103254, 0x13254,
    0x210354, 0x120354, 0x201354, 0x21354, 0x102354, 0x12354, 0x432105, 0x342105, 0x423105,
    0x243105, 0x324105, 0x234105, 0x431205, 0x341205, 0x413205, 0x143205, 0x314205, 0x134205,
    0x421305, 0x241305, 0x412305, 0x142305, 0x214305, 0x124305, 0x321405, 0x231405, 0x312405,
    0x132405, 0x213405, 0x123405, 0x432015, 0x342015, 0x423015, 0x243015, 0x324015, 0x234015,
    0x430215, 0x340215, 0x403215, 0x43215, 0x304215, 0x34215, 0x420315, 0x240315, 0x402315, 0x42315,
    0x204315, 0x24315, 0x320415, 0x230415, 0x302415, 0x32415, 0x203415, 0x23415, 0x431025, 0x341025,
    0x413025, 0x143025, 0x314025, 0x134025, 0x430125, 0x340125, 0x403125, 0x43125, 0x304125,
    0x34125, 0x410325, 0x140325, 0x401325, 0x41325, 0x104325, 0x14325, 0x310425, 0x130425, 0x301425,
    0x31425, 0x103425, 0x13425, 0x421035, 0x241035, 0x412035, 0x142035, 0x214035, 0x124035,
    0x420135, 0x240135, 0x402135, 0x42135, 0x204135, 0x24135, 0x410235, 0x140235, 0x401235, 0x41235,
    0x104235, 0x14235, 0x210435, 0x120435, 0x201435, 0x21435, 0x102435, 0x12435, 0x321045, 0x231045,
    0x312045, 0x132045, 0x213045, 0x123045, 0x320145, 0x230145, 0x302145, 0x32145, 0x203145,
    0x23145, 0x310245, 0x130245, 0x301245, 0x31245, 0x103245, 0x13245, 0x210345, 0x120345, 0x201345,
    0x21345, 0x102345, 0x12345,
];

#[cfg(test)]
mod tests {
    // Local imports

    use super::{PERMUTATIONS, Rng, RngTrait};

    #[test]
    fn test_rng_next_below_range() {
        let mut rng = RngTrait::new('seed');
        let mut hits: (u32, u32, u32, u32, u32, u32) = (0, 0, 0, 0, 0, 0);
        let mut index: u32 = 0;
        while index != 600 {
            let value = rng.next_below(6);
            assert!(value < 6);
            let (a, b, c, d, e, f) = hits;
            hits = match value {
                0 => (a + 1, b, c, d, e, f),
                1 => (a, b + 1, c, d, e, f),
                2 => (a, b, c + 1, d, e, f),
                3 => (a, b, c, d + 1, e, f),
                4 => (a, b, c, d, e + 1, f),
                _ => (a, b, c, d, e, f + 1),
            };
            index += 1;
        }
        // Loose uniformity check: every face shows up between 60 and 140 times out of 600
        let (a, b, c, d, e, f) = hits;
        let mut all = array![a, b, c, d, e, f].span();
        while let Option::Some(count) = all.pop_front() {
            assert!(*count > 60 && *count < 140);
        }
    }

    #[test]
    fn test_rng_deterministic() {
        let mut lhs: Rng = RngTrait::new('seed');
        let mut rhs: Rng = RngTrait::new('seed');
        let mut index: u32 = 0;
        while index != 100 {
            assert!(lhs.next_below(255) == rhs.next_below(255));
            index += 1;
        }
    }

    #[test]
    fn test_rng_mix() {
        assert!(RngTrait::mix(1, 2) == RngTrait::mix(1, 2));
        assert!(RngTrait::mix(1, 2) != RngTrait::mix(2, 1));
        assert!(RngTrait::mix(1, 2) != 0);
    }

    #[test]
    fn test_rng_permutations_table() {
        // Every entry is a permutation of 0..6, checked through a presence mask
        let mut table = PERMUTATIONS.span();
        assert!(table.len() == 720);
        while let Option::Some(entry) = table.pop_front() {
            let mut value = *entry;
            let mut seen: u32 = 0;
            let mut index: u8 = 0;
            while index != 6 {
                let (rest, nibble) = DivRem::div_rem(value, 16);
                assert!(nibble < 6);
                let bit: u32 = match nibble {
                    0 => 1,
                    1 => 2,
                    2 => 4,
                    3 => 8,
                    4 => 16,
                    _ => 32,
                };
                assert!(seen & bit == 0);
                seen += bit;
                value = rest;
                index += 1;
            }
            assert!(value == 0);
        }
    }

    #[test]
    fn test_rng_shuffle6() {
        let mut rng = RngTrait::new('seed');
        let first = rng.shuffle6();
        let mut distinct = false;
        let mut index: u32 = 0;
        while index != 10 {
            if rng.shuffle6() != first {
                distinct = true;
            }
            index += 1;
        }
        assert!(distinct);
    }
}
