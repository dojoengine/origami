//! Breadth-First Search algorithm implementation for pathfinding.

// Core imports
use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports
use origami_map::helpers::queue::{Queue, QueueTrait};
use origami_map::helpers::bitmap::Bitmap;
use origami_map::types::node::{Node, NodeTrait};
use origami_map::types::direction::Direction;


/// BFS implementation for pathfinding
#[generate_trait]
pub impl BFS of BFSTrait {
    /// Searches for a path from 'from' to 'to' on the given grid using BFS
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

        // [Effect] Initialize the queue and the visited nodes
        let mut queue: Queue<Node> = QueueTrait::new();
        let mut visited: Felt252Dict<bool> = Default::default();
        let mut parents: Felt252Dict<u8> = Default::default();

        queue.enqueue(start);
        visited.insert(start.position.into(), true);

        // [Compute] BFS until the target is reached or queue is empty
        let mut path_found = false;
        loop {
            if queue.is_empty() {
                break;
            }

            let current = queue.dequeue().unwrap();

            // [Check] Stop if we reached the target
            if current.position == target.position {
                path_found = true;
                break;
            }

            // [Compute] Evaluate the neighbors for all 4 directions
            let directions = array![
                Direction::North, Direction::East, Direction::South, Direction::West
            ];
            let mut i = 0;
            loop {
                if i >= directions.len() {
                    break;
                }
                let direction = *directions.at(i);
                if Self::check(grid, width, height, current.position, direction, ref visited) {
                    let neighbor_position = Self::get_neighbor_position(
                        current.position, direction, width
                    );
                    parents.insert(neighbor_position.into(), current.position);
                    let neighbor = NodeTrait::new(neighbor_position, current.position, 0, 0);
                    queue.enqueue(neighbor);
                    visited.insert(neighbor_position.into(), true);
                }
                i += 1;
            };
        };

        // Reconstruct and return the path if found
        if path_found {
            Self::path(parents, start, target)
        } else {
            array![].span()
        }
    }

    /// Checks if a neighbor in the given direction is valid and unvisited
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
            Direction::North => {
                y < height
                    - 1
                        && Bitmap::get(grid, position + width.into()) == 1
                        && !visited.get((position + width.into()).into())
            },
            Direction::East => {
                x < width
                    - 1
                        && Bitmap::get(grid, position + 1) == 1
                        && !visited.get((position + 1).into())
            },
            Direction::South => {
                y > 0
                    && Bitmap::get(grid, position - width.into()) == 1
                    && !visited.get((position - width.into()).into())
            },
            Direction::West => {
                x > 0 && Bitmap::get(grid, position - 1) == 1 && !visited.get((position - 1).into())
            },
            _ => false,
        }
    }

    /// Calculates the position of a neighbor in the given direction
    #[inline]
    fn get_neighbor_position(position: u8, direction: Direction, width: u8) -> u8 {
        match direction {
            Direction::North => position + width,
            Direction::East => position + 1,
            Direction::South => position - width,
            Direction::West => position - 1,
            _ => 0,
        }
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
    use super::BFS;

    #[test]
    fn test_bfs_search_small() {
        // x───┐
        // 1 0 │
        // 0 1 s
        let grid: felt252 = 0x1EB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![8, 7, 6, 3].span());
    }

    #[test]
    fn test_bfs_search_impossible() {
        // x 1 0
        // 1 0 1
        // 0 1 s
        let grid: felt252 = 0x1AB;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }

    #[test]
    fn test_bfs_search_medium() {
        // ┌─x 0 0
        // │ 0 1 1
        // └─────┐
        // 1 1 1 s
        let grid: felt252 = 0xCBFF;
        let width = 4;
        let height = 4;
        let from = 0;
        let to = 14;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![14, 15, 11, 7, 6, 5, 4].span());
    }

    #[test]
    fn test_bfs_single_cell_path() {
        // Grid representation:
        // x s
        // 1 1
        let grid: felt252 = 0xF;
        let width = 2;
        let height = 2;
        let from = 0;
        let to = 1;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![1].span());
    }

    #[test]
    fn test_bfs_maze() {
        // Grid representation:
        // x 1 0 0 0
        // 0 1 1 1 0
        // 0 0 0 1 0
        // 1 1 1 1 s
        let grid: felt252 = 0x1F1F0F43;
        let width = 5;
        let height = 4;
        let from = 0;
        let to = 19;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![19, 18, 17, 16, 11, 6, 1].span());
    }

    #[test]
    fn test_bfs_long_straight_path() {
        // Grid representation:
        // x 1 1 1 1 s
        let grid: felt252 = 0x3F;
        let width = 6;
        let height = 1;
        let from = 0;
        let to = 5;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![5, 4, 3, 2, 1].span());
    }

    #[test]
    fn test_bfs_all_obstacles() {
        // Grid representation:
        // 0 0 0
        // 0 0 0
        // 0 0 0
        let grid: felt252 = 0x0;
        let width = 3;
        let height = 3;
        let from = 0;
        let to = 8;
        let path = BFS::search(grid, width, height, from, to);
        assert_eq!(path, array![].span());
    }
}
