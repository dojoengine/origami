#[derive(Copy, Drop)]
struct Vector<T> {
    data: Span<T>,
}

mod errors {
    const INVALID_INDEX: felt252 = 'Vector: index out of bounds';
    const INVALID_SIZE: felt252 = 'Vector: invalid size';
}

trait VectorTrait<T> {
    fn new(data: Span<T>) -> Vector<T>;

    fn get(ref self: Vector<T>, index: u8) -> T;

    fn size(self: Vector<T>) -> u32;

    fn dot(self: Vector<T>, vector: Vector<T>) -> T;
}

impl VectorImpl<T, +Mul<T>, +AddEq<T>, +Zeroable<T>, +Copy<T>, +Drop<T>,> of VectorTrait<T> {
    fn new(data: Span<T>) -> Vector<T> {
        Vector { data }
    }

    fn get(ref self: Vector<T>, index: u8) -> T {
        *self.data.get(index.into()).expect(errors::INVALID_INDEX).unbox()
    }

    fn size(self: Vector<T>) -> u32 {
        self.data.len()
    }

    fn dot(mut self: Vector<T>, mut vector: Vector<T>) -> T {
        // [Check] Dimesions are compatible
        assert(self.size() == vector.size(), errors::INVALID_SIZE);
        // [Compute] Dot product in a loop
        let mut index = 0;
        let mut value = Zeroable::zero();
        loop {
            match self.data.pop_front() {
                Option::Some(x_value) => {
                    let y_value = vector.data.pop_front().unwrap();
                    value += *x_value * *y_value;
                },
                Option::None => { break value; },
            };
        }
    }
}

impl VectorAdd<
    T, +Mul<T>, +AddEq<T>, +Add<T>, +Zeroable<T>, +Copy<T>, +Drop<T>,
> of Add<Vector<T>> {
    fn add(mut lhs: Vector<T>, mut rhs: Vector<T>) -> Vector<T> {
        // [Check] Dimesions are compatible
        assert(lhs.size() == rhs.size(), errors::INVALID_SIZE);
        let mut values = array![];
        let max_index = lhs.size();
        let mut index: u8 = 0;
        loop {
            if max_index == index.into() {
                break;
            }
            values.append(lhs.get(index) + rhs.get(index));
            index += 1;
        };
        VectorTrait::new(values.span())
    }
}

impl VectorSub<
    T, +Mul<T>, +AddEq<T>, +Sub<T>, +Zeroable<T>, +Copy<T>, +Drop<T>,
> of Sub<Vector<T>> {
    fn sub(mut lhs: Vector<T>, mut rhs: Vector<T>) -> Vector<T> {
        // [Check] Dimesions are compatible
        assert(lhs.size() == rhs.size(), errors::INVALID_SIZE);
        let mut values = array![];
        let max_index = lhs.size();
        let mut index: u8 = 0;
        loop {
            if max_index == index.into() {
                break;
            }
            values.append(lhs.get(index) - rhs.get(index));
            index += 1;
        };
        VectorTrait::new(values.span())
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use debug::PrintTrait;

    // Local imports

    use super::{Vector, VectorTrait};

    impl I128Zeroable of Zeroable<i128> {
        fn zero() -> i128 {
            0
        }
        fn is_zero(self: i128) -> bool {
            self == 0
        }
        fn is_non_zero(self: i128) -> bool {
            self != 0
        }
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_vector_get() {
        let mut vector: Vector = VectorTrait::new(array![1, 2, 3, 4].span());
        assert(vector.get(0) == 1, 'Vector: get failed');
        assert(vector.get(2) == 3, 'Vector: get failed');
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_vector_dot_product() {
        let vector1: Vector = VectorTrait::new(array![1, 2, 3].span());
        let vector2: Vector = VectorTrait::new(array![4, 5, 6].span());
        let result = vector1.dot(vector2);
        assert(result == 32, 'Vector: dot product failed'); // 1*4 + 2*5 + 3*6 = 32
    }
}
