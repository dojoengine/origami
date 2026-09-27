//! Gas benchmarks of lot L6, random walk generator: one `#[test]` per fixture and algorithm, each
//! with an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! The library walker (`Walker::generate`) is benchmarked on 17x14 for 50, 200 and 500 steps, and
//! on 7x7 and 19x13. The variants below are the losers of the lot, kept test-only: each one
//! changes a single axis of the winner (random source, move, grid accumulation, loop shape) and
//! runs 504 steps on 17x14 (a multiple of every block size, no tail). Variants that consume the
//! same draws as the winner assert the same grid.

// Core imports

use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::generators::walker::Walker;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::types::direction::{Direction, DirectionTrait};

// Constants

const SEED: felt252 = 'SEED';
/// Steps of the variant benchmarks: a multiple of 36.
const STEPS: u16 = 504;
/// Grid of the library walker on 17x14, 504 steps, `SEED` (see `bench_walker_17x14_504`).
const EXPECTED: felt252 = 0xfc007e003f111ffccfbfe7fff1fff83ffc0ffe077f038f0080c0000;
/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
const TRIPLE_COUNT: NonZero<u128> = 216;
const PAIR_COUNT: NonZero<u128> = 36;
const OCTAL: NonZero<u128> = 8;
const TWO_POW_32: u128 = 0x100000000;

// Movers: one walker state per move formulation, behind a trait so that the drivers below are
// shared (monomorphised, no runtime cost).

trait Mover<T> {
    /// Make one move if the target is interior, return whether the walker moved.
    fn step(ref self: T, direction: u8) -> bool;
    /// One-hot position of the walker.
    fn position(self: @T) -> felt252;
}

/// Winner: doubled column, row, one-hot position, swapped diagonal factors.
#[derive(Copy, Drop)]
struct Doubled {
    column: felt252,
    row: felt252,
    position: felt252,
    factor: felt252,
    other: felt252,
    right: felt252,
    top: felt252,
    down: felt252,
}

