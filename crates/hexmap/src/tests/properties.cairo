//! Property tests of the L0 primitives against independent references.

// Internal imports

use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::geometry::Geometry;
use origami_hexmap::helpers::layout::{Layout, LayoutTrait};
use origami_hexmap::helpers::rng::RngTrait;
use origami_hexmap::tests::fixtures::*;
use origami_hexmap::tests::variants::{MaskLayoutTrait, Variants};
use origami_hexmap::types::direction::{Direction, DirectionTrait};

/// Every formulation of the dilation agrees with the reference on `frontier`.
fn check_expand(layout: @Layout, width: u8, height: u8, frontier: u256) {
    let expected = MaskLayoutTrait::new(width, height).expand(frontier);
    assert!(layout.expand(frontier) == expected);
    assert!(Variants::expand_felt_double(layout, frontier) == expected);
    assert!(Variants::expand_felt_vertical(layout, frontier) == expected);
    let (low, high) = Variants::expand_limbs(layout, frontier.low, frontier.high);
    assert!(u256 { low, high } == expected);
    let size: u16 = width.into() * height.into();
    if size <= 128 {
        assert!(layout.expand_small(frontier.low).into() == expected);
        assert!(Variants::expand_small_felt_double(layout, frontier.low).into() == expected);
    }
}

/// Dilation on pseudo-random interior frontiers (dense and sparse) and on every single tile.
fn check_expand_random(width: u8, height: u8) {
    let layout = LayoutTrait::new(width, height);
    let interior: u256 = LayoutTrait::interior(width, height).into();
    let mut index: felt252 = 0;
    while index != 12 {
        let dense: u256 = RngTrait::mix(index, width.into()).into() & interior;
        let sparse = dense & RngTrait::mix(index, 1).into() & RngTrait::mix(index, 2).into();
        check_expand(@layout, width, height, dense);
        check_expand(@layout, width, height, sparse);
        index += 1;
    }
    check_expand(@layout, width, height, interior);
    // Every interior tile alone: itself plus its 6 neighbours
    let size = width * height;
    let mut position: u8 = 0;
    while position != size {
        let tile: u256 = Bits::pow(position).into();
        if tile & interior != 0 {
            let expected: u256 = (Bits::pow(position) + layout.neighbour_mask(position)).into();
            assert!(layout.expand(tile) == expected);
            assert!(Variants::expand_scalar(width, height, tile) == expected);
        }
        position += 1;
    }
}

#[test]
fn test_properties_expand_fixtures() {
    let fixtures: Array<(felt252, u8, u8)> = array![
        (EMPTY_17X14, 17, 14), (CAVE_17X14, 17, 14), (MAZE_17X14, 17, 14),
        (SERPENTINE_17X14, 17, 14), (UNREACHABLE_17X14, 17, 14), (EMPTY_7X7, 7, 7),
        (CAVE_7X7, 7, 7), (MAZE_7X7, 7, 7), (SERPENTINE_7X7, 7, 7), (UNREACHABLE_7X7, 7, 7),
    ];
    let mut fixtures = fixtures.span();
    while let Option::Some((grid, width, height)) = fixtures.pop_front() {
        let layout = LayoutTrait::new(*width, *height);
        let frontier: u256 = (*grid).into();
        check_expand(@layout, *width, *height, frontier);
        // The reference itself agrees with the scalar neighbour walk
        assert!(
            MaskLayoutTrait::new(*width, *height)
                .expand(frontier) == Variants::expand_scalar(*width, *height, frontier),
        );
    }
}

#[test]
fn test_properties_expand_3x3() {
    check_expand_random(3, 3);
}

#[test]
fn test_properties_expand_7x7() {
    check_expand_random(7, 7);
}

#[test]
fn test_properties_expand_17x14() {
    check_expand_random(17, 14);
}

#[test]
fn test_properties_expand_19x13() {
    check_expand_random(19, 13);
}

#[test]
fn test_properties_expand_25x10() {
    check_expand_random(25, 10);
}

