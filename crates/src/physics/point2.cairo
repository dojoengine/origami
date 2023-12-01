struct Point2<N> {
    x: N,
    y: N,
}

trait Point2Trait<N> {
    #[inline(always)]
    fn new(x: N, y: N) -> Point2<N>;
}