impl DoubledMover of Mover<Doubled> {
    #[inline]
    fn step(ref self: Doubled, direction: u8) -> bool {
        match direction {
            0 => {
                if (self.column - 2) * (self.column - 3) == 0 {
                    return false;
                }
                self.column -= 2;
                self.position *= INV_2;
            },
            1 => {
                if self.row == self.top || self.column == 2 {
                    return false;
                }
                self.column -= 1;
                self.row += 1;
                self.position *= self.factor;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            2 => {
                if self.row == self.top || self.column == self.right {
                    return false;
                }
                self.column += 1;
                self.row += 1;
                self.position *= self.factor + self.factor;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            3 => {
                if (self.column - self.right) * (self.column + 1 - self.right) == 0 {
                    return false;
                }
                self.column += 2;
                self.position += self.position;
            },
            4 => {
                if self.row == 1 || self.column == self.right {
                    return false;
                }
                self.column += 1;
                self.row -= 1;
                self.position *= (self.factor + self.factor) * self.down;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            _ => {
                if self.row == 1 || self.column == 2 {
                    return false;
                }
                self.column -= 1;
                self.row -= 1;
                self.position *= self.factor * self.down;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
        }
        true
    }

    #[inline]
    fn position(self: @Doubled) -> felt252 {
        *self.position
    }
}

/// Variant (x, y) tracked incrementally, parity as a bool, per-parity deltas.
#[derive(Copy, Drop)]
struct Coords {
    x: felt252,
    y: felt252,
    odd: bool,
    position: felt252,
    up: felt252,
    down: felt252,
    right: felt252,
    top: felt252,
}

impl CoordsMover of Mover<Coords> {
    #[inline]
    fn step(ref self: Coords, direction: u8) -> bool {
        match direction {
            0 => {
                if self.x == 1 {
                    return false;
                }
                self.x -= 1;
                self.position *= INV_2;
            },
            1 => {
                if self.y == self.top {
                    return false;
                }
                if self.odd {
                    self.position *= self.up;
                } else {
                    if self.x == 1 {
                        return false;
                    }
                    self.x -= 1;
                    self.position *= self.up * INV_2;
                }
                self.y += 1;
                self.odd = !self.odd;
            },
            2 => {
                if self.y == self.top {
                    return false;
                }
                if self.odd {
                    if self.x == self.right {
                        return false;
                    }
                    self.x += 1;
                    self.position *= self.up + self.up;
                } else {
                    self.position *= self.up;
                }
                self.y += 1;
                self.odd = !self.odd;
            },
            3 => {
                if self.x == self.right {
                    return false;
                }
                self.x += 1;
                self.position += self.position;
            },
            4 => {
                if self.y == 1 {
                    return false;
                }
                if self.odd {
                    if self.x == self.right {
                        return false;
                    }
                    self.x += 1;
                    self.position *= self.down + self.down;
                } else {
                    self.position *= self.down;
                }
                self.y -= 1;
                self.odd = !self.odd;
            },
            _ => {
                if self.y == 1 {
                    return false;
                }
                if self.odd {
                    self.position *= self.down;
                } else {
                    if self.x == 1 {
                        return false;
                    }
                    self.x -= 1;
                    self.position *= self.down * INV_2;
                }
                self.y -= 1;
                self.odd = !self.odd;
            },
        }
        true
    }

    #[inline]
    fn position(self: @Coords) -> felt252 {
        *self.position
    }
}

/// Variant index arithmetic (`DirectionTrait::next`), border test by mask (`2^i & INTERIOR`).
#[derive(Copy, Drop)]
struct Index {
    index: u8,
    odd: bool,
    width: u8,
    interior: u256,
}

impl IndexMover of Mover<Index> {
    #[inline]
    fn step(ref self: Index, direction: u8) -> bool {
        let direction: Direction = direction.try_into().unwrap();
        let target = direction.next(self.index, self.width, self.odd);
        if !Bits::get(self.interior, target) {
            return false;
        }
        self.index = target;
        match direction {
            Direction::East | Direction::West => {},
            _ => self.odd = !self.odd,
        }
        true
    }

    #[inline]
    fn position(self: @Index) -> felt252 {
        Bits::pow(*self.index)
    }
}

/// Variant one-hot position, per-parity offset table in field elements, interior test = one AND.
#[derive(Copy, Drop)]
struct OneHot {
    position: felt252,
    odd: felt252,
    table: Span<felt252>,
    interior: u256,
}

impl OneHotMover of Mover<OneHot> {
    #[inline]
    fn step(ref self: OneHot, direction: u8) -> bool {
        let slot: felt252 = direction.into() + self.odd;
        let slot: u32 = slot.try_into().unwrap();
        let target = self.position * *self.table.at(slot);
        let bit: u256 = target.into();
        if bit & self.interior == 0 {
            return false;
        }
        self.position = target;
        // [Compute] Vertical moves flip the parity: slots 1, 2, 4, 5 (and +6)
        if direction != 0 && direction != 3 {
            self.odd = 6 - self.odd;
        }
        true
    }

    #[inline]
    fn position(self: @OneHot) -> felt252 {
        *self.position
    }
}

// Constructors: same start as the library (two `next_below` on the seed).

#[inline]
fn start(width: u8, height: u8, seed: felt252) -> (u8, u8, felt252) {
    Asserter::assert_valid_dimension(width, height);
    let mut rng = RngTrait::new(seed);
    let x = 1 + rng.next_below(width - 2);
    let y = 1 + rng.next_below(height - 2);
    (x, y, rng.seed)
}

#[inline]
fn doubled(width: u8, height: u8, x: u8, y: u8) -> Doubled {
    let up = Bits::pow(width);
    let inv = Bits::inv(width);
    let odd = y % 2;
    let (factor, other) = if odd == 1 {
        (up, up * INV_2)
    } else {
        (up * INV_2, up)
    };
    Doubled {
        column: (2 * x + odd).into(),
        row: y.into(),
        position: Bits::pow(y * width + x),
        factor,
        other,
        right: (2 * width - 3).into(),
        top: (height - 2).into(),
        down: inv * inv,
    }
}

#[inline]
fn coords(width: u8, height: u8, x: u8, y: u8) -> Coords {
    Coords {
        x: x.into(),
        y: y.into(),
        odd: y % 2 == 1,
        position: Bits::pow(y * width + x),
        up: Bits::pow(width),
        down: Bits::inv(width),
        right: (width - 2).into(),
        top: (height - 2).into(),
    }
}

#[inline]
fn index(width: u8, height: u8, x: u8, y: u8) -> Index {
    Index {
        index: y * width + x,
        odd: y % 2 == 1,
        width,
        interior: LayoutTrait::interior(width, height).into(),
    }
}

#[inline]
fn one_hot(width: u8, height: u8, x: u8, y: u8) -> OneHot {
    let up = Bits::pow(width);
    let down = Bits::inv(width);
    // [Compute] Factors by direction, even row then odd row
    let table = array![
        INV_2, up * INV_2, up, 2, down, down * INV_2, INV_2, up, up + up, 2, down + down, down,
    ];
    OneHot {
        position: Bits::pow(y * width + x),
        odd: if y % 2 == 1 {
            6
        } else {
            0
        },
        table: table.span(),
        interior: LayoutTrait::interior(width, height).into(),
    }
}

// Random sources.

#[inline]
fn refill(ref seed: felt252) -> u128 {
    let (next, word, _) = hades_permutation(seed, 0, 2);
    let word: u256 = word.into();
    seed = next;
    word.low
}

/// 3-bit digits from the pool with rejection of 6 and 7.
#[inline]
fn octal(ref pool: u128, ref seed: felt252) -> u8 {
    loop {
        if pool < TWO_POW_32 {
            pool = refill(ref seed);
        }
        let (quotient, digit) = DivRem::div_rem(pool, OCTAL);
        pool = quotient;
        if digit < 6 {
            break digit.try_into().unwrap();
        }
    }
}

#[inline(never)]
fn triple(draw: u128) -> (u8, u8, u8) {
    let draw: felt252 = draw.into();
    match draw {
        0 => (0, 0, 0),
        1 => (1, 0, 0),
        2 => (2, 0, 0),
        3 => (3, 0, 0),
        4 => (4, 0, 0),
        5 => (5, 0, 0),
        6 => (0, 1, 0),
        7 => (1, 1, 0),
        8 => (2, 1, 0),
        9 => (3, 1, 0),
        10 => (4, 1, 0),
        11 => (5, 1, 0),
        12 => (0, 2, 0),
        13 => (1, 2, 0),
        14 => (2, 2, 0),
        15 => (3, 2, 0),
        16 => (4, 2, 0),
        17 => (5, 2, 0),
        18 => (0, 3, 0),
        19 => (1, 3, 0),
        20 => (2, 3, 0),
        21 => (3, 3, 0),
        22 => (4, 3, 0),
        23 => (5, 3, 0),
        24 => (0, 4, 0),
        25 => (1, 4, 0),
        26 => (2, 4, 0),
        27 => (3, 4, 0),
        28 => (4, 4, 0),
        29 => (5, 4, 0),
        30 => (0, 5, 0),
        31 => (1, 5, 0),
        32 => (2, 5, 0),
        33 => (3, 5, 0),
        34 => (4, 5, 0),
        35 => (5, 5, 0),
        36 => (0, 0, 1),
        37 => (1, 0, 1),
        38 => (2, 0, 1),
        39 => (3, 0, 1),
        40 => (4, 0, 1),
        41 => (5, 0, 1),
        42 => (0, 1, 1),
        43 => (1, 1, 1),
        44 => (2, 1, 1),
        45 => (3, 1, 1),
        46 => (4, 1, 1),
        47 => (5, 1, 1),
        48 => (0, 2, 1),
        49 => (1, 2, 1),
        50 => (2, 2, 1),
        51 => (3, 2, 1),
        52 => (4, 2, 1),
        53 => (5, 2, 1),
        54 => (0, 3, 1),
        55 => (1, 3, 1),
        56 => (2, 3, 1),
        57 => (3, 3, 1),
        58 => (4, 3, 1),
        59 => (5, 3, 1),
        60 => (0, 4, 1),
        61 => (1, 4, 1),
        62 => (2, 4, 1),
        63 => (3, 4, 1),
        64 => (4, 4, 1),
        65 => (5, 4, 1),
        66 => (0, 5, 1),
        67 => (1, 5, 1),
        68 => (2, 5, 1),
        69 => (3, 5, 1),
        70 => (4, 5, 1),
        71 => (5, 5, 1),
        72 => (0, 0, 2),
        73 => (1, 0, 2),
        74 => (2, 0, 2),
        75 => (3, 0, 2),
        76 => (4, 0, 2),
        77 => (5, 0, 2),
        78 => (0, 1, 2),
        79 => (1, 1, 2),
        80 => (2, 1, 2),
        81 => (3, 1, 2),
        82 => (4, 1, 2),
        83 => (5, 1, 2),
        84 => (0, 2, 2),
        85 => (1, 2, 2),
        86 => (2, 2, 2),
        87 => (3, 2, 2),
        88 => (4, 2, 2),
        89 => (5, 2, 2),
        90 => (0, 3, 2),
        91 => (1, 3, 2),
        92 => (2, 3, 2),
        93 => (3, 3, 2),
        94 => (4, 3, 2),
        95 => (5, 3, 2),
        96 => (0, 4, 2),
        97 => (1, 4, 2),
        98 => (2, 4, 2),
        99 => (3, 4, 2),
        100 => (4, 4, 2),
        101 => (5, 4, 2),
        102 => (0, 5, 2),
        103 => (1, 5, 2),
        104 => (2, 5, 2),
        105 => (3, 5, 2),
        106 => (4, 5, 2),
        107 => (5, 5, 2),
        108 => (0, 0, 3),
        109 => (1, 0, 3),
        110 => (2, 0, 3),
        111 => (3, 0, 3),
        112 => (4, 0, 3),
        113 => (5, 0, 3),
        114 => (0, 1, 3),
        115 => (1, 1, 3),
        116 => (2, 1, 3),
        117 => (3, 1, 3),
        118 => (4, 1, 3),
        119 => (5, 1, 3),
        120 => (0, 2, 3),
        121 => (1, 2, 3),
        122 => (2, 2, 3),
        123 => (3, 2, 3),
        124 => (4, 2, 3),
        125 => (5, 2, 3),
        126 => (0, 3, 3),
        127 => (1, 3, 3),
        128 => (2, 3, 3),
        129 => (3, 3, 3),
        130 => (4, 3, 3),
        131 => (5, 3, 3),
        132 => (0, 4, 3),
        133 => (1, 4, 3),
        134 => (2, 4, 3),
        135 => (3, 4, 3),
        136 => (4, 4, 3),
        137 => (5, 4, 3),
        138 => (0, 5, 3),
        139 => (1, 5, 3),
        140 => (2, 5, 3),
        141 => (3, 5, 3),
        142 => (4, 5, 3),
        143 => (5, 5, 3),
        144 => (0, 0, 4),
        145 => (1, 0, 4),
        146 => (2, 0, 4),
        147 => (3, 0, 4),
        148 => (4, 0, 4),
        149 => (5, 0, 4),
        150 => (0, 1, 4),
        151 => (1, 1, 4),
        152 => (2, 1, 4),
        153 => (3, 1, 4),
        154 => (4, 1, 4),
        155 => (5, 1, 4),
        156 => (0, 2, 4),
        157 => (1, 2, 4),
        158 => (2, 2, 4),
        159 => (3, 2, 4),
        160 => (4, 2, 4),
        161 => (5, 2, 4),
        162 => (0, 3, 4),
        163 => (1, 3, 4),
        164 => (2, 3, 4),
        165 => (3, 3, 4),
        166 => (4, 3, 4),
        167 => (5, 3, 4),
        168 => (0, 4, 4),
        169 => (1, 4, 4),
        170 => (2, 4, 4),
        171 => (3, 4, 4),
        172 => (4, 4, 4),
        173 => (5, 4, 4),
        174 => (0, 5, 4),
        175 => (1, 5, 4),
        176 => (2, 5, 4),
        177 => (3, 5, 4),
        178 => (4, 5, 4),
        179 => (5, 5, 4),
        180 => (0, 0, 5),
        181 => (1, 0, 5),
        182 => (2, 0, 5),
        183 => (3, 0, 5),
        184 => (4, 0, 5),
        185 => (5, 0, 5),
        186 => (0, 1, 5),
        187 => (1, 1, 5),
        188 => (2, 1, 5),
        189 => (3, 1, 5),
        190 => (4, 1, 5),
        191 => (5, 1, 5),
        192 => (0, 2, 5),
        193 => (1, 2, 5),
        194 => (2, 2, 5),
        195 => (3, 2, 5),
        196 => (4, 2, 5),
        197 => (5, 2, 5),
        198 => (0, 3, 5),
        199 => (1, 3, 5),
        200 => (2, 3, 5),
        201 => (3, 3, 5),
        202 => (4, 3, 5),
        203 => (5, 3, 5),
        204 => (0, 4, 5),
        205 => (1, 4, 5),
        206 => (2, 4, 5),
        207 => (3, 4, 5),
        208 => (4, 4, 5),
        209 => (5, 4, 5),
        210 => (0, 5, 5),
        211 => (1, 5, 5),
        212 => (2, 5, 5),
        213 => (3, 5, 5),
        214 => (4, 5, 5),
        _ => (5, 5, 5),
    }
}

#[inline]
fn triple_inline(draw: u128) -> (u8, u8, u8) {
    let draw: felt252 = draw.into();
    match draw {
        0 => (0, 0, 0),
        1 => (1, 0, 0),
        2 => (2, 0, 0),
        3 => (3, 0, 0),
        4 => (4, 0, 0),
        5 => (5, 0, 0),
        6 => (0, 1, 0),
        7 => (1, 1, 0),
        8 => (2, 1, 0),
        9 => (3, 1, 0),
        10 => (4, 1, 0),
        11 => (5, 1, 0),
        12 => (0, 2, 0),
        13 => (1, 2, 0),
        14 => (2, 2, 0),
        15 => (3, 2, 0),
        16 => (4, 2, 0),
        17 => (5, 2, 0),
        18 => (0, 3, 0),
        19 => (1, 3, 0),
        20 => (2, 3, 0),
        21 => (3, 3, 0),
        22 => (4, 3, 0),
        23 => (5, 3, 0),
        24 => (0, 4, 0),
        25 => (1, 4, 0),
        26 => (2, 4, 0),
        27 => (3, 4, 0),
        28 => (4, 4, 0),
        29 => (5, 4, 0),
        30 => (0, 5, 0),
        31 => (1, 5, 0),
        32 => (2, 5, 0),
        33 => (3, 5, 0),
        34 => (4, 5, 0),
        35 => (5, 5, 0),
        36 => (0, 0, 1),
        37 => (1, 0, 1),
        38 => (2, 0, 1),
        39 => (3, 0, 1),
        40 => (4, 0, 1),
        41 => (5, 0, 1),
        42 => (0, 1, 1),
        43 => (1, 1, 1),
        44 => (2, 1, 1),
        45 => (3, 1, 1),
        46 => (4, 1, 1),
        47 => (5, 1, 1),
        48 => (0, 2, 1),
        49 => (1, 2, 1),
        50 => (2, 2, 1),
        51 => (3, 2, 1),
        52 => (4, 2, 1),
        53 => (5, 2, 1),
        54 => (0, 3, 1),
        55 => (1, 3, 1),
        56 => (2, 3, 1),
        57 => (3, 3, 1),
        58 => (4, 3, 1),
        59 => (5, 3, 1),
        60 => (0, 4, 1),
        61 => (1, 4, 1),
        62 => (2, 4, 1),
        63 => (3, 4, 1),
        64 => (4, 4, 1),
        65 => (5, 4, 1),
        66 => (0, 5, 1),
        67 => (1, 5, 1),
        68 => (2, 5, 1),
        69 => (3, 5, 1),
        70 => (4, 5, 1),
        71 => (5, 5, 1),
        72 => (0, 0, 2),
        73 => (1, 0, 2),
        74 => (2, 0, 2),
        75 => (3, 0, 2),
        76 => (4, 0, 2),
        77 => (5, 0, 2),
        78 => (0, 1, 2),
        79 => (1, 1, 2),
        80 => (2, 1, 2),
        81 => (3, 1, 2),
        82 => (4, 1, 2),
        83 => (5, 1, 2),
        84 => (0, 2, 2),
        85 => (1, 2, 2),
        86 => (2, 2, 2),
        87 => (3, 2, 2),
        88 => (4, 2, 2),
        89 => (5, 2, 2),
        90 => (0, 3, 2),
        91 => (1, 3, 2),
        92 => (2, 3, 2),
        93 => (3, 3, 2),
        94 => (4, 3, 2),
        95 => (5, 3, 2),
        96 => (0, 4, 2),
        97 => (1, 4, 2),
        98 => (2, 4, 2),
        99 => (3, 4, 2),
        100 => (4, 4, 2),
        101 => (5, 4, 2),
        102 => (0, 5, 2),
        103 => (1, 5, 2),
        104 => (2, 5, 2),
        105 => (3, 5, 2),
        106 => (4, 5, 2),
        107 => (5, 5, 2),
        108 => (0, 0, 3),
        109 => (1, 0, 3),
        110 => (2, 0, 3),
        111 => (3, 0, 3),
        112 => (4, 0, 3),
        113 => (5, 0, 3),
        114 => (0, 1, 3),
        115 => (1, 1, 3),
        116 => (2, 1, 3),
        117 => (3, 1, 3),
        118 => (4, 1, 3),
        119 => (5, 1, 3),
        120 => (0, 2, 3),
        121 => (1, 2, 3),
        122 => (2, 2, 3),
        123 => (3, 2, 3),
        124 => (4, 2, 3),
        125 => (5, 2, 3),
        126 => (0, 3, 3),
        127 => (1, 3, 3),
        128 => (2, 3, 3),
        129 => (3, 3, 3),
        130 => (4, 3, 3),
        131 => (5, 3, 3),
        132 => (0, 4, 3),
        133 => (1, 4, 3),
        134 => (2, 4, 3),
        135 => (3, 4, 3),
        136 => (4, 4, 3),
        137 => (5, 4, 3),
        138 => (0, 5, 3),
        139 => (1, 5, 3),
        140 => (2, 5, 3),
        141 => (3, 5, 3),
        142 => (4, 5, 3),
        143 => (5, 5, 3),
        144 => (0, 0, 4),
        145 => (1, 0, 4),
        146 => (2, 0, 4),
        147 => (3, 0, 4),
        148 => (4, 0, 4),
        149 => (5, 0, 4),
        150 => (0, 1, 4),
        151 => (1, 1, 4),
        152 => (2, 1, 4),
        153 => (3, 1, 4),
        154 => (4, 1, 4),
        155 => (5, 1, 4),
        156 => (0, 2, 4),
        157 => (1, 2, 4),
        158 => (2, 2, 4),
        159 => (3, 2, 4),
        160 => (4, 2, 4),
        161 => (5, 2, 4),
        162 => (0, 3, 4),
        163 => (1, 3, 4),
        164 => (2, 3, 4),
        165 => (3, 3, 4),
        166 => (4, 3, 4),
        167 => (5, 3, 4),
        168 => (0, 4, 4),
        169 => (1, 4, 4),
        170 => (2, 4, 4),
        171 => (3, 4, 4),
        172 => (4, 4, 4),
        173 => (5, 4, 4),
        174 => (0, 5, 4),
        175 => (1, 5, 4),
        176 => (2, 5, 4),
        177 => (3, 5, 4),
        178 => (4, 5, 4),
        179 => (5, 5, 4),
        180 => (0, 0, 5),
        181 => (1, 0, 5),
        182 => (2, 0, 5),
        183 => (3, 0, 5),
        184 => (4, 0, 5),
        185 => (5, 0, 5),
        186 => (0, 1, 5),
        187 => (1, 1, 5),
        188 => (2, 1, 5),
        189 => (3, 1, 5),
        190 => (4, 1, 5),
        191 => (5, 1, 5),
        192 => (0, 2, 5),
        193 => (1, 2, 5),
        194 => (2, 2, 5),
        195 => (3, 2, 5),
        196 => (4, 2, 5),
        197 => (5, 2, 5),
        198 => (0, 3, 5),
        199 => (1, 3, 5),
        200 => (2, 3, 5),
        201 => (3, 3, 5),
        202 => (4, 3, 5),
        203 => (5, 3, 5),
        204 => (0, 4, 5),
        205 => (1, 4, 5),
        206 => (2, 4, 5),
        207 => (3, 4, 5),
        208 => (4, 4, 5),
        209 => (5, 4, 5),
        210 => (0, 5, 5),
        211 => (1, 5, 5),
        212 => (2, 5, 5),
        213 => (3, 5, 5),
        214 => (4, 5, 5),
        _ => (5, 5, 5),
    }
}

#[inline]
fn pair(draw: u128) -> (u8, u8) {
    let draw: felt252 = draw.into();
    match draw {
        0 => (0, 0),
        1 => (1, 0),
        2 => (2, 0),
        3 => (3, 0),
        4 => (4, 0),
        5 => (5, 0),
        6 => (0, 1),
        7 => (1, 1),
        8 => (2, 1),
        9 => (3, 1),
        10 => (4, 1),
        11 => (5, 1),
        12 => (0, 2),
        13 => (1, 2),
        14 => (2, 2),
        15 => (3, 2),
        16 => (4, 2),
        17 => (5, 2),
        18 => (0, 3),
        19 => (1, 3),
        20 => (2, 3),
        21 => (3, 3),
        22 => (4, 3),
        23 => (5, 3),
        24 => (0, 4),
        25 => (1, 4),
        26 => (2, 4),
        27 => (3, 4),
        28 => (4, 4),
        29 => (5, 4),
        30 => (0, 5),
        31 => (1, 5),
        32 => (2, 5),
        33 => (3, 5),
        34 => (4, 5),
        _ => (5, 5),
    }
}

// Grid accumulation: new positions of three moves, each once (only the first and the third can
// coincide).

#[inline]
fn walk3<T, +Mover<T>, +Drop<T>>(ref walk: T, first: u8, second: u8, third: u8) -> felt252 {
    let mut batch = 0;
    if walk.step(first) {
        batch += walk.position();
    }
    let middle = walk.position();
    if walk.step(second) {
        batch += walk.position();
    }
    if walk.step(third) && walk.position() != middle {
        batch += walk.position();
    }
    batch
}

/// Grid variant: OR every new position into a `u256` grid, one conversion at the end.
#[inline]
fn or_each<T, +Mover<T>, +Drop<T>>(ref walk: T, ref grid: u256, direction: u8) {
    if walk.step(direction) {
        grid = grid | walk.position().into();
    }
}

/// Grid variant: felt grid, OR through a `u256` round trip on every new position.
#[inline]
fn or_felt<T, +Mover<T>, +Drop<T>>(ref walk: T, ref grid: felt252, direction: u8) {
    if walk.step(direction) {
        let wide: u256 = grid.into();
        grid = Bits::to_felt(wide | walk.position().into());
    }
}

/// Grid variant: felt grid, bit test and add only when unset.
#[inline]
fn test_add<T, +Mover<T>, +Drop<T>>(ref walk: T, ref grid: felt252, direction: u8) {
    if walk.step(direction) {
        let position = walk.position();
        let wide: u256 = grid.into();
        if wide & position.into() == 0 {
            grid += position;
        }
    }
}

/// Grid variant: batch of three, OR on the low limb only when the batch fits in it.
#[inline]
fn open_limb(ref grid: u256, batch: felt252) {
    match batch.try_into() {
        Option::Some(low) => grid.low = grid.low | low,
        Option::None => grid = grid | batch.into(),
    }
}

/// Loop variant: one draw (3 moves) per iteration.
fn loop_3<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 3);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 12;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Loop variant: two draws (6 moves) per iteration.
fn loop_6<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 6);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 6;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Loop variant: four draws (12 moves) per iteration.
fn loop_12<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 12);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 3;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Winner shape: six draws (18 moves) per iteration.
fn loop_18<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Loop variant: twelve draws (36 moves, one pool) per iteration.
fn loop_36<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 36);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 1;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Loop variant: four draws per iteration, table inlined.
fn loop_12_inline<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 12);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 3;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Loop variant: twelve draws per iteration, table inlined.
fn loop_36_inline<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 36);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 1;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple_inline(draw);
        grid = grid | walk3(ref walk, first, second, third).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Grid variant: OR each step into a `u256`, one conversion at the end.
