// Source: https://github.com/johnBuffer/VerletSFML/blob/main/solver.hpp

use dict::{Felt252Dict, Felt252DictTrait};
use nullable::{NullableTrait, nullable_from_box, match_nullable, FromNullableResult};

use orion::numbers::fixed_point::core::{FixedTrait};
use orion::operators::tensor::core::{Tensor, TensorTrait};
use orion::numbers::{FP64x64, FP64x64Impl};
use orion::operators::tensor::implementations::tensor_fp64x64::{
    FP64x64Tensor, FP64x64TensorAdd, FP64x64TensorSub, FP64x64TensorMul, FP64x64TensorDiv
};

#[derive(Drop, Copy)]
struct Object {
    position: Tensor<FP64x64>,
    position_last: Tensor<FP64x64>,
    acceleration: Tensor<FP64x64>,
    radius: FP64x64,
}

impl ObjectDefault of Default<Object> {
    fn default() -> Object {
        let zero: FP64x64 = FixedTrait::ZERO();
        let ten: FP64x64 = FixedTrait::new_unscaled(10, false);
        Object {
            position: TensorTrait::new(array![2].span(), array![zero, zero].span()),
            position_last: TensorTrait::new(array![2].span(), array![zero, zero].span()),
            acceleration: TensorTrait::new(array![2].span(), array![zero, zero].span()),
            radius: ten,
        }
    }
}

#[generate_trait]
impl ObjectImpl of ObjectTrait {
    fn new(x: FP64x64, y: FP64x64, radius: FP64x64) -> Object {
        let zero: FP64x64 = FixedTrait::ZERO();
        let position: Tensor<FP64x64> = TensorTrait::new(array![2].span(), array![x, y].span());
        Object {
            position: position,
            position_last: position,
            acceleration: TensorTrait::new(array![2].span(), array![zero, zero].span()),
            radius: radius,
        }
    }
    fn update(ref self: Object, dt: FP64x64) {
        let dt_squarred: Tensor<FP64x64> = TensorTrait::constant_of_shape(
            self.acceleration.shape, dt * dt
        );
        let displacement = self.position - self.position_last;
        self.position_last = self.position;
        self.position = self.position + displacement + self.acceleration * dt_squarred;
        self
            .acceleration =
                TensorTrait::constant_of_shape(self.acceleration.shape, FixedTrait::ZERO());
    }

    fn accelerate(ref self: Object, acceleration: Tensor<FP64x64>) {
        self.acceleration = self.acceleration + acceleration;
    }

    fn set_velocity(ref self: Object, velocity: Tensor<FP64x64>, dt: FP64x64) {
        let dt: Tensor<FP64x64> = TensorTrait::constant_of_shape(velocity.shape, dt);
        self.position_last = self.position - velocity * dt;
    }

    fn add_velocity(ref self: Object, velocity: Tensor<FP64x64>, dt: FP64x64) {
        let dt: Tensor<FP64x64> = TensorTrait::constant_of_shape(velocity.shape, dt);
        self.position_last = self.position_last - velocity * dt;
    }

    fn get_velocity(ref self: Object, dt: FP64x64) -> Tensor<FP64x64> {
        let dt: Tensor<FP64x64> = TensorTrait::constant_of_shape(self.position.shape, dt);
        let velocity = (self.position - self.position_last) / dt;
        velocity
    }
}

#[derive(Destruct)]
struct Solver {
    sub_steps: u32,
    gravity: Tensor<FP64x64>,
    constraint_center: Tensor<FP64x64>,
    constraint_radius: FP64x64,
    count: u128,
    objects: Felt252Dict<Nullable<Object>>,
    time: FP64x64,
    frame_dt: FP64x64,
}

impl SolverDefault of Default<Solver> {
    fn default() -> Solver {
        let hundred: FP64x64 = FixedTrait::new_unscaled(100, false);
        let earth_gravity: FP64x64 = FixedTrait::new_unscaled(981, true) / hundred;
        Solver {
            sub_steps: 1,
            gravity: TensorTrait::new(
                array![2].span(), array![FixedTrait::ZERO(), earth_gravity].span()
            ),
            constraint_center: TensorTrait::new(
                array![2].span(), array![FixedTrait::ZERO(), FixedTrait::ZERO()].span()
            ),
            constraint_radius: hundred,
            count: 0,
            objects: Default::default(),
            time: FixedTrait::ZERO(),
            frame_dt: FixedTrait::ZERO(),
        }
    }
}

#[generate_trait]
impl PublicImpl of PublicTrait {
    fn add_object(ref self: Solver, mut object: Object) {
        self.objects.insert(self.count.into(), nullable_from_box(BoxTrait::new(object)));
        self.count = self.count + 1;
    }

