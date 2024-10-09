//! Depth-First Search algorithm implementation for pathfinding.

// Core imports
use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports
use origami_map::finders::astar::Astar;
use origami_map::helpers::bitmap::Bitmap;
use origami_map::helpers::seeder::Seeder;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::{Direction, DirectionTrait};

/// DFS implementation for pathfinding
#[generate_trait]
pub impl DFS of DFSTrait {
    /// Searches for a path from 'from' to 'to' on the given grid using DFS
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
        let mut start = NodeTrait::new(from, 0, 0, 0);
        let target = NodeTrait::new(to, 0, 0, 0);

        // [Effect] Initialize the stack and the visited nodes
        let mut stack: Array<Node> = array![start];
        let mut visited: Felt252Dict<bool> = Default::default();
        let mut parents: Felt252Dict<u8> = Default::default();

        // [Compute] DFS until the target is reached or stack is empty
        let mut path_found = false;
        while let Option::Some(current) = stack.pop_front() {
            // [Check] Stop if we reached the target
            if current.position == target.position {
                path_found = true;
                break;
            }

            // [Check] Skip if already visited
            if visited.get(current.position.into()) {
                continue;
            }

            // [Effect] Mark as visited
            visited.insert(current.position.into(), true);

            // [Compute] Evaluate the neighbors for all 4 directions
            let seed = Seeder::shuffle(grid, current.position.into());
            let mut directions = DirectionTrait::compute_shuffled_directions(seed);
            while directions != 0 {
                let direction = DirectionTrait::pop_front(ref directions);
                if Astar::check(grid, width, height, current.position, direction, ref visited) {
                    let neighbor_position = direction.next(current.position, width);
                    parents.insert(neighbor_position.into(), current.position);
                    let neighbor = NodeTrait::new(neighbor_position, current.position, 0, 0);
                    stack.append(neighbor);
                }
            };
        };

        // Reconstruct and return the path if found
        if !path_found {
            return array![].span();
        };
        Self::path(parents, start, target)
    }

    /// Reconstructs the path from start to target using the parents dictionary
    #[inline]
    fn path(mut parents: Felt252Dict<u8>, start: Node, target: Node) -> Span<u8> {
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
}
#[cfg(test)]
mod test {
    // Local imports
    use super::DFS;

    #[test]
    fn test_dfs_search_small() {
        // x───┐
        // 1 0 │
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = DFS::search(grid, width, height, from, to);
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
        let path = DFS::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_dfs_search_medium() {
        // ┌─x 0 0
        // │ 0 1 1
        // └─────┐
        // 1 1 1 s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let path = DFS::search(grid, width, height, from, to);
        assert!(
            path.len() > 0
        ); // DFS may not find the shortest path, so we just check if a path is found
    }

    #[test]
    fn test_dfs_single_cell_path() {
        // Grid representation:
        // x s
        // 1 1
        let grid: felt252 = 0xF;
        let width = 2;
        let height = 2;
        let from = 0;
        let to = 1;
        let path = DFS::search(grid, width, height, from, to);
        assert_eq!(path, array![1].span());
    }

    #[test]
    fn test_dfs_maze() {
        // Grid representation:
        // x 1 0 0 0
        // 0 1 1 1 0
        // 0 0 0 1 0
        // 1 1 1 1 s
        let grid: felt252 = 0xC385F;
        let width = 5;
        let height = 4;
        let from = 0;
        let to = 19;
        let path = DFS::search(grid, width, height, from, to);
        assert!(
            path.len() > 0
        ); // DFS may not find the shortest path, so we just check if a path is found
    }
}
