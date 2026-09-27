//! Constant fixture grids shared by every benchmark (generated offline).
//!
//! Pointy-top odd-r layout, `i = y * W + x`, printed like `HexPrinter`: top row first,
//! `x = 0` on the right, even rows indented by one space. `#` marks the endpoints.
//! Every grid only holds interior tiles. `*_DISTANCE` is the BFS path length (the number
//! of items of the path returned by a finder), 0 when the target is unreachable.

// EMPTY 17x14: every interior tile open.
// near: 129 -> 77 (3), far: 202 -> 18 (19)
//
// 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 # 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 # 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
pub const EMPTY_17X14: felt252 = 0xfffe7fff3fff9fffcfffe7fff3fff9fffcfffe7fff3fff9fffc0000;
pub const EMPTY_17X14_NEAR_FROM: u8 = 129;
pub const EMPTY_17X14_NEAR_TO: u8 = 77;
pub const EMPTY_17X14_NEAR_DISTANCE: u32 = 3;
pub const EMPTY_17X14_FAR_FROM: u8 = 202;
pub const EMPTY_17X14_FAR_TO: u8 = 18;
pub const EMPTY_17X14_FAR_DISTANCE: u32 = 19;

// CAVE 17x14: hex automaton, 60 % fill, 3 generations of B4/S2, largest component.
// near: 191 -> 139 (3), far: 52 -> 20 (24)
//
// 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
//  0 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0
// 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
// 0 0 1 1 1 1 1 1 1 1 1 0 0 1 1 1 0
//  0 0 1 1 1 1 0 0 0 1 0 0 0 1 1 1 0
// 0 0 1 1 1 1 0 0 0 0 0 0 0 1 1 1 0
//  0 1 1 1 1 1 0 0 0 1 1 0 0 1 1 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 # 0
//  0 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0
// 0 0 0 0 0 0 0 0 0 1 1 1 1 # 0 0 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
pub const CAVE_17X14: felt252 = 0xff803ffc3ffe1fffcfffe3fe71e238f01cf8ce7ff93ffc001f00000;
pub const CAVE_17X14_NEAR_FROM: u8 = 191;
pub const CAVE_17X14_NEAR_TO: u8 = 139;
pub const CAVE_17X14_NEAR_DISTANCE: u32 = 3;
pub const CAVE_17X14_FAR_FROM: u8 = 52;
pub const CAVE_17X14_FAR_TO: u8 = 20;
pub const CAVE_17X14_FAR_DISTANCE: u32 = 24;

// MAZE 17x14: recursive backtracker from (1, 1), order 0 carve rule.
// near: 66 -> 47 (3), far: 149 -> 18 (53)
//
// 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
//  0 0 1 1 0 0 1 1 1 0 1 1 1 1 0 1 0
// 0 1 1 0 0 1 1 0 0 0 1 0 0 0 1 1 0
//  0 0 1 1 1 0 1 1 1 1 0 0 1 0 0 0 0
// 0 0 1 0 0 0 1 0 0 0 0 1 1 0 1 1 0
//  0 1 0 # 1 0 1 0 1 1 1 0 0 1 0 1 0
// 0 0 1 0 0 1 0 1 1 0 0 1 1 1 0 1 0
//  0 0 1 0 0 1 0 0 0 1 0 0 0 1 0 1 0
// 0 0 0 1 0 1 0 1 1 1 0 1 1 0 0 1 0
//  0 0 0 1 0 1 1 0 0 1 1 0 1 0 1 0 0
// 0 1 1 1 0 0 0 1 0 1 0 0 0 1 0 1 0
//  0 0 0 1 1 0 0 0 0 1 0 1 0 1 0 1 0
// 0 1 1 1 0 1 1 1 1 1 0 0 1 1 0 # 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
pub const MAZE_17X14: felt252 = 0x677a66231de40886cb5ca259d1222857642cd471450c2a9df340000;
pub const MAZE_17X14_NEAR_FROM: u8 = 66;
pub const MAZE_17X14_NEAR_TO: u8 = 47;
pub const MAZE_17X14_NEAR_DISTANCE: u32 = 3;
pub const MAZE_17X14_FAR_FROM: u8 = 149;
pub const MAZE_17X14_FAR_TO: u8 = 18;
pub const MAZE_17X14_FAR_DISTANCE: u32 = 53;

// SERPENTINE 17x14: open odd rows joined by one tile at alternating ends, worst case.
// near: 93 -> 90 (3), far: 202 -> 32 (90)
//
// 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
// 0 # 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
// 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0
// 0 # 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
pub const SERPENTINE_17X14: felt252 = 0x7fff00009fffc80007fff00009fffc80007fff00009fffc0000;
pub const SERPENTINE_17X14_NEAR_FROM: u8 = 93;
pub const SERPENTINE_17X14_NEAR_TO: u8 = 90;
pub const SERPENTINE_17X14_NEAR_DISTANCE: u32 = 3;
pub const SERPENTINE_17X14_FAR_FROM: u8 = 202;
pub const SERPENTINE_17X14_FAR_TO: u8 = 32;
pub const SERPENTINE_17X14_FAR_DISTANCE: u32 = 90;

