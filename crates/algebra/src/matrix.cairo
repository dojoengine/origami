use zeroable::Zeroable;

#[derive(Copy, Drop)]
struct Matrix<T> {
    data: Span<T>,
    rows: u8,
    cols: u8,
}

mod errors {
    const INVALID_INDEX: felt252 = 'Matrix: index out of bounds';
    const INVALID_DIMENSION: felt252 = 'Matrix: invalid dimension';
    const INVALID_MATRIX_INVERSION: felt252 = 'Matrix: matrix not invertible';
}

trait MatrixTrait<T> {
    fn new(data: Span<T>, rows: u8, cols: u8) -> Matrix<T>;

    fn get(ref self: Matrix<T>, row: u8, col: u8) -> T;

    fn transpose(ref self: Matrix<T>) -> Matrix<T>;

    fn minor(ref self: Matrix<T>, exclude_row: u8, exclude_col: u8) -> Matrix<T>;

    fn det(ref self: Matrix<T>) -> T;

    fn inv(ref self: Matrix<T>) -> Matrix<T>;
}

impl MatrixImpl<
    T,
    +Mul<T>,
    +Div<T>,
    +Add<T>,
    +AddEq<T>,
    +Sub<T>,
    +SubEq<T>,
    +Neg<T>,
    +Zeroable<T>,
    +Copy<T>,
    +Drop<T>,
> of MatrixTrait<T> {
    fn new(data: Span<T>, rows: u8, cols: u8) -> Matrix<T> {
        // [Check] Data is consistent with dimensions
        assert(data.len() == (rows * cols).into(), errors::INVALID_DIMENSION);
        Matrix { data, rows, cols }
    }

    fn get(ref self: Matrix<T>, row: u8, col: u8) -> T {
        let index: u8 = row * self.cols + col;
        *self.data.get(index.into()).expect(errors::INVALID_INDEX).unbox()
    }

    fn transpose(ref self: Matrix<T>) -> Matrix<T> {
        let mut values = array![];
        let max_index: u8 = self.rows * self.cols;
        let mut index: u8 = 0;
        loop {
            if index == max_index {
                break;
            }
            let row = index % self.rows;
            let col = index / self.rows;
            values.append(self.get(row, col));
            index += 1;
        };
        MatrixTrait::new(values.span(), self.cols, self.rows)
    }

    fn minor(ref self: Matrix<T>, exclude_row: u8, exclude_col: u8) -> Matrix<T> {
        let mut values = array![];
        let mut index: u8 = 0;
        let max_index: u8 = self.rows * self.cols;
        loop {
            if index == max_index {
                break;
            };

            let row = index / self.cols;
            let col = index % self.cols;

            if row != exclude_row && col != exclude_col {
                values.append(self.get(row, col));
            };

            index += 1;
        };

        MatrixTrait::new(values.span(), self.cols - 1, self.rows - 1)
    }

    fn det(ref self: Matrix<T>) -> T {
        // [Check] Matrix is square
        assert(self.rows == self.cols, errors::INVALID_DIMENSION);
        if self.rows == 1 {
            return self.get(0, 0);
        }

        if self.rows == 2 {
            return (self.get(0, 0) * self.get(1, 1)) - (self.get(0, 1) * self.get(1, 0));
        }

        let mut det: T = Zeroable::zero();
        let mut col: u8 = 0;
        loop {
            if col >= self.cols {
                break;
            }

            let coef = self.get(0, col);
            let mut minor = self.minor(0, col);
            if col % 2 == 0 {
                det += coef * minor.det();
            } else {
                det -= coef * minor.det();
            };

            col += 1;
        };

        return det;
    }

    fn inv(ref self: Matrix<T>) -> Matrix<T> {
        let determinant = self.det();
        assert(determinant.is_non_zero(), errors::INVALID_MATRIX_INVERSION);

        let mut values: Array<T> = array![];

        let max_index: u8 = self.rows * self.cols;
        let mut index: u8 = 0;

        loop {
            if index == max_index {
                break;
            }

            // Extract row and column from the linear index
            let col = index / self.rows;
            let row = index % self.rows;

            // Compute the cofactor
            let mut minor = self.minor(row, col);
            let cofactor = if (row + col) % 2 == 0 {
                minor.det()
            } else {
                -minor.det()
            };
            values.append(cofactor / determinant);

            index += 1;
        };

        MatrixTrait::new(values.span(), self.cols, self.rows)
    }
}

impl MatrixAdd<
    T,
    +Mul<T>,
    +Div<T>,
    +Add<T>,
    +AddEq<T>,
    +Sub<T>,
    +SubEq<T>,
    +Neg<T>,
    +Zeroable<T>,
    +Copy<T>,
    +Drop<T>,
