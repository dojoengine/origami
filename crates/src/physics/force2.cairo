// External imports

use orion::numbers::FixedTrait;
// use orion::operators::tensor::{Tensor, TensorTrait, implementation::tensor_fp64x64::FP64x64Tensor};

mod errors {
    const FORCE2_INVALID_SIZE: felt252 = 'Force2: invalid size';
}

#[derive(Drop, Copy)]
struct Force2<N> {
    /// The linear force.
    linear: Span<N>,
    /// The torque.
    angular: N,
}

trait Force2Trait<N> {
    fn new(linear: Span<N>, angular: N) -> Force2<N>;
    fn zero() -> Force2<N>;
    fn from_span(data: Span<N>) -> Force2<N>;
    fn from_spans(linear: Span<N>, angular: Span<N>) -> Force2<N>;
    fn torque_from_vector(torque: Span<N>) -> Force2<N>;
    fn torque(torque: N) -> Force2<N>;
    fn linear(linear: Span<N>) -> Force2<N>;
}

impl Force2Impl<N, T, +FixedTrait<N, T>, +Copy<N>, +Drop<N>> of Force2Trait<N> {
    /// Creates a force from its linear and angular components.
    #[inline(always)]
    fn new(linear: Span<N>, angular: N) -> Force2<N> {
        Force2 { linear, angular }
    }

    /// A zero force.
    #[inline(always)]
    fn zero() -> Force2<N> {
        Force2Trait::new(array![].span(), FixedTrait::ZERO())
    }

    /// Create a force from a span where the entries 0 and 1 are for the linear part and 2 for the angular part.
    #[inline(always)]
    fn from_span(mut data: Span<N>) -> Force2<N> {
        assert(data.len() == 3, errors::FORCE2_INVALID_SIZE);
        let torque = data.pop_back().unwrap();
        Force2Trait::new(data, *torque)
    }

    /// Creates a force from its linear and angular components, both in vector form.
    #[inline(always)]
    fn from_spans(linear: Span<N>, angular: Span<N>) -> Force2<N> {
        Force2 { linear, angular: angular.pop_front().unwrap(), }
    }

    /// Create a pure torque.
    #[inline(always)]
    fn torque(torque: N) -> Force2<N> {
        Force2Trait::new(array![].span(), torque)
    }

    /// Create a pure torque.
    #[inline(always)]
    fn torque_from_vector(torque: Span<N>) -> Force2<N> {
        Force2Trait::new(array![].span(), angular.pop_front().unwrap())
    }

    /// Create a pure linear force.
    #[inline(always)]
    fn linear(linear: Span<N>) -> Force2<N> {
        Force2Trait::new(linear, FixedTrait::ZERO())
    }
/// Creates the resultant of a linear force applied at the given point (relative to the center of mass).
// #[inline(always)]
// fn linear_at_point(linear: Vector2<N>, point: &Point2<N>) -> Force2 {
//     Force2Trait::new(linear, point.coords.perp(&linear))
// }

// /// Creates the resultant of a torque applied at the given point (relative to the center of mass).
// #[inline(always)]
// fn torque_at_point(torque: N, point: &Point2<N>) -> Force2 {
//     Force2Trait::new(point.coords * -torque, torque)
// }

// /// Creates the resultant of a torque applied at the given point (relative to the center of mass).
// #[inline(always)]
// fn torque_from_vector_at_point(torque: Vector1<N>, point: &Point2<N>) -> Force2 {
//     Force2::torque_at_point(torque.x, point)
// }

// /// The angular part of the force.
// #[inline(always)]
// fn angular_vector(&self) -> Vector1<N> {
//     Vector1::new(self.angular)
// }

// /// Apply the given transformation to this force.
// #[inline(always)]
// fn transform_by(&self, m: &Isometry2<N>) -> Force2 {
//     Force2Trait::new(m * self.linear, self.angular)
// }

// /// This force seen as a slice.
// ///
// /// The two first entries contain the linear part and the third entry contais the angular part.
// #[inline(always)]
// fn as_slice(&self) -> &[N] {
//     self.as_vector().as_slice()
// }

// /// This force seen as a vector.
// ///
// /// The two first entries contain the linear part and the third entry contais the angular part.
// #[inline(always)]
// fn as_vector(&self) -> &Vector3<N> {
//     unsafe { mem::transmute(self) }
// }

// /// This force seen as a mutable vector.
// ///
// /// The two first entries contain the linear part and the third entry contais the angular part.
// #[inline(always)]
// fn as_vector_mut(&mut self) -> &mut Vector3<N> {
//     unsafe { mem::transmute(self) }
// }
}

#[cfg(test)]
mod tests {
    // Extenral imports

    use orion::numbers::{FP64x64, FP64x64Impl, FixedTrait};

    // Local imports

    use super::{Force2, Force2Trait};

    #[test]
    #[available_gas(100_000)]
    fn test_force2_new() {
        let one: FP64x64 = FixedTrait::new(1, false);
        let two: FP64x64 = FixedTrait::new(2, false);
        let three: FP64x64 = FixedTrait::new(3, false);
        let force: Force2<FP64x64> = Force2Trait::new(array![one, two].span(), three);
        assert(force.linear == array![one, two].span(), 'Force2: wrong linear');
        assert(force.angular == three, 'Force2: wrong angular');
    }

    #[test]
    #[available_gas(100_000)]
    fn test_force2_zero() {
        let force: Force2<FP64x64> = Force2Trait::zero();
        assert(force.linear == array![].span(), 'Force2: wrong linear');
        assert(force.angular == FixedTrait::ZERO(), 'Force2: wrong angular');
    }

    #[test]
    #[available_gas(100_000)]
    fn test_force2_from_slice() {
        let one: FP64x64 = FixedTrait::new(1, false);
        let two: FP64x64 = FixedTrait::new(2, false);
        let three: FP64x64 = FixedTrait::new(3, false);
        let force: Force2<FP64x64> = Force2Trait::from_slice(array![one, two, three].span());
        assert(force.linear == array![one, two].span(), 'Force2: wrong linear');
        assert(force.angular == three, 'Force2: wrong angular');
    }
}
