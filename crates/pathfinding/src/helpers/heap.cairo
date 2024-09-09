// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_pathfinding::types::node::Node;

// Constants

const KEY_OFFSET: felt252 = 252;

/// Traits.
pub trait HeapTrait<T> {
    fn new() -> Heap<T>;
    fn is_empty(self: @Heap<T>) -> bool;
    fn get(ref self: Heap<T>, key: u8) -> Option<T>;
    fn at(ref self: Heap<T>, key: u8) -> T;
    fn contains(ref self: Heap<T>, key: u8) -> bool;
    fn add(ref self: Heap<T>, item: T);
    fn update(ref self: Heap<T>, item: T);
    fn pop_front(ref self: Heap<T>) -> Option<T>;
    fn sort_up(ref self: Heap<T>, item_key: u8);
    fn sort_down(ref self: Heap<T>, item_key: u8);
    fn swap(ref self: Heap<T>, lhs: u8, rhs: u8);
}

pub trait ItemTrait<T> {
    fn key(self: T) -> u8;
}

/// Types.
pub struct Heap<T> {
    pub len: u8,
    pub keys: Felt252Dict<u8>,
    pub data: Felt252Dict<Nullable<T>>,
}

/// Implementations.
pub impl HeapImpl<
    T, +ItemTrait<T>, +PartialOrd<T>, +PartialEq<T>, +Copy<T>, +Drop<T>
