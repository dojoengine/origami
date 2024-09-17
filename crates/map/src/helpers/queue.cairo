//! Queue implementation.

// Custom Queue implementation
#[derive(Drop)]
pub struct Queue<T> {
    /// The elements in the queue, stored in an Array.
    elements: Array<T>,
}

/// Trait defining the Queue operations
pub trait QueueTrait<T> {
    /// Creates a new empty queue.
    /// # Returns
    /// * A new Queue<T>
    fn new() -> Queue<T>;

    /// Adds an element to the back of the queue.
    /// # Arguments
    /// * `self` - The queue
    /// * `value` - The value to be added
    /// # Effects
    /// * The value is appended to the end of the queue
    fn enqueue(ref self: Queue<T>, value: T);

    /// Removes and returns the front element of the queue.
    /// # Arguments
    /// * `self` - The queue
    /// # Returns
    /// * The front element if the queue is not empty, `None` otherwise
    /// # Effects
    /// * The front element is removed from the queue if it exists
    fn dequeue(ref self: Queue<T>) -> Option<T>;

    /// Checks if the queue is empty.
    /// # Arguments
    /// * `self` - The queue
    /// # Returns
    /// * `true` if the queue is empty, `false` otherwise
    fn is_empty(self: @Queue<T>) -> bool;
}

/// Implementation of QueueTrait
pub impl QueueImpl<T, impl TDrop: Drop<T>> of QueueTrait<T> {
    /// Creates a new empty queue.
    /// # Returns
    /// * A new Queue<T>
    #[inline]
    fn new() -> Queue<T> {
        Queue { elements: ArrayTrait::new() }
    }

    /// Adds an element to the back of the queue.
    /// # Arguments
    /// * `self` - The queue
    /// * `value` - The value to be added
    /// # Effects
    /// * The value is appended to the end of the queue
    #[inline]
    fn enqueue(ref self: Queue<T>, value: T) {
        self.elements.append(value);
    }

    /// Removes and returns the front element of the queue.
    /// # Arguments
    /// * `self` - The queue
    /// # Returns
    /// * The front element if the queue is not empty, `None` otherwise
    /// # Effects
    /// * The front element is removed from the queue if it exists
    #[inline]
    fn dequeue(ref self: Queue<T>) -> Option<T> {
        if self.elements.is_empty() {
            return Option::None;
        }
        Option::Some(self.elements.pop_front().unwrap())
    }

    /// Checks if the queue is empty.
    /// # Arguments
    /// * `self` - The queue
    /// # Returns
    /// * `true` if the queue is empty, `false` otherwise
    #[inline]
    fn is_empty(self: @Queue<T>) -> bool {
        self.elements.is_empty()
    }
}