> of Add<Matrix<T>> {
    fn add(mut lhs: Matrix<T>, mut rhs: Matrix<T>) -> Matrix<T> {
        // [Check] Dimesions are compatible
        assert(lhs.rows == rhs.rows && lhs.cols == rhs.cols, errors::INVALID_DIMENSION);
        let mut values = array![];
        let max_index = lhs.rows * lhs.cols;
        let mut index = 0;
        loop {
            if index == max_index {
                break;
            }
            let row = index / lhs.cols;
            let col = index % lhs.cols;
            values.append(lhs.get(row, col) + rhs.get(row, col));
            index += 1;
        };
        MatrixTrait::new(values.span(), lhs.rows, lhs.cols)
    }
}

impl MatrixSub<
    T,
    +Mul<T>,
    +Div<T>,
    +Add<T>,
    +AddEq<T>,
    +Sub<T>,
    +SubEq<T>,
    +Neg<T>,
    +Zeroable<T>,
    +Copy<T>,
    +Drop<T>,
> of Sub<Matrix<T>> {
    fn sub(mut lhs: Matrix<T>, mut rhs: Matrix<T>) -> Matrix<T> {
        // [Check] Dimesions are compatible
        assert(lhs.rows == rhs.rows && lhs.cols == rhs.cols, errors::INVALID_DIMENSION);
        let mut values = array![];
        let max_index = lhs.rows * lhs.cols;
        let mut index = 0;
        loop {
            if index == max_index {
                break;
            }
            let row = index / lhs.cols;
            let col = index % lhs.cols;
            values.append(lhs.get(row, col) - rhs.get(row, col));
            index += 1;
        };
        MatrixTrait::new(values.span(), lhs.rows, lhs.cols)
    }
}

impl MatrixMul<
    T,
    +Mul<T>,
    +Div<T>,
    +Add<T>,
    +AddEq<T>,
    +Sub<T>,
    +SubEq<T>,
    +Neg<T>,
    +Zeroable<T>,
    +Copy<T>,
    +Drop<T>,
> of Mul<Matrix<T>> {
    fn mul(mut lhs: Matrix<T>, mut rhs: Matrix<T>) -> Matrix<T> {
        // [Check] Dimesions are compatible
        assert(lhs.cols == rhs.rows, errors::INVALID_DIMENSION);
        let mut values = array![];
        let max_index = lhs.rows * rhs.cols;
        let mut index: u8 = 0;
        loop {
            if index == max_index {
                break;
            }

            let row = index / rhs.cols;
            let col = index % rhs.cols;

            let mut sum: T = Zeroable::zero();
            let mut k: u8 = 0;
            loop {
                if k == lhs.cols {
                    break;
                }

                sum += lhs.get(row, k) * rhs.get(k, col);
                k += 1;
            };
            values.append(sum);
            index += 1;
        };

        MatrixTrait::new(values.span(), lhs.rows, rhs.cols)
    }
}

#[cfg(test)]
mod tests {
    use core::traits::TryInto;
    use super::{Matrix, MatrixTrait};
    use debug::PrintTrait;

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

