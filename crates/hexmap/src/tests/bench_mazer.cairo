//! Gas benchmarks of lot L5, maze generator and digger: one `#[test]` per fixture and algorithm,
//! each with an `#[available_gas(l2_gas: N)]` budget (measured + 5 %), see `GAS.md`.
//!
//! The variants below are test-only. They share a base (`BaseEngine`): the library carve rule
//! with a runtime direction dispatch (`CarverTrait::carve`), recursion, a `u256` maze, `(x, y)`
//! tracked incrementally and one draw of the 6 orders of the forward directions per tile. Each
//! variant changes one of these choices; the library (`Mazer`) replaces the runtime dispatch by
//! per-direction code (`Heading`). Variants that do not change the random draws produce the same
//! maze as the library (checked below); the others are compared per carved tile over 8 seeds.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::nullable::NullableTrait;

// Internal imports

use origami_hexmap::generators::digger::Digger;
use origami_hexmap::generators::mazer::{Carver, CarverTrait, Mazer, TurnTrait};
use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::Bits;
use origami_hexmap::helpers::rng::{Rng, RngTrait};
use origami_hexmap::types::direction::{Direction, DirectionTrait};

// Constants

const SEED: felt252 = 'SEED';
const SEEDS: felt252 = 8;
/// A 3x2 room in the middle of 17x14: tiles x = 7..9 of rows 6 and 7.
const ROOM: felt252 = 0x1c000e000000000000000000000000000;
/// Tile (3, 0) of 17x14, bottom edge.
const START: u8 = 3;

// Variant engines

/// A carve-and-recurse strategy on the shared state.
trait Engine {
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool;
}

/// Root and constants shared by the engines, as in `Mazer::generate`.
fn generate<impl E: Engine>(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
    Asserter::assert_valid_dimension(width, height);
    let carver = BoxTrait::new(CarverTrait::new(width, height, order));
    let mut rng = RngTrait::new(seed);
    let x = rng.next_below(width - 2) + 1;
    let y = rng.next_below(height - 2) + 1;
    let power = Bits::pow(y * width + x);
    let odd = y % 2 == 1;
    let mut maze: u256 = power.into();
    let mut directions = rng.shuffle6();
    let mut count: u8 = 6;
    while count != 0 {
        let direction = DirectionTrait::pop_front(ref directions);
        E::visit(carver, ref maze, ref rng, power, x.into(), y.into(), odd, direction);
        count -= 1;
    }
    Bits::to_felt(maze)
}

/// Draw one of the 6 orders of the forward directions, `mid` is the rank of `forward`.
#[inline]
fn draw_order(ref rng: Rng, forward: Direction) -> (Direction, Direction, Direction, u8) {
    let left = forward.left();
    let right = forward.right();
    match rng.draw(6) {
        0 => (left, forward, right, 1_u8),
        1 => (left, right, forward, 2),
        2 => (forward, left, right, 0),
        3 => (forward, right, left, 0),
        4 => (right, left, forward, 2),
        _ => (right, forward, left, 1),
    }
}

// Base: runtime dispatch, recursion, one draw of 6 orders

impl BaseEngine of Engine {
    #[inline]
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool {
        match carver.as_snapshot().unbox().carve(ref maze, power, x, y, odd, direction) {
            Some((
                next, nx, ny, nodd,
            )) => {
                base_iter(carver, ref maze, ref rng, next, nx, ny, nodd, direction);
                true
            },
            None => false,
        }
    }
}

fn base_iter(
    carver: Box<Carver>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let (first, second, third, mid) = draw_order(ref rng, forward);
    if BaseEngine::visit(carver, ref maze, ref rng, power, x, y, odd, first) {
        if mid != 0 {
            let other = if mid == 1 {
                third
            } else {
                second
            };
            BaseEngine::visit(carver, ref maze, ref rng, power, x, y, odd, other);
        }
    } else if BaseEngine::visit(carver, ref maze, ref rng, power, x, y, odd, second) {
        if mid == 0 {
            BaseEngine::visit(carver, ref maze, ref rng, power, x, y, odd, third);
        }
    } else {
        BaseEngine::visit(carver, ref maze, ref rng, power, x, y, odd, third);
    }
}

// Direction order: one draw of 3, rotation of the base order (L, F, R)

impl RotationEngine of Engine {
    #[inline]
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool {
        match carver.as_snapshot().unbox().carve(ref maze, power, x, y, odd, direction) {
            Some((
                next, nx, ny, nodd,
            )) => {
                rotation_iter(carver, ref maze, ref rng, next, nx, ny, nodd, direction);
                true
            },
            None => false,
        }
    }
}

