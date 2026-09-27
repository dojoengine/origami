//! Bit-parallel breadth-first search with layer backtracking (lot L1).
//!
//! The frontier advances one layer per hex dilation (the `Layout::expand` formulation, set
//! operations applied limb by limb with the bitwise builtin). Every layer is stored, then the path
//! is rebuilt from the target: the neighbour mask of the current tile is intersected with the
//! previous layer on the limb that holds it, and its lowest set bit is the next tile.
//!
//! Endpoints are handled outside the layer loop, which runs on interior tiles only (border
//! invariant). The first layer is the open interior neighbourhood of the start, and the loop stops
//! on the first layer that touches the open interior neighbours of the target, so neither endpoint
//! layer is expanded. An open edge tile (an entrance dug by `Digger`) may therefore be an
//! endpoint: paths never cross an edge tile other than their endpoints. The hex distance between
//! the endpoints bounds the path length from below: the layers before it skip the target test.
//!
//! Boards of at most 128 bits run the same loops on a single `u128` limb. The loops are unrolled
//! four times; see `GAS.md` for the measured alternatives.

// Core imports

use core::felt252_div;
use core::integer::Bitwise;

// Internal imports

use origami_hexmap::helpers::asserter::Asserter;
use origami_hexmap::helpers::bits::{Bits, TWO_POW_128};
use origami_hexmap::helpers::layout::LayoutTrait;
use origami_hexmap::types::direction::Direction;

// Constants

/// 1/2 in the field.
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
/// Largest board of the single-limb path.
const SMALL_SIZE: u8 = 128;

/// Errors module.
pub mod errors {
    pub const BFS_POSITION_NOT_WALKABLE: felt252 = 'Bfs: position not walkable';
}

/// AND, XOR and OR of two limbs in a single application of the bitwise builtin, see
/// `generators::caver`.
extern fn bitwise(lhs: u128, rhs: u128) -> (u128, u128, u128) implicits(Bitwise) nopanic;

/// Constants of the layer step.
#[derive(Copy, Drop)]
pub struct Step {
    /// Bits of the even rows.
    pub even_low: u128,
    pub even_high: u128,
    /// 2^(W-1): up shift of the even rows (the odd rows shift by twice as much).
    pub up: felt252,
    /// 2^-(W+1): down shift of the even rows (the odd rows shift by twice as much).
    pub down: felt252,
}

/// Constants of the backtracking.
#[derive(Copy, Drop)]
pub struct Back {
    pub width: u8,
    /// W - 1
    pub narrow: u8,
    /// W + 1
    pub wide: u8,
    /// Field sum of the 6 neighbour offsets of an even-row tile.
    pub around_even: felt252,
    /// Field sum of the 6 neighbour offsets of an odd-row tile.
    pub around_odd: felt252,
    /// 2^(W-1)
    pub up_even: felt252,
    /// 2^W
    pub up_odd: felt252,
    /// 2^-(W+1)
    pub down_even: felt252,
    /// 2^-W
    pub down_odd: felt252,
    /// 2^(W+1)
    pub up_wide: felt252,
    /// 2^-(W-1)
    pub down_wide: felt252,
}

/// An endpoint.
#[derive(Copy, Drop)]
pub struct Endpoint {
    pub position: u8,
    /// 2^position
    pub power: felt252,
    /// Whether the tile is interior.
    pub interior: bool,
    /// Whether the row is odd.
    pub odd: bool,
    /// Column.
    pub x: u8,
    /// Row.
    pub y: u8,
    /// Half row, `y / 2`.
    pub half: u8,
    /// Bits of the board neighbours.
    pub around: felt252,
}

/// Where the layers go: stored for the backtracking, or only counted.
pub trait Store<S> {
    fn push(ref self: S, low: u128, high: u128);
}

pub impl ArrayStore of Store<Array<u256>> {
    #[inline(always)]
    fn push(ref self: Array<u256>, low: u128, high: u128) {
        self.append(u256 { low, high });
    }
}

pub impl CountStore of Store<u8> {
    #[inline(always)]
    fn push(ref self: u8, low: u128, high: u128) {
        self += 1;
    }
}

/// Where the layers of a single-limb board go.
pub trait SmallStore<S> {
    fn push(ref self: S, layer: u128);
}

pub impl SmallArrayStore of SmallStore<Array<u128>> {
    #[inline(always)]
    fn push(ref self: Array<u128>, layer: u128) {
        self.append(layer);
    }
}

pub impl SmallCountStore of SmallStore<u8> {
    #[inline(always)]
    fn push(ref self: u8, layer: u128) {
        self += 1;
    }
}

/// Target test of a layer: the open interior neighbours of the target, on the limbs they use.
pub trait Goal<G> {
    fn hit(self: G, low: u128, high: u128) -> bool;
}

/// Goal in the low limb.
#[derive(Copy, Drop)]
pub struct LowGoal {
    pub mask: u128,
}

/// Goal in the high limb.
#[derive(Copy, Drop)]
pub struct HighGoal {
    pub mask: u128,
}

impl LowGoalImpl of Goal<LowGoal> {
    #[inline(always)]
    fn hit(self: LowGoal, low: u128, high: u128) -> bool {
        let (hit, _, _) = bitwise(low, self.mask);
        hit != 0
    }
}

impl HighGoalImpl of Goal<HighGoal> {
    #[inline(always)]
    fn hit(self: HighGoal, low: u128, high: u128) -> bool {
        let (hit, _, _) = bitwise(high, self.mask);
        hit != 0
    }
}

impl WideGoalImpl of Goal<u256> {
    #[inline(always)]
    fn hit(self: u256, low: u128, high: u128) -> bool {
        let (hit_low, _, _) = bitwise(low, self.low);
        let (hit_high, _, _) = bitwise(high, self.high);
        hit_low != 0 || hit_high != 0
    }
}