    fn update(ref self: Solver) {
        self.time += self.frame_dt;
        let dt = self.get_step_dt();
        let mut index = self.sub_steps;
        loop {
            if index == 0 {
                break;
            }
            self.apply_gravity();
            self.check_collision(dt);
            self.apply_constraint();
            self.update_objects(dt);
            index -= 1;
        };
    }

    fn set_simulation_update_rate(ref self: Solver, rate: u32) {
        let one = FixedTrait::new_unscaled(1, false);
        let rate = FixedTrait::new_unscaled(rate.into(), false);
        self.frame_dt = one / rate;
    }

    fn set_constraint(ref self: Solver, position: Tensor<FP64x64>, radius: FP64x64) {
        self.constraint_center = position;
        self.constraint_radius = radius;
    }

    fn set_sub_steps_count(ref self: Solver, sub_steps: u32) {
        self.sub_steps = sub_steps;
    }

    fn set_object_velocity(ref self: Solver, ref object: Object, velocity: Tensor<FP64x64>) {
        object.set_velocity(velocity, self.get_step_dt());
    }

    fn get_objects(ref self: Solver) -> Span<Object> {
        let mut objects = array![];
        let mut index: felt252 = 0;
        loop {
            if index == self.count.into() {
                break;
            }
            let object = self.get_object(index);
            objects.append(object);
            index += 1;
        };
        objects.span()
    }

    fn get_constraint(ref self: Solver) -> Span<FP64x64> {
        let zero_index = array![0].span();
        let one_index = array![1].span();
        array![
            self.constraint_center.at(zero_index),
            self.constraint_center.at(one_index),
            self.constraint_radius
        ]
            .span()
    }

    fn get_objects_count(ref self: Solver) -> u128 {
        self.count.into()
    }

    fn get_time(ref self: Solver) -> FP64x64 {
        self.time
    }

    fn get_step_dt(ref self: Solver) -> FP64x64 {
        let sub_steps: FP64x64 = FixedTrait::new_unscaled(self.sub_steps.into(), false);
        self.frame_dt / sub_steps
    }
}

#[generate_trait]
impl PrivateImpl of PrivateTrait {
    fn get_object(ref self: Solver, index: felt252) -> Object {
        let object = match match_nullable(self.objects.get(index)) {
            FromNullableResult::Null => Default::default(),
            FromNullableResult::NotNull(item) => item.unbox(),
        };
        assert(object.radius != FixedTrait::ZERO(), 'Solver: object not found');
        object
    }

    fn apply_gravity(ref self: Solver) {
        let mut index: felt252 = 0;
        loop {
            if index == self.count.into() {
                break;
            }
            let mut object = self.get_object(index);
            object.accelerate(self.gravity);
            self.objects.insert(index, nullable_from_box(BoxTrait::new(object)));
            index += 1;
        };
    }

    fn check_collision(ref self: Solver, dt: FP64x64) {
        // Check at least 2 objects
        if self.count < 2 {
            return;
        }
        // Constants
        let hundred: FP64x64 = FixedTrait::new_unscaled(100, false);
        let half: FP64x64 = FixedTrait::new_unscaled(50, false) / hundred;
        let response_coef: FP64x64 = FixedTrait::new_unscaled(75, false) / hundred;
        let zero_index = array![0].span();
        // Iterate on all objects
        let mut outer_index: felt252 = self.count.into() - 1;
        loop {
            if outer_index == 0 {
                break;
            }
            let mut object_1 = self.get_object(outer_index);
            // Iterate on object involved in new collision pairs
            let mut inner_index: felt252 = outer_index - 1;
            loop {
                let mut object_2 = self.get_object(inner_index);
                let vector = (object_1.position - object_2.position);
                let distance = vector.matmul(@vector).at(zero_index).sqrt();
                let min_distance = object_1.radius + object_2.radius;
                // Check overlap
                if distance < min_distance {
                    let overlap = min_distance - distance;
                    let distance_vectorized: Tensor<FP64x64> = TensorTrait::constant_of_shape(
                        vector.shape, distance
                    );
                    let normal = vector / distance_vectorized;
                    let response_1 = object_2.radius / min_distance;
                    let response_2 = object_1.radius / min_distance;
                    let delta = half * response_coef * overlap;
                    let delta_1: Tensor<FP64x64> = TensorTrait::constant_of_shape(
                        vector.shape, delta * response_1
                    );
                    let delta_2: Tensor<FP64x64> = TensorTrait::constant_of_shape(
                        vector.shape, delta * response_2
                    );
                    // Update positions
                    object_1.position = object_1.position + normal * delta_1;
                    object_2.position = object_2.position - normal * delta_2;
                    // Update objects
                    self.objects.insert(outer_index, nullable_from_box(BoxTrait::new(object_1)));
                    self.objects.insert(inner_index, nullable_from_box(BoxTrait::new(object_2)));
                };
                if inner_index == 0 {
                    break;
                }
                inner_index -= 1;
            };
            outer_index -= 1;
        };
    }

