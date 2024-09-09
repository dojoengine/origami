// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_pathfinding::helpers::heap::{Heap, HeapTrait};
use origami_pathfinding::helpers::bitmap::Bitmap;
use origami_pathfinding::types::node::{Node, NodeTrait};

#[generate_trait]
pub impl Astar of AstarTrait {
    #[inline]
    fn search(grid: felt252, width: u8, height: u8, from: u8, to: u8) -> Span<u8> {
        let mut start = NodeTrait::new(from, 0, 0, 0);
        let target = NodeTrait::new(to, 0, 0, 0);
        let mut heap: Heap<Node> = HeapTrait::new();
        let mut visited: Felt252Dict<bool> = Default::default();
        heap.add(start);

        // [Compute] Evaluate the path until the target is reached
        while !heap.is_empty() {
            // [Compute] Get the less expensive node
            let current: Node = heap.pop_front().unwrap();
            visited.insert(current.position.into(), true);
            // [Check] Stop if we reached the target
            if current.position == target.position {
                break;
            }
            // [Compute] Evaluate the neighbors
            if Self::check(grid, width, height, current.position, 0, ref visited) {
                let neighbor_position = current.position + width;
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            if Self::check(grid, width, height, current.position, 1, ref visited) {
                let neighbor_position = current.position + 1;
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            if Self::check(grid, width, height, current.position, 2, ref visited) {
                let neighbor_position = current.position - width;
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
            if Self::check(grid, width, height, current.position, 3, ref visited) {
                let neighbor_position = current.position - 1;
                Self::assess(width, neighbor_position, current, target, ref heap);
            }
        };

        // [Return] The path from the start to the target
        Self::path(ref heap, start, target)
    }

    #[inline]
    fn check(
        grid: felt252,
        width: u8,
        height: u8,
        position: u8,
        direction: u8,
        ref visisted: Felt252Dict<bool>
    ) -> bool {
        let (x, y) = (position % width, position / width);
        match direction {
            0 => (y < height - 1)
                && (Bitmap::get(grid, position + width) == 1)
                && !visisted.get((position + width).into()),
            1 => (x < width - 1)
                && (Bitmap::get(grid, position + 1) == 1)
                && !visisted.get((position + 1).into()),
            2 => (y > 0)
                && (Bitmap::get(grid, position - width) == 1)
                && !visisted.get((position - width).into()),
            _ => (x > 0)
                && (Bitmap::get(grid, position - 1) == 1)
                && !visisted.get((position - 1).into()),
        }
    }

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
                heap.add(neighbor);
            } else {
                heap.update(neighbor);
            }
        }
    }

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
        // x───┐
        // 1 0 │
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
        // ┌─x 0 0
        // │ 0 1 1
        // └─────┐
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
        // 0 0 0 1 1 1 1 ┌───x 0 0 0 0 0 0 0 0
        // 0 0 0 0 1 1 1 │ 0 0 0 1 0 0 1 0 0 0
        // 0 0 0 1 1 1 1 │ 0 0 0 1 1 1 1 1 0 0
        // 0 0 1 1 1 1 1 └───┐ 1 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 0 1 │ 1 0 1 1 1 1 1 0
        // 0 0 0 0 1 1 1 1 1 └─┐ 1 1 1 1 1 1 0
        // 0 0 0 1 1 1 1 1 1 1 └───────────s 0
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
            array![170, 171, 172, 154, 136, 118, 117, 116, 98, 80, 79, 61, 60, 59, 58, 57, 56]
                .span()
        );
    }
}