fn grid_or_each<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_each(ref walk, ref grid, first);
        or_each(ref walk, ref grid, second);
        or_each(ref walk, ref grid, third);
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Grid variant: OR each step on a felt grid (u256 round trip).
fn grid_or_felt<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: felt252 = start;
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        or_felt(ref walk, ref grid, first);
        or_felt(ref walk, ref grid, second);
        or_felt(ref walk, ref grid, third);
        pool = quotient;
    }
    grid
}

/// Grid variant: test the bit, add only when unset.
fn grid_test_add<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: felt252 = start;
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        test_add(ref walk, ref grid, first);
        test_add(ref walk, ref grid, second);
        test_add(ref walk, ref grid, third);
        pool = quotient;
    }
    grid
}

/// Grid variant: batch of three, low-limb OR when the batch fits.
fn grid_limb<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
        let (first, second, third) = triple(draw);
        open_limb(ref grid, walk3(ref walk, first, second, third));
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Random variant: `Rng::next_below(6)` per move.
fn random_next_below<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut rng: Rng = RngTrait::new(seed);
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = rng.next_below(6);
        let second = rng.next_below(6);
        let third = rng.next_below(6);
        grid = grid | walk3(ref walk, first, second, third).into();
    }
    Bits::to_felt(grid)
}