fn rotation_iter(
    carver: Box<Carver>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let left = forward.left();
    let right = forward.right();
    match rng.draw(3) {
        0 => {
            // L, F, R
            if RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, left)
                || !RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, forward) {
                RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, right);
            }
        },
        1 => {
            // F, R, L
            if !RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, forward) {
                RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, right);
                RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, left);
            }
        },
        _ => {
            // R, L, F
            if RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, right) {
                RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, left);
            } else if !RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, left) {
                RotationEngine::visit(carver, ref maze, ref rng, power, x, y, odd, forward);
            }
        },
    }
}

// Direction order: lazy draws, the second direction is drawn only when the first one fails

impl LazyEngine of Engine {
    #[inline]
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool {
        match carver.as_snapshot().unbox().carve(ref maze, power, x, y, odd, direction) {
            Some((
                next, nx, ny, nodd,
            )) => {
                lazy_iter(carver, ref maze, ref rng, next, nx, ny, nodd, direction);
                true
            },
            None => false,
        }
    }
}

fn lazy_iter(
    carver: Box<Carver>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let left = forward.left();
    let right = forward.right();
    let (first, lhs, rhs) = match rng.draw(3) {
        0 => (left, forward, right),
        1 => (forward, left, right),
        _ => (right, left, forward),
    };
    if LazyEngine::visit(carver, ref maze, ref rng, power, x, y, odd, first) {
        if first != forward {
            let other = if first == left {
                right
            } else {
                left
            };
            LazyEngine::visit(carver, ref maze, ref rng, power, x, y, odd, other);
        }
    } else {
        let (second, third) = if rng.draw(2) == 0 {
            (lhs, rhs)
        } else {
            (rhs, lhs)
        };
        if LazyEngine::visit(carver, ref maze, ref rng, power, x, y, odd, second) {
            if first == forward {
                LazyEngine::visit(carver, ref maze, ref rng, power, x, y, odd, third);
            }
        } else {
            LazyEngine::visit(carver, ref maze, ref rng, power, x, y, odd, third);
        }
    }
}

// Direction order: `Rng::shuffle6` per tile, the non forward directions are skipped

impl ShuffleEngine of Engine {
    #[inline]
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool {
        match carver.as_snapshot().unbox().carve(ref maze, power, x, y, odd, direction) {
            Some((
                next, nx, ny, nodd,
            )) => {
                shuffle_iter(carver, ref maze, ref rng, next, nx, ny, nodd, direction);
                true
            },
            None => false,
        }
    }
}

fn shuffle_iter(
    carver: Box<Carver>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let left = forward.left();
    let right = forward.right();
    let mut directions = rng.shuffle6();
    let mut skip_middle = false;
    let mut skip_sides = false;
    let mut count: u8 = 6;
    while count != 0 {
        count -= 1;
        let direction = DirectionTrait::pop_front(ref directions);
        if direction == forward {
            if !skip_middle
                && ShuffleEngine::visit(carver, ref maze, ref rng, power, x, y, odd, direction) {
                skip_sides = true;
            }
        } else if direction == left || direction == right {
            if !skip_sides
                && ShuffleEngine::visit(carver, ref maze, ref rng, power, x, y, odd, direction) {
                skip_middle = true;
            }
        }
    }
}

// Explicit stack: frames in a `Felt252Dict<Nullable<Frame>>`, same draws as the recursion

#[derive(Copy, Drop)]
struct Frame {
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    first: Direction,
    second: Direction,
    third: Direction,
    mid: u8,
    stage: u8,
}

/// Stages: 0 try `first`, 1 try `second`, 2 try `third`, 3 try the side opposite to `first`,
/// 4 done.
const DONE: u8 = 4;

#[inline]
fn frame(
    ref rng: Rng, power: felt252, x: felt252, y: felt252, odd: bool, forward: Direction,
) -> Frame {
    let (first, second, third, mid) = draw_order(ref rng, forward);
    Frame { power, x, y, odd, first, second, third, mid, stage: 0 }
}

