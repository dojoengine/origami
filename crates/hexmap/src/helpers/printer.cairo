//! Module for printing hex maps (tests only).
//!
//! Rows are printed top (`y = H - 1`) to bottom, `x = 0` on the right, like `origami_map`. Odd rows
//! are shifted half a tile toward increasing `x`: even rows get one leading space.
//!
//! ```text
//!  0 0 0 0 0      y = 2
//! 0 1 1 1 0       y = 1
//!  0 0 0 0 0      y = 0
//! ```

// Internal imports

use origami_hexmap::helpers::bits::Bits;

#[generate_trait]
pub impl HexPrinter of HexPrinterTrait {
    /// Render the bitmap, `1` is walkable and `0` is not.
    /// # Arguments
    /// * `grid` - The bitmap to render
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// # Returns
    /// * The drawing, one line per row
    fn render(grid: felt252, width: u8, height: u8) -> ByteArray {
        Self::render_with_path(grid, width, height, 0xff, array![].span())
    }

    /// Render the bitmap with a path: `S` is the start, `E` the end (first item of the path), `*`
    /// the rest of the path.
    /// # Arguments
    /// * `grid` - The bitmap to render
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `from` - The index of the starting position
    /// * `path` - The path, from the end (included) to the start (excluded)
    /// # Returns
    /// * The drawing, one line per row
    fn render_with_path(
        grid: felt252, width: u8, height: u8, from: u8, path: Span<u8>,
    ) -> ByteArray {
        let grid: u256 = grid.into();
        let mut marks: felt252 = 0;
        let mut items = path;
        while let Option::Some(item) = items.pop_front() {
            marks += Bits::pow(*item);
        }
        let marks: u256 = marks.into();
        let end: u8 = if path.is_empty() {
            0xff
        } else {
            *path[0]
        };
        let mut drawing: ByteArray = "";
        let mut y = height;
        while y != 0 {
            y -= 1;
            if y % 2 == 0 {
                drawing.append(@" ");
            }
            let mut x = width;
            while x != 0 {
                x -= 1;
                let index = y * width + x;
                if index == from {
                    drawing.append(@"S");
                } else if index == end {
                    drawing.append(@"E");
                } else if Bits::get(marks, index) {
                    drawing.append(@"*");
                } else if Bits::get(grid, index) {
                    drawing.append(@"1");
                } else {
                    drawing.append(@"0");
                }
                if x != 0 {
                    drawing.append(@" ");
                }
            }
            drawing.append(@"\n");
        }
        drawing
    }

    /// Print the bitmap, `1` is walkable and `0` is not.
    /// # Arguments
    /// * `grid` - The bitmap to print
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    fn print(grid: felt252, width: u8, height: u8) {
        println!("");
        print!("{}", Self::render(grid, width, height));
    }

    /// Print the bitmap with a path, see `render_with_path`.
    /// # Arguments
    /// * `grid` - The bitmap to print
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `from` - The index of the starting position
    /// * `path` - The path, from the end (included) to the start (excluded)
    fn print_with_path(grid: felt252, width: u8, height: u8, from: u8, path: Span<u8>) {
        println!("");
        print!("{}", Self::render_with_path(grid, width, height, from, path));
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::HexPrinter;

    #[test]
    fn test_printer_render_shifts_even_rows() {
        // 5x3, interior (1..3, 1) open
        let grid: felt252 = 0b000000111000000;
        let expected: ByteArray = " 0 0 0 0 0\n0 1 1 1 0\n 0 0 0 0 0\n";
        assert!(HexPrinter::render(grid, 5, 3) == expected);
    }

    #[test]
    fn test_printer_render_with_path() {
        // Path from 6 to 8 through 7, printed right to left
        let grid: felt252 = 0b000000111000000;
        let expected: ByteArray = " 0 0 0 0 0\n0 E * S 0\n 0 0 0 0 0\n";
        assert!(HexPrinter::render_with_path(grid, 5, 3, 6, array![8, 7].span()) == expected);
    }
}