#[generate_trait]
pub impl Bfs of BfsTrait {
    /// Search the shortest path between two tiles.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    /// # Panics
    /// * If the dimensions are invalid, or an endpoint is outside the board or not walkable
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        // [Check] Dimensions and endpoints
        let open: u256 = BfsInternal::check(grid, width, height, from, to);
        if from == to {
            return array![].span();
        }
        // [Compute] Constants and endpoints
        let (step, back, free) = BfsInternal::constants(open, width, height);
        let start = BfsInternal::endpoint(@back, height, from);
        let target = BfsInternal::endpoint(@back, height, to);
        if !start.interior && Bits::get(start.around.into(), to) {
            return array![to].span();
        }
        // [Return] Layers until the target neighbourhood is touched, then backtrack
        if width * height <= SMALL_SIZE {
            BfsInternal::search_small(@step, back, @start, @target, height, free.low)
        } else {
            BfsInternal::search_wide(@step, back, @start, @target, height, free)
        }
    }

    /// Length of the shortest path between two tiles, without building the path.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The number of steps, `None` if unreachable
    /// # Panics
    /// * If the dimensions are invalid, or an endpoint is outside the board or not walkable
    fn distance(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Option<u8> {
        // [Check] Dimensions and endpoints
        let open: u256 = BfsInternal::check(grid, width, height, from, to);
        if from == to {
            return Option::Some(0);
        }
        // [Compute] Constants and endpoints
        let (step, back, free) = BfsInternal::constants(open, width, height);
        let start = BfsInternal::endpoint(@back, height, from);
        let target = BfsInternal::endpoint(@back, height, to);
        if !start.interior && Bits::get(start.around.into(), to) {
            return Option::Some(1);
        }
        // [Compute] Layers until the target neighbourhood is touched, only counted
        let mut count: u8 = 0;
        let reached = if width * height <= SMALL_SIZE {
            BfsInternal::advance_small(@step, @start, @target, free.low, ref count)
        } else {
            BfsInternal::advance(@step, @start, @target, free, ref count)
        };
        if !reached {
            return Option::None;
        }
        // [Return] One step per layer, plus the step onto the target
        if count == 1 && start.interior && Bits::get(start.around.into(), to) {
            return Option::Some(1);
        }
        Option::Some(count + 1)
    }

    /// Flood fill: every tile reachable from a position.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The starting position
    /// # Returns
    /// * The bitmap of the reachable tiles, `from` included; an open edge tile is reachable when
    /// it touches the component (it can end a path, not continue it)
    /// # Panics
    /// * If the dimensions are invalid, or `from` is outside the board or not walkable
    fn reachable(grid: felt252, width: u8, height: u8, from: u8) -> felt252 {
        Self::tiles_within_range(grid, width, height, from, 0xff)
    }

    /// Every walkable tile reachable within `range` steps of a position.
    /// # Arguments
    /// * `grid` - The grid, `1` is walkable
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The centre position
    /// * `range` - The number of steps
    /// # Returns
    /// * The bitmap of the tiles in range, `position` included; an open edge tile is in range
    /// when a path of at most `range` steps ends on it
    /// # Panics
    /// * If the dimensions are invalid, or `position` is outside the board or not walkable
    fn tiles_within_range(
        grid: felt252, width: u8, height: u8, position: u8, range: u8,
    ) -> felt252 {
        // [Check] Dimensions and position
        let open: u256 = BfsInternal::check_one(grid, width, height, position);
        let power = Bits::pow(position);
        if range == 0 {
            return power;
        }
        // [Compute] First layer: the open interior neighbourhood
        let (step, back, free) = BfsInternal::constants(open, width, height);
        let centre = BfsInternal::endpoint(@back, height, position);
        let closed = if centre.interior {
            centre.around + power
        } else {
            centre.around
        };
        let first = BfsInternal::and(closed.into(), free);
        // [Compute] Remaining layers, `inner` is the ball of radius `range - 1`
        let small = width * height <= SMALL_SIZE;
        let (ball, inner) = if small {
            BfsInternal::flood_small(@step, first.low, free.low, range - 1)
        } else {
            BfsInternal::flood(@step, first, free, range - 1)
        };
        let ball = if centre.interior {
            ball
        } else {
            ball + power
        };
        // [Return] Open edge tiles end a path: add those next to the inner ball
        let edges = Bits::to_felt(open) - Bits::to_felt(free);
        if edges == 0 {
            return ball;
        }
        let near: u256 = if range == 1 {
            centre.around.into()
        } else if small {
            let next: u256 = BfsInternal::expand_small(@step, inner.try_into().unwrap()).into();
            BfsInternal::or(next, centre.around.into())
        } else {
            let inner_u256: u256 = inner.into();
            let (low, high) = BfsInternal::expand(@step, inner_u256.low, inner_u256.high, inner);
            BfsInternal::or(u256 { low, high }, centre.around.into())
        };
        let reach = BfsInternal::and(near, edges.into());
        Bits::to_felt(BfsInternal::or(reach, ball.into()))
    }
}

#[generate_trait]
pub impl BfsInternal of BfsInternalTrait {
    /// `search` once the endpoints are known, two limbs.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `back` - The backtracking constants
    /// * `start` - The start
    /// * `target` - The target
    /// * `height` - The height of the map
    /// * `free` - The walkable interior tiles
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    #[inline]
    fn search_wide(
        step: @Step, back: Back, start: @Endpoint, target: @Endpoint, height: u8, free: u256,
    ) -> Span<u8> {
        let mut layers: Array<u256> = array![];
        if !Self::advance(step, start, target, free, ref layers) {
            return array![].span();
        }
        // [Check] Adjacent endpoints
        let to = *target.position;
        let mut path: Array<u8> = array![to];
        let mut layers = layers.span();
        if layers.len() == 1 && *start.interior && Bits::get((*start.around).into(), to) {
            return path.span();
        }
        // [Compute] Backtrack from the target, layer by layer
        let (position, power, odd) = if *target.interior {
            (to, *target.power, *target.odd)
        } else {
            let (position, power, odd) = Self::enter(
                @back, height, to, *layers.pop_back().unwrap(),
            );
            path.append(position);
            (position, power, odd)
        };
        Self::backtrack(BoxTrait::new(back), position, power, odd, layers, ref path);
        path.span()
    }

    /// `search` once the endpoints are known, single limb.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `back` - The backtracking constants
    /// * `start` - The start
    /// * `target` - The target
    /// * `height` - The height of the map
    /// * `free` - The walkable interior tiles
    /// # Returns
    /// * The path from the target (included) to the start (excluded), empty if unreachable
    #[inline]
    fn search_small(
        step: @Step, back: Back, start: @Endpoint, target: @Endpoint, height: u8, free: u128,
    ) -> Span<u8> {
        let mut layers: Array<u128> = array![];
        if !Self::advance_small(step, start, target, free, ref layers) {
            return array![].span();
        }
        // [Check] Adjacent endpoints
        let to = *target.position;
        let mut path: Array<u8> = array![to];
        let mut layers = layers.span();
        if layers.len() == 1 && *start.interior && Bits::get((*start.around).into(), to) {
            return path.span();
        }
        // [Compute] Backtrack from the target, layer by layer
        let (position, power, odd) = if *target.interior {
            (to, *target.power, *target.odd)
        } else {
            let last: u128 = *layers.pop_back().unwrap();
            let (position, power, odd) = Self::enter(@back, height, to, last.into());
            path.append(position);
            (position, power, odd)
        };
        Self::backtrack_small(BoxTrait::new(back), position, power, odd, layers, ref path);
        path.span()
    }