impl StackEngine of Engine {
    #[inline]
    fn visit(
        carver: Box<Carver>,
        ref maze: u256,
        ref rng: Rng,
        power: felt252,
        x: felt252,
        y: felt252,
        odd: bool,
        direction: Direction,
    ) -> bool {
        let constants = carver.as_snapshot().unbox();
        let (next, nx, ny, nodd) = match constants.carve(ref maze, power, x, y, odd, direction) {
            Some(carved) => carved,
            None => { return false; },
        };
        let mut stack: Felt252Dict<Nullable<Frame>> = Default::default();
        let mut depth: felt252 = 0;
        let mut top = frame(ref rng, next, nx, ny, nodd, direction);
        loop {
            // [Compute] Candidate of the top frame and the stages after success and failure
            let (candidate, success, failure) = match top.stage {
                0 => (top.first, if top.mid == 0 {
                    DONE
                } else {
                    3
                }, 1),
                1 => (top.second, if top.mid == 0 {
                    2
                } else {
                    DONE
                }, 2),
                2 => (top.third, DONE, DONE),
                3 => (if top.mid == 1 {
                    top.third
                } else {
                    top.second
                }, DONE, DONE),
                _ => {
                    // [Effect] Pop
                    if depth == 0 {
                        break;
                    }
                    depth -= 1;
                    top = stack.get(depth).deref();
                    continue;
                },
            };
            match constants.carve(ref maze, top.power, top.x, top.y, top.odd, candidate) {
                Some((
                    next, nx, ny, nodd,
                )) => {
                    // [Effect] Push
                    top.stage = success;
                    stack.insert(depth, NullableTrait::new(top));
                    depth += 1;
                    top = frame(ref rng, next, nx, ny, nodd, candidate);
                },
                None => { top.stage = failure; },
            }
        }
        true
    }
}

// Carve test: one bit test per tile instead of one mask test (order 0 only)

/// Index-based recursion: the candidate and its neighbours except `c` are tested with
/// `Bits::get`, early exit on the first open tile.
fn bits_visit(
    carver: Box<Carver>,
    width: u8,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    index: u8,
    x: felt252,
    y: felt252,
    odd: bool,
    direction: Direction,
) -> bool {
    let constants = carver.as_snapshot().unbox();
    let (step, nx, ny, nodd) = match constants.locate(direction, x, y, odd) {
        Some(located) => located,
        None => { return false; },
    };
    let candidate = direction.next(index, width, odd);
    if Bits::get(maze, candidate) {
        return false;
    }
    let back = direction.opposite();
    let mut directions = array![
        Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
        Direction::SouthWest, Direction::SouthEast,
    ]
        .span();
    while let Option::Some(neighbor) = directions.pop_front() {
        if *neighbor != back && Bits::get(maze, (*neighbor).next(candidate, width, nodd)) {
            return false;
        }
    }
    let next = power * step;
    let bit: u256 = next.into();
    maze = u256 { low: maze.low + bit.low, high: maze.high + bit.high };
    bits_iter(carver, width, ref maze, ref rng, next, candidate, nx, ny, nodd, direction);
    true
}

fn bits_iter(
    carver: Box<Carver>,
    width: u8,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    index: u8,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let (first, second, third, mid) = draw_order(ref rng, forward);
    if bits_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, first) {
        if mid != 0 {
            let other = if mid == 1 {
                third
            } else {
                second
            };
            bits_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, other);
        }
    } else if bits_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, second) {
        if mid == 0 {
            bits_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, third);
        }
    } else {
        bits_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, third);
    }
}

fn bits_generate(width: u8, height: u8, seed: felt252) -> felt252 {
    Asserter::assert_valid_dimension(width, height);
    let carver = BoxTrait::new(CarverTrait::new(width, height, 0));
    let mut rng = RngTrait::new(seed);
    let x = rng.next_below(width - 2) + 1;
    let y = rng.next_below(height - 2) + 1;
    let index = y * width + x;
    let power = Bits::pow(index);
    let odd = y % 2 == 1;
    let mut maze: u256 = power.into();
    let mut directions = rng.shuffle6();
    let mut count: u8 = 6;
    while count != 0 {
        let direction = DirectionTrait::pop_front(ref directions);
        bits_visit(
            carver, width, ref maze, ref rng, power, index, x.into(), y.into(), odd, direction,
        );
        count -= 1;
    }
    Bits::to_felt(maze)
}

// Maze kept as a felt252 (set by addition, converted for every test)

fn felt_visit(
    carver: Box<Carver>,
    ref maze: felt252,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    direction: Direction,
) -> bool {
    let constants = carver.as_snapshot().unbox();
    let (step, nx, ny, nodd) = match constants.locate(direction, x, y, odd) {
        Some(located) => located,
        None => { return false; },
    };
    let mask: u256 = (power * constants.mask(direction, odd, step, ny, nodd)).into();
    let open: u256 = maze.into();
    if open.low & mask.low != 0 || open.high & mask.high != 0 {
        return false;
    }
    let next = power * step;
    maze += next;
    felt_iter(carver, ref maze, ref rng, next, nx, ny, nodd, direction);
    true
}

