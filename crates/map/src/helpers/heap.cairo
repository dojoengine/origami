//! Heap implementation.

// Core imports

use core::dict::{Felt252Dict, Felt252DictTrait};

// Internal imports

use origami_map::types::node::Node;

// Constants

const KEY_OFFSET: felt252 = 252;

/// Traits.
pub trait HeapTrait<T> {
    fn new() -> Heap<T>;
    /// Create if the heap is empty.
    /// # Arguments
    /// * `self` - The heap
    /// # Returns
    /// * `true` if the heap is empty, `false` otherwise
    fn is_empty(self: @Heap<T>) -> bool;
    /// Get an item from the heap if it exists.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * The item if it exists, `None` otherwise
    fn get(ref self: Heap<T>, key: u8) -> Option<T>;
    /// Get an item from the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * The item
    /// # Panics
    /// * If the item does not exist
    fn at(ref self: Heap<T>, key: u8) -> T;
    /// Check if the heap contains an item.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * `true` if the item exists, `false` otherwise
    fn contains(ref self: Heap<T>, key: u8) -> bool;
    /// Add an item to the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item` - The item to add
    /// # Effects
    /// * The item is added at the end of the heap and the heap is sorted up
    fn add(ref self: Heap<T>, item: T);
    /// Update an item in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item` - The item to update
    /// # Effects
    /// * The item is updated and the heap is sorted up since it cannot be updated with a lower
    /// score in case of A* algorithm
    fn update(ref self: Heap<T>, item: T);
    /// Pop the first item from the heap.
    /// # Arguments
    /// * `self` - The heap
    /// # Returns
    /// * The first item if the heap is not empty, `None` otherwise
    fn pop_front(ref self: Heap<T>) -> Option<T>;
    /// Sort an item up in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item_key` - The key of the item to sort up
    /// # Effects
    /// * The items are swapped until the item is in the right place
    fn sort_up(ref self: Heap<T>, item_key: u8);
    /// Sort an item down in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item_key` - The key of the item to sort down
    /// # Effects
    /// * The items are swapped until the item is in the right place
    fn sort_down(ref self: Heap<T>, item_key: u8);
    /// Swap two items in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `lhs` - The key of the first item
    /// * `rhs` - The key of the second item
    /// # Effects
    /// * The items are swapped
    fn swap(ref self: Heap<T>, lhs: u8, rhs: u8);
}

pub trait ItemTrait<T> {
    /// Get the key of the item.
    /// # Arguments
    /// * `self` - The item
    /// # Returns
    /// * The key of the item
    fn key(self: T) -> u8;
}

/// Types.
pub struct Heap<T> {
    /// The length of the heap.
    pub len: u8,
    /// The keys of the items in the heap and also the indexes of the items in the data.
    /// Both information is stored in the same map to save gas.
    pub keys: Felt252Dict<u8>,
    /// The items.
    pub data: Felt252Dict<Nullable<T>>,
}

/// Implementations.
pub impl HeapImpl<T, +ItemTrait<T>, +PartialOrd<T>, +Copy<T>, +Drop<T>> of HeapTrait<T> {
    /// Create a new heap.
    /// # Returns
    /// * The heap
    #[inline]
    fn new() -> Heap<T> {
        Heap { len: 0, keys: Default::default(), data: Default::default(), }
    }

    /// Check if the heap is empty.
    /// # Arguments
    /// * `self` - The heap
    /// # Returns
    /// * `true` if the heap is empty, `false` otherwise
    #[inline]
    fn is_empty(self: @Heap<T>) -> bool {
        *self.len == 0
    }

    /// Get an item from the heap if it exists.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * The item if it exists, `None` otherwise
    #[inline]
    fn get(ref self: Heap<T>, key: u8) -> Option<T> {
        let nullable: Nullable<T> = self.data.get(key.into());
        if nullable.is_null() {
            return Option::None;
        }
        Option::Some(nullable.deref())
    }

    /// Get an item from the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * The item
    /// # Panics
    /// * If the item does not exist
    #[inline]
    fn at(ref self: Heap<T>, key: u8) -> T {
        self.data.get(key.into()).deref()
    }

    /// Check if the heap contains an item.
    /// # Arguments
    /// * `self` - The heap
    /// * `key` - The key of the item
    /// # Returns
    /// * `true` if the item exists, `false` otherwise
    #[inline]
    fn contains(ref self: Heap<T>, key: u8) -> bool {
        let index = self.keys.get(key.into() + KEY_OFFSET);
        let item_key = self.keys.get(index.into());
        index < self.len && item_key == key
    }

    /// Add an item to the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item` - The item to add
    /// # Effects
    /// * The item is added at the end of the heap and the heap is sorted up
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

    /// Update an item in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item` - The item to update
    /// # Effects
    /// * The item is updated and the heap is sorted up
    /// # Info
    /// * The heap is only sorted up since it cannot be updated with a lower score in case of A*
    /// algorithm
    #[inline]
    fn update(ref self: Heap<T>, item: T) {
        // [Effect] Update item
        let key = item.key();
        self.data.insert(key.into(), NullableTrait::new(item));
        // [Effect] Sort up
        self.sort_up(key);
    }

    /// Pop the first item from the heap.
    /// # Arguments
    /// * `self` - The heap
    /// # Returns
    /// * The first item if the heap is not empty, `None` otherwise
    /// # Effects
    /// * The first item is removed, replaced by the last item and the heap is sorted down
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

    /// Sort an item up in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item_key` - The key of the item to sort up
    /// # Effects
    /// * The items are swapped from bottom to top until the item is in the right place
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
            if parent <= item {
                break;
            }
            self.swap(parent_key, item_key);
        }
    }

    /// Sort an item down in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `item_key` - The key of the item to sort down
    /// # Effects
    /// * The items are swapped from top to bottom until the item is in the right place
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
            if item <= child {
                break;
            };
            self.swap(item_key, child_key);
            // [Check] Stop criteria, assess left child side
            lhs_index = index * 2 + 1;
        }
    }

    /// Swap two items in the heap.
    /// # Arguments
    /// * `self` - The heap
    /// * `lhs` - The key of the first item
    /// * `rhs` - The key of the second item
    /// # Effects
    /// * The items are swapped
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
        self.keys.squash();
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
