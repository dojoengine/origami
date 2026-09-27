//! Cave generator: synchronous bit-sliced cellular automaton (lot L4).
//!
//! The whole board is one generation: the 6 neighbour planes are field shifts of the grid, a
//! carry-save adder counts them bit-sliced, and the rule is two set operations. Rule `B4/S2`: a
//! wall with at least 4 floor neighbours becomes floor, a floor with at least 2 stays floor.

// Internal imports

use origami_hexmap::finders::bfs::BfsInternal;
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Largest board of the single-limb path.
const SMALL_SIZE: u8 = 128;

/// Errors module.
pub mod errors {
    pub const CAVER_POSITION_NOT_FLOOR: felt252 = 'Caver: position not floor';
}

/// Shift constants of the neighbour planes.
#[derive(Copy, Drop)]
struct Shifts {
    /// 2^(W-1)
    up_even: felt252,
    /// 2^W
    up_odd: felt252,
    /// 2^(W+1)
    up_wide: felt252,
    /// 2^-(W+1)
    down_even: felt252,
    /// 2^-W
    down_odd: felt252,
    /// 2^-(W-1)
    down_wide: felt252,
}

#[generate_trait]
pub impl Caver of CaverTrait {
    /// Generate a cave.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `order` - The number of generations
    /// * `seed` - The seed
    /// # Returns
    /// * The generated grid
    fn generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
        // [Check] Dimensions
        Asserter::assert_valid_dimension(width, height);
        // [Compute] Initial fill: half of the interior
        if order == 0 {
            let interior = LayoutTrait::interior(width, height);
            return Bits::to_felt(CaverInternal::fill(interior, seed));
        }
        let (layout, interior) = LayoutTrait::with_interior(width, height);
        let grid = CaverInternal::fill(interior, seed);
        // [Compute] Generations
        if width * height <= SMALL_SIZE {
            CaverInternal::evolve_small(@layout, grid.low, order)
        } else {
            CaverInternal::evolve(@layout, grid, order)
        }
    }

    /// Keep the floor tiles connected to a position: the flood fill of `Bfs::reachable`, one
    /// dilation per layer on the frontier only (see `GAS.md`, P1).
    /// # Arguments
    /// * `grid` - The grid, interior tiles only
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The position, a floor tile
    /// # Returns
    /// * The connected component of `from`
    /// # Panics
    /// * If `from` is not floor, or the dimensions are invalid
    fn keep_component(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
        // [Check] Start is floor
        let open: u256 = grid.into();
        assert(Bits::get(open, from), errors::CAVER_POSITION_NOT_FLOOR);
        // [Return] Flood fill, the grid has no open edge tile
        Asserter::assert_valid_dimension(width, height);
        BfsInternal::component(open, width, height, from)
    }
}

#[generate_trait]
impl CaverInternal of CaverInternalTrait {
    /// Random initial fill, each interior tile is floor with probability 1/2.
    /// # Arguments
    /// * `interior` - The interior mask
    /// * `seed` - The seed
    /// # Returns
    /// * The initial grid, interior tiles only
    #[inline]
    fn fill(interior: felt252, seed: felt252) -> u256 {
        let (noise, _, _) = core::poseidon::hades_permutation(seed, 0, 2);
        Bits::and(noise.into(), interior.into())
    }

    /// Run `order` generations of the automaton on a grid of interior tiles.
    /// # Arguments
    /// * `layout` - The layout
    /// * `grid` - The grid, interior tiles only
    /// * `order` - The number of generations, `0` returns the grid
    /// # Returns
    /// * The grid after `order` generations
    fn evolve(layout: @Layout, grid: u256, order: u8) -> felt252 {
        let layout = *layout;
        let shifts = Self::shifts(@layout);
        let mut felt = Bits::to_felt(grid);
        let mut grid = grid;
        let mut order = order;
        while order != 0 {
            order -= 1;
            grid = Self::step(@shifts, layout.even, grid, felt);
            felt = Bits::to_felt(grid);
        }
        felt
    }