fn felt_iter(
    carver: Box<Carver>,
    ref maze: felt252,
    ref rng: Rng,
    power: felt252,
    x: felt252,
    y: felt252,
    odd: bool,
    forward: Direction,
) {
    let (first, second, third, mid) = draw_order(ref rng, forward);
    if felt_visit(carver, ref maze, ref rng, power, x, y, odd, first) {
        if mid != 0 {
            let other = if mid == 1 {
                third
            } else {
                second
            };
            felt_visit(carver, ref maze, ref rng, power, x, y, odd, other);
        }
    } else if felt_visit(carver, ref maze, ref rng, power, x, y, odd, second) {
        if mid == 0 {
            felt_visit(carver, ref maze, ref rng, power, x, y, odd, third);
        }
    } else {
        felt_visit(carver, ref maze, ref rng, power, x, y, odd, third);
    }
}

fn felt_generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
    Asserter::assert_valid_dimension(width, height);
    let carver = BoxTrait::new(CarverTrait::new(width, height, order));
    let mut rng = RngTrait::new(seed);
    let x = rng.next_below(width - 2) + 1;
    let y = rng.next_below(height - 2) + 1;
    let power = Bits::pow(y * width + x);
    let odd = y % 2 == 1;
    let mut maze = power;
    let mut directions = rng.shuffle6();
    let mut count: u8 = 6;
    while count != 0 {
        let direction = DirectionTrait::pop_front(ref directions);
        felt_visit(carver, ref maze, ref rng, power, x.into(), y.into(), odd, direction);
        count -= 1;
    }
    maze
}

// Position tracked as an index, coordinates recomputed with `DivRem` once per tile

fn divrem_visit(
    carver: Box<Carver>,
    width: NonZero<u8>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    index: u8,
    x: felt252,
    y: felt252,
    odd: bool,
    direction: Direction,
) -> bool {
    match carver.as_snapshot().unbox().carve(ref maze, power, x, y, odd, direction) {
        Some((
            next, _, _, _,
        )) => {
            let candidate = direction.next(index, width.into(), odd);
            divrem_iter(carver, width, ref maze, ref rng, next, candidate, direction);
            true
        },
        None => false,
    }
}

fn divrem_iter(
    carver: Box<Carver>,
    width: NonZero<u8>,
    ref maze: u256,
    ref rng: Rng,
    power: felt252,
    index: u8,
    forward: Direction,
) {
    let (y, x) = DivRem::div_rem(index, width);
    let odd = y % 2 == 1;
    let (x, y): (felt252, felt252) = (x.into(), y.into());
    let (first, second, third, mid) = draw_order(ref rng, forward);
    if divrem_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, first) {
        if mid != 0 {
            let other = if mid == 1 {
                third
            } else {
                second
            };
            divrem_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, other);
        }
    } else if divrem_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, second) {
        if mid == 0 {
            divrem_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, third);
        }
    } else {
        divrem_visit(carver, width, ref maze, ref rng, power, index, x, y, odd, third);
    }
}

fn divrem_generate(width: u8, height: u8, order: u8, seed: felt252) -> felt252 {
    Asserter::assert_valid_dimension(width, height);
    let carver = BoxTrait::new(CarverTrait::new(width, height, order));
    let mut rng = RngTrait::new(seed);
    let x = rng.next_below(width - 2) + 1;
    let y = rng.next_below(height - 2) + 1;
    let index = y * width + x;
    let power = Bits::pow(index);
    let odd = y % 2 == 1;
    let mut maze: u256 = power.into();
    let mut directions = rng.shuffle6();
    let mut count: u8 = 6;
    while count != 0 {
        let direction = DirectionTrait::pop_front(ref directions);
        divrem_visit(
            carver,
            width.try_into().unwrap(),
            ref maze,
            ref rng,
            power,
            index,
            x.into(),
            y.into(),
            odd,
            direction,
        );
        count -= 1;
    }
    Bits::to_felt(maze)
}

// Equivalences

#[test]
fn test_bench_mazer_variants_same_maze() {
    let expected = Mazer::generate(17, 14, 0, SEED);
    assert!(generate::<BaseEngine>(17, 14, 0, SEED) == expected);
    assert!(generate::<StackEngine>(17, 14, 0, SEED) == expected);
    assert!(bits_generate(17, 14, SEED) == expected);
    assert!(felt_generate(17, 14, 0, SEED) == expected);
    assert!(divrem_generate(17, 14, 0, SEED) == expected);
    let expected = Mazer::generate(17, 14, 1, SEED);
    assert!(generate::<BaseEngine>(17, 14, 1, SEED) == expected);
}

