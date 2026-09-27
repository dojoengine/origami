//! Test-only formulations: references for the property tests and the measured losers of the
//! microbenchmarks (see `GAS.md`). Nothing here is part of the library.

// Core imports

use core::felt252_div;

// Internal imports

use origami_hexmap::helpers::bits::{Bits, POW128};
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::types::direction::Direction;

// Constants

const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;

/// Masks of the reference expansion (no border invariant, open borders, up to 252 bits).
#[derive(Copy, Drop)]
pub struct MaskLayout {
    pub even: u256,
    pub odd: u256,
    pub not_left: u256,
    pub not_right: u256,
    pub not_top: u256,
    pub row_shift: u256,
}

#[generate_trait]
pub impl MaskLayoutImpl of MaskLayoutTrait {
    /// Masks of a board, precomputed once like `Layout::new`.
    fn new(width: u8, height: u8) -> MaskLayout {
        let board = LayoutTrait::board(width, height);
        let even = LayoutTrait::even(width, height);
        let row = Bits::pow(width);
        // Column x = 0 in every row
        let right = felt252_div(board, (row - 1).try_into().unwrap());
        let left = right * Bits::pow(width - 1);
        MaskLayout {
            even: even.into(),
            odd: (board - even).into(),
            not_left: (board - left).into(),
            not_right: (board - right).into(),
            not_top: (Bits::pow(width * (height - 1)) - 1).into(),
            row_shift: row.into(),
        }
    }

    /// (b) Reference dilation: `u256` shifts (mul/div) with row and column masks, no invariant.
    fn expand(self: @MaskLayout, frontier: u256) -> u256 {
        let masks = *self;
        let west = (frontier & masks.not_left) * 2;
        let east = (frontier & masks.not_right) / 2;
        let pairs_west = frontier | west;
        let pairs_east = frontier | east;
        // Even rows reach {x-1, x} above and below, odd rows {x, x+1}
        let vertical = (pairs_east & masks.even) | (pairs_west & masks.odd);
        let up = (vertical & masks.not_top) * masks.row_shift;
        let down = vertical / masks.row_shift;
        pairs_west | pairs_east | up | down
    }
}

#[generate_trait]
pub impl Variants of VariantsTrait {
    /// (a') Felt dilation with the West shift converted from a felt instead of a `u256` add.
    fn expand_felt_double(layout: @Layout, frontier: u256) -> u256 {
        let layout = *layout;
        let felt = Bits::to_felt(frontier);
        let double: u256 = (felt + felt).into();
        let pairs = frontier | double;
        let pairs_even = Bits::to_felt(pairs & layout.even);
        let pairs_odd = Bits::to_felt(pairs) - pairs_even;
        let up = pairs_even * layout.up_even + pairs_odd * layout.up_odd;
        let down = pairs_even * layout.down_even + pairs_odd * layout.down_odd;
        let east = felt * INV_2;
        pairs | east.into() | up.into() | down.into()
    }

    /// (a'') Felt dilation, horizontal triple then vertical from the parity-selected pairs.
    fn expand_felt_vertical(layout: @Layout, frontier: u256) -> u256 {
        let layout = *layout;
        let pairs_west = frontier | (frontier + frontier);
        let west_felt = Bits::to_felt(pairs_west);
        // {x-1, x} = pairs_west / 2
        let pairs_east: u256 = (west_felt * INV_2).into();
        let vertical = Bits::to_felt(pairs_east & layout.even)
            + west_felt
            - Bits::to_felt(pairs_west & layout.even);
        let up = vertical * layout.up_odd;
        let down = vertical * layout.down_odd;
        pairs_west | pairs_east | up.into() | down.into()
    }