/// Random variant: 3-bit digits from the pool, rejection of 6 and 7.
fn random_octal<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
        let first = octal(ref pool, ref seed);
        let second = octal(ref pool, ref seed);
        let third = octal(ref pool, ref seed);
        grid = grid | walk3(ref walk, first, second, third).into();
    }
    Bits::to_felt(grid)
}

/// Random variant: one draw in `0..36` per two moves (36-arm table).
fn random_pairs<T, +Mover<T>, +Drop<T>>(
    ref walk: T, steps: u16, seed: felt252, start: felt252,
) -> felt252 {
    let (blocks, tail) = DivRem::div_rem(steps, 18);
    assert!(tail == 0);
    let mut blocks: felt252 = blocks.into();
    let mut seed = seed;
    let mut pool: u128 = 0;
    let mut left: felt252 = 0;
    let mut grid: u256 = start.into();
    while blocks != 0 {
        blocks -= 1;
        if left == 0 {
            pool = refill(ref seed);
            left = 2;
        }
        left -= 1;
        let (quotient, draw) = DivRem::div_rem(pool, PAIR_COUNT);
        let (d0, d1) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d2, d3) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d4, d5) = pair(draw);
        grid = grid | walk3(ref walk, d0, d1, d2).into();
        grid = grid | walk3(ref walk, d3, d4, d5).into();
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d0, d1) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d2, d3) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d4, d5) = pair(draw);
        grid = grid | walk3(ref walk, d0, d1, d2).into();
        grid = grid | walk3(ref walk, d3, d4, d5).into();
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d0, d1) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d2, d3) = pair(draw);
        let (quotient, draw) = DivRem::div_rem(quotient, PAIR_COUNT);
        let (d4, d5) = pair(draw);
        grid = grid | walk3(ref walk, d0, d1, d2).into();
        grid = grid | walk3(ref walk, d3, d4, d5).into();
        pool = quotient;
    }
    Bits::to_felt(grid)
}