    /// Check the dimensions and that both endpoints are inside the board and walkable.
    /// # Arguments
    /// * `grid` - The grid
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `from` - The first endpoint
    /// * `to` - The second endpoint
    /// # Returns
    /// * The grid as `u256`
    #[inline]
    fn check(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u256 {
        Asserter::assert_valid_dimension(width, height);
        Asserter::assert_inside(width, height, from);
        Asserter::assert_inside(width, height, to);
        let open: u256 = grid.into();
        assert(Bits::get(open, from), errors::BFS_POSITION_NOT_WALKABLE);
        assert(Bits::get(open, to), errors::BFS_POSITION_NOT_WALKABLE);
        open
    }

    /// Check the dimensions and that a position is inside the board and walkable.
    /// # Arguments
    /// * `grid` - The grid
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The position
    /// # Returns
    /// * The grid as `u256`
    #[inline]
    fn check_one(grid: felt252, width: u8, height: u8, position: u8) -> u256 {
        Asserter::assert_valid_dimension(width, height);
        Asserter::assert_inside(width, height, position);
        let open: u256 = grid.into();
        assert(Bits::get(open, position), errors::BFS_POSITION_NOT_WALKABLE);
        open
    }

    /// Backtracking constants.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `up_even` - 2^(W-1)
    /// * `down_even` - 2^-(W+1)
    /// # Returns
    /// * The constants
    #[inline]
    fn back_constants(width: u8, up_even: felt252, down_even: felt252) -> Back {
        let up_odd = up_even + up_even;
        let down_odd = down_even + down_even;
        Back {
            width,
            narrow: width - 1,
            wide: width + 1,
            around_even: INV_2 + 2 + 3 * (up_even + down_even),
            around_odd: INV_2 + 2 + 3 * (up_odd + down_odd),
            up_even,
            up_odd,
            down_even,
            down_odd,
            up_wide: up_odd + up_odd,
            down_wide: down_odd + down_odd,
        }
    }

    /// Per-map constants and the walkable interior tiles, with 3 table lookups shared by the
    /// masks (see `Layout::even` and `Layout::interior`).
    /// # Arguments
    /// * `open` - The grid
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// # Returns
    /// * The layer constants, the backtracking constants and the walkable interior tiles
    #[inline]
    fn constants(open: u256, width: u8, height: u8) -> (Step, Back, u256) {
        let row = Bits::pow(width);
        let inv_row = Bits::inv(width);
        let board = Bits::pow(width * height);
        let up = row * INV_2;
        let down = inv_row * INV_2;
        // [Compute] Even rows, ROW * (2^(2W * ceil(H/2)) - 1) / (2^(2W) - 1)
        let top = if height % 2 == 0 {
            board
        } else {
            board * row
        };
        let even: u256 = felt252_div((row - 1) * (top - 1), (row * row - 1).try_into().unwrap())
            .into();
        // [Compute] Interior, (2^(W-1) - 2) * 2^W * (2^(W*(H-2)) - 1) / (2^W - 1)
        let rows = board * inv_row * inv_row - 1;
        let interior = felt252_div((up - 2) * row * rows, (row - 1).try_into().unwrap());
        let step = Step { even_low: even.low, even_high: even.high, up, down };
        (step, Self::back_constants(width, up, down), Self::and(open, interior.into()))
    }

    /// Describe an endpoint.
    /// # Arguments
    /// * `back` - The constants
    /// * `height` - The height of the map
    /// * `position` - The position
    /// # Returns
    /// * The endpoint
    #[inline]
    fn endpoint(back: @Back, height: u8, position: u8) -> Endpoint {
        let back = *back;
        let width = back.width;
        let power = Bits::pow(position);
        let (half, rem) = DivRem::div_rem(position, (2 * width).try_into().unwrap());
        let (x, y, odd) = if rem < width {
            (rem, 2 * half, false)
        } else {
            (rem - width, 2 * half + 1, true)
        };
        let interior = x != 0 && x != width - 1 && y != 0 && y != height - 1;
        let around = if interior {
            power * if odd {
                back.around_odd
            } else {
                back.around_even
            }
        } else {
            Self::around_edge(width, height, position)
        };
        Endpoint { position, power, interior, odd, x, y, half, around }
    }

    /// Hex distance between two endpoints, a lower bound of the path length.
    /// # Arguments
    /// * `start` - The first endpoint
    /// * `target` - The second endpoint
    /// # Returns
    /// * The distance on an empty board
    #[inline]
    fn gap(start: @Endpoint, target: @Endpoint) -> u8 {
        let start = *start;
        let target = *target;
        // [Compute] dq = (x2 - x1) - (y2/2 - y1/2), dr = y2 - y1
        let lhs = target.x + start.half;
        let rhs = start.x + target.half;
        let (dq, dq_negative) = if lhs >= rhs {
            (lhs - rhs, false)
        } else {
            (rhs - lhs, true)
        };
        let (dr, dr_negative) = if target.y >= start.y {
            (target.y - start.y, false)
        } else {
            (start.y - target.y, true)
        };
        // [Return] Same signs: |dq| + |dr|, opposite signs: max(|dq|, |dr|)
        if dq_negative == dr_negative {
            dq + dr
        } else if dq > dr {
            dq
        } else {
            dr
        }
    }

    /// Board neighbours of an edge tile, one direction at a time.
    /// # Arguments
    /// * `width` - The width of the map
    /// * `height` - The height of the map
    /// * `position` - The edge tile
    /// # Returns
    /// * The bits of its neighbours
    fn around_edge(width: u8, height: u8, position: u8) -> felt252 {
        let mut around: felt252 = 0;
        for direction in Self::directions().span() {
            if let Option::Some(next) = LayoutTrait::neighbor(width, height, position, *direction) {
                around += Bits::pow(next);
            }
        }
        around
    }

    /// The 6 directions.
    #[inline]
    fn directions() -> [Direction; 6] {
        [
            Direction::East, Direction::NorthEast, Direction::NorthWest, Direction::West,
            Direction::SouthWest, Direction::SouthEast,
        ]
    }

    /// Advance layer by layer from the start neighbourhood until a layer touches the open
    /// interior neighbours of the target.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `start` - The start
    /// * `target` - The target
    /// * `free` - The walkable interior tiles
    /// * `store` - The layers, the first one is the start neighbourhood (and the start itself
    /// when interior)
    /// # Returns
    /// * `true` if the target is reached, the last stored layer touches it
    #[inline]
    fn advance<S, +Store<S>, +Drop<S>>(
        step: @Step, start: @Endpoint, target: @Endpoint, free: u256, ref store: S,
    ) -> bool {
        // [Compute] Target neighbourhood, empty means unreachable
        let goal = Self::and((*target.around).into(), free);
        if goal.low == 0 && goal.high == 0 {
            return false;
        }
        // [Compute] First layer
        let closed = if *start.interior {
            *start.around + *start.power
        } else {
            *start.around
        };
        let first = Self::and(closed.into(), free);
        let mut low = first.low;
        let mut high = first.high;
        let mut free_low = free.low - low;
        let mut free_high = free.high - high;
        // [Compute] Layers closer than the hex distance minus one cannot touch the goal
        let gap = Self::gap(start, target);
        if gap > 2 {
            if !Self::skip(
                step, gap - 2, ref low, ref high, ref free_low, ref free_high, ref store,
            ) {
                return false;
            }
        }
        // [Compute] Layers with the target test
        if goal.high == 0 {
            Self::reach(step, LowGoal { mask: goal.low }, low, high, free_low, free_high, ref store)
        } else if goal.low == 0 {
            Self::reach(
                step, HighGoal { mask: goal.high }, low, high, free_low, free_high, ref store,
            )
        } else {
            Self::reach(step, goal, low, high, free_low, free_high, ref store)
        }
    }

    /// Store and advance `count` layers without the target test, 4 per iteration.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `count` - The number of layers
    /// * `low`, `high` - The current layer, replaced by the next one
    /// * `free_low`, `free_high` - The unvisited walkable interior tiles, updated
    /// * `store` - The layers
    /// # Returns
    /// * `false` if the frontier runs out
    #[inline]
    fn skip<S, +Store<S>, +Drop<S>>(
        step: @Step,
        count: u8,
        ref low: u128,
        ref high: u128,
        ref free_low: u128,
        ref free_high: u128,
        ref store: S,
    ) -> bool {
        let mut count: felt252 = count.into();
        loop {
            if count == 0 {
                break true;
            }
            count -= 1;
            store.push(low, high);
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                break false;
            }
            if count == 0 {
                break true;
            }
            count -= 1;
            store.push(low, high);
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                break false;
            }
            if count == 0 {
                break true;
            }
            count -= 1;
            store.push(low, high);
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                break false;
            }
            if count == 0 {
                break true;
            }
            count -= 1;
            store.push(low, high);
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                break false;
            }
        }
    }

    /// Layers with the target test, 4 per iteration.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `goal` - The target neighbourhood
    /// * `low`, `high` - The current layer
    /// * `free_low`, `free_high` - The unvisited walkable interior tiles
    /// * `store` - The layers
    /// # Returns
    /// * `true` if the target is reached
    #[inline]
    fn reach<S, G, +Store<S>, +Drop<S>, +Goal<G>, +Copy<G>, +Drop<G>>(
        step: @Step, goal: G, low: u128, high: u128, free_low: u128, free_high: u128, ref store: S,
    ) -> bool {
        let mut low = low;
        let mut high = high;
        let mut free_low = free_low;
        let mut free_high = free_high;
        loop {
            store.push(low, high);
            if goal.hit(low, high) {
                return true;
            }
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                return false;
            }
            store.push(low, high);
            if goal.hit(low, high) {
                return true;
            }
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                return false;
            }
            store.push(low, high);
            if goal.hit(low, high) {
                return true;
            }
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                return false;
            }
            store.push(low, high);
            if goal.hit(low, high) {
                return true;
            }
            if !Self::layer(step, ref low, ref high, ref free_low, ref free_high) {
                return false;
            }
        }
    }

    /// One layer: the unvisited neighbours of the frontier.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `low`, `high` - The frontier, replaced by the next layer
    /// * `free_low`, `free_high` - The unvisited walkable interior tiles, updated
    /// # Returns
    /// * `false` if the frontier is empty
    #[inline(always)]
    fn layer(
        step: @Step, ref low: u128, ref high: u128, ref free_low: u128, ref free_high: u128,
    ) -> bool {
        let felt: felt252 = low.into() + high.into() * TWO_POW_128;
        if felt == 0 {
            return false;
        }
        let (next_low, next_high) = Self::expand(step, low, high, felt);
        let (next_low, _, _) = bitwise(next_low, free_low);
        let (next_high, _, _) = bitwise(next_high, free_high);
        free_low -= next_low;
        free_high -= next_high;
        low = next_low;
        high = next_high;
        true
    }

    /// Flood `steps` more layers from a first layer.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `first` - The first layer
    /// * `free` - The walkable interior tiles
    /// * `steps` - The number of layers after the first
    /// # Returns
    /// * The ball and the ball of one step less
    #[inline]
    fn flood(step: @Step, first: u256, free: u256, steps: u8) -> (felt252, felt252) {
        let mut low = first.low;
        let mut high = first.high;
        let mut free_low = free.low - low;
        let mut free_high = free.high - high;
        let total = Bits::to_felt(free);
        let mut inner: felt252 = 0;
        let mut steps = steps;
        while steps != 0 {
            let felt: felt252 = low.into() + high.into() * TWO_POW_128;
            if felt == 0 {
                break;
            }
            steps -= 1;
            inner = total - free_low.into() - free_high.into() * TWO_POW_128;
            let (next_low, next_high) = Self::expand(step, low, high, felt);
            let (next_low, _, _) = bitwise(next_low, free_low);
            let (next_high, _, _) = bitwise(next_high, free_high);
            free_low -= next_low;
            free_high -= next_high;
            low = next_low;
            high = next_high;
        }
        let ball = total - free_low.into() - free_high.into() * TWO_POW_128;
        if steps != 0 {
            // Exhausted: the ball is closed
            return (ball, ball);
        }
        (ball, inner)
    }

    /// Hex dilation of a frontier of interior tiles, see `Layout::expand`. With the West pairs
    /// `P` split by row parity, the up neighbours are `Pe * 2^(W-1) + Po * 2^W`, that is
    /// `(2P - Pe) * 2^(W-1)`, and the down neighbours `(2P - Pe) * 2^-(W+1)`.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `low` - The low limb of the frontier
    /// * `high` - The high limb of the frontier
    /// * `felt` - The frontier as a felt
    /// # Returns
    /// * The frontier and its neighbours
    #[inline(always)]
    fn expand(step: @Step, low: u128, high: u128, felt: felt252) -> (u128, u128) {
        let step = *step;
        // [Compute] Frontier and its West neighbours, then split by row parity
        let double: u256 = (felt + felt).into();
        let (double_low, double_high) = (double.low, double.high);
        let (_, _, pairs_low) = bitwise(low, double_low);
        let (_, _, pairs_high) = bitwise(high, double_high);
        let (even_low, _, _) = bitwise(pairs_low, step.even_low);
        let (even_high, _, _) = bitwise(pairs_high, step.even_high);
        let pairs: felt252 = pairs_low.into() + pairs_high.into() * TWO_POW_128;
        let even: felt252 = even_low.into() + even_high.into() * TWO_POW_128;
        let rows = pairs + pairs - even;
        // [Compute] NE/NW, SE/SW and East neighbours
        let up: u256 = (rows * step.up).into();
        let down: u256 = (rows * step.down).into();
        let east: u256 = (felt * INV_2).into();
        // [Return] Union
        let (_, _, side_low) = bitwise(pairs_low, east.low);
        let (_, _, side_high) = bitwise(pairs_high, east.high);
        let (_, _, vertical_low) = bitwise(up.low, down.low);
        let (_, _, vertical_high) = bitwise(up.high, down.high);
        let (_, _, low) = bitwise(side_low, vertical_low);
        let (_, _, high) = bitwise(side_high, vertical_high);
        (low, high)
    }

    /// Backtrack through the layers, four per iteration.
    /// # Arguments
    /// * `back` - The constants
    /// * `position` - The current tile, interior
    /// * `power` - 2^position
    /// * `odd` - Whether its row is odd
    /// * `layers` - The remaining layers, the last one holds a neighbour of the current tile
    /// * `path` - The path
    #[inline]
    fn backtrack(
        back: Box<Back>,
        position: u8,
        power: felt252,
        odd: bool,
        layers: Span<u256>,
        ref path: Array<u8>,
    ) {
        let mut position = position;
        let mut power = power;
        let mut odd = odd;
        let mut layers = layers;
        while let Option::Some(four) = layers.multi_pop_back::<4>() {
            let [first, second, third, fourth] = (*four).unbox();
            let (next, next_power, next_odd) = Self::back(back, position, power, odd, fourth);
            path.append(next);
            let (next, next_power, next_odd) = Self::back(back, next, next_power, next_odd, third);
            path.append(next);
            let (next, next_power, next_odd) = Self::back(back, next, next_power, next_odd, second);
            path.append(next);
            let (next, next_power, next_odd) = Self::back(back, next, next_power, next_odd, first);
            path.append(next);
            position = next;
            power = next_power;
            odd = next_odd;
        }
        // [Compute] At most 3 layers left, no loop
        if let Option::Some(two) = layers.multi_pop_back::<2>() {
            let [first, second] = (*two).unbox();
            let (next, next_power, next_odd) = Self::back(back, position, power, odd, second);
            path.append(next);
            let (next, next_power, next_odd) = Self::back(back, next, next_power, next_odd, first);
            path.append(next);
            position = next;
            power = next_power;
            odd = next_odd;
        }
        if let Option::Some(layer) = layers.pop_back() {
            let (next, _, _) = Self::back(back, position, power, odd, *layer);
            path.append(next);
        }
    }

    /// One backtracking step: the lowest neighbour of the current tile in the previous layer,
    /// intersected on the limbs that hold the 6 neighbours, identified among the 6 offsets.
    /// # Arguments
    /// * `back` - The constants
    /// * `position` - The current tile, interior
    /// * `power` - 2^position
    /// * `odd` - Whether its row is odd
    /// * `layer` - The previous layer, it holds a neighbour of the current tile
    /// # Returns
    /// * The neighbour, its power and its row parity
    #[inline(always)]
    fn back(
        back: Box<Back>, position: u8, power: felt252, odd: bool, layer: u256,
    ) -> (u8, felt252, bool) {
        let boxed = back;
        let back = back.unbox();
        // [Compute] Neighbours in the layer, lowest one
        let mask: u256 = (power * if odd {
            back.around_odd
        } else {
            back.around_even
        }).into();
        let lowest: felt252 = if mask.high == 0 {
            let (hit, _, _) = bitwise(mask.low, layer.low);
            let (rest, _, _) = bitwise(hit, hit - 1);
            hit.into() - rest.into()
        } else if mask.low == 0 {
            let (hit, _, _) = bitwise(mask.high, layer.high);
            let (rest, _, _) = bitwise(hit, hit - 1);
            (hit.into() - rest.into()) * TWO_POW_128
        } else {
            let (hit, _, _) = bitwise(mask.low, layer.low);
            if hit != 0 {
                let (rest, _, _) = bitwise(hit, hit - 1);
                hit.into() - rest.into()
            } else {
                let (hit, _, _) = bitwise(mask.high, layer.high);
                let (rest, _, _) = bitwise(hit, hit - 1);
                (hit.into() - rest.into()) * TWO_POW_128
            }
        };
        Self::identify(boxed, position, power, odd, lowest)
    }

    /// Identify the lowest neighbour among the 6 offsets, in increasing order.
    /// # Arguments
    /// * `back` - The constants
    /// * `position` - The current tile
    /// * `power` - 2^position
    /// * `odd` - Whether its row is odd
    /// * `lowest` - The bit of the neighbour
    /// # Returns
    /// * The neighbour, its power and its row parity
    #[inline(always)]
    fn identify(
        back: Box<Back>, position: u8, power: felt252, odd: bool, lowest: felt252,
    ) -> (u8, felt252, bool) {
        let back = back.unbox();
        let width = back.width;
        if odd {
            if lowest == power * back.down_odd {
                (position - width, lowest, false)
            } else if lowest == power * back.down_wide {
                (position - back.narrow, lowest, false)
            } else if lowest == power * INV_2 {
                (position - 1, lowest, true)
            } else if lowest == power * 2 {
                (position + 1, lowest, true)
            } else if lowest == power * back.up_odd {
                (position + width, lowest, false)
            } else {
                (position + back.wide, lowest, false)
            }
        } else if lowest == power * back.down_even {
            (position - back.wide, lowest, true)
        } else if lowest == power * back.down_odd {
            (position - width, lowest, true)
        } else if lowest == power * INV_2 {
            (position - 1, lowest, false)
        } else if lowest == power * 2 {
            (position + 1, lowest, false)
        } else if lowest == power * back.up_even {
            (position + back.narrow, lowest, true)
        } else {
            (position + width, lowest, true)
        }
    }

    /// `advance` for boards of at most 128 bits, on a single limb.
    #[inline]
    fn advance_small<S, +SmallStore<S>, +Drop<S>>(
        step: @Step, start: @Endpoint, target: @Endpoint, free: u128, ref store: S,
    ) -> bool {
        // [Compute] Target neighbourhood, empty means unreachable
        let (goal, _, _) = bitwise((*target.around).try_into().unwrap(), free);
        if goal == 0 {
            return false;
        }
        // [Compute] First layer
        let closed = if *start.interior {
            *start.around + *start.power
        } else {
            *start.around
        };
        let (mut layer, _, _) = bitwise(closed.try_into().unwrap(), free);
        let mut free = free - layer;
        // [Compute] Layers closer than the hex distance minus one cannot touch the goal
        let gap = Self::gap(start, target);
        if gap > 2 {
            let mut count: felt252 = (gap - 2).into();
            let alive = loop {
                if count == 0 {
                    break true;
                }
                count -= 1;
                store.push(layer);
                if !Self::layer_small(step, ref layer, ref free) {
                    break false;
                }
                if count == 0 {
                    break true;
                }
                count -= 1;
                store.push(layer);
                if !Self::layer_small(step, ref layer, ref free) {
                    break false;
                }
            };
            if !alive {
                return false;
            }
        }
        // [Compute] Layers with the target test
        loop {
            store.push(layer);
            let (hit, _, _) = bitwise(layer, goal);
            if hit != 0 {
                break true;
            }
            if !Self::layer_small(step, ref layer, ref free) {
                break false;
            }
            store.push(layer);
            let (hit, _, _) = bitwise(layer, goal);
            if hit != 0 {
                break true;
            }
            if !Self::layer_small(step, ref layer, ref free) {
                break false;
            }
        }
    }

    /// One layer on a single limb.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `layer` - The frontier, replaced by the next layer
    /// * `free` - The unvisited walkable interior tiles, updated
    /// # Returns
    /// * `false` if the frontier is empty
    #[inline(always)]
    fn layer_small(step: @Step, ref layer: u128, ref free: u128) -> bool {
        if layer == 0 {
            return false;
        }
        let (next, _, _) = bitwise(Self::expand_small(step, layer), free);
        free -= next;
        layer = next;
        true
    }

    /// Hex dilation for boards of at most 128 bits, see `expand`: every shift fits the limb.
    /// # Arguments
    /// * `step` - The layer constants
    /// * `frontier` - The frontier, interior tiles only
    /// # Returns
    /// * The frontier and its neighbours
    #[inline(always)]
    fn expand_small(step: @Step, frontier: u128) -> u128 {
        let step = *step;
        let (_, _, pairs) = bitwise(frontier, frontier + frontier);
        let (even, _, _) = bitwise(pairs, step.even_low);
        let pairs_felt: felt252 = pairs.into();
        let rows = pairs_felt + pairs_felt - even.into();
        let up: u128 = (rows * step.up).try_into().unwrap();
        let down: u128 = (rows * step.down).try_into().unwrap();
        let east: u128 = (frontier.into() * INV_2).try_into().unwrap();
        let (_, _, side) = bitwise(pairs, east);
        let (_, _, vertical) = bitwise(up, down);
        let (_, _, next) = bitwise(side, vertical);
        next
    }

    /// Flood `steps` more layers from a first layer, single limb, see `flood`.
    #[inline]
    fn flood_small(step: @Step, first: u128, free: u128, steps: u8) -> (felt252, felt252) {
        let mut layer = first;
        let mut unvisited = free - first;
        let total: felt252 = free.into();
        let mut inner: felt252 = 0;
        let mut steps = steps;
        while steps != 0 {
            if layer == 0 {
                break;
            }
            steps -= 1;
            inner = total - unvisited.into();
            let (next, _, _) = bitwise(Self::expand_small(step, layer), unvisited);
            unvisited -= next;
            layer = next;
        }
        let ball = total - unvisited.into();
        if steps != 0 {
            return (ball, ball);
        }
        (ball, inner)
    }

    /// Backtrack through the layers of a single limb, four per iteration.
    #[inline]
    fn backtrack_small(
        back: Box<Back>,
        position: u8,
        power: felt252,
        odd: bool,
        layers: Span<u128>,
        ref path: Array<u8>,
    ) {
        let mut position = position;
        let mut power = power;
        let mut odd = odd;
        let mut layers = layers;
        while let Option::Some(four) = layers.multi_pop_back::<4>() {
            let [first, second, third, fourth] = (*four).unbox();
            let (next, next_power, next_odd) = Self::back_small(back, position, power, odd, fourth);
            path.append(next);
            let (next, next_power, next_odd) = Self::back_small(
                back, next, next_power, next_odd, third,
            );
            path.append(next);
            let (next, next_power, next_odd) = Self::back_small(
                back, next, next_power, next_odd, second,
            );
            path.append(next);
            let (next, next_power, next_odd) = Self::back_small(
                back, next, next_power, next_odd, first,
            );
            path.append(next);
            position = next;
            power = next_power;
            odd = next_odd;
        }
        // [Compute] At most 3 layers left, no loop
        if let Option::Some(two) = layers.multi_pop_back::<2>() {
            let [first, second] = (*two).unbox();
            let (next, next_power, next_odd) = Self::back_small(back, position, power, odd, second);
            path.append(next);
            let (next, next_power, next_odd) = Self::back_small(
                back, next, next_power, next_odd, first,
            );
            path.append(next);
            position = next;
            power = next_power;
            odd = next_odd;
        }
        if let Option::Some(layer) = layers.pop_back() {
            let (next, _, _) = Self::back_small(back, position, power, odd, *layer);
            path.append(next);
        }
    }

    /// One backtracking step on a single limb, see `back`.
    #[inline(always)]
    fn back_small(
        back: Box<Back>, position: u8, power: felt252, odd: bool, layer: u128,
    ) -> (u8, felt252, bool) {
        let boxed = back;
        let back = back.unbox();
        let mask: u128 = (power * if odd {
            back.around_odd
        } else {
            back.around_even
        })
            .try_into()
            .unwrap();
        let (hit, _, _) = bitwise(mask, layer);
        let (rest, _, _) = bitwise(hit, hit - 1);
        Self::identify(boxed, position, power, odd, hit.into() - rest.into())
    }

    /// First backtracking step from an edge target: its first neighbour in the last layer.
    /// # Arguments
    /// * `back` - The constants
    /// * `height` - The height of the map
    /// * `position` - The edge target
    /// * `layer` - The last layer, it holds a neighbour of the target
    /// # Returns
    /// * The neighbour, its power and its row parity
    fn enter(back: @Back, height: u8, position: u8, layer: u256) -> (u8, felt252, bool) {
        let width = *back.width;
        for direction in Self::directions().span() {
            if let Option::Some(next) = LayoutTrait::neighbor(width, height, position, *direction) {
                if Bits::get(layer, next) {
                    let (_, odd) = LayoutTrait::parity(width, next);
                    return (next, Bits::pow(next), odd);
                }
            }
        }
        panic!("unreachable")
    }

    /// `u256` AND with the bitwise builtin.
    #[inline(always)]
    fn and(lhs: u256, rhs: u256) -> u256 {
        let (low, _, _) = bitwise(lhs.low, rhs.low);
        let (high, _, _) = bitwise(lhs.high, rhs.high);
        u256 { low, high }
    }

    /// `u256` OR with the bitwise builtin.
    #[inline(always)]
    fn or(lhs: u256, rhs: u256) -> u256 {
        let (_, _, low) = bitwise(lhs.low, rhs.low);
        let (_, _, high) = bitwise(lhs.high, rhs.high);
        u256 { low, high }
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::dict::{Felt252Dict, Felt252DictTrait};

    // Internal imports

    use origami_hexmap::generators::caver::Caver;
    use origami_hexmap::generators::digger::Digger;
    use origami_hexmap::generators::mazer::Mazer;
    use origami_hexmap::helpers::bits::Bits;
    use origami_hexmap::helpers::layout::LayoutTrait;
    use origami_hexmap::helpers::printer::HexPrinter;
    use origami_hexmap::tests::fixtures::*;
    use origami_hexmap::tests::variants::Variants;

    // Local imports

    use super::{Bfs, BfsInternal};

    // Helpers

    /// Whether two tiles are neighbours.
    fn adjacent(width: u8, height: u8, lhs: u8, rhs: u8) -> bool {
        for direction in BfsInternal::directions().span() {
            if LayoutTrait::neighbor(width, height, lhs, *direction) == Option::Some(rhs) {
                return true;
            }
        }
        false
    }

    /// Scalar queue BFS from `from` over the walkable interior tiles; an edge tile ends a path
    /// only. Distances plus one, 0 when unreachable, indexed by position.
    fn reference_all(grid: felt252, width: u8, height: u8, from: u8) -> Felt252Dict<u8> {
        let interior: u256 = LayoutTrait::interior(width, height).into();
        let open: u256 = grid.into();
        let inner = open & interior;
        let mut distances: Felt252Dict<u8> = Default::default();
        distances.insert(from.into(), 1);
        // An edge start only steps to its neighbours
        let mut queue: Array<u8> = array![from];
        while let Option::Some(current) = queue.pop_front() {
            let next = distances.get(current.into()) + 1;
            for direction in BfsInternal::directions().span() {
                if let Option::Some(tile) =
                    LayoutTrait::neighbor(width, height, current, *direction) {
                    if Bits::get(open, tile) && distances.get(tile.into()) == 0 {
                        distances.insert(tile.into(), next);
                        // Edge tiles end a path
                        if Bits::get(inner, tile) {
                            queue.append(tile);
                        }
                    }
                }
            }
        }
        distances
    }

    /// Scalar reference distance, 0 when unreachable or equal.
    fn reference(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> u32 {
        let mut distances = reference_all(grid, width, height, from);
        let distance = distances.get(to.into());
        if distance == 0 || from == to {
            0
        } else {
            (distance - 1).into()
        }
    }

    /// Check `search` and `distance` against an expected length, and the path itself.
    fn check_with(
        grid: felt252, width: u8, height: u8, from: u8, to: u8, expected: u32,
    ) -> Span<u8> {
        let path = Bfs::search(grid, width, height, from, to);
        assert!(path.len() == expected, "length {} -> {}: {}", from, to, path.len());
        let distance = Bfs::distance(grid, width, height, from, to);
        if from == to {
            assert!(distance == Option::Some(0));
        } else if expected == 0 {
            assert!(distance == Option::None);
        } else {
            assert!(distance == Option::Some(expected.try_into().unwrap()));
        }
        if expected == 0 {
            return path;
        }
        // [Check] From the target to a neighbour of the start, through walkable interior tiles
        let open: u256 = grid.into();
        let interior: u256 = LayoutTrait::interior(width, height).into();
        assert!(*path[0] == to);
        let mut index = 1;
        while index != path.len() {
            let tile = *path[index];
            assert!(Bits::get(open & interior, tile));
            assert!(adjacent(width, height, *path[index - 1], tile));
            index += 1;
        }
        assert!(adjacent(width, height, *path[path.len() - 1], from));
        // [Check] Determinism
        assert!(Bfs::search(grid, width, height, from, to) == path);
        path
    }

    /// Check a pair against the reference.
    fn check(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        check_with(grid, width, height, from, to, reference(grid, width, height, from, to))
    }

    /// Check pairs of a sample of walkable tiles: starts one in `stride`, targets one in 5.
    fn check_sample(grid: felt252, width: u8, height: u8, stride: u8) {
        let open: u256 = grid.into();
        let size: u16 = width.into() * height.into();
        let mut from: u16 = 0;
        while from < size {
            let start: u8 = from.try_into().unwrap();
            if Bits::get(open, start) {
                let mut distances = reference_all(grid, width, height, start);
                let mut to: u16 = (from * 7) % 5;
                while to < size {
                    let target: u8 = to.try_into().unwrap();
                    if Bits::get(open, target) {
                        let distance = distances.get(to.into());
                        let expected = if distance == 0 || to == from {
                            0
                        } else {
                            distance - 1
                        };
                        check_with(grid, width, height, start, target, expected.into());
                    }
                    to += 5;
                }
            }
            from += stride.into();
        }
    }

    /// Check `tiles_within_range` against the reference distances.
    fn check_range(grid: felt252, width: u8, height: u8, position: u8, range: u8) {
        let ball: u256 = Bfs::tiles_within_range(grid, width, height, position, range).into();
        let mut distances = reference_all(grid, width, height, position);
        let size: u16 = width.into() * height.into();
        let mut to: u16 = 0;
        while to < size {
            let distance = distances.get(to.into());
            let expected = distance != 0 && distance - 1 <= range;
            assert!(
                Bits::get(ball, to.try_into().unwrap()) == expected,
                "range {} -> {} ({})",
                position,
                to,
                range,
            );
            to += 1;
        }
    }

    /// Check `reachable` against the reference distances.
    fn check_reachable(grid: felt252, width: u8, height: u8, from: u8) {
        check_range(grid, width, height, from, 0xff);
        assert!(
            Bfs::reachable(
                grid, width, height, from,
            ) == Bfs::tiles_within_range(grid, width, height, from, 0xff),
        );
    }

    /// Check every range from 0 to `max` around a position.
    fn check_ranges(grid: felt252, width: u8, height: u8, position: u8, max: u8) {
        let mut range: u8 = 0;
        while range <= max {
            check_range(grid, width, height, position, range);
            range += 1;
        }
    }

    // Fixtures

    #[test]
    fn test_bfs_fixtures_17x14() {
        check(EMPTY_17X14, 17, 14, EMPTY_17X14_NEAR_FROM, EMPTY_17X14_NEAR_TO);
        check(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, EMPTY_17X14_FAR_TO);
        check(CAVE_17X14, 17, 14, CAVE_17X14_NEAR_FROM, CAVE_17X14_NEAR_TO);
        check(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
        check(MAZE_17X14, 17, 14, MAZE_17X14_NEAR_FROM, MAZE_17X14_NEAR_TO);
        check(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM, MAZE_17X14_FAR_TO);
        check(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_NEAR_FROM, SERPENTINE_17X14_NEAR_TO);
        check(SERPENTINE_17X14, 17, 14, SERPENTINE_17X14_FAR_FROM, SERPENTINE_17X14_FAR_TO);
        check(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_NEAR_FROM, UNREACHABLE_17X14_NEAR_TO);
        check(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM, UNREACHABLE_17X14_FAR_TO);
    }

    #[test]
    fn test_bfs_fixtures_7x7() {
        check(EMPTY_7X7, 7, 7, EMPTY_7X7_NEAR_FROM, EMPTY_7X7_NEAR_TO);
        check(EMPTY_7X7, 7, 7, EMPTY_7X7_FAR_FROM, EMPTY_7X7_FAR_TO);
        check(CAVE_7X7, 7, 7, CAVE_7X7_NEAR_FROM, CAVE_7X7_NEAR_TO);
        check(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM, CAVE_7X7_FAR_TO);
        check(MAZE_7X7, 7, 7, MAZE_7X7_NEAR_FROM, MAZE_7X7_NEAR_TO);
        check(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
        check(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_NEAR_FROM, SERPENTINE_7X7_NEAR_TO);
        check(SERPENTINE_7X7, 7, 7, SERPENTINE_7X7_FAR_FROM, SERPENTINE_7X7_FAR_TO);
        check(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_NEAR_FROM, UNREACHABLE_7X7_NEAR_TO);
        check(UNREACHABLE_7X7, 7, 7, UNREACHABLE_7X7_FAR_FROM, UNREACHABLE_7X7_FAR_TO);
    }

    #[test]
    fn test_bfs_reference_matches_layers() {
        // The queue reference agrees with the layered reference of the fixtures
        let mut to: u8 = 0;
        while to != 49 {
            if Bits::get(MAZE_7X7.into(), to) {
                assert!(
                    reference(
                        MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, to,
                    ) == Variants::bfs_distance(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, to),
                );
            }
            to += 1;
        }
    }

    #[test]
    fn test_bfs_search_print() {
        let path = Bfs::search(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, MAZE_7X7_FAR_TO);
        HexPrinter::print_with_path(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, path);
        println!("{:?}", path);
        let path = Bfs::search(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, CAVE_17X14_FAR_TO);
        HexPrinter::print_with_path(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, path);
        println!("{:?}", path);
    }

    // Pseudo-random grids and sizes

    #[test]
    fn test_bfs_sample_cave_17x14() {
        check_sample(CAVE_17X14, 17, 14, 23);
    }

    #[test]
    fn test_bfs_sample_maze_17x14() {
        check_sample(MAZE_17X14, 17, 14, 31);
    }

    #[test]
    fn test_bfs_sample_random_caves() {
        let mut seed: felt252 = 1;
        while seed != 4 {
            check_sample(Caver::generate(17, 14, 3, seed), 17, 14, 47);
            check_sample(Caver::generate(19, 13, 3, seed), 19, 13, 47);
            check_sample(Caver::generate(7, 7, 2, seed), 7, 7, 3);
            seed += 1;
        }
    }

    #[test]
    fn test_bfs_sample_random_mazes() {
        check_sample(Mazer::generate(17, 14, 1, 'MAZE'), 17, 14, 29);
        check_sample(Mazer::generate(19, 13, 0, 'MAZE'), 19, 13, 37);
        check_sample(Mazer::generate(7, 7, 0, 'MAZE'), 7, 7, 2);
    }

    #[test]
    fn test_bfs_sizes() {
        // 3x3: a single interior tile
        let grid: felt252 = Bits::pow(4);
        check_with(grid, 3, 3, 4, 4, 0);
        // 8x16 = 128 bits, the largest single-limb board, and 9x15 = 135 bits
        check_sample(LayoutTrait::interior(8, 16), 8, 16, 13);
        check_sample(LayoutTrait::interior(9, 15), 9, 15, 17);
        // Wide and tall boards: 83x3 (one interior row), 25x10, 3x83 (one interior column)
        let row = LayoutTrait::interior(83, 3);
        check_with(row, 83, 3, 84, 164, 80);
        check_sample(LayoutTrait::interior(25, 10), 25, 10, 41);
        let column = LayoutTrait::interior(3, 83);
        check_with(column, 3, 83, 4, 244, 80);
    }

    // Edge endpoints

    /// `EMPTY_17X14` with open edge tiles.
    fn empty_with(tiles: Span<u8>) -> felt252 {
        let mut grid = EMPTY_17X14;
        let mut tiles = tiles;
        while let Option::Some(tile) = tiles.pop_front() {
            grid += Bits::pow(*tile);
        }
        grid
    }

    #[test]
    fn test_bfs_edge_to_interior() {
        // Bottom (3), top (225), right (68, x = 0) and left (84, x = 16) entrances
        let grid = empty_with(array![3, 225, 68, 84].span());
        let targets = array![18, 120, 200, 3, 225, 68, 84].span();
        for from in array![3_u8, 225, 68, 84].span() {
            for to in targets {
                check(grid, 17, 14, *from, *to);
            }
        }
        check_reachable(grid, 17, 14, 3);
        check_reachable(grid, 17, 14, 120);
    }

    #[test]
    fn test_bfs_edge_to_edge_no_shortcut() {
        // The whole bottom row open: paths between bottom tiles go through the interior, up
        // one row, 9 tiles along it and down (11 steps), never along the edge (10 steps)
        let grid = empty_with(array![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].span());
        let path = check(grid, 17, 14, 2, 12);
        assert!(path.len() == 11);
        // Adjacent edge tiles: one step
        assert!(check(grid, 17, 14, 4, 5) == array![5].span());
        assert!(check(grid, 17, 14, 5, 4) == array![4].span());
        check_reachable(grid, 17, 14, 8);
    }

    #[test]
    fn test_bfs_edge_adjacent_interior() {
        // Edge start next to an interior target and the reverse
        let grid = empty_with(array![3].span());
        assert!(check(grid, 17, 14, 3, 19) == array![19].span());
        assert!(check(grid, 17, 14, 19, 3) == array![3].span());
        // Interior start next to an interior target
        assert!(check(grid, 17, 14, 19, 20) == array![20].span());
    }

    #[test]
    fn test_bfs_corners() {
        // Corner 16 (x = 16, y = 0) touches the interior tile 32; corner 0 only edge tiles
        let grid = empty_with(array![0, 1, 16].span());
        check(grid, 17, 14, 16, 200);
        check(grid, 17, 14, 200, 16);
        assert!(check(grid, 17, 14, 0, 1) == array![1].span());
        check(grid, 17, 14, 0, 200);
        check(grid, 17, 14, 16, 0);
        check_reachable(grid, 17, 14, 0);
        check_reachable(grid, 17, 14, 16);
        check_ranges(grid, 17, 14, 16, 4);
    }

    #[test]
    fn test_bfs_edge_closed() {
        // An entrance with no open interior neighbour is only reachable from its edge neighbours
        let grid = UNREACHABLE_17X14 - Bits::pow(18) - Bits::pow(19) + Bits::pow(2);
        check(grid, 17, 14, 2, 120);
        check(grid, 17, 14, 120, 2);
        check_reachable(grid, 17, 14, 2);
    }

    #[test]
    fn test_bfs_digger_entrances() {
        // Entrances dug by the digger on a cave and on an empty board
        let cave = Digger::corridor(17, 14, 0, 3, CAVE_17X14, 'DIG');
        check_sample(cave, 17, 14, 19);
        check(cave, 17, 14, 3, CAVE_17X14_FAR_TO);
        let maze = Digger::maze(17, 14, 0, 230, 0, 'DIG');
        check_sample(maze, 17, 14, 23);
        let small = Digger::maze(7, 7, 0, 3, 0, 'DIG');
        check_sample(small, 7, 7, 2);
    }

    // Reachable and range

    #[test]
    fn test_bfs_reachable_fixtures() {
        check_reachable(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_FROM);
        check_reachable(UNREACHABLE_17X14, 17, 14, UNREACHABLE_17X14_FAR_TO);
        check_reachable(CAVE_7X7, 7, 7, CAVE_7X7_FAR_FROM);
        check_reachable(MAZE_17X14, 17, 14, MAZE_17X14_FAR_FROM);
    }

    #[test]
    fn test_bfs_reachable_matches_caver() {
        let mut seed: felt252 = 1;
        while seed != 4 {
            let cave = Caver::generate(17, 14, 3, seed);
            let open: u256 = cave.into();
            let mut position: u8 = 18;
            while position < 220 {
                if Bits::get(open, position) {
                    assert!(
                        Bfs::reachable(
                            cave, 17, 14, position,
                        ) == Caver::keep_component(cave, 17, 14, position),
                    );
                }
                position += 37;
            }
            seed += 1;
        }
    }

    #[test]
    fn test_bfs_range_fixtures() {
        check_ranges(CAVE_17X14, 17, 14, CAVE_17X14_FAR_FROM, 6);
        check_ranges(MAZE_7X7, 7, 7, MAZE_7X7_FAR_FROM, 4);
        check_range(EMPTY_17X14, 17, 14, EMPTY_17X14_FAR_FROM, 30);
    }

    #[test]
    fn test_bfs_range_zero() {
        assert!(Bfs::tiles_within_range(CAVE_17X14, 17, 14, 52, 0) == Bits::pow(52));
    }

    // Panics

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_bfs_search_revert_start_wall() {
        let _ = Bfs::search(UNREACHABLE_17X14, 17, 14, 25, 18);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_bfs_search_revert_target_wall() {
        let _ = Bfs::search(UNREACHABLE_17X14, 17, 14, 18, 25);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_bfs_search_revert_edge_wall() {
        let _ = Bfs::search(EMPTY_17X14, 17, 14, 3, 18);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not inside')]
    fn test_bfs_search_revert_outside() {
        let _ = Bfs::search(EMPTY_17X14, 17, 14, 18, 238);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_bfs_search_revert_dimension() {
        let _ = Bfs::search(EMPTY_17X14, 18, 14, 19, 20);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_bfs_distance_revert_wall() {
        let _ = Bfs::distance(EMPTY_17X14, 17, 14, 18, 0);
    }

    #[test]
    #[should_panic(expected: 'Bfs: position not walkable')]
    fn test_bfs_reachable_revert_wall() {
        let _ = Bfs::reachable(EMPTY_17X14, 17, 14, 0);
    }

    #[test]
    #[should_panic(expected: 'Asserter: position not inside')]
    fn test_bfs_range_revert_outside() {
        let _ = Bfs::tiles_within_range(EMPTY_17X14, 17, 14, 250, 3);
    }

    #[test]
    #[should_panic(expected: 'Asserter: invalid dimension')]
    fn test_bfs_range_revert_dimension() {
        let _ = Bfs::tiles_within_range(EMPTY_7X7, 2, 7, 8, 3);
    }
}