    impl I128Div of Div<i128> {
        fn div(lhs: i128, rhs: i128) -> i128 {
            let lhs_u256: u256 = Into::<felt252, u256>::into(lhs.into());
            let rhs_u256: u256 = Into::<felt252, u256>::into(rhs.into());
            let div: felt252 = (lhs_u256 / rhs_u256).try_into().unwrap();
            div.try_into().unwrap()
        }
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_matrix_get() {
        let rows: u8 = 3;
        let cols: u8 = 4;
        let values: Array<i128> = array![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        let mut matrix: Matrix = MatrixTrait::new(values.span(), rows, cols);
        assert(matrix.get(0, 1) == 2, 'Matrix: get failed');
        assert(matrix.get(2, 3) == 12, 'Matrix: get failed');
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_matrix_transpose() {
        let rows: u8 = 2;
        let cols: u8 = 3;
        let values: Array<i128> = array![1, 2, 3, 4, 5, 6];
        let mut matrix: Matrix = MatrixTrait::new(values.span(), rows, cols);
        let mut transposed = matrix.transpose();
        assert(transposed.get(0, 1) == 4, 'Matrix: transpose failed');
        assert(transposed.get(2, 1) == 6, 'Matrix: transpose failed');
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_matrix_addition() {
        let rows: u8 = 2;
        let cols: u8 = 3;
        let values: Array<i128> = array![1, 2, 3, 4, 5, 6];
        let mut matrix1 = MatrixTrait::new(values.span(), rows, cols);
        let mut matrix2 = MatrixTrait::new(values.span(), rows, cols);
        let mut result = matrix1 + matrix2;
        assert(result.get(0, 0) == 2, 'Matrix: addition failed');
        assert(result.get(1, 1) == 10, 'Matrix: addition failed');
    }

    #[test]
    #[available_gas(1_000_000)]
    fn test_matrix_subtraction() {
        let rows: u8 = 2;
        let cols: u8 = 3;
        let values: Array<i128> = array![1, 2, 3, 4, 5, 6];
        let mut matrix1 = MatrixTrait::new(values.span(), rows, cols);
        let values: Array<i128> = array![7, 8, 9, 10, 11, 12];
        let mut matrix2 = MatrixTrait::new(values.span(), rows, cols);
        let mut result = matrix1 - matrix2;
        assert(result.get(0, 0) == -6, 'Matrix: subtraction failed');
        assert(result.get(1, 1) == -6, 'Matrix: subtraction failed');
    }

    #[test]
    #[available_gas(10_000_000)]
    fn test_matrix_square_multiplication() {
        let size: u8 = 2;
        let values: Array<i128> = array![1, 2, 3, 4];
        let mut matrix1 = MatrixTrait::new(values.span(), size, size);
        let mut matrix2 = MatrixTrait::new(values.span(), size, size);
        let mut result = matrix1 * matrix2;
        assert(result.get(0, 0) == 7, 'Matrix: multiplication failed');
        assert(result.get(0, 1) == 10, 'Matrix: multiplication failed');
        assert(result.get(1, 0) == 15, 'Matrix: multiplication failed');
        assert(result.get(1, 1) == 22, 'Matrix: multiplication failed');
    }

    #[test]
    #[available_gas(10_000_000)]
    fn test_matrix_rectangle_multiplication() {
        let values: Array<i128> = array![1, 2, 3, 4, 5, 6];
        let mut matrix1 = MatrixTrait::new(values.span(), 2, 3);
        let mut matrix2 = MatrixTrait::new(values.span(), 3, 2);
        let mut result = matrix1 * matrix2;
        assert(result.get(0, 0) == 22, 'Matrix: multiplication failed');
        assert(result.get(0, 1) == 28, 'Matrix: multiplication failed');
        assert(result.get(1, 0) == 49, 'Matrix: multiplication failed');
        assert(result.get(1, 1) == 64, 'Matrix: multiplication failed');
    }

    #[test]
    #[available_gas(5_000_000)]
    fn test_matrix_determinant_2x2() {
        let values: Array<i128> = array![4, 3, 1, 2];
        let mut matrix = MatrixTrait::new(values.span(), 2, 2);
        assert(matrix.det() == 5, 'Matrix: det computation failed');
    }

    #[test]
    #[available_gas(10_000_000)]
    fn test_matrix_determinant_3x3() {
        let values: Array<i128> = array![6, 1, 1, 4, -2, 5, 2, 8, 7];
        let mut matrix = MatrixTrait::new(values.span(), 3, 3);
        assert(matrix.det() == -306, 'Matrix: det computation failed');
    }

    #[test]
    #[available_gas(10_000_000)]
    fn test_matrix_inverse_2x2() {
        let values: Array<i128> = array![1, 2, 0, 1];
        let mut matrix = MatrixTrait::new(values.span(), 2, 2);
        let mut inverse = matrix.inv();
        assert(inverse.get(0, 0) == 1, 'Matrix: inversion failed');
        assert(inverse.get(0, 1) == -2, 'Matrix: inversion failed');
        assert(inverse.get(1, 0) == 0, 'Matrix: inversion failed');
        assert(inverse.get(1, 1) == 1, 'Matrix: inversion failed');
    }

    #[test]
    #[available_gas(10_000_000)]
    fn test_matrix_inverse_3x3() {
        let values: Array<i128> = array![1, 1, 0, 0, 1, 0, 0, 1, 1];
        let mut matrix = MatrixTrait::new(values.span(), 3, 3);
        let mut inverse = matrix.inv();
        assert(inverse.get(0, 0) == 1, 'Matrix: inversion failed');
        assert(inverse.get(0, 1) == -1, 'Matrix: inversion failed');
        assert(inverse.get(0, 2) == 0, 'Matrix: inversion failed');
        assert(inverse.get(1, 0) == 0, 'Matrix: inversion failed');
        assert(inverse.get(1, 1) == 1, 'Matrix: inversion failed');
        assert(inverse.get(1, 2) == 0, 'Matrix: inversion failed');
        assert(inverse.get(2, 0) == 0, 'Matrix: inversion failed');
        assert(inverse.get(2, 1) == -1, 'Matrix: inversion failed');
        assert(inverse.get(2, 2) == 1, 'Matrix: inversion failed');
    }
}