/// Naive baseline: one move per iteration, `Rng::next_below(6)`, `(x, y)` with a parity bool, OR
/// of every new position into a `u256` grid.
fn naive(width: u8, height: u8, steps: u16, seed: felt252) -> felt252 {
    let (x, y, _) = start(width, height, seed);
    let mut walk = coords(width, height, x, y);
    let mut rng: Rng = RngTrait::new(seed);
    let mut grid: u256 = walk.position.into();
    let mut steps: felt252 = steps.into();
    while steps != 0 {
        steps -= 1;
        let direction = rng.next_below(6);
        or_each(ref walk, ref grid, direction);
    }
    Bits::to_felt(grid)
}

fn assert_closed(grid: felt252, width: u8, height: u8) {
    let outside: u256 = LayoutTrait::board(width, height).into()
        - LayoutTrait::interior(width, height).into();
    let grid: u256 = grid.into();
    assert!(grid & outside == 0);
}

// Library walker

#[test]
#[available_gas(l2_gas: 39000)]
fn bench_walker_17x14_0() {
    let grid = Walker::generate(17, 14, 0, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 317000)]
fn bench_walker_17x14_50() {
    let grid = Walker::generate(17, 14, 50, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 1052000)]
fn bench_walker_17x14_200() {
    let grid = Walker::generate(17, 14, 200, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 2591000)]
