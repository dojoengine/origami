// External imports

use orion::numbers::FixedTrait;
use orion::operators::tensor::{TensorTrait, Tensor};

struct Vector2<N> {
    x: N,
    y: N,
}

trait Vector2Trait<N> {
    #[inline(always)]
    fn new(x: N, y: N) -> Vector2<N>;
}
