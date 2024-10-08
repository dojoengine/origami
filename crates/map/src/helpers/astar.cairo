//! A* algorithm implementation for pathfinding.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_map::helpers::heap::{Heap, HeapTrait};
use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::{Direction, DirectionTrait};

#[generate_trait]
pub impl Astar of AstarTrait {
    /// Search for the shortest path from a start to a target position.
    /// # Arguments
    /// * `grid` - The grid to search (1 is walkable and 0 is not)
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `from` - The starting position
    /// * `to` - The target position
    /// # Returns
    /// * The path from the target (incl.) to the start (excl.)
    #[inline]
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        // [Check] The start and target are walkable
        if Bitmap::get(grid, from) == 0 || Bitmap::get(grid, to) == 0 {
            return array![].span();
        }
        // [Effect] Initialize the start and target nodes
        let mut start = NodeTrait::new(from, 0, 0, 0);
        let target = NodeTrait::new(to, 0, 0, 0);
        // [Effect] Initialize the heap and the visited nodes
        let mut heap: Heap<Node> = HeapTrait::new();
        let mut visited: Felt252Dict<bool> = Default::default();
        heap.add(start);
        // [Compute] Evaluate the path until the target is reached
        while let Option::Some(current) = heap.pop_front() {
            // [Compute] Get the less expensive node
            visited.insert(current.position.into(), true);
            // [Check] Stop if we reached the target
            if current.position == target.position {
                break;
            }
            // [Compute] Evaluate the neighbors for all 4 directions
            let seed = Seeder::shuffle(grid, current.position.into());
            let mut directions = DirectionTrait::compute_shuffled_directions(seed);
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Self::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Self::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Self::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Self::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
        };

        // [Return] The path from the start to the target
        Self::path(ref heap, start, target)
    }

    /// Check if the position can be visited in the specified direction.
    /// # Arguments
    /// * `grid` - The grid to search (1 is walkable and 0 is not)
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `position` - The current position
    /// * `direction` - The direction to check
    /// * `visited` - The visited nodes
    /// # Returns
    /// * Whether the position can be visited in the specified direction
    #[inline]
    fn check(
        grid: felt252,
        width: u8,
        height: u8,
        position: u8,
        direction: Direction,
        ref visited: Felt252Dict<bool>
    ) -> bool {
        let (x, y) = (position % width, position / width);
        match direction {
            Direction::North => (y < height - 1)
                && (Bitmap::get(grid, position + width) == 1)
                && !visited.get((position + width).into()),
            Direction::East => (x > 0)
                && (Bitmap::get(grid, position - 1) == 1)
                && !visited.get((position - 1).into()),
            Direction::South => (y > 0)
                && (Bitmap::get(grid, position - width) == 1)
                && !visited.get((position - width).into()),
            Direction::West => (x < width - 1)
                && (Bitmap::get(grid, position + 1) == 1)
                && !visited.get((position + 1).into()),
            _ => false,
        }
    }

    /// Assess the neighbor node and update the heap.
    /// # Arguments
    /// * `width` - The width of the grid
    /// * `neighbor_position` - The position of the neighbor
    /// * `current` - The current node
    /// * `target` - The target node
    /// * `heap` - The heap of nodes
    /// # Effects
    /// * Update the heap with the neighbor node
    #[inline]
    fn assess(
        width: u8, neighbor_position: u8, current: Node, target: Node, ref heap: Heap<Node>,
    ) {
        let distance = Self::heuristic(current.position, neighbor_position, width);
        let neighbor_gcost = current.gcost + distance;
        let neighbor_hcost = Self::heuristic(neighbor_position, target.position, width);
        let mut neighbor = match heap.get(neighbor_position.into()) {
            Option::Some(node) => node,
            Option::None => NodeTrait::new(
                neighbor_position, current.position, neighbor_gcost, neighbor_hcost
            ),
        };
        if neighbor_gcost < neighbor.gcost || !heap.contains(neighbor.position) {
            neighbor.gcost = neighbor_gcost;
            neighbor.source = current.position;
            if !heap.contains(neighbor.position) {
                return heap.add(neighbor);
            }
            return heap.update(neighbor);
        }
    }

    /// Compute the heuristic cost between two positions.
    /// # Arguments
    /// * `position` - The current position
    /// * `target` - The target position
    /// * `width` - The width of the grid
    /// # Returns
    /// * The heuristic cost between the two positions
    #[inline]
    fn heuristic(position: u8, target: u8, width: u8) -> u16 {
        let (x1, y1) = (position % width, position / width);
        let (x2, y2) = (target % width, target / width);
        let dx = if x1 > x2 {
            x1 - x2
        } else {
            x2 - x1
        };
        let dy = if y1 > y2 {
            y1 - y2
        } else {
            y2 - y1
        };
        (dx + dy).into()
    }

    /// Reconstruct the path from the target to the start.
    /// # Arguments
    /// * `heap` - The heap of nodes
    /// * `start` - The starting node
    /// * `target` - The target node
    /// # Returns
    /// * The span of positions from the target to the start
    #[inline]
    fn path(ref heap: Heap<Node>, start: Node, target: Node) -> Span<u8> {
        // [Check] The heap contains the target
        let mut path: Array<u8> = array![];
        match heap.get(target.position) {
            Option::None => { path.span() },
            Option::Some(mut current) => {
                // [Compute] Reconstruct the path from the target to the start
                loop {
                    if current.position == start.position {
                        break;
                    }
                    path.append(current.position);
                    current = heap.at(current.source);
                };
                // [Return] The path from the start to the target
                path.span()
            },
        }
    }
}