#[test]
fn test_properties_expand_83x3() {
    check_expand_random(83, 3);
}

#[test]
fn test_properties_expand_3x83() {
    check_expand_random(3, 83);
}

#[test]
fn test_properties_sequential_step() {
    let layout = LayoutTrait::new(17, 14);
    let unvisited: u256 = CAVE_17X14.into();
    let frontier: u256 = Bits::pow(CAVE_17X14_FAR_FROM).into();
    let unvisited = unvisited - frontier;
    let expected = layout.expand(frontier) & unvisited;
    let (next, left) = Variants::step_sequential(@layout, frontier, unvisited);
    assert!(next == expected);
    assert!(left == unvisited - expected);
}

/// Geometric distance equals the BFS distance on a fully open board.
fn check_distance(width: u8, height: u8, from: u8) {
    let board = LayoutTrait::board(width, height);
    let layers = Variants::bfs_layers(board, width, height, from);
    let mut layers = layers.span();
    let mut depth: u8 = 0;
    let size = width * height;
    while let Option::Some(layer) = layers.pop_front() {
        let layer: u256 = (*layer).into();
        let mut to: u8 = 0;
        while to != size {
            if Bits::get(layer, to) {
                assert!(Geometry::distance(width, from, to) == depth);
                assert!(Geometry::distance(width, to, from) == depth);
                assert!(Variants::distance_split(width, from, to) == depth);
            }
            to += 1;
        }
        depth += 1;
    }
}

#[test]
fn test_properties_distance_7x7_all_pairs() {
    let mut from: u8 = 0;
    while from != 49 {
        check_distance(7, 7, from);
        from += 1;
    }
}

#[test]
fn test_properties_distance_large_boards() {
    // Corners, both row parities, centre
    check_distance(17, 14, 0);
    check_distance(17, 14, 16);
    check_distance(17, 14, 17);
    check_distance(17, 14, 237);
    check_distance(17, 14, 7 * 17 + 8);
    check_distance(19, 13, 6 * 19 + 9);
    check_distance(83, 3, 83 + 41);
    check_distance(3, 83, 41 * 3 + 1);
}

/// `neighbor` against the offset table, for every position and direction.
fn check_neighbor(width: u8, height: u8) {
    let layout = LayoutTrait::new(width, height);
    let size = width * height;
    let mut position: u8 = 0;
    while position != size {
        let (x, y) = LayoutTrait::coords(width, position);
        assert!(LayoutTrait::index(width, x, y) == position);
        let odd = y % 2 == 1;
        let (_, parity) = LayoutTrait::parity(width, position);
        assert!(parity == odd);
        let x: i16 = x.into();
        let y: i16 = y.into();
        let shift: i16 = if odd {
            1
        } else {
            0
        };
        // (dx, dy) per direction, the diagonal columns depend on the row parity
        let offsets: Array<(Direction, i16, i16)> = array![
            (Direction::East, -1, 0), (Direction::NorthEast, shift - 1, 1),
            (Direction::NorthWest, shift, 1), (Direction::West, 1, 0),
            (Direction::SouthWest, shift, -1), (Direction::SouthEast, shift - 1, -1),
        ];
        let mut offsets = offsets.span();
        let mut mask: felt252 = 0;
        let mut count: u8 = 0;
        while let Option::Some((direction, dx, dy)) = offsets.pop_front() {
            let nx = x + *dx;
            let ny = y + *dy;
            let inside = nx >= 0 && ny >= 0 && nx < width.into() && ny < height.into();
            let actual = LayoutTrait::neighbor(width, height, position, *direction);
            if inside {
                let expected: u8 = (ny * width.into() + nx).try_into().unwrap();
                assert!(actual == Option::Some(expected));
                assert!(direction.next(position, width, odd) == expected);
                mask += Bits::pow(expected);
                count += 1;
            } else {
                assert!(actual.is_none());
            }
        }
        // Interior tiles: the closed-form mask matches the 6 neighbours
        if count == 6 && x > 0 && y > 0 && x < (width - 1).into() && y < (height - 1).into() {
            assert!(layout.neighbour_mask(position) == mask);
            assert!(Variants::neighbour_mask_lookups(width, position) == mask);
        }
        position += 1;
    }
}