    fn apply_constraint(ref self: Solver) {
        let zero_index = array![0].span();
        let one_index = array![0].span();
        let mut index: felt252 = 0;
        loop {
            if index == self.count.into() {
                break;
            }
            let mut object = self.get_object(index);
            let vector = self.constraint_center - object.position;
            let x = vector.at(zero_index);
            let y = vector.at(one_index);
            let distance = vector.matmul(@vector).at(zero_index).sqrt();
            let min_distance = self.constraint_radius - object.radius;
            // Check overlap
            if distance > min_distance {
                let distance_vectorized: Tensor<FP64x64> = TensorTrait::constant_of_shape(
                    vector.shape, distance
                );
                let normal = vector / distance_vectorized;
                let delta_vectorized: Tensor<FP64x64> = TensorTrait::constant_of_shape(
                    vector.shape, min_distance
                );
                // Update position
                object.position = self.constraint_center - normal * delta_vectorized;
                // Update object
                self.objects.insert(index, nullable_from_box(BoxTrait::new(object)));
            };
            index += 1;
        };
    }

    fn update_objects(ref self: Solver, dt: FP64x64) {
        let mut index: felt252 = 0;
        loop {
            if index == self.count.into() {
                break;
            }
            let mut object = self.get_object(index);
            object.update(dt);
            self.objects.insert(index, nullable_from_box(BoxTrait::new(object)));
            index += 1;
        };
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use debug::PrintTrait;

    // External imports

    use orion::numbers::fixed_point::core::{FixedTrait};
    use orion::numbers::{NumberTrait, FP64x64, FP64x64Impl};
    use orion::operators::tensor::core::{Tensor, TensorTrait};
    use orion::operators::tensor::implementations::tensor_fp64x64::{FP64x64Tensor};

    // Local imports

    use super::{Object, ObjectTrait, Solver, PublicTrait, PrivateTrait};

    #[test]
    #[available_gas(1_000_000)]
    fn test_create_default_object() {
        let object: Object = Default::default();
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_create_new_object() {
        let x: FP64x64 = FixedTrait::new_unscaled(1, false);
        let y: FP64x64 = FixedTrait::new_unscaled(2, false);
        let r: FP64x64 = FixedTrait::new_unscaled(3, false);
        let object: Object = ObjectTrait::new(x, y, r);
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_solver_add_object() {
        let x: FP64x64 = FixedTrait::new_unscaled(1, false);
        let y: FP64x64 = FixedTrait::new_unscaled(2, false);
        let r: FP64x64 = FixedTrait::new_unscaled(3, false);
        let object: Object = ObjectTrait::new(x, y, r);
        let mut solver: Solver = Default::default();
        solver.add_object(object);
    }

    #[test]
    #[available_gas(1_000_000_000)]
    fn test_solver_one_object_update() {
        let x: FP64x64 = FixedTrait::new_unscaled(1, false);
        let y: FP64x64 = FixedTrait::new_unscaled(2, false);
        let r: FP64x64 = FixedTrait::new_unscaled(3, false);
        let object: Object = ObjectTrait::new(x, y, r);
        let mut solver: Solver = Default::default();
        solver.add_object(object);
        solver.update();
    }

    #[test]
    #[available_gas(1_000_000_000)]
    fn test_solver_two_objects_update() {
        let mut solver: Solver = Default::default();
        let x: FP64x64 = FixedTrait::new_unscaled(1, false);
        let y: FP64x64 = FixedTrait::new_unscaled(2, false);
        let r1: FP64x64 = FixedTrait::new_unscaled(3, false);
        let r2: FP64x64 = FixedTrait::new_unscaled(4, false);
        let object_1: Object = ObjectTrait::new(x, y, r1);
        solver.add_object(object_1);
        let object_2: Object = ObjectTrait::new(y, x, r2);
        solver.add_object(object_2);
        solver.update();
        let objects = solver.get_objects();
        let zero: FP64x64 = FixedTrait::ZERO();
        let zero_index = array![0].span();
        let one_index = array![1].span();
        let updated_object_1 = *objects.at(0);
        assert(updated_object_1.radius == object_1.radius, 'Solver: wrong object 1 radius');
        assert(
            updated_object_1.position.at(zero_index) != object_1.position.at(zero_index),
            'Solver: wrong object Px'
        );
        assert(
            updated_object_1.position.at(one_index) != object_1.position.at(one_index),
            'Solver: wrong object Py'
        );
    }
}