    /// `evolve` for boards of at most 128 bits, on a single limb.
    /// # Arguments
    /// * `layout` - The layout, `W * H <= 128`
    /// * `grid` - The grid, interior tiles only
    /// * `order` - The number of generations, `0` returns the grid
    /// # Returns
    /// * The grid after `order` generations
    fn evolve_small(layout: @Layout, grid: u128, order: u8) -> felt252 {
        let layout = *layout;
        let shifts = Self::shifts(@layout);
        let mut felt: felt252 = grid.into();
        let mut grid = grid;
        let mut order = order;
        while order != 0 {
            order -= 1;
            grid = Self::step_small(@shifts, layout.even.low, grid, felt);
            felt = grid.into();
        }
        felt
    }

    /// Shift constants of the neighbour planes.
    #[inline]
    fn shifts(layout: @Layout) -> Shifts {
        let layout = *layout;
        Shifts {
            up_even: layout.up_even,
            up_odd: layout.up_odd,
            up_wide: layout.up_odd + layout.up_odd,
            down_even: layout.down_even,
            down_odd: layout.down_odd,
            down_wide: layout.down_odd + layout.down_odd,
        }
    }

    /// One generation on the whole board.
    /// # Arguments
    /// * `shifts` - The shift constants
    /// * `even` - The even rows mask
    /// * `grid` - The grid, interior tiles only
    /// * `felt` - The same grid as a felt
    /// # Returns
    /// * The next grid, interior tiles only
    #[inline]
    fn step(shifts: @Shifts, even: u256, grid: u256, felt: felt252) -> u256 {
        let shifts = *shifts;
        // [Compute] Split by row parity
        let (low, _, _) = Bits::bitwise(grid.low, even.low);
        let (high, _, _) = Bits::bitwise(grid.high, even.high);
        let grid_even = Bits::to_felt(u256 { low, high });
        let grid_odd = felt - grid_even;
        // [Compute] Neighbour planes: bit i of a plane is the grid at one neighbour of i
        let east: u256 = (felt + felt).into();
        let west: u256 = (felt * INV_2).into();
        let north: u256 = (felt * shifts.down_odd).into();
        let north_other: u256 = (grid_odd * shifts.down_wide + grid_even * shifts.down_even).into();
        let south: u256 = (felt * shifts.up_odd).into();
        let south_other: u256 = (grid_odd * shifts.up_wide + grid_even * shifts.up_even).into();
        // [Compute] Rule, per limb
        let low = Self::rule(
            grid.low, east.low, west.low, north.low, north_other.low, south.low, south_other.low,
        );
        let high = Self::rule(
            grid.high,
            east.high,
            west.high,
            north.high,
            north_other.high,
            south.high,
            south_other.high,
        );
        // [Return] Next grid
        u256 { low, high }
    }

    /// One generation on a single limb, `W * H <= 128`.
    /// # Arguments
    /// * `shifts` - The shift constants
    /// * `even` - The even rows mask
    /// * `grid` - The grid, interior tiles only
    /// * `felt` - The same grid as a felt
    /// # Returns
    /// * The next grid, interior tiles only
    #[inline]
    fn step_small(shifts: @Shifts, even: u128, grid: u128, felt: felt252) -> u128 {
        let shifts = *shifts;
        let (grid_even, _, _) = Bits::bitwise(grid, even);
        let grid_even: felt252 = grid_even.into();
        let grid_odd = felt - grid_even;
        Self::rule(
            grid,
            (felt + felt).try_into().unwrap(),
            (felt * INV_2).try_into().unwrap(),
            (felt * shifts.down_odd).try_into().unwrap(),
            (grid_odd * shifts.down_wide + grid_even * shifts.down_even).try_into().unwrap(),
            (felt * shifts.up_odd).try_into().unwrap(),
            (grid_odd * shifts.up_wide + grid_even * shifts.up_even).try_into().unwrap(),
        )
    }

