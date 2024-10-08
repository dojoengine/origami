//! Greedy algorithm implementation for pathfinding.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_map::helpers::heap::{Heap, HeapTrait};
use origami_map::helpers::astar::Astar;
use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::{Direction, DirectionTrait};

#[generate_trait]
pub impl Greedy of GreedyTrait {
    /// Search for the shortest path from a start to a target position using Greedy Search.
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
            if Astar::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Astar::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Astar::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Astar::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
        };

        // [Return] The path from the start to the target
        Astar::path(ref heap, start, target)
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
        let neighbor_hcost = Astar::heuristic(neighbor_position, target.position, width);
        let mut neighbor = match heap.get(neighbor_position.into()) {
            Option::Some(node) => node,
            Option::None => NodeTrait::new(neighbor_position, current.position, 0, neighbor_hcost),
        };
        if !heap.contains(neighbor.position) {
            neighbor.source = current.position;
            return heap.add(neighbor);
        }
        return heap.update(neighbor);
    }
}

#[cfg(test)]
mod test {
    use super::{Greedy, Node, NodeTrait};

    #[test]
    fn test_greedy_search_small() {
        // x * *
        // 1 0 *
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Greedy::search(grid, width, height, from, to);
        assert_eq!(path, array![8, 7, 6, 3].span());
    }

    #[test]
    fn test_greedy_search_impossible() {
        // x 1 0
        // 1 0 1
        // 0 1 s
        let grid: felt252 = 0x1AB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Greedy::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_greedy_search_large() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 * * x 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 * 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 * 0 0 0 * * * 1 1 0 0
        // 0 0 1 1 1 1 1 * * * * * 1 * 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 1 1 0 1 * * 1 1 0
        // 0 0 0 0 1 1 1 1 1 1 1 1 1 1 * * 1 0
        // 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 * s 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid: felt252 = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let width = 18;
        let height = 14;
        let from = 55;
        let to = 170;
        let mut path = Greedy::search(grid, width, height, from, to);

        assert_eq!(
            path,
            array![
                170,
                171,
                172,
                154,
                136,
                118,
                117,
                116,
                115,
                114,
                132,
                131,
                130,
                112,
                94,
                93,
                75,
                74,
                56
            ]
                .span()
        );
    }
}