#[test]
fn test_bench_mazer_tiles() {
    // Carved tiles over the 8 seeds, to normalise the variants that change the draws
    let mut totals: Array<u32> = array![];
    let mut variant: u8 = 0;
    while variant != 5 {
        let mut total: u32 = 0;
        let mut seed = SEEDS;
        while seed != 0 {
            seed -= 1;
            let maze = match variant {
                0 => Mazer::generate(17, 14, 0, seed),
                1 => Mazer::generate(17, 14, 1, seed),
                2 => generate::<RotationEngine>(17, 14, 0, seed),
                3 => generate::<LazyEngine>(17, 14, 0, seed),
                _ => generate::<ShuffleEngine>(17, 14, 0, seed),
            };
            total += Bits::popcount(maze.into()).into();
        }
        totals.append(total);
        variant += 1;
    }
    println!("tiles: {:?}", totals);
    let single: u32 = Bits::popcount(Mazer::generate(17, 14, 0, SEED).into()).into();
    println!("tiles single order 0: {}", single);
    let single: u32 = Bits::popcount(Mazer::generate(17, 14, 1, SEED).into()).into();
    println!("tiles single order 1: {}", single);
}

// Library

#[test]
#[available_gas(l2_gas: 3020000)]
fn bench_mazer_17x14_order_0() {
    assert!(Mazer::generate(17, 14, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 1918000)]
fn bench_mazer_17x14_order_1() {
    assert!(Mazer::generate(17, 14, 1, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 551000)]
fn bench_mazer_7x7_order_0() {
    assert!(Mazer::generate(7, 7, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 3326000)]
fn bench_mazer_19x13_order_0() {
    assert!(Mazer::generate(19, 13, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 24752000)]
fn bench_mazer_17x14_order_0_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(Mazer::generate(17, 14, 0, seed) != 0);
    }
}

#[test]
#[available_gas(l2_gas: 15537000)]
fn bench_mazer_17x14_order_1_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(Mazer::generate(17, 14, 1, seed) != 0);
    }
}

#[test]
#[available_gas(l2_gas: 331000)]
fn bench_digger_corridor_17x14() {
    assert!(Digger::corridor(17, 14, 0, START, ROOM, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 3392000)]
fn bench_digger_maze_17x14() {
    assert!(Digger::maze(17, 14, 0, START, ROOM, SEED) != 0);
}

// Variants, same maze as the library

#[test]
#[available_gas(l2_gas: 3158000)]
fn bench_mazer_variant_base_17x14() {
    assert!(generate::<BaseEngine>(17, 14, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 2025000)]
fn bench_mazer_variant_base_17x14_order_1() {
    assert!(generate::<BaseEngine>(17, 14, 1, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 4771000)]
fn bench_mazer_variant_stack_17x14() {
    assert!(generate::<StackEngine>(17, 14, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 10116000)]
fn bench_mazer_variant_bits_17x14() {
    assert!(bits_generate(17, 14, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 3218000)]
fn bench_mazer_variant_felt_17x14() {
    assert!(felt_generate(17, 14, 0, SEED) != 0);
}

#[test]
#[available_gas(l2_gas: 3549000)]
fn bench_mazer_variant_divrem_17x14() {
    assert!(divrem_generate(17, 14, 0, SEED) != 0);
}

// Variants of the direction order, 8 seeds

#[test]
#[available_gas(l2_gas: 25897000)]
fn bench_mazer_variant_base_17x14_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(generate::<BaseEngine>(17, 14, 0, seed) != 0);
    }
}

#[test]
#[available_gas(l2_gas: 24326000)]
fn bench_mazer_variant_rotation_17x14_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(generate::<RotationEngine>(17, 14, 0, seed) != 0);
    }
}

#[test]
#[available_gas(l2_gas: 27706000)]
fn bench_mazer_variant_lazy_17x14_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(generate::<LazyEngine>(17, 14, 0, seed) != 0);
    }
}

#[test]
#[available_gas(l2_gas: 77306000)]
fn bench_mazer_variant_shuffle_17x14_seeds() {
    let mut seed = SEEDS;
    while seed != 0 {
        seed -= 1;
        assert!(generate::<ShuffleEngine>(17, 14, 0, seed) != 0);
    }
}