// UNREACHABLE 17x14: empty board split by a wall column at x = W / 2.
// near: 126 -> 128 (0), far: 18 -> 219 (0)
//
// 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
//  0 # 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
//  0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 1 0
// 0 1 1 1 1 1 1 1 0 1 1 1 1 1 1 # 0
//  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
pub const UNREACHABLE_17X14: felt252 = 0xfefe7f7f3fbf9fdfcfefe7f7f3fbf9fdfcfefe7f7f3fbf9fdfc0000;
pub const UNREACHABLE_17X14_NEAR_FROM: u8 = 126;
pub const UNREACHABLE_17X14_NEAR_TO: u8 = 128;
pub const UNREACHABLE_17X14_NEAR_DISTANCE: u32 = 0;
pub const UNREACHABLE_17X14_FAR_FROM: u8 = 18;
pub const UNREACHABLE_17X14_FAR_TO: u8 = 219;
pub const UNREACHABLE_17X14_FAR_DISTANCE: u32 = 0;

// EMPTY 7x7: every interior tile open.
// near: 30 -> 8 (3), far: 40 -> 8 (6)
//
//  0 0 0 0 0 0 0
// 0 # 1 1 1 1 0
//  0 1 1 1 1 1 0
// 0 1 1 1 1 1 0
//  0 1 1 1 1 1 0
// 0 1 1 1 1 # 0
//  0 0 0 0 0 0 0
pub const EMPTY_7X7: felt252 = 0x1f3e7cf9f00;
pub const EMPTY_7X7_NEAR_FROM: u8 = 30;
pub const EMPTY_7X7_NEAR_TO: u8 = 8;
pub const EMPTY_7X7_NEAR_DISTANCE: u32 = 3;
pub const EMPTY_7X7_FAR_FROM: u8 = 40;
pub const EMPTY_7X7_FAR_TO: u8 = 8;
pub const EMPTY_7X7_FAR_DISTANCE: u32 = 6;

// CAVE 7x7: hex automaton, 60 % fill, 3 generations of B4/S2, largest component.
// near: 24 -> 8 (3), far: 40 -> 8 (6)
//
//  0 0 0 0 0 0 0
// 0 # 1 1 1 1 0
//  0 1 1 1 1 1 0
// 0 0 1 1 1 1 0
//  0 1 1 1 1 0 0
// 0 1 1 1 1 # 0
//  0 0 0 0 0 0 0
pub const CAVE_7X7: felt252 = 0x1f3e3cf1f00;
pub const CAVE_7X7_NEAR_FROM: u8 = 24;
pub const CAVE_7X7_NEAR_TO: u8 = 8;
pub const CAVE_7X7_NEAR_DISTANCE: u32 = 3;
pub const CAVE_7X7_FAR_FROM: u8 = 40;
pub const CAVE_7X7_FAR_TO: u8 = 8;
pub const CAVE_7X7_FAR_DISTANCE: u32 = 6;

// MAZE 7x7: recursive backtracker from (1, 1), order 0 carve rule.
// near: 22 -> 9 (3), far: 26 -> 12 (13)
//
//  0 0 0 0 0 0 0
// 0 1 0 1 1 1 0
//  0 1 1 0 0 1 0
// 0 # 0 1 0 1 0
//  0 0 0 0 0 1 0
// 0 # 1 1 1 1 0
//  0 0 0 0 0 0 0
pub const MAZE_7X7: felt252 = 0x17325409f00;
pub const MAZE_7X7_NEAR_FROM: u8 = 22;
pub const MAZE_7X7_NEAR_TO: u8 = 9;
pub const MAZE_7X7_NEAR_DISTANCE: u32 = 3;
pub const MAZE_7X7_FAR_FROM: u8 = 26;
pub const MAZE_7X7_FAR_TO: u8 = 12;
pub const MAZE_7X7_FAR_DISTANCE: u32 = 13;

// SERPENTINE 7x7: open odd rows joined by one tile at alternating ends, worst case.
// near: 15 -> 10 (3), far: 36 -> 12 (14)
//
//  0 0 0 0 0 0 0
// 0 1 1 1 1 # 0
//  0 1 0 0 0 0 0
// 0 1 1 1 1 1 0
//  0 0 0 0 0 1 0
// 0 # 1 1 1 1 0
//  0 0 0 0 0 0 0
pub const SERPENTINE_7X7: felt252 = 0x1f207c09f00;
pub const SERPENTINE_7X7_NEAR_FROM: u8 = 15;
pub const SERPENTINE_7X7_NEAR_TO: u8 = 10;
pub const SERPENTINE_7X7_NEAR_DISTANCE: u32 = 3;
pub const SERPENTINE_7X7_FAR_FROM: u8 = 36;
pub const SERPENTINE_7X7_FAR_TO: u8 = 12;
pub const SERPENTINE_7X7_FAR_DISTANCE: u32 = 14;

