// Internal imports

use origami_map::helpers::power::{TwoPower, TwoPowerTrait};

#[generate_trait]
pub impl Bitmap of BitmapTrait {
    #[inline]
    fn popcount(mut x: u256) -> u8 {
        let mut count: u8 = 0;
        while (x > 0) {
            count += PrivateTrait::_popcount((x % 0x100000000).try_into().unwrap());
            x /= 0x100000000;
        };
        count
    }

    #[inline]
    fn get(map: felt252, index: u8) -> u8 {
        let map: u256 = map.into();
        let offset: u256 = TwoPower::power(index);
        (map / offset % 2).try_into().unwrap()
    }

    #[inline]
    fn set(map: felt252, index: u8) -> felt252 {
        let map: u256 = map.into();
        let offset: u256 = TwoPower::power(index);
        let bit = map / offset % 2;
        let offset: u256 = offset * (1 - bit);
        (map + offset).try_into().unwrap()
    }

    #[inline]
    fn unset(map: felt252, index: u8) -> felt252 {
        let map: u256 = map.into();
        let offset: u256 = TwoPower::power(index);
        let bit = map / offset % 2;
        let offset: u256 = offset * bit;
        (map - offset).try_into().unwrap()
    }
}

#[generate_trait]
impl Private of PrivateTrait {
    #[inline]
    fn _popcount(mut x: u32) -> u8 {
        x -= ((x / 2) & 0x55555555);
        x = (x & 0x33333333) + ((x / 4) & 0x33333333);
        x = (x + (x / 16)) & 0x0f0f0f0f;
        x += (x / 256);
        x += (x / 65536);
        return (x % 64).try_into().unwrap();
    }
}

#[cfg(test)]
mod tests {
    // Local imports

    use super::Bitmap;

    #[test]
    fn test_bitmap_popcount_large() {
        let count = Bitmap::popcount(0x4003FBB391C53CCB8E99752EB665586B695BB2D026BEC9071FF30002);
        assert_eq!(count, 109);
    }

    #[test]
    fn test_bitmap_popcount_small() {
        let count = Bitmap::popcount(0b101);
        assert_eq!(count, 2);
    }

    #[test]
    fn test_bitmap_get() {
        let bit = Bitmap::get(0b1001011, 0);
        assert_eq!(bit, 1);
    }

    #[test]
    fn test_bitmap_set() {
        let bit = Bitmap::set(0b1001010, 0);
        assert_eq!(bit, 0b1001011);
    }

    #[test]
    fn test_bitmap_set_unchanged() {
        let bit = Bitmap::set(0b1001011, 0);
        assert_eq!(bit, 0b1001011);
    }

    #[test]
    fn test_bitmap_unset() {
        let bit = Bitmap::unset(0b1001011, 0);
        assert_eq!(bit, 0b1001010);
    }

    #[test]
    fn test_bitmap_unset_unchanged() {
        let bit = Bitmap::unset(0b1001010, 0);
        assert_eq!(bit, 0b1001010);
    }
}
