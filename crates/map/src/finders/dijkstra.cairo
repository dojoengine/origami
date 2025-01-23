//! Dijkstra algorithm for pathfinding.

// Core imports
use core::dict::{Felt252Dict, Felt252DictTrait}; 

// Internal Imports
use origami_map::finders::finder::Finder;
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
        // [Check] Ensure the start and target are walkable
        if Bitmap::get(grid, from) == 0 || Bitmap::get(grid, to) == 0 {
            return array![].span();
        }
        // [Effect] Initialize the start node
        let mut start = NodeTrait::new(from, 0, 0, 0);
        let mut heap: Heap<Node> = HeapTrait::new();
        let mut visited: Felt252Dict<bool> = Default::default();
        // @note No target node because the Dijkstra algorithm does not use heuristics and does not need the target node. 
        heap.add(start);

        // [Compute] Process nodes in the heap
        while let Option::Some(current) = heap.pop_front() {
            visited.insert(current.position.into(), true);

            // [Check] Stop if the target is reached
            if current.position == to {
                break;
            }

            // [Compute] Evaluate neighbors in all 4 directions
            let seed = Seeder::shuffle(grid, current.position.into());
            let mut directions = DirectionTrait::compute_shuffled_directions(seed);
            while let Option::Some(direction) = DirectionTrait::pop_front(ref directions) {
                if Self::check(grid, width, height, current.position, direction, ref visited) {
                    let neighbor_position = direction.next(current.position, width);
                    Self::assess(width, neighbor_position, current, ref heap);
                }
            }
        }

        // [Return] Reconstruct the path from the start to the target
        Finder::path_with_heap(ref heap, start, NodeTrait::new(to, 0, 0, 0))
    }

    /// Check if a node can be visited (same as A*).
    #[inline]
    fn check(
        grid: felt252,
        width: u8,
        height: u8,
        position: u8,
        direction: Direction,
        ref visited: Felt252Dict<bool>,
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

    /// Assess a neighbor node (simplified from A*).
    #[inline]
    fn assess(
        width: u8,
        neighbor_position: u8,
        current: Node,
        ref heap: Heap<Node>,
    ) {
        let neighbor_gcost = current.gcost + 1; // Uniform cost for now
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
        // x* *
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
        // * * * *
        // 1 1 1 s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(path, array![14, 15, 11, 7, 6, 5, 4].span());
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
        let mut path = Dijkstra::search(grid, width, height, from, to);
        assert_eq!(
            path,
            array![170, 171, 172, 154, 136, 118, 117, 116, 115, 114, 113, 112, 94, 93, 75, 74, 56]
                .span()
        );
    }

    #[test]
    fn test_dijkstra_search_issue() {
        // 0 0 0 0 0 0 0 1 0 0 0
    }
}