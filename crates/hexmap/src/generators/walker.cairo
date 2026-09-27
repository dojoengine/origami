//! Random walk generator (lot L6).
//!
//! The walker starts on a seed-selected interior tile and makes `steps` moves. Each move draws one
//! of the 6 directions, moves if the target is interior (stays otherwise) and opens the tile.
//!
//! Gas layout (see `GAS.md`, L6):
//! * Directions are drawn three at a time: one pool division by 216 and a 216-arm table (not
//!   inlined: one copy of the table, one call per three moves).
//! * The main loop makes 18 moves per iteration (6 draws, two iterations per pool refill).
//! * The column is tracked doubled, `c = 2x + (y & 1)`: every move shifts it by a constant
//!   (East -2, West +2, NorthEast/SouthEast -1, NorthWest/SouthWest +1) and every bound test is
//!   one felt equality, with no parity branch.
//! * The position is a one-hot felt `2^i`: a move is one field product. The diagonal factors
//!   depend on the row parity: the walker carries the NorthEast factor of its row and of the
//!   other row, and swaps them on every vertical move.
//! * Tiles are opened three moves at a time: the three positions are summed (only the first and
//!   the third can coincide, one felt equality) and the sum is ORed into the grid once.

// Core imports

use core::poseidon::hades_permutation;

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::rng::RngTrait;

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Number of direction triples, one draw per three moves.
const TRIPLE_COUNT: NonZero<u128> = 216;
/// Iterations per pool refill: 12 draws, 216^12 < 2^96, the pool stays above 2^32 like `Rng`.
const BLOCKS_PER_POOL: felt252 = 2;

/// Walker state.
#[derive(Copy, Drop)]
struct Walk {
    /// Doubled column, `2x + (y & 1)`, `2 <= c <= 2W - 3`.
    column: felt252,
    /// Row, `1 <= y <= H - 2`.
    row: felt252,
    /// One-hot position, `2^(y * W + x)`.
    position: felt252,
    /// NorthEast factor of the current row: 2^(W-1) on even rows, 2^W on odd rows.
    factor: felt252,
    /// NorthEast factor of the other row parity.
    other: felt252,
}

/// Per-map constants.
#[derive(Copy, Drop)]
struct Bounds {
    /// Largest doubled column, `2W - 3`.
    right: felt252,
    /// Largest row, `H - 2`.
    top: felt252,
    /// 2^-2W: SouthEast factor = NorthEast factor * 2^-2W.
    down: felt252,
}

#[generate_trait]
pub impl Walker of WalkerTrait {
    /// Generate a random walk.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `steps` - The number of steps
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    fn generate(width: u8, height: u8, steps: u16, seed: felt252) -> felt252 {
        // [Check] Valid dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Compute] Per-map constants
        let up = Bits::pow(width);
        let inv = Bits::inv(width);
        let bounds = Bounds {
            right: (2 * width - 3).into(), top: (height - 2).into(), down: inv * inv,
        };
        // [Compute] Start on a random interior tile
        let mut rng = RngTrait::new(seed);
        let x = 1 + rng.next_below(width - 2);
        let y = 1 + rng.next_below(height - 2);
        let odd = y % 2;
        let (factor, other) = if odd == 1 {
            (up, up * INV_2)
        } else {
            (up * INV_2, up)
        };
        let position = Bits::pow(y * width + x);
        let mut walk = Walk {
            column: (2 * x + odd).into(), row: y.into(), position, factor, other,
        };
        let mut grid: u256 = position.into();
        // [Compute] Walk, 6 draws of three moves per iteration
        let (blocks, tail) = DivRem::div_rem(steps, 18);
        let mut blocks: felt252 = blocks.into();
        let mut seed = rng.seed;
        let mut pool: u128 = 0;
        let mut left: felt252 = 0;
        while blocks != 0 {
            blocks -= 1;
            if left == 0 {
                let (next, word, _) = hades_permutation(seed, 0, 2);
                let word: u256 = word.into();
                seed = next;
                pool = word.low;
                left = BLOCKS_PER_POOL;
            }
            left -= 1;
            let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            let (quotient, draw) = DivRem::div_rem(quotient, TRIPLE_COUNT);
            grid = grid | walk.walk3(@bounds, draw).into();
            pool = quotient;
        }
        // [Compute] Remaining moves, at most 6 draws: the pool holds them
        if tail != 0 {
            if left == 0 {
                let (_, word, _) = hades_permutation(seed, 0, 2);
                let word: u256 = word.into();
                pool = word.low;
            }
            let (full, count) = DivRem::div_rem(tail, 3);
            let mut full: felt252 = full.into();
            while full != 0 {
                full -= 1;
                let (quotient, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
                pool = quotient;
                grid = grid | walk.walk3(@bounds, draw).into();
            }
            if count != 0 {
                let (_, draw) = DivRem::div_rem(pool, TRIPLE_COUNT);
                grid = grid | walk.walk2(@bounds, draw, count).into();
            }
        }
        // [Return] Grid
        Bits::to_felt(grid)
    }
}

#[generate_trait]
impl WalkImpl of WalkTrait {
    /// Make three moves.
    /// # Arguments
    /// * `self` - The walker state
    /// * `bounds` - The per-map constants
    /// * `draw` - The draw in `0..216`, three directions
    /// # Returns
    /// * The new positions, each once: only the first and the third can coincide
    #[inline]
    fn walk3(ref self: Walk, bounds: @Bounds, draw: u128) -> felt252 {
        let (first, second, third) = triple(draw);
        let mut batch = 0;
        if self.step(bounds, first) {
            batch += self.position;
        }
        let middle = self.position;
        if self.step(bounds, second) {
            batch += self.position;
        }
        if self.step(bounds, third) && self.position != middle {
            batch += self.position;
        }
        batch
    }