    /// Rule `B4/S2` on one limb of the 6 neighbour planes: `b2 | (grid & b1)`, where
    /// `count = 4 * b2 + 2 * b1 + b0` (`b0` is not needed). Born tiles are interior: a border tile
    /// has at most 3 interior neighbours.
    /// 9 builtin applications, carries as additions of disjoint bitmaps.
    /// # Returns
    /// * The next limb
    #[inline(always)]
    fn rule(grid: u128, a: u128, b: u128, c: u128, d: u128, e: u128, f: u128) -> u128 {
        // [Compute] Full adders on (a, b, c) and (d, e, f)
        let (ab, x, _) = Bits::bitwise(a, b);
        let (xc, s1, _) = Bits::bitwise(x, c);
        let (de, y, _) = Bits::bitwise(d, e);
        let (yf, s2, _) = Bits::bitwise(y, f);
        // [Compute] Half adder on the sums: weight-2 carry
        let (c3, _, _) = Bits::bitwise(s1, s2);
        // [Compute] Full adder on the weight-2 carries
        let (c12, x12, _) = Bits::bitwise(ab + xc, de + yf);
        let (x3, b1, _) = Bits::bitwise(x12, c3);
        // [Return] Born with 4+, survive with 2+
        let (survive, _, _) = Bits::bitwise(grid, b1);
        let (_, _, next) = Bits::bitwise(c12 + x3, survive);
        next
    }
}

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::tests::bench_caver::{fill_half, keep_component_dilation, reference};
    use origami_hexmap::tests::fixtures::{UNREACHABLE_17X14, UNREACHABLE_17X14_FAR_FROM};

    // Local imports

    use super::Caver;

    // Constants

    const SEED: felt252 = 'CAVE';

    /// Invariants of a generated cave: interior only, deterministic, equal to the scalar
    /// reference automaton (B4/S2) run on the same initial fill.
    fn check_generate(width: u8, height: u8) {
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let mut seed: felt252 = 0;
        while seed != 4 {
            let fill = fill_half(width, height, seed);
            let mut order: u8 = 0;
            while order != 5 {
                let grid = Caver::generate(width, height, order, seed);
                let open: u256 = grid.into();
                assert!(open & interior == open, "border ring must stay closed");
                assert!(grid == Caver::generate(width, height, order, seed));
                assert!(grid == reference(fill, width, height, order, 4, 2));
                order += 1;
            }
            seed += 1;
        }
    }

    #[test]
    fn test_caver_generate_17x14() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        //  0 0 1 1 1 0 0 1 0 0 0 0 0 0 1 0 0
        // 0 1 1 1 1 1 1 1 1 0 0 0 0 0 1 1 0
        //  0 1 1 1 1 1 1 1 1 0 1 1 1 1 1 0 0
        // 0 1 1 1 1 1 1 1 1 0 0 1 1 1 0 0 0
        //  0 1 1 1 1 1 0 0 0 0 1 1 1 0 0 0 0
        // 0 0 1 1 1 1 0 0 0 1 1 1 1 1 0 0 0
        //  0 1 1 1 1 1 0 0 0 1 1 1 1 1 1 1 0
        // 0 1 1 1 1 1 1 0 0 1 1 1 1 1 1 1 0
        //  0 1 1 1 1 1 1 0 1 1 1 1 1 1 1 1 0
        // 0 0 1 1 1 1 1 0 0 1 0 0 1 1 1 0 0
        //  0 0 1 1 1 1 1 1 1 1 0 1 1 1 0 0 0
        // 0 0 0 0 1 1 1 1 1 1 0 0 1 0 0 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid = Caver::generate(17, 14, 3, SEED);
        assert!(grid == 0x72047f833fdf1fe70f8703c7c3e3f9f9fcfdfe3e4e1fee03f200000);
    }

    #[test]
    fn test_caver_generate_19x13() {
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 0 0 1 1 1 1 1 0 0 0 0 1 0 0 0
        //  0 1 1 1 1 1 1 1 1 1 1 1 0 0 1 1 1 0 0
        // 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
        //  0 1 1 1 1 1 1 1 1 1 0 0 1 1 1 0 0 0 0
        // 0 0 1 1 1 0 0 1 1 1 1 0 0 1 1 0 0 0 0
        //  0 1 1 1 1 0 0 0 1 1 1 0 0 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 0 1 1 1 1 0 1 1 1 1 0 0
        //  0 0 1 1 1 1 1 1 1 1 1 0 0 1 1 1 1 0 0
        // 0 0 0 1 1 1 1 1 1 1 1 0 0 1 1 1 1 0 0
        //  0 0 1 1 0 0 1 1 1 1 1 0 0 0 1 1 0 0 0
        // 0 0 0 0 0 0 0 0 1 1 1 1 0 0 0 1 1 0 0
        //  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid = Caver::generate(19, 13, 3, SEED);
        assert!(grid == 0x33e10ffe70ffff3fe7039e60f1cf0fbde1ff3c1fe7867c6003c600000);
    }

    #[test]
    fn test_caver_generate_7x7() {
        //  0 0 0 0 0 0 0
        // 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0
        // 0 0 1 1 0 0 0
        //  0 1 1 0 0 0 0
        // 0 0 0 0 0 0 0
        //  0 0 0 0 0 0 0
        let grid = Caver::generate(7, 7, 3, SEED);
        assert!(grid == 0x30c0000);
    }

    #[test]
    fn test_caver_generate_order_zero() {
        // Initial fill, about half of the interior
        let grid = Caver::generate(17, 14, 0, SEED);
        assert!(grid == 0x534e7d202fd79ea60b2882c2c35799e8d42b1a665d1c2603f640000);
        assert!(grid == fill_half(17, 14, SEED));
    }

    #[test]
    fn test_caver_generate_3x3() {
        // A single interior tile: never has a floor neighbour
        assert!(Caver::generate(3, 3, 0, 2) == 0x10);
        assert!(Caver::generate(3, 3, 1, 2) == 0);
        check_generate(3, 3);
    }

    #[test]
    fn test_caver_generate_invariants_7x7() {
        check_generate(7, 7);
    }

    #[test]
    fn test_caver_generate_invariants_11x11() {
        check_generate(11, 11);
    }

    #[test]
    fn test_caver_generate_invariants_17x14() {
        check_generate(17, 14);
    }

    #[test]
    fn test_caver_generate_invariants_19x13() {
        check_generate(19, 13);
    }

    #[test]
    fn test_caver_generate_invariants_83x3() {
        check_generate(83, 3);
    }

    #[test]
    fn test_caver_generate_invariants_3x83() {
        check_generate(3, 83);
    }

    #[test]
    fn test_caver_generate_invariants_25x10() {
        check_generate(25, 10);
    }

    #[test]
    fn test_caver_generate_invariants_16x8() {
        // 128 bits: largest board of the single-limb path
        check_generate(16, 8);
    }

    #[test]
    fn test_caver_generate_seeds_differ() {
        assert!(Caver::generate(17, 14, 3, 1) != Caver::generate(17, 14, 3, 2));
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_caver_generate_revert_too_small() {
        Caver::generate(2, 17, 3, SEED);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_caver_generate_revert_too_large() {
        Caver::generate(16, 16, 3, SEED);
    }

    #[test]
    fn test_caver_keep_component_split() {
        // Left half (x = 1..7) of the board split by the wall column x = 8
        let mut expected: felt252 = 0;
        let mut y: u8 = 1;
        while y != 13 {
            expected += 0xfe * Bits::pow(17 * y);
            y += 1;
        }
        let component = Caver::keep_component(
            UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM,
        );
        assert!(component == expected);
        let other = Caver::keep_component(UNREACHABLE_17X14, 17, 14, 219);
        assert!(component + other == UNREACHABLE_17X14);
    }

    #[test]
    fn test_caver_keep_component_closed() {
        // The component is a subset of the cave, closed under dilation, and holds the start
        let layout = LayoutTrait::new(17, 14);
        let mut seed: felt252 = 1;
        while seed != 9 {
            let cave = Caver::generate(17, 14, 3, seed);
            let open: u256 = cave.into();
            let mut position: u8 = 18;
            while position < 220 {
                if Bits::get(open, position) {
                    let component: u256 = Caver::keep_component(cave, 17, 14, position).into();
                    assert!(component & open == component);
                    assert!(layout.expand(component) & open == component);
                    assert!(Bits::get(component, position));
                    let felt = Bits::to_felt(component);
                    assert!(felt == keep_component_dilation(cave, 17, 14, position));
                }
                position += 29;
            }
            seed += 1;
        }
    }

    #[test]
    fn test_caver_keep_component_single() {
        // 7x7 cave: one component of 4 tiles
        let cave = Caver::generate(7, 7, 3, SEED);
        assert!(Caver::keep_component(cave, 7, 7, 18) == cave);
    }

    #[test]
    #[should_panic(expected: 'Caver: position not floor')]
    fn test_caver_keep_component_revert_wall() {
        Caver::keep_component(UNREACHABLE_17X14, 17, 14, 25);
    }
}