#[cfg(test)]
mod test {
    // Local imports

    use super::{Astar, Node, NodeTrait};

    #[test]
    fn test_astar_search_small() {
        // x* *
        // 1 0 *
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Astar::search(grid, width, height, from, to);
        assert_eq!(path, array![8, 7, 6, 3].span());
    }

    #[test]
    fn test_astar_search_impossible() {
        // x 1 0
        // 1 0 1
        // 0 1 s
        let grid: felt252 = 0x1AB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Astar::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_astar_search_medium() {
        // * x 0 0
        // * 0 1 1
        // * * * *
        // 1 1 1 s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let mut path = Astar::search(grid, width, height, from, to);
        assert_eq!(path, array![14, 15, 11, 7, 6, 5, 4].span());
    }

    #[test]
    fn test_astar_search_large() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 * * x 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 * 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 * 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 * * * * * * * * 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 1 * * 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 * 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 * s 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid: felt252 = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let width = 18;
        let height = 14;
        let from = 55;
        let to = 170;
        let mut path = Astar::search(grid, width, height, from, to);
        assert_eq!(
            path,
            array![170, 171, 172, 154, 136, 118, 117, 116, 115, 114, 113, 112, 94, 93, 75, 74, 56]
                .span()
        );
    }

    #[test]
    fn test_astar_search_issue() {
        // 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
        // 0 1 1 1 1 1 1 1 0 1 1 0 0 1 0
        // 0 1 1 1 1 1 1 1 0 0 E * 1 1 0  <-- 180 + 4 = 184
        // 0 1 1 1 1 1 1 1 1 1 0 * 0 1 0
        // 0 1 1 1 1 1 1 1 1 1 0 * 0 1 0
        // 0 1 1 1 0 0 1 0 0 0 1 * * 0 0
        // 0 1 1 1 1 0 0 1 1 1 1 0 * * 0
        // 1 1 1 1 0 1 1 1 0 0 1 1 0 * 1
        // 0 1 1 1 1 0 0 0 0 1 0 0 * * 0
        // 0 1 1 1 0 0 * * * * * * * 0 0
        // 0 1 1 1 0 0 * 1 0 1 1 1 0 0 0
        // 0 1 1 * * * * 0 1 0 1 1 1 1 0
        // 0 1 1 S 1 1 1 0 1 0 1 1 1 1 0  <-- 30 + 11 = 41
        // 0 1 1 1 1 1 1 1 1 1 0 1 1 1 0
        // 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0
        let grid: felt252 = 0x201fd93f9e7fd4ffa9c8e3cf6f736f099cfe39b87ebcfd79ff70080;
        let width = 15;
        let height = 15;
        let from = 41;
        let to = 184;
        let mut path = Astar::search(grid, width, height, from, to);
        assert_eq!(
            path,
            array![
                184,
                183,
                168,
                153,
                138,
                137,
                122,
                121,
                106,
                91,
                92,
                77,
                78,
                79,
                80,
                81,
                82,
                83,
                68,
                53,
                54,
                55,
                56,
            ]
                .span()
        );
    }
}
