use cubit::f64::procgen::simplex3;
use cubit::f64::types::vec3::{Vec3, Vec3Trait};
use cubit::f64::types::fixed::{Fixed, FixedTrait, FixedPrint, FixedImpl, ONE};

use origami::map::hex::{types::{Direction, HexTile}};
use origami::map::hex::{hex::{IHexTile, ImplHexTile}};

mod TileType {
    const WATER: u8 = 0;
    const LAND: u8 = 1;
    const HILL: u8 = 2;
    const MOUNTAIN: u8 = 3;
}

#[generate_trait]
impl ImplTile of ITile {
    fn terrain_type(self: HexTile) -> u8 {
        let simplex = simplex3::noise(
            Vec3Trait::new(
                FixedTrait::new_unscaled(self.col.into(), false),
                FixedTrait::new_unscaled(self.row.into(), false),
                FixedTrait::from_felt(0)
            )
        );

        let mag = simplex.mag;
        let one: u64 = ONE.into();

        if mag > (one * 3 / 4) {
            TileType::MOUNTAIN
        } else if mag > (one * 2 / 4) {
            TileType::HILL
        } else if mag > (one * 1 / 4) {
            TileType::LAND
        } else {
            TileType::WATER
        }
    }
    fn check_moveable(self: HexTile) {
        assert(self.terrain_type() != TileType::WATER, 'Cannot walk on water');
    }
}

#[cfg(test)]
mod tests {
    use traits::{TryInto, Into};
    use option::OptionTrait;
    use debug::PrintTrait;
    use super::{Direction, HexTile, ImplHexTile, ITile};

    #[test]
    #[available_gas(500000000)]
    fn test_gradient() {
        let mut i = 5;

        let mut tile = ImplHexTile::new(7, 5);

        let neighbors = tile.neighbors();

        let mut j = 0;
        loop {
            if (j >= neighbors.len()) {
                break;
            }
            let n = *neighbors.at(j);

            j += 1;
        };

        i += 1;
    }
}
