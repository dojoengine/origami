//! A* algorithm implementation for pathfinding.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::num::traits::Sqrt;

// Internal imports

use origami_map::helpers::heap::{Heap, HeapTrait};
use origami_map::helpers::bitmap::Bitmap;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::Direction;

#[generate_trait]
pub impl Finder of FinderTrait {
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

    /// Compute the amplified euclidean distance between two positions.
    /// # Arguments
    /// * `position` - The current position
    /// * `target` - The target position
    /// * `width` - The width of the grid
    /// # Returns
    /// * The amplified euclidean distance between the two positions
    #[inline]
    fn euclidean(position: u8, target: u8, width: u8, multiplier: u32) -> u16 {
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
        (multiplier * (dx.into() * dx.into() + dy.into() * dy.into())).sqrt()
    }

    /// Compute the manhattan distance between two positions.
    /// # Arguments
    /// * `position` - The current position
    /// * `target` - The target position
    /// * `width` - The width of the grid
    /// # Returns
    /// * The manhattan distance between the two positions
    #[inline]
    fn manhattan(position: u8, target: u8, width: u8) -> u16 {
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

    /// Reconstructs the path from start to target using the parents dictionary.
    /// # Arguments
    /// * `parents` - The parents dictionary
    /// * `start` - The starting node
    /// * `target` - The target node
    /// # Returns
    /// * The span of positions from the target to the start
    #[inline]
    fn path_with_parents(ref parents: Felt252Dict<u8>, start: Node, target: Node) -> Span<u8> {
        let mut path: Array<u8> = array![];
        let mut current = target.position;
        loop {
            if current == start.position {
                break;
            }
            path.append(current);
            current = parents.get(current.into());
        };
        path.span()
    }

    /// Reconstruct the path from the target to the start using a heap.
    /// # Arguments
    /// * `heap` - The heap of nodes
    /// * `start` - The starting node
    /// * `target` - The target node
    /// # Returns
    /// * The span of positions from the target to the start
    #[inline]
    fn path_with_heap(ref heap: Heap<Node>, start: Node, target: Node) -> Span<u8> {
        // [Check] The heap contains the target
        let mut path: Array<u8> = array![];
        match heap.get(target.position) {
            Option::None => { path.span() },
            Option::Some(mut current) => {
                // [Compute] Reconstruct the path from the target to the start
                loop {
                    path.append(current.position);
                    if current.source == start.position {
                        break;
                    }
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

    use super::{Finder, Node, NodeTrait, Felt252Dict, Direction, Heap, HeapTrait};

    #[test]
    fn test_finder_euclidean() {
        // x 0 0
        // 0 0 0
        // 0 0 s
        let start = 0;
        let target = 8;
        let width = 3;
        assert_eq!(Finder::euclidean(start, target, width, 1), 2);
        assert_eq!(Finder::euclidean(start, target, width, 100), 28);
        assert_eq!(Finder::euclidean(start, target, width, 10000), 282);
    }

    #[test]
    fn test_finder_manhattan() {
        // x 0 0
        // 0 0 0
        // 0 0 s
        let start = 0;
        let target = 8;
        let width = 3;
        assert_eq!(Finder::manhattan(start, target, width), 4);
    }

    #[test]
    fn test_finder_check_corner() {
        // 1 1 1
        // 1 0 1
        // 1 1 x
        let grid: felt252 = 0x1EF;
        let width = 3;
        let height = 3;
        let position = 0;
        let mut visited: Felt252Dict<bool> = Default::default();
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::North, ref visited), true,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::East, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::South, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::West, ref visited), true,
        );
    }

    #[test]
    fn test_finder_check_edge() {
        // 1 1 1
        // 1 0 1
        // 1 x 1
        let grid: felt252 = 0x1EF;
        let width = 3;
        let height = 3;
        let position = 1;
        let mut visited: Felt252Dict<bool> = Default::default();
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::North, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::East, ref visited), true,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::South, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::West, ref visited), true,
        );
    }

    #[test]
    fn test_finder_check_inside() {
        // 1 1 1
        // 1 x 0
        // 1 0 1
        let grid: felt252 = 0x1F5;
        let width = 3;
        let height = 3;
        let position = 4;
        let mut visited: Felt252Dict<bool> = Default::default();
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::North, ref visited), true,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::East, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::South, ref visited), false,
        );
        assert_eq!(
            Finder::check(grid, width, height, position, Direction::West, ref visited), true,
        );
    }

    #[test]
    fn test_finder_path_with_parents() {
        // 1 < 1 < 1
        //         ^
        // 1 > 1 > 1
        // ^
        // 1 < 1 < 1
        let start: Node = NodeTrait::new(0, 0, 0, 0);
        let target: Node = NodeTrait::new(8, 7, 0, 0);
        let mut parents: Felt252Dict<u8> = Default::default();
        parents.insert(1, 0);
        parents.insert(2, 1);
        parents.insert(5, 2);
        parents.insert(4, 5);
        parents.insert(3, 4);
        parents.insert(6, 3);
        parents.insert(7, 6);
        parents.insert(8, 7);
        let path = Finder::path_with_parents(ref parents, start, target);
        assert_eq!(path, array![8, 7, 6, 3, 4, 5, 2, 1].span());
    }

    #[test]
    fn test_finder_path_with_heap() {
        // 1 < 1 < 1
        //         ^
        // 1 > 1 > 1
        // ^
        // 1 < 1 < 1
        let start: Node = NodeTrait::new(0, 0, 0, 0);
        let target: Node = NodeTrait::new(8, 7, 0, 0);
        let mut heap: Heap<Node> = HeapTrait::new();
        heap.add(NodeTrait::new(1, 0, 0, 0));
        heap.add(NodeTrait::new(2, 1, 0, 0));
        heap.add(NodeTrait::new(5, 2, 0, 0));
        heap.add(NodeTrait::new(4, 5, 0, 0));
        heap.add(NodeTrait::new(3, 4, 0, 0));
        heap.add(NodeTrait::new(6, 3, 0, 0));
        heap.add(NodeTrait::new(7, 6, 0, 0));
        heap.add(NodeTrait::new(8, 7, 0, 0));
        let path = Finder::path_with_heap(ref heap, start, target);
        assert_eq!(path, array![8, 7, 6, 3, 4, 5, 2, 1].span());
    }
}