    /// (c) Per-limb `u128` dilation: same felt shifts, set operations on explicit limbs.
    fn expand_limbs(layout: @Layout, low: u128, high: u128) -> (u128, u128) {
        let layout = *layout;
        let felt: felt252 = low.into() + high.into() * 0x100000000000000000000000000000000;
        let double: u256 = (felt + felt).into();
        let pairs_low = low | double.low;
        let pairs_high = high | double.high;
        let even_low = pairs_low & layout.even.low;
        let even_high = pairs_high & layout.even.high;
        let pairs_even: felt252 = even_low.into()
            + even_high.into() * 0x100000000000000000000000000000000;
        let pairs_felt: felt252 = pairs_low.into()
            + pairs_high.into() * 0x100000000000000000000000000000000;
        let pairs_odd = pairs_felt - pairs_even;
        let up: u256 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd).into();
        let down: u256 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd).into();
        let east: u256 = (felt * INV_2).into();
        (pairs_low | east.low | up.low | down.low, pairs_high | east.high | up.high | down.high)
    }

    /// (c'') Single-limb dilation, West shift through a felt instead of a `u128` add.
    fn expand_small_felt_double(layout: @Layout, frontier: u128) -> u128 {
        let layout = *layout;
        let felt: felt252 = frontier.into();
        let double: u128 = (felt + felt).try_into().unwrap();
        let pairs = frontier | double;
        let pairs_even: felt252 = (pairs & layout.even.low).into();
        let pairs_odd = pairs.into() - pairs_even;
        let up: u128 = (pairs_even * layout.up_even + pairs_odd * layout.up_odd)
            .try_into()
            .unwrap();
        let down: u128 = (pairs_even * layout.down_even + pairs_odd * layout.down_odd)
            .try_into()
            .unwrap();
        let east: u128 = (felt * INV_2).try_into().unwrap();
        pairs | east | up | down
    }

    /// Sequential form: every neighbour shift is ANDed with the unvisited set and subtracted.
    /// Returns the next frontier and the remaining unvisited set.
    fn step_sequential(layout: @Layout, frontier: u256, unvisited: u256) -> (u256, u256) {
        let layout = *layout;
        let felt = Bits::to_felt(frontier);
        let even = Bits::to_felt(frontier & layout.even);
        let odd = felt - even;
        let mut next: felt252 = 0;
        let mut left = Bits::to_felt(unvisited);
        let shifts: [felt252; 6] = [
            felt * 2, felt * INV_2, even * layout.up_even + odd * layout.up_odd,
            even * layout.up_odd + odd * layout.up_odd * 2,
            even * layout.down_even + odd * layout.down_odd,
            even * layout.down_odd + odd * layout.down_odd * 2,
        ];
        let mut shifts = shifts.span();
        while let Option::Some(shift) = shifts.pop_front() {
            let hit = Bits::to_felt((*shift).into() & left.into());
            next += hit;
            left -= hit;
        }
        (next.into(), left.into())
    }

    /// Scalar dilation through `neighbor`, the independent reference of the references.
    fn expand_scalar(width: u8, height: u8, frontier: u256) -> u256 {
        let size = width * height;
        let mut result: u256 = frontier;
        let mut index: u8 = 0;
        while index != size {
            if Bits::get(frontier, index) {
                let mut directions = array![
                    Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
                    Direction::SouthWest, Direction::SouthEast,
                ]
                    .span();
                while let Option::Some(direction) = directions.pop_front() {
                    if let Option::Some(next) =
                        LayoutTrait::neighbor(width, height, index, *direction) {
                        result = result | Bits::pow(next).into();
                    }
                }
            }
            index += 1;
        }
        result
    }

    /// Shortest path length by layered scalar BFS over `grid`, 0 if unreachable or equal.
    fn bfs_distance(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u32 {
        let layers = Self::bfs_layers(grid, width, height, from);
        let mut layers = layers.span();
        let mut depth: u32 = 0;
        while let Option::Some(layer) = layers.pop_front() {
            if Bits::get((*layer).into(), to) {
                return depth;
            }
            depth += 1;
        }
        0
    }

    /// BFS layers (bitmaps) from a position over the walkable tiles of `grid`.
    fn bfs_layers(grid: felt252, width: u8, height: u8, from: u8) -> Array<felt252> {
        let grid: u256 = grid.into();
        let mut layers: Array<felt252> = array![];
        let mut frontier: u256 = Bits::pow(from).into();
        let mut visited: u256 = frontier;
        while frontier != 0 {
            layers.append(Bits::to_felt(frontier));
            let next = Self::expand_scalar(width, height, frontier) & grid;
            frontier = next & ~visited;
            visited = visited | frontier;
        }
        layers
    }

    /// Distance with one division by `2W` per position instead of two divisions.
    fn distance_split(width: u8, from: u8, to: u8) -> u8 {
        let period: NonZero<u8> = (2 * width).try_into().unwrap();
        let (half_from, rem_from) = DivRem::div_rem(from, period);
        let (half_to, rem_to) = DivRem::div_rem(to, period);
        let (x_from, y_from) = if rem_from < width {
            (rem_from, 2 * half_from)
        } else {
            (rem_from - width, 2 * half_from + 1)
        };
        let (x_to, y_to) = if rem_to < width {
            (rem_to, 2 * half_to)
        } else {
            (rem_to - width, 2 * half_to + 1)
        };
        let lhs = x_to + half_from;
        let rhs = x_from + half_to;
        let (dq, dq_negative) = if lhs >= rhs {
            (lhs - rhs, false)
        } else {
            (rhs - lhs, true)
        };
        let (dr, dr_negative) = if y_to >= y_from {
            (y_to - y_from, false)
        } else {
            (y_from - y_to, true)
        };
        if dq_negative == dr_negative {
            dq + dr
        } else if dq > dr {
            dq
        } else {
            dr
        }
    }

    /// Neighbour mask from 6 table lookups instead of one lookup and one product.
    fn neighbour_mask_lookups(width: u8, position: u8) -> felt252 {
        let (_, odd) = LayoutTrait::parity(width, position);
        let base = Bits::pow(position - 1) + Bits::pow(position + 1);
        if odd {
            base
                + Bits::pow(position + width)
                + Bits::pow(position + width + 1)
                + Bits::pow(position - width)
                + Bits::pow(position + 1 - width)
        } else {
            base
                + Bits::pow(position + width - 1)
                + Bits::pow(position + width)
                + Bits::pow(position - width - 1)
                + Bits::pow(position - width)
        }
    }

    /// Right shift by a field division instead of a product with the inverse table.
    fn shr_div(value: felt252, count: u8) -> felt252 {
        felt252_div(value, Bits::pow(count).try_into().unwrap())
    }

    /// `origami_map` bit test: two `u256` divisions.
    fn get_divmod(value: u256, index: u8) -> bool {
        let pow: u256 = Bits::pow(index).into();
        (value / pow) % 2 == 1
    }

    /// Bit set with an OR instead of an addition.
    fn set_or(value: u256, index: u8) -> u256 {
        if index < 128 {
            u256 { low: value.low | *POW128.span().at(index.into()), high: value.high }
        } else {
            u256 { low: value.low, high: value.high | *POW128.span().at(index.into() - 128) }
        }
    }

    /// Fisher-Yates over 6 slots with 5 draws, packed like `Rng::shuffle6`.
    fn shuffle6_fisher_yates(ref pool: u128) -> u32 {
        let mut slots: Array<u32> = array![0, 1, 2, 3, 4, 5];
        let mut packed: u32 = 0;
        let mut factor: u32 = 1;
        let mut remaining: u128 = 6;
        while remaining != 0 {
            let (rest, pick) = DivRem::div_rem(pool, remaining.try_into().unwrap());
            pool = rest;
            // Take slot `pick` out, keep the others in order
            let mut next: Array<u32> = array![];
            let mut index: u128 = 0;
            let mut span = slots.span();
            while let Option::Some(slot) = span.pop_front() {
                if index == pick {
                    packed += *slot * factor;
                } else {
                    next.append(*slot);
                }
                index += 1;
            }
            slots = next;
            factor *= 16;
            remaining -= 1;
        }
        packed
    }

    /// Power of two through a 252-arm match instead of a constant table lookup.
    fn pow_match(exp: u8) -> felt252 {
        match exp {
            0 => 0x1,
            1 => 0x2,
            2 => 0x4,
            3 => 0x8,
            4 => 0x10,
            5 => 0x20,
            6 => 0x40,
            7 => 0x80,
            8 => 0x100,
            9 => 0x200,
            10 => 0x400,
            11 => 0x800,
            12 => 0x1000,
            13 => 0x2000,
            14 => 0x4000,
            15 => 0x8000,
            16 => 0x10000,
            17 => 0x20000,
            18 => 0x40000,
            19 => 0x80000,
            20 => 0x100000,
            21 => 0x200000,
            22 => 0x400000,
            23 => 0x800000,
            24 => 0x1000000,
            25 => 0x2000000,
            26 => 0x4000000,
            27 => 0x8000000,
            28 => 0x10000000,
            29 => 0x20000000,
            30 => 0x40000000,
            31 => 0x80000000,
            32 => 0x100000000,
            33 => 0x200000000,
            34 => 0x400000000,
            35 => 0x800000000,
            36 => 0x1000000000,
            37 => 0x2000000000,
            38 => 0x4000000000,
            39 => 0x8000000000,
            40 => 0x10000000000,
            41 => 0x20000000000,
            42 => 0x40000000000,
            43 => 0x80000000000,
            44 => 0x100000000000,
            45 => 0x200000000000,
            46 => 0x400000000000,
            47 => 0x800000000000,
            48 => 0x1000000000000,
            49 => 0x2000000000000,
            50 => 0x4000000000000,
            51 => 0x8000000000000,
            52 => 0x10000000000000,
            53 => 0x20000000000000,
            54 => 0x40000000000000,
            55 => 0x80000000000000,
            56 => 0x100000000000000,
            57 => 0x200000000000000,
            58 => 0x400000000000000,
            59 => 0x800000000000000,
            60 => 0x1000000000000000,
            61 => 0x2000000000000000,
            62 => 0x4000000000000000,
            63 => 0x8000000000000000,
            64 => 0x10000000000000000,
            65 => 0x20000000000000000,
            66 => 0x40000000000000000,
            67 => 0x80000000000000000,
            68 => 0x100000000000000000,
            69 => 0x200000000000000000,
            70 => 0x400000000000000000,
            71 => 0x800000000000000000,
            72 => 0x1000000000000000000,
            73 => 0x2000000000000000000,
            74 => 0x4000000000000000000,
            75 => 0x8000000000000000000,
            76 => 0x10000000000000000000,
            77 => 0x20000000000000000000,
            78 => 0x40000000000000000000,
            79 => 0x80000000000000000000,
            80 => 0x100000000000000000000,
            81 => 0x200000000000000000000,
            82 => 0x400000000000000000000,
            83 => 0x800000000000000000000,
            84 => 0x1000000000000000000000,
            85 => 0x2000000000000000000000,
            86 => 0x4000000000000000000000,
            87 => 0x8000000000000000000000,
            88 => 0x10000000000000000000000,
            89 => 0x20000000000000000000000,
            90 => 0x40000000000000000000000,
            91 => 0x80000000000000000000000,
            92 => 0x100000000000000000000000,
            93 => 0x200000000000000000000000,
            94 => 0x400000000000000000000000,
            95 => 0x800000000000000000000000,
            96 => 0x1000000000000000000000000,
            97 => 0x2000000000000000000000000,
            98 => 0x4000000000000000000000000,
            99 => 0x8000000000000000000000000,
            100 => 0x10000000000000000000000000,
            101 => 0x20000000000000000000000000,
            102 => 0x40000000000000000000000000,
            103 => 0x80000000000000000000000000,
            104 => 0x100000000000000000000000000,
            105 => 0x200000000000000000000000000,
            106 => 0x400000000000000000000000000,
            107 => 0x800000000000000000000000000,
            108 => 0x1000000000000000000000000000,
            109 => 0x2000000000000000000000000000,
            110 => 0x4000000000000000000000000000,
            111 => 0x8000000000000000000000000000,
            112 => 0x10000000000000000000000000000,
            113 => 0x20000000000000000000000000000,
            114 => 0x40000000000000000000000000000,
            115 => 0x80000000000000000000000000000,
            116 => 0x100000000000000000000000000000,
            117 => 0x200000000000000000000000000000,
            118 => 0x400000000000000000000000000000,
            119 => 0x800000000000000000000000000000,
            120 => 0x1000000000000000000000000000000,
            121 => 0x2000000000000000000000000000000,
            122 => 0x4000000000000000000000000000000,
            123 => 0x8000000000000000000000000000000,
            124 => 0x10000000000000000000000000000000,
            125 => 0x20000000000000000000000000000000,
            126 => 0x40000000000000000000000000000000,
            127 => 0x80000000000000000000000000000000,
            128 => 0x100000000000000000000000000000000,
            129 => 0x200000000000000000000000000000000,
            130 => 0x400000000000000000000000000000000,
            131 => 0x800000000000000000000000000000000,
            132 => 0x1000000000000000000000000000000000,
            133 => 0x2000000000000000000000000000000000,
            134 => 0x4000000000000000000000000000000000,
            135 => 0x8000000000000000000000000000000000,
            136 => 0x10000000000000000000000000000000000,
            137 => 0x20000000000000000000000000000000000,
            138 => 0x40000000000000000000000000000000000,
            139 => 0x80000000000000000000000000000000000,
            140 => 0x100000000000000000000000000000000000,
            141 => 0x200000000000000000000000000000000000,
            142 => 0x400000000000000000000000000000000000,
            143 => 0x800000000000000000000000000000000000,
            144 => 0x1000000000000000000000000000000000000,
            145 => 0x2000000000000000000000000000000000000,
            146 => 0x4000000000000000000000000000000000000,
            147 => 0x8000000000000000000000000000000000000,
            148 => 0x10000000000000000000000000000000000000,
            149 => 0x20000000000000000000000000000000000000,
            150 => 0x40000000000000000000000000000000000000,
            151 => 0x80000000000000000000000000000000000000,
            152 => 0x100000000000000000000000000000000000000,
            153 => 0x200000000000000000000000000000000000000,
            154 => 0x400000000000000000000000000000000000000,
            155 => 0x800000000000000000000000000000000000000,
            156 => 0x1000000000000000000000000000000000000000,
            157 => 0x2000000000000000000000000000000000000000,
            158 => 0x4000000000000000000000000000000000000000,
            159 => 0x8000000000000000000000000000000000000000,
            160 => 0x10000000000000000000000000000000000000000,
            161 => 0x20000000000000000000000000000000000000000,
            162 => 0x40000000000000000000000000000000000000000,
            163 => 0x80000000000000000000000000000000000000000,
            164 => 0x100000000000000000000000000000000000000000,
            165 => 0x200000000000000000000000000000000000000000,
            166 => 0x400000000000000000000000000000000000000000,
            167 => 0x800000000000000000000000000000000000000000,
            168 => 0x1000000000000000000000000000000000000000000,
            169 => 0x2000000000000000000000000000000000000000000,
            170 => 0x4000000000000000000000000000000000000000000,
            171 => 0x8000000000000000000000000000000000000000000,
            172 => 0x10000000000000000000000000000000000000000000,
            173 => 0x20000000000000000000000000000000000000000000,
            174 => 0x40000000000000000000000000000000000000000000,
            175 => 0x80000000000000000000000000000000000000000000,
            176 => 0x100000000000000000000000000000000000000000000,
            177 => 0x200000000000000000000000000000000000000000000,
            178 => 0x400000000000000000000000000000000000000000000,
            179 => 0x800000000000000000000000000000000000000000000,
            180 => 0x1000000000000000000000000000000000000000000000,
            181 => 0x2000000000000000000000000000000000000000000000,
            182 => 0x4000000000000000000000000000000000000000000000,
            183 => 0x8000000000000000000000000000000000000000000000,
            184 => 0x10000000000000000000000000000000000000000000000,
            185 => 0x20000000000000000000000000000000000000000000000,
            186 => 0x40000000000000000000000000000000000000000000000,
            187 => 0x80000000000000000000000000000000000000000000000,
            188 => 0x100000000000000000000000000000000000000000000000,
            189 => 0x200000000000000000000000000000000000000000000000,
            190 => 0x400000000000000000000000000000000000000000000000,
            191 => 0x800000000000000000000000000000000000000000000000,
            192 => 0x1000000000000000000000000000000000000000000000000,
            193 => 0x2000000000000000000000000000000000000000000000000,
            194 => 0x4000000000000000000000000000000000000000000000000,
            195 => 0x8000000000000000000000000000000000000000000000000,
            196 => 0x10000000000000000000000000000000000000000000000000,
            197 => 0x20000000000000000000000000000000000000000000000000,
            198 => 0x40000000000000000000000000000000000000000000000000,
            199 => 0x80000000000000000000000000000000000000000000000000,
            200 => 0x100000000000000000000000000000000000000000000000000,
            201 => 0x200000000000000000000000000000000000000000000000000,
            202 => 0x400000000000000000000000000000000000000000000000000,
            203 => 0x800000000000000000000000000000000000000000000000000,
            204 => 0x1000000000000000000000000000000000000000000000000000,
            205 => 0x2000000000000000000000000000000000000000000000000000,
            206 => 0x4000000000000000000000000000000000000000000000000000,
            207 => 0x8000000000000000000000000000000000000000000000000000,
            208 => 0x10000000000000000000000000000000000000000000000000000,
            209 => 0x20000000000000000000000000000000000000000000000000000,
            210 => 0x40000000000000000000000000000000000000000000000000000,
            211 => 0x80000000000000000000000000000000000000000000000000000,
            212 => 0x100000000000000000000000000000000000000000000000000000,
            213 => 0x200000000000000000000000000000000000000000000000000000,
            214 => 0x400000000000000000000000000000000000000000000000000000,
            215 => 0x800000000000000000000000000000000000000000000000000000,
            216 => 0x1000000000000000000000000000000000000000000000000000000,
            217 => 0x2000000000000000000000000000000000000000000000000000000,
            218 => 0x4000000000000000000000000000000000000000000000000000000,
            219 => 0x8000000000000000000000000000000000000000000000000000000,
            220 => 0x10000000000000000000000000000000000000000000000000000000,
            221 => 0x20000000000000000000000000000000000000000000000000000000,
            222 => 0x40000000000000000000000000000000000000000000000000000000,
            223 => 0x80000000000000000000000000000000000000000000000000000000,
            224 => 0x100000000000000000000000000000000000000000000000000000000,
            225 => 0x200000000000000000000000000000000000000000000000000000000,
            226 => 0x400000000000000000000000000000000000000000000000000000000,
            227 => 0x800000000000000000000000000000000000000000000000000000000,
            228 => 0x1000000000000000000000000000000000000000000000000000000000,
            229 => 0x2000000000000000000000000000000000000000000000000000000000,
            230 => 0x4000000000000000000000000000000000000000000000000000000000,
            231 => 0x8000000000000000000000000000000000000000000000000000000000,
            232 => 0x10000000000000000000000000000000000000000000000000000000000,
            233 => 0x20000000000000000000000000000000000000000000000000000000000,
            234 => 0x40000000000000000000000000000000000000000000000000000000000,
            235 => 0x80000000000000000000000000000000000000000000000000000000000,
            236 => 0x100000000000000000000000000000000000000000000000000000000000,
            237 => 0x200000000000000000000000000000000000000000000000000000000000,
            238 => 0x400000000000000000000000000000000000000000000000000000000000,
            239 => 0x800000000000000000000000000000000000000000000000000000000000,
            240 => 0x1000000000000000000000000000000000000000000000000000000000000,
            241 => 0x2000000000000000000000000000000000000000000000000000000000000,
            242 => 0x4000000000000000000000000000000000000000000000000000000000000,
            243 => 0x8000000000000000000000000000000000000000000000000000000000000,
            244 => 0x10000000000000000000000000000000000000000000000000000000000000,
            245 => 0x20000000000000000000000000000000000000000000000000000000000000,
            246 => 0x40000000000000000000000000000000000000000000000000000000000000,
            247 => 0x80000000000000000000000000000000000000000000000000000000000000,
            248 => 0x100000000000000000000000000000000000000000000000000000000000000,
            249 => 0x200000000000000000000000000000000000000000000000000000000000000,
            250 => 0x400000000000000000000000000000000000000000000000000000000000000,
            _ => 0x800000000000000000000000000000000000000000000000000000000000000,
        }
    }
}
