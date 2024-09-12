//! Module for printing maps.
use core::fmt::Formatter;

#[generate_trait]
pub impl MapPrinter of MapPrinterTrait {
    /// Prints the bitmap as a 2D grid where 1 is walkable and 0 is not.
    ///
    /// # Arguments
    /// * `map` - The bitmap to print
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    fn print(map: felt252, width: u8, height: u8) {
        println!("");

        let mut x: u256 = map.into();
        let mut y = 0;
        let mut lines: Array<ByteArray> = array![];

        while y < height {
            let mut line: ByteArray = "";
            let mut x_pos = 0;
            while x_pos < width {
                if x % 2 == 1 {
                    line.append(@"1");
                } else {
                    line.append(@"0");
                }
                x /= 2;
                x_pos += 1;
            };

            // Reverse the line to have smaller x coordinates at the end of the string.
            lines.append(line.rev());
            y += 1;
        };

        let mut lines = lines.span();
        // Reverse order to have smaller y coordinates at the bottom.
        while let Option::Some(l) = lines.pop_back() {
            println!("{}", l);
        };

        println!("");
    }

    /// Prints the bitmap as a 2D grid where 1 is walkable and 0 is not.
    /// The path is printed as a series of * characters and the start and end are printed as S and E
    /// respectively.
    ///
    /// # Arguments
    /// * `map` - The bitmap to print
    /// * `width` - The width of the grid
    /// * `height` - The height of the grid
    /// * `from` - The index of the starting position
    /// * `path` - The path to print
    fn print_with_path(map: felt252, width: u8, height: u8, from: u8, path: Span<u8>) {
        if path.is_empty() {
            return;
        }

        println!("");

        let mut x: u256 = map.into();
        let mut y = 0;
        let mut lines: Array<ByteArray> = array![];

        let last_path_index: u8 = *path[0];

        while y < height {
            let mut line: ByteArray = "";
            let mut x_pos = 0;
            while x_pos < width {
                let current_index = y * width + x_pos;

                let mut path_span = path;
                let mut found = false;
                while let Option::Some(value) = path_span.pop_front() {
                    if *value == current_index {
                        found = true;
                        break;
                    }
                };

                if current_index == from {
                    line.append(@"S");
                } else if current_index == last_path_index {
                    line.append(@"E");
                } else if found {
                    line.append(@"*");
                } else if x % 2 == 1 {
                    line.append(@"1");
                } else {
                    line.append(@"0");
                }
                x /= 2;
                x_pos += 1;
            };

            // Reverse the line to have smaller x coordinates at the end of the string.
            lines.append(line.rev());
            y += 1;
        };

        let mut lines = lines.span();
        // Reverse order to have smaller y coordinates at the bottom.
        while let Option::Some(l) = lines.pop_back() {
            println!("{}", l);
        };

        println!("");
    }
}