fn bench_walker_17x14_500() {
    let grid = Walker::generate(17, 14, 500, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 2587000)]
fn bench_walker_17x14_504() {
    let grid = Walker::generate(17, 14, 504, SEED);
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 318000)]
fn bench_walker_7x7_50() {
    let grid = Walker::generate(7, 7, 50, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 1045000)]
fn bench_walker_7x7_200() {
    let grid = Walker::generate(7, 7, 200, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 1060000)]
fn bench_walker_19x13_200() {
    let grid = Walker::generate(19, 13, 200, SEED);
    assert!(grid != 0);
}

#[test]
#[available_gas(l2_gas: 321000)]
fn bench_walker_3x3_50() {
    let grid = Walker::generate(3, 3, 50, SEED);
    assert!(grid != 0);
}

// Variants, 17x14, 504 steps

#[test]
#[available_gas(l2_gas: 2791000)]
fn bench_walker_variant_winner() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_18(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2843000)]
fn bench_walker_variant_move_coords() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = coords(17, 14, x, y);
    let grid = loop_18(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 6249000)]
fn bench_walker_variant_move_index_mask() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = index(17, 14, x, y);
    let grid = loop_18(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 4783000)]
fn bench_walker_variant_move_one_hot_and() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = one_hot(17, 14, x, y);
    let grid = loop_18(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 3794000)]
