//! Dijkstra algorithm for pathfinding.

// Core imports
use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal Imports
use origami_map::finders::finder::Finder;
use origami_map::finders::astar::Astar;
use origami_map::helpers::heap::{Heap, HeapTrait};
use origami_map::helpers::bitmap::Bitmap;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::{Direction, DirectionTrait};
use origami_map::helpers::seeder::Seeder;

#[generate_trait]
pub impl Dijkstra of DijkstraTrait {
    /// Search for the shortest path from a start to a target position using Dijkstra's algorithm.
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
            if Finder::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Finder::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Finder::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            let direction: Direction = DirectionTrait::pop_front(ref directions);
            if Finder::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
        };

        // [Return] Reconstruct the path from the start to the target
        Finder::path_with_heap(ref heap, start, NodeTrait::new(to, 0, 0, 0))
    }

    /// Assess a neighbor node (simplified from A*).
    #[inline]
    fn assess(width: u8, neighbor_position: u8, current: Node, target: Node, ref heap: Heap<Node>) {
        let distance = Finder::manhattan(current.position, neighbor_position, width);
        let neighbor_gcost = current.gcost + distance;
        let mut neighbor = match heap.get(neighbor_position.into()) {
            Option::Some(node) => node,
            Option::None => NodeTrait::new(neighbor_position, current.position, neighbor_gcost, 0),
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
}

// => Tests <=//
#[cfg(test)]
mod test {
    // Local imports
    use super::Dijkstra;

    #[test]
    fn test_dijkstra_search_small() {
        // x * *
        // 1 0 *
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(path, array![8, 7, 6, 3].span());
    }

    #[test]
    fn test_dijkstra_search_impossible() {
        // x 1 0
        // 1 0 1
        // 0 1 s
        let grid: felt252 = 0x1AB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_dijkstra_search_medium() {
        // * x 0 0
        // * 0 1 1
        // * 1 1 1
        // * * * s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(path, array![14, 15, 11, 7, 3, 2, 1].span());
    }

    #[test]
    fn test_dijkstra_search_large() {
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0
        // 0 0 1 1 1 1 1 0 1 1 0 0 0 0 0 0 0 0
        // 0 0 0 1 1 1 1 * * x 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 * 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 * 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 * * 1 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 * 1 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 * * 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 * * * * * * * s 0
        // 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 0
        // 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        let grid: felt252 = 0x7F003F800FB001FC003C481F1F0FFFE1EEF83FFE1FFF81FFE03FF80000;
        let width = 18;
        let height = 14;
        let from = 55;
        let to = 170;
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(
            path,
            array![170, 171, 172, 154, 136, 118, 117, 99, 81, 80, 62, 61, 60, 59, 58, 57, 56]
                .span(),
        );
    }
}
