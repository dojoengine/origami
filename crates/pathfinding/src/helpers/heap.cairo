// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_pathfinding::types::node::Node;

/// Traits.
pub trait HeapTrait<T> {
    fn new() -> Heap<T>;
    fn is_empty(self: @Heap<T>) -> bool;
    fn contains(ref self: Heap<T>, item: T) -> bool;
    fn add(ref self: Heap<T>, item: T);
    fn update(ref self: Heap<T>, item: T);
    fn pop_front(ref self: Heap<T>) -> Option<T>;
    fn sort_up(ref self: Heap<T>, item: T);
    fn sort_down(ref self: Heap<T>, item: T);
    fn swap(ref self: Heap<T>, ref lhs: T, ref rhs: T);
}

pub trait ItemTrait<T> {
    fn get_index(self: T) -> u8;
    fn set_index(ref self: T, index: u8);
}

/// Types.
pub struct Heap<T> {
    pub len: u8,
    pub data: Felt252Dict<Nullable<T>>,
}

/// Implementations.
pub impl HeapImpl<T, +ItemTrait<T>, +PartialOrd<T>, +Copy<T>, +Drop<T>> of HeapTrait<T> {
    #[inline]
    fn new() -> Heap<T> {
        Heap { len: 0, data: Default::default(), }
    }

    #[inline]
    fn is_empty(self: @Heap<T>) -> bool {
        *self.len == 0
    }

    #[inline]
    fn contains(ref self: Heap<T>, item: T) -> bool {
        if item.get_index() >= self.len {
            return false;
        }
        let node: T = self.data.get(item.get_index().into()).deref();
        node.get_index() == item.get_index()
    }

    #[inline]
    fn add(ref self: Heap<T>, mut item: T) {
        item.set_index(self.len);
        self.data.insert(item.get_index().into(), NullableTrait::new(item));
        self.sort_up(item);
        self.len += 1;
    }

    #[inline]
    fn update(ref self: Heap<T>, item: T) {
        self.sort_up(item);
    }

    #[inline]
    fn pop_front(ref self: Heap<T>) -> Option<T> {
        if self.is_empty() {
            return Option::None;
        }
        self.len -= 1;
        let first: T = self.data.get(0).deref();
        let mut last: T = self.data.get(self.len.into()).deref();
        last.set_index(0);
        self.data.insert(0, NullableTrait::new(last));
        self.sort_down(last);
        Option::Some(first)
    }

    #[inline]
    fn sort_up(ref self: Heap<T>, mut item: T) {
        loop {
            if item.get_index() == 0 {
                break;
            }
            let index = (item.get_index() - 1) / 2;
            let mut parent: T = self.data.get(index.into()).deref();
            if parent > item {
                self.swap(ref parent, ref item);
            } else {
                break;
            }
        }
    }

    #[inline]
    fn sort_down(ref self: Heap<T>, mut item: T) {
        loop {
            // [Check] Stop criteria
            let lhs_index = item.get_index() * 2 + 1;
            if lhs_index >= self.len {
                break;
            }
            // [Compute] Child to swap
            let rhs_index = item.get_index() * 2 + 2;
            let lhs: T = self.data.get(lhs_index.into()).deref();
            let rhs: T = self.data.get(rhs_index.into()).deref();
            let mut child: T = if rhs_index < self.len && rhs < lhs {
                rhs
            } else {
                lhs
            };
            // [Effect] Swap if necessary
            if item > child {
                self.swap(ref item, ref child);
            } else {
                break;
            }
        }
    }

    #[inline]
    fn swap(ref self: Heap<T>, ref lhs: T, ref rhs: T) {
        // [Effect] Swap indexes
        let (lhs_index, rhs_index) = (lhs.get_index(), rhs.get_index());
        lhs.set_index(rhs_index);
        rhs.set_index(lhs_index);
        // [Effect] Swap nodes
        self.data.insert(lhs_index.into(), NullableTrait::new(rhs));
        self.data.insert(rhs_index.into(), NullableTrait::new(lhs));
    }
}

impl DestructHeap<T, +Drop<T>> of Destruct<Heap<T>> {
    fn destruct(self: Heap<T>) nopanic {
        self.data.squash();
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::{Node, Heap, HeapTrait};

    #[test]
    fn test_heap_new() {
        let heap: Heap<Node> = HeapTrait::new();
        assert!(heap.is_empty());
    }

    #[test]
    fn test_heap_add() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { index: 0, fcost: 0, hcost: 0, };
        heap.add(node);
        assert!(!heap.is_empty());
    }

    #[test]
    fn test_heap_contains() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { index: 0, fcost: 0, hcost: 0, };
        heap.add(node);
        assert!(heap.contains(node));
    }

    #[test]
    fn test_heap_not_contains() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { index: 0, fcost: 0, hcost: 0, };
        assert!(!heap.contains(node));
    }

    #[test]
    fn test_heap_pop_front_sorted() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { index: 0, fcost: 1, hcost: 0, };
        let second: Node = Node { index: 0, fcost: 1, hcost: 1, };
        let third: Node = Node { index: 0, fcost: 2, hcost: 0, };
        heap.add(first);
        heap.add(second);
        heap.add(third);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.index, 0);
        assert_eq!(popped.fcost, 1);
        assert_eq!(popped.hcost, 0);
    }

    #[test]
    fn test_heap_pop_front_reversed() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { index: 0, fcost: 2, hcost: 0, };
        let second: Node = Node { index: 0, fcost: 1, hcost: 1, };
        let third: Node = Node { index: 0, fcost: 1, hcost: 0, };
        heap.add(first);
        heap.add(second);
        heap.add(third);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.index, 0);
        assert_eq!(popped.fcost, 1);
        assert_eq!(popped.hcost, 0);
    }

    #[test]
    fn test_heap_swap() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let mut first: Node = Node { index: 0, fcost: 1, hcost: 1, };
        let mut second: Node = Node { index: 1, fcost: 2, hcost: 0, };
        heap.add(first);
        heap.add(second);
        heap.swap(ref first, ref second);
        assert_eq!(first.index, 1);
        assert_eq!(first.fcost, 1);
        assert_eq!(first.hcost, 1);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.index, 0);
        assert_eq!(popped.fcost, 2);
        assert_eq!(popped.hcost, 0);
    }
}