fn bench_walker_variant_grid_or_each() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = grid_or_each(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 4690000)]
fn bench_walker_variant_grid_or_felt() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = grid_or_felt(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 4743000)]
fn bench_walker_variant_grid_test_add() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = grid_test_add(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2896000)]
fn bench_walker_variant_grid_limb() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = grid_limb(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 3619000)]
fn bench_walker_variant_loop_3() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_3(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 3122000)]
fn bench_walker_variant_loop_6() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_6(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2873000)]
fn bench_walker_variant_loop_12() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_12(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2708000)]
fn bench_walker_variant_loop_36() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_36(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2813000)]
fn bench_walker_variant_loop_12_inline() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_12_inline(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 2648000)]
fn bench_walker_variant_loop_36_inline() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = loop_36_inline(ref walk, STEPS, seed, walk.position());
    assert!(grid == EXPECTED);
}

#[test]
#[available_gas(l2_gas: 4113000)]
fn bench_walker_variant_random_next_below() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = random_next_below(ref walk, STEPS, seed, walk.position());
    assert_closed(grid, 17, 14);
}

#[test]
#[available_gas(l2_gas: 6686000)]
fn bench_walker_variant_random_octal() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = random_octal(ref walk, STEPS, seed, walk.position());
    assert_closed(grid, 17, 14);
}

#[test]
#[available_gas(l2_gas: 2999000)]
fn bench_walker_variant_random_pairs() {
    let (x, y, seed) = start(17, 14, SEED);
    let mut walk = doubled(17, 14, x, y);
    let grid = random_pairs(ref walk, STEPS, seed, walk.position());
    assert_closed(grid, 17, 14);
}

#[test]
#[available_gas(l2_gas: 7238000)]
fn bench_walker_variant_naive() {
    let grid = naive(17, 14, STEPS, SEED);
    assert_closed(grid, 17, 14);
}