// UNREACHABLE 7x7: empty board split by a wall column at x = W / 2.
// near: 23 -> 25 (0), far: 8 -> 40 (0)
//
//  0 0 0 0 0 0 0
// 0 # 1 0 1 1 0
//  0 1 1 0 1 1 0
// 0 1 1 0 1 1 0
//  0 1 1 0 1 1 0
// 0 1 1 0 1 # 0
//  0 0 0 0 0 0 0
pub const UNREACHABLE_7X7: felt252 = 0x1b366cd9b00;
pub const UNREACHABLE_7X7_NEAR_FROM: u8 = 23;
pub const UNREACHABLE_7X7_NEAR_TO: u8 = 25;
pub const UNREACHABLE_7X7_NEAR_DISTANCE: u32 = 0;
pub const UNREACHABLE_7X7_FAR_FROM: u8 = 8;
pub const UNREACHABLE_7X7_FAR_TO: u8 = 40;
pub const UNREACHABLE_7X7_FAR_DISTANCE: u32 = 0;

#[cfg(test)]
mod tests {
    // Internal imports

    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::tests::variants::Variants;

    // Local imports

    use super::*;

    /// Check a fixture against the scalar BFS reference.
    fn check(grid: felt252, width: u8, height: u8, pairs: Span<(u8, u8, u32)>) {
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let grid_u256: u256 = grid.into();
        assert!(grid_u256 & ~interior == 0);
        let mut pairs = pairs;
        while let Option::Some((from, to, distance)) = pairs.pop_front() {
            assert!(Bits::get(grid_u256, *from));
            assert!(Bits::get(grid_u256, *to));
            assert!(Variants::bfs_distance(grid, width, height, *from, *to) == *distance);
        }
    }

    #[test]
    fn test_fixture_empty_17x14() {
        let pairs = array![
            (EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO, EMPTY_17X14_NEAR_DISTANCE),
            (EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO, EMPTY_17X14_FAR_DISTANCE),
        ];
        check(EMPTY_17X14, 17, 14, pairs.span());
    }

    #[test]
    fn test_fixture_cave_17x14() {
        let pairs = array![
            (CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO, CAVE_17X14_NEAR_DISTANCE),
            (CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO, CAVE_17X14_FAR_DISTANCE),
        ];
        check(CAVE_17X14, 17, 14, pairs.span());
    }

    #[test]
    fn test_fixture_maze_17x14() {
        let pairs = array![
            (MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO, MAZE_17X14_NEAR_DISTANCE),
            (MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO, MAZE_17X14_FAR_DISTANCE),
        ];
        check(MAZE_17X14, 17, 14, pairs.span());
    }

    #[test]
    fn test_fixture_serpentine_17x14() {
        let pairs = array![
            (SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO, SERPENTINE_17X14_NEAR_DISTANCE),
            (SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO, SERPENTINE_17X14_FAR_DISTANCE),
        ];
        check(SERPENTINE_17X14, 17, 14, pairs.span());
    }

    #[test]
    fn test_fixture_unreachable_17x14() {
        let pairs = array![
            (
                UNREACHABLE_17X14_NEAR_FROM,
                UNREACHABLE_17X14_NEAR_TO,
                UNREACHABLE_17X14_NEAR_DISTANCE,
            ),
            (UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO, UNREACHABLE_17X14_FAR_DISTANCE),
        ];
        check(UNREACHABLE_17X14, 17, 14, pairs.span());
    }

    #[test]
    fn test_fixture_empty_7x7() {
        let pairs = array![
            (EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO, EMPTY_7X7_NEAR_DISTANCE),
            (EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO, EMPTY_7X7_FAR_DISTANCE),
        ];
        check(EMPTY_7X7, 7, 7, pairs.span());
    }

    #[test]
    fn test_fixture_cave_7x7() {
        let pairs = array![
            (CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO, CAVE_7X7_NEAR_DISTANCE),
            (CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO, CAVE_7X7_FAR_DISTANCE),
        ];
        check(CAVE_7X7, 7, 7, pairs.span());
    }

    #[test]
    fn test_fixture_maze_7x7() {
        let pairs = array![
            (MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO, MAZE_7X7_NEAR_DISTANCE),
            (MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO, MAZE_7X7_FAR_DISTANCE),
        ];
        check(MAZE_7X7, 7, 7, pairs.span());
    }

    #[test]
    fn test_fixture_serpentine_7x7() {
        let pairs = array![
            (SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO, SERPENTINE_7X7_NEAR_DISTANCE),
            (SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO, SERPENTINE_7X7_FAR_DISTANCE),
        ];
        check(SERPENTINE_7X7, 7, 7, pairs.span());
    }

    #[test]
    fn test_fixture_unreachable_7x7() {
        let pairs = array![
            (UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO, UNREACHABLE_7X7_NEAR_DISTANCE),
            (UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO, UNREACHABLE_7X7_FAR_DISTANCE),
        ];
        check(UNREACHABLE_7X7, 7, 7, pairs.span());
    }
}
