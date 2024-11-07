//! Depth-First Search algorithm implementation for pathfinding.

// Core imports
use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports
use origami_map::finders::finder::Finder;
use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::DirectionTrait;

/// DepthFirstSearch implementation for pathfinding
#[generate_trait]
pub impl DepthFirstSearch of DepthFirstSearchTrait {
    /// Searches for a path from 'from' to 'to' on the given grid using DepthFirstSearch
    ///
    /// # Arguments
    /// * `grid` - The grid represented as a felt252
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `from` - The starting position
    /// * `to` - The target position
    ///
    /// # Returns
    /// A Span<u8> representing the path from 'from' to 'to', or an empty span if no path exists
    #[inline]
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        // [Check] The start and target are walkable
        if Bitmap::get(grid, from) == 0 || Bitmap::get(grid, to) == 0 {
            return array![].span();
        }

        // [Effect] Initialize the start and target nodes
        let start = NodeTrait::new(from, 0, 0, 0);
        let target = NodeTrait::new(to, 0, 0, 0);

        // [Effect] Initialize visited nodes and parents
        let mut visited: Felt252Dict<bool> = Default::default();
        let mut parents: Felt252Dict<u8> = Default::default();

        // [Compute] Start the recursive DFS
        let found = Self::iter(grid, width, height, start, target, ref visited, ref parents);

        // Reconstruct and return the path if found
        if found {
            Finder::path_with_parents(ref parents, start, target)
        } else {
            array![].span()
        }
    }

    /// Recursive helper function for DFS
    #[inline]
    fn iter(
        grid: felt252,
        width: u8,
        height: u8,
        current: Node,
        target: Node,
        ref visited: Felt252Dict<bool>,
        ref parents: Felt252Dict<u8>
    ) -> bool {
        // [Check] If the current node has already been visited, return false
        if visited.get(current.position.into()) {
            return false;
        }

        // [Check] Mark current node as visited
        visited.insert(current.position.into(), true);

        // [Check] If we've reached the target, we're done
        if current.position == target.position {
            return true;
        }

        // [Compute] Evaluate the neighbors for all 4 directions
        let seed = Seeder::shuffle(grid, current.position.into());
        let mut directions = DirectionTrait::compute_shuffled_directions(seed);
        let mut found = false;

        loop {
            if directions == 0 {
                break;
            }
            let direction = DirectionTrait::pop_front(ref directions);
            if Finder::check(grid, width, height, current.position, direction, ref visited) {
                let neighbor_position = direction.next(current.position, width);
                let neighbor = NodeTrait::new(neighbor_position, current.position, 0, 0);

                // [Effect] Set parent for the neighbor
                parents.insert(neighbor_position.into(), current.position);

                // [Recurse] Continue DFS from the neighbor
                found = Self::iter(grid, width, height, neighbor, target, ref visited, ref parents);

                if found {
                    break;
                }
            }
        };

        // [Check] Return whether we've found the target
        found
    }
}

#[cfg(test)]
mod test {
    use super::DepthFirstSearch;

    #[test]
    fn test_dfs_search_small() {
        // x * *
        // 1 0 *
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = DepthFirstSearch::search(grid, width, height, from, to);
        assert_eq!(path, array![8, 7, 6, 3].span());
    }

    #[test]
    fn test_dfs_search_impossible() {
        // x 1 0
        // 1 0 1
        // 0 1 s
        let grid: felt252 = 0x1AB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = DepthFirstSearch::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_dfs_search_medium() {
        //  * x 0 0
        //  * 0 * *
        //  * 1 * *
        //  * * * s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let path = DepthFirstSearch::search(grid, width, height, from, to);
        assert_eq!(path, array![14, 15, 11, 7, 3, 2, 1, 5, 9, 8, 4].span());
    }

    #[test]
    fn test_dfs_single_cell_path() {
        // Grid representation:
        // x s
        // 1 1
        let grid: felt252 = 0xF;
        let width = 2;
        let height = 2;
        let from = 3;
        let to = 2;
        let path = DepthFirstSearch::search(grid, width, height, from, to);
        assert_eq!(path, array![2].span());
    }

    #[test]
    fn test_dfs_maze() {
        // Grid representation:
        // x * 0 0 0
        // 0 * * * 0
        // 0 0 0 * 0
        // 1 1 1 * s
        let grid: felt252 = 0xC385F;
        let width = 5;
        let height = 4;
        let from = 0;
        let to = 19;
        let path = DepthFirstSearch::search(grid, width, height, from, to);
        assert_eq!(path, array![19, 18, 13, 12, 11, 6, 1].span());
    }
}