    /// Make one or two moves.
    /// # Arguments
    /// * `self` - The walker state
    /// * `bounds` - The per-map constants
    /// * `draw` - The draw in `0..216`, its first `count` directions are used
    /// * `count` - The number of moves, 1 or 2
    /// # Returns
    /// * The new positions, each once
    #[inline]
    fn walk2(ref self: Walk, bounds: @Bounds, draw: u128, count: u16) -> felt252 {
        let (first, second, _) = triple(draw);
        let mut batch = 0;
        if self.step(bounds, first) {
            batch += self.position;
        }
        if count == 2 && self.step(bounds, second) {
            batch += self.position;
        }
        batch
    }

    /// Make one move if the target is interior.
    /// # Arguments
    /// * `self` - The walker state
    /// * `bounds` - The per-map constants
    /// * `direction` - The direction, in `0..6` (`Direction` order)
    /// # Returns
    /// * `true` if the walker moved
    #[inline]
    fn step(ref self: Walk, bounds: @Bounds, direction: u8) -> bool {
        let bounds = *bounds;
        match direction {
            // East: i - 1
            0 => {
                if (self.column - 2) * (self.column - 3) == 0 {
                    return false;
                }
                self.column -= 2;
                self.position *= INV_2;
            },
            // NorthEast: i + W - 1 (even), i + W (odd)
            1 => {
                if self.row == bounds.top || self.column == 2 {
                    return false;
                }
                self.column -= 1;
                self.row += 1;
                self.position *= self.factor;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            // NorthWest: i + W (even), i + W + 1 (odd)
            2 => {
                if self.row == bounds.top || self.column == bounds.right {
                    return false;
                }
                self.column += 1;
                self.row += 1;
                self.position *= self.factor + self.factor;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            // West: i + 1
            3 => {
                if (self.column - bounds.right) * (self.column + 1 - bounds.right) == 0 {
                    return false;
                }
                self.column += 2;
                self.position += self.position;
            },
            // SouthWest: i - W (even), i - W + 1 (odd)
            4 => {
                if self.row == 1 || self.column == bounds.right {
                    return false;
                }
                self.column += 1;
                self.row -= 1;
                self.position *= (self.factor + self.factor) * bounds.down;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
            // SouthEast: i - W - 1 (even), i - W (odd)
            _ => {
                if self.row == 1 || self.column == 2 {
                    return false;
                }
                self.column -= 1;
                self.row -= 1;
                self.position *= self.factor * bounds.down;
                let factor = self.factor;
                self.factor = self.other;
                self.other = factor;
            },
        }
        true
    }
}

/// Split a draw in `0..216` into three directions (base-6 digits, lowest first).
/// # Arguments
/// * `draw` - The draw
/// # Returns
/// * The three directions
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

#[cfg(test)]
mod tests {
    // Core imports

    use core::poseidon::hades_permutation;

    // Internal imports

    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::helpers::rng::RngTrait;
    use origami_hexmap::types::direction::Direction;

    // Local imports

    use super::Walker;

    // Constants

    const SEED: felt252 = 'SEED';

    /// Scalar reference on the same draws: `neighbor`, an interior test on the coordinates, and a
    /// bit test before every set.
    fn reference(width: u8, height: u8, steps: u16, seed: felt252) -> felt252 {
        let mut rng = RngTrait::new(seed);
        let x = 1 + rng.next_below(width - 2);
        let y = 1 + rng.next_below(height - 2);
        let mut position = y * width + x;
        let mut grid = Bits::pow(position);
        let mut seed = rng.seed;
        let mut pool: u128 = 0;
        let mut draws: u32 = 0;
        let mut digits: u128 = 0;
        let mut remaining: u8 = 0;
        let mut index: u16 = 0;
        while index != steps {
            if remaining == 0 {
                if draws % 12 == 0 {
                    let (next, word, _) = hades_permutation(seed, 0, 2);
                    let word: u256 = word.into();
                    seed = next;
                    pool = word.low;
                }
                let (quotient, draw) = DivRem::div_rem(pool, 216);
                pool = quotient;
                digits = draw;
                draws += 1;
                remaining = 3;
            }
            let (rest, digit) = DivRem::div_rem(digits, 6);
            digits = rest;
            remaining -= 1;
            let digit: u8 = digit.try_into().unwrap();
            let direction: Direction = digit.try_into().unwrap();
            if let Option::Some(target) =
                LayoutTrait::neighbor(width, height, position, direction) {
                let (tx, ty) = LayoutTrait::coords(width, target);
                if tx != 0 && ty != 0 && tx != width - 1 && ty != height - 1 {
                    position = target;
                    if !Bits::get(grid.into(), position) {
                        grid = Bits::set(grid, position);
                    }
                }
            }
            index += 1;
        }
        grid
    }

    fn assert_matches_reference(width: u8, height: u8, steps: u16, seed: felt252) {
        let grid = Walker::generate(width, height, steps, seed);
        assert!(grid == reference(width, height, steps, seed));
        // [Check] Border ring closed
        let outside: u256 = LayoutTrait::board(width, height).into()
            - LayoutTrait::interior(width, height).into();
        let grid: u256 = grid.into();
        assert!(grid & outside == 0);
    }

    #[test]
    fn test_walker_generate_17x14() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
        // 0 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
        //  0 1 1 1 1 1 1 0 0 0 1 0 0 0 1 0 0
        // 0 1 1 1 1 1 1 1 1 1 1 1 0 0 1 1 0
        //  0 1 1 1 1 1 0 1 1 1 1 1 1 1 1 1 0
        // 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        //  0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        //  0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 1 1 1 0 1 1 1 1 1 1 1 0
        //  0 0 0 0 0 1 1 1 0 0 0 1 1 1 1 0 0
        // 0 0 0 0 0 0 1 0 0 0 0 0 0 0 1 1 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid = Walker::generate(17, 14, 500, SEED);
        assert!(grid == 0xfc007e003f111ffccfbfe7fff1fff83ffc0ffe077f038f0080c0000);
    }

    #[test]
    fn test_walker_generate_7x7() {
        //  0 0 0 0 0 0 0
        // 0 1 1 1 1 1 0
        //  0 1 1 1 1 0 0
        // 0 0 1 1 1 1 0
        //  0 0 1 0 1 1 0
        // 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0
        let grid = Walker::generate(7, 7, 50, SEED);
        assert!(grid == 0x1f3c3c58000);
    }

    #[test]
    fn test_walker_generate_19x13() {
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 0 0 1 1 1 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        //  0 0 1 1 1 1 1 1 1 1 0 0 0 1 1 0 0 0 0
        // 0 1 1 1 1 1 1 1 1 1 1 1 1 1 0 1 1 1 0
        //  0 1 1 0 1 1 1 1 0 1 0 1 1 1 1 1 1 1 0
        // 0 1 1 1 0 1 1 0 0 0 0 1 1 1 1 1 1 1 0
        //  0 1 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid = Walker::generate(19, 13, 200, SEED);
        assert!(grid == 0x40001c0007e001fe007f8c1fff737afe761fc80200000000000);
    }

    #[test]
    fn test_walker_generate_3x3() {
        // The only interior tile, every move is blocked
        //  0 0 0
        // 0 1 0
        //  0 0 0
        let grid = Walker::generate(3, 3, 20, SEED);
        assert!(grid == 0x10);
    }

    #[test]
    fn test_walker_generate_no_step() {
        // Only the start tile, (9, 4)
        let grid = Walker::generate(17, 14, 0, SEED);
        assert!(grid == 0x20000000000000000000);
        assert!(grid == Bits::pow(4 * 17 + 9));
    }

    #[test]
    fn test_walker_deterministic() {
        let grid = Walker::generate(17, 14, 200, SEED);
        assert!(grid == Walker::generate(17, 14, 200, SEED));
        assert!(grid != Walker::generate(17, 14, 200, 'OTHER'));
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_walker_revert_too_large() {
        Walker::generate(18, 14, 10, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_walker_revert_too_narrow() {
        Walker::generate(2, 14, 10, SEED);
    }

    #[test]
    fn test_walker_reference_small_steps() {
        // Every tail length and the first refill boundaries
        let mut steps: u16 = 0;
        while steps != 80 {
            assert_matches_reference(17, 14, steps, SEED);
            assert_matches_reference(7, 7, steps, 'OTHER');
            steps += 1;
        }
    }

    #[test]
    fn test_walker_reference_sizes() {
        let sizes: Array<(u8, u8)> = array![
            (3, 3), (4, 3), (3, 4), (7, 7), (17, 14), (19, 13), (16, 15), (25, 10), (83, 3),
            (3, 83), (11, 11),
        ];
        let mut sizes = sizes.span();
        while let Option::Some((width, height)) = sizes.pop_front() {
            assert_matches_reference(*width, *height, 0, SEED);
            assert_matches_reference(*width, *height, 1, SEED);
            assert_matches_reference(*width, *height, 200, SEED);
            assert_matches_reference(*width, *height, 301, 'OTHER');
        }
    }

    #[test]
    fn test_walker_reference_seeds() {
        let mut seed: felt252 = 0;
        while seed != 20 {
            assert_matches_reference(17, 14, 500, seed);
            seed += 1;
        }
    }
}