> of HeapTrait<T> {
    #[inline]
    fn new() -> Heap<T> {
        Heap { len: 0, keys: Default::default(), data: Default::default(), }
    }

    #[inline]
    fn is_empty(self: @Heap<T>) -> bool {
        *self.len == 0
    }

    #[inline]
    fn get(ref self: Heap<T>, key: u8) -> Option<T> {
        let nullable: Nullable<T> = self.data.get(key.into());
        if nullable.is_null() {
            Option::None
        } else {
            Option::Some(nullable.deref())
        }
    }

    #[inline]
    fn at(ref self: Heap<T>, key: u8) -> T {
        self.data.get(key.into()).deref()
    }

    #[inline]
    fn contains(ref self: Heap<T>, key: u8) -> bool {
        let index = self.keys.get(key.into() + KEY_OFFSET);
        let item_key = self.keys.get(index.into());
        index < self.len && item_key == key
    }

    #[inline]
    fn add(ref self: Heap<T>, item: T) {
        // [Effect] Update heap length
        let key = item.key();
        let index = self.len;
        self.len += 1;
        // [Effect] Insert item at the end
        self.data.insert(key.into(), NullableTrait::new(item));
        self.keys.insert(index.into(), key);
        self.keys.insert(key.into() + KEY_OFFSET, index);
        // [Effect] Sort up
        self.sort_up(key);
    }

    #[inline]
    fn update(ref self: Heap<T>, item: T) {
        // [Effect] Update item
        let key = item.key();
        self.data.insert(key.into(), NullableTrait::new(item));
        // [Effect] Sort up (since it cannot be updated with a lower value)
        self.sort_up(key);
    }

    #[inline]
    fn pop_front(ref self: Heap<T>) -> Option<T> {
        if self.is_empty() {
            return Option::None;
        }
        self.len -= 1;
        let first_key: u8 = self.keys.get(0);
        let mut first: T = self.data.get(first_key.into()).deref();
        if self.len != 0 {
            let last_key: u8 = self.keys.get(self.len.into());
            self.swap(first_key, last_key);
            self.sort_down(last_key);
        }
        Option::Some(first)
    }

    #[inline]
    fn sort_up(ref self: Heap<T>, item_key: u8) {
        // [Compute] Item
        let item: T = self.data.get(item_key.into()).deref();
        let mut index = self.keys.get(item_key.into() + KEY_OFFSET);
        // [Compute] Peform swaps until the item is in the right place
        while index != 0 {
            index = (index - 1) / 2;
            let parent_key = self.keys.get(index.into());
            let mut parent: T = self.data.get(parent_key.into()).deref();
            if parent > item {
                self.swap(parent_key, item_key);
            } else {
                break;
            }
        }
    }

    #[inline]
    fn sort_down(ref self: Heap<T>, item_key: u8) {
        // [Compute] Item
        let item: T = self.data.get(item_key.into()).deref();
        let mut index: u8 = self.keys.get(item_key.into() + KEY_OFFSET);
        // [Compute] Peform swaps until the item is in the right place
        let mut lhs_index = index * 2 + 1;
        while lhs_index < self.len {
            // [Compute] Child to swap
            index = lhs_index;
            let mut child_key: u8 = self.keys.get(index.into());
            let mut child: T = self.data.get(child_key.into()).deref();
            // [Compute] Assess right child side
            let rhs_index = index * 2 + 2;
            if rhs_index < self.len {
                let rhs_key: u8 = self.keys.get(rhs_index.into());
                let rhs: T = self.data.get(rhs_key.into()).deref();
                if rhs < child {
                    index = rhs_index;
                    child_key = rhs_key;
                    child = rhs;
                };
            }
            // [Effect] Swap if necessary
            if item > child {
                self.swap(item_key, child_key);
            } else {
                break;
            }
            // [Check] Stop criteria, assess left child side
            lhs_index = index * 2 + 1;
        }
    }

    #[inline]
    fn swap(ref self: Heap<T>, lhs: u8, rhs: u8) {
        // [Effect] Swap keys
        let lhs_index = self.keys.get(lhs.into() + KEY_OFFSET);
        let rhs_index = self.keys.get(rhs.into() + KEY_OFFSET);
        self.keys.insert(lhs.into() + KEY_OFFSET, rhs_index);
        self.keys.insert(rhs.into() + KEY_OFFSET, lhs_index);
        self.keys.insert(lhs_index.into(), rhs);
        self.keys.insert(rhs_index.into(), lhs);
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

    use super::{Node, Heap, HeapTrait, ItemTrait};

    #[test]
    fn test_heap_new() {
        let heap: Heap<Node> = HeapTrait::new();
        assert!(heap.is_empty());
    }

    #[test]
    fn test_heap_add() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        heap.add(node);
        assert!(!heap.is_empty());
    }

    #[test]
    fn test_heap_contains() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        heap.add(node);
        assert!(heap.contains(node.position));
    }

    #[test]
    fn test_heap_not_contains() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let node: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        assert!(!heap.contains(node.position));
    }

    #[test]
    fn test_heap_pop_front_sorted() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        let third: Node = Node { position: 3, source: 3, gcost: 3, hcost: 3, };
        heap.add(first);
        heap.add(second);
        heap.add(third);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.gcost, 1);
        assert_eq!(popped.hcost, 1);
    }

    #[test]
    fn test_heap_pop_front_reversed() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        let third: Node = Node { position: 3, source: 3, gcost: 3, hcost: 3, };
        heap.add(third);
        heap.add(second);
        heap.add(first);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.gcost, 1);
        assert_eq!(popped.hcost, 1);
    }

    #[test]
    fn test_heap_swap() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        heap.add(first);
        heap.add(second);
        heap.swap(first.key(), second.key());
        assert_eq!(first.position, 1);
        assert_eq!(first.gcost, 1);
        let popped: Node = heap.pop_front().unwrap();
        assert_eq!(popped.position, 2);
        assert_eq!(popped.gcost, 2);
    }

    #[test]
    fn test_heap_get() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        heap.add(first);
        heap.add(second);
        assert_eq!(heap.get(first.position).unwrap().position, 1);
        assert_eq!(heap.get(second.position).unwrap().position, 2);
        heap.swap(first.key(), second.key());
        assert_eq!(heap.get(first.position).unwrap().position, 1);
        assert_eq!(heap.get(second.position).unwrap().position, 2);
    }

    #[test]
    fn test_heap_at() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        heap.add(first);
        heap.add(second);
        assert_eq!(heap.at(first.position).position, 1);
        assert_eq!(heap.at(second.position).position, 2);
        heap.swap(first.key(), second.key());
        assert_eq!(heap.at(first.position).position, 1);
        assert_eq!(heap.at(second.position).position, 2);
    }

    #[test]
    fn test_heap_add_pop_add() {
        let mut heap: Heap<Node> = HeapTrait::new();
        let first: Node = Node { position: 1, source: 1, gcost: 1, hcost: 1, };
        let second: Node = Node { position: 2, source: 2, gcost: 2, hcost: 2, };
        heap.add(first);
        heap.add(second);
        heap.pop_front().unwrap();
        assert_eq!(heap.at(1).position, 1);
        assert_eq!(heap.at(2).position, 2);
    }
}