#[test]
fn test_properties_neighbor_3x3() {
    check_neighbor(3, 3);
}

#[test]
fn test_properties_neighbor_7x7() {
    check_neighbor(7, 7);
}

#[test]
fn test_properties_neighbor_17x14() {
    check_neighbor(17, 14);
}

#[test]
fn test_properties_neighbor_83x3() {
    check_neighbor(83, 3);
}

/// Masks against a bit-by-bit construction.
fn check_masks(width: u8, height: u8) {
    let mut board: felt252 = 0;
    let mut even: felt252 = 0;
    let mut interior: felt252 = 0;
    let mut y: u8 = 0;
    while y != height {
        let mut x: u8 = 0;
        while x != width {
            let bit = Bits::pow(y * width + x);
            board += bit;
            if y % 2 == 0 {
                even += bit;
            }
            if x > 0 && y > 0 && x < width - 1 && y < height - 1 {
                interior += bit;
            }
            x += 1;
        }
        y += 1;
    }
    assert!(LayoutTrait::board(width, height) == board);
    assert!(LayoutTrait::even(width, height) == even);
    assert!(LayoutTrait::interior(width, height) == interior);
}

#[test]
fn test_properties_masks() {
    check_masks(3, 3);
    check_masks(7, 7);
    check_masks(17, 14);
    check_masks(19, 13);
    check_masks(25, 10);
    check_masks(83, 3);
    check_masks(3, 83);
}

#[test]
fn test_properties_hexagon() {
    let mut radius: u8 = 1;
    while radius != 7 {
        let width = 2 * radius + 3;
        let mask = LayoutTrait::hexagon(radius);
        let interior: u256 = LayoutTrait::interior(width, width).into();
        let mask_u256: u256 = mask.into();
        assert!(mask_u256 & ~interior == 0);
        let expected: u16 = 3 * radius.into() * (radius.into() + 1) + 1;
        assert!(Bits::popcount(mask_u256).into() == expected);
        // Exactly the tiles within `radius` of the centre
        let center = (radius + 1) * width + radius + 1;
        let size = width * width;
        let mut position: u8 = 0;
        while position != size {
            let inside = Geometry::distance(width, center, position) <= radius;
            assert!(Bits::get(mask_u256, position) == inside);
            position += 1;
        }
        radius += 1;
    }
    // Radius 6 fits in 15x15 = 225 bits, radius 7 would need 17x17 = 289
    assert!(Bits::popcount(LayoutTrait::hexagon(6).into()) == 127);
}

#[test]
fn test_properties_shuffle6_fisher_yates_is_permutation() {
    let mut pool: u128 = 0xfedcba9876543210fedcba9876543210;
    let packed = Variants::shuffle6_fisher_yates(ref pool);
    let mut seen: u8 = 0;
    let mut value = packed;
    let mut index: u8 = 0;
    while index != 6 {
        let direction: u8 = DirectionTrait::pop_front(ref value).into();
        seen = seen | match direction {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 8,
            4 => 16,
            _ => 32,
        };
        index += 1;
    }
    assert!(seen == 63);
}

#[test]
fn test_properties_bit_variants() {
    let value: felt252 = MAZE_17X14;
    let mut index: u8 = 0;
    while index != 238 {
        assert!(Bits::get(value.into(), index) == Variants::get_divmod(value.into(), index));
        if !Bits::get(value.into(), index) {
            let set: u256 = Bits::set(value, index).into();
            assert!(set == Variants::set_or(value.into(), index));
        }
        assert!(
            Variants::shr_div(
                Bits::pow(index) * 5, index,
            ) == Bits::shr_exact(Bits::pow(index) * 5, index),
        );
        index += 1;
    }
}
