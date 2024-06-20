// Core imports

use core::integer::BoundedInt;
use core::debug::PrintTrait;

// Internal imports

use matchmaker::constants;

// Errors

mod errors {
    const INVALID_INDEX: felt252 = 'Bitmap: invalid index';
}

#[generate_trait]
impl Bitmap of BitmapTrait {
    #[inline(always)]
    fn get_bit_at(bitmap: u256, index: felt252) -> bool {
        let mask = Self::two_pow(index);
        bitmap & mask == mask
    }

    #[inline(always)]
    fn set_bit_at(bitmap: u256, index: felt252, value: bool) -> u256 {
        let mask = Self::two_pow(index);
        if value {
            bitmap | mask
        } else {
            bitmap & (BoundedInt::max() - mask)
        }
    }

    /// The index of the nearest significant bit to the index of the number,
    /// where the least significant bit is at index 0 and the most significant bit is at index 255
    /// # Arguments
    /// * `x` - The value for which to compute the most significant bit, must be greater than 0.
    /// * `s` - The index for which to start the search.
    /// # Returns
    /// * The index of the nearest significant bit
    #[inline(always)]
    fn nearest_significant_bit(x: u256, s: u8) -> Option::<u8> {
        let lower_mask = Self::set_bit_at(0, (s + 1).into(), true) - 1;
        let lower = Self::most_significant_bit(x & lower_mask);
        let upper_mask = ~(lower_mask / 2);
        let upper = Self::least_significant_bit(x & upper_mask);
        match (lower, upper) {
            (
                Option::Some(l), Option::Some(u)
            ) => { if s - l < u - s {
                Option::Some(l)
            } else {
                Option::Some(u)
            } },
            (Option::Some(l), Option::None) => Option::Some(l),
            (Option::None, Option::Some(u)) => Option::Some(u),
            (Option::None, Option::None) => Option::None,
        }
    }

    /// The index of the most significant bit of the number,
    /// where the least significant bit is at index 0 and the most significant bit is at index 255
    /// # Arguments * `x` - The value for which to compute the most significant bit, must be greater
    /// than 0.
    /// # Returns
    /// * The index of the most significant bit
    #[inline(always)]
    fn most_significant_bit(mut x: u256) -> Option<u8> {
        if x == 0 {
            return Option::None;
        }
        let mut r: u8 = 0;

        if x >= 0x100000000000000000000000000000000 {
            x /= 0x100000000000000000000000000000000;
            r += 128;
        }
        if x >= 0x10000000000000000 {
            x /= 0x10000000000000000;
            r += 64;
        }
        if x >= 0x100000000 {
            x /= 0x100000000;
            r += 32;
        }
        if x >= 0x10000 {
            x /= 0x10000;
            r += 16;
        }
        if x >= 0x100 {
            x /= 0x100;
            r += 8;
        }
        if x >= 0x10 {
            x /= 0x10;
            r += 4;
        }
        if x >= 0x4 {
            x /= 0x4;
            r += 2;
        }
        if x >= 0x2 {
            r += 1;
        }
        Option::Some(r)
    }

    /// The index of the least significant bit of the number,
    /// where the least significant bit is at index 0 and the most significant bit is at index 255
    /// # Arguments * `x` - The value for which to compute the least significant bit, must be
    /// greater than 0.
    /// # Returns
    /// * The index of the least significant bit
    #[inline(always)]
    fn least_significant_bit(mut x: u256) -> Option<u8> {
        if x == 0 {
            return Option::None;
        }
        let mut r: u8 = 255;

        if (x & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > 0 {
            r -= 128;
        } else {
            x /= 0x100000000000000000000000000000000;
        }
        if (x & 0xFFFFFFFFFFFFFFFF) > 0 {
            r -= 64;
        } else {
            x /= 0x10000000000000000;
        }
        if (x & 0xFFFFFFFF) > 0 {
            r -= 32;
        } else {
            x /= 0x100000000;
        }
        if (x & 0xFFFF) > 0 {
            r -= 16;
        } else {
            x /= 0x10000;
        }
        if (x & 0xFF) > 0 {
            r -= 8;
        } else {
            x /= 0x100;
        }
        if (x & 0xF) > 0 {
            r -= 4;
        } else {
            x /= 0x10;
        }
        if (x & 0x3) > 0 {
            r -= 2;
        } else {
            x /= 0x4;
        }
        if (x & 0x1) > 0 {
            r -= 1;
        }
        Option::Some(r)
    }

    #[inline(always)]
    fn two_pow(exponent: felt252) -> u256 {
        match exponent {
            0 => constants::TWO_POW_0,
            1 => constants::TWO_POW_1,
            2 => constants::TWO_POW_2,
            3 => constants::TWO_POW_3,
            4 => constants::TWO_POW_4,
            5 => constants::TWO_POW_5,
            6 => constants::TWO_POW_6,
            7 => constants::TWO_POW_7,
            8 => constants::TWO_POW_8,
            9 => constants::TWO_POW_9,
            10 => constants::TWO_POW_10,
            11 => constants::TWO_POW_11,
            12 => constants::TWO_POW_12,
            13 => constants::TWO_POW_13,
            14 => constants::TWO_POW_14,
            15 => constants::TWO_POW_15,
            16 => constants::TWO_POW_16,
            17 => constants::TWO_POW_17,
            18 => constants::TWO_POW_18,
            19 => constants::TWO_POW_19,
            20 => constants::TWO_POW_20,
            21 => constants::TWO_POW_21,
            22 => constants::TWO_POW_22,
            23 => constants::TWO_POW_23,
            24 => constants::TWO_POW_24,
            25 => constants::TWO_POW_25,
            26 => constants::TWO_POW_26,
            27 => constants::TWO_POW_27,
            28 => constants::TWO_POW_28,
            29 => constants::TWO_POW_29,
            30 => constants::TWO_POW_30,
            31 => constants::TWO_POW_31,
            32 => constants::TWO_POW_32,
            33 => constants::TWO_POW_33,
            34 => constants::TWO_POW_34,
            35 => constants::TWO_POW_35,
            36 => constants::TWO_POW_36,
            37 => constants::TWO_POW_37,
            38 => constants::TWO_POW_38,
            39 => constants::TWO_POW_39,
            40 => constants::TWO_POW_40,
            41 => constants::TWO_POW_41,
            42 => constants::TWO_POW_42,
            43 => constants::TWO_POW_43,
            44 => constants::TWO_POW_44,
            45 => constants::TWO_POW_45,
            46 => constants::TWO_POW_46,
            47 => constants::TWO_POW_47,
            48 => constants::TWO_POW_48,
            49 => constants::TWO_POW_49,
            50 => constants::TWO_POW_50,
            51 => constants::TWO_POW_51,
            52 => constants::TWO_POW_52,
            53 => constants::TWO_POW_53,
            54 => constants::TWO_POW_54,
            55 => constants::TWO_POW_55,
            56 => constants::TWO_POW_56,
            57 => constants::TWO_POW_57,
            58 => constants::TWO_POW_58,
            59 => constants::TWO_POW_59,
            60 => constants::TWO_POW_60,
            61 => constants::TWO_POW_61,
            62 => constants::TWO_POW_62,
            63 => constants::TWO_POW_63,
            64 => constants::TWO_POW_64,
            65 => constants::TWO_POW_65,
            66 => constants::TWO_POW_66,
            67 => constants::TWO_POW_67,
            68 => constants::TWO_POW_68,
            69 => constants::TWO_POW_69,
            70 => constants::TWO_POW_70,
            71 => constants::TWO_POW_71,
            72 => constants::TWO_POW_72,
            73 => constants::TWO_POW_73,
            74 => constants::TWO_POW_74,
            75 => constants::TWO_POW_75,
            76 => constants::TWO_POW_76,
            77 => constants::TWO_POW_77,
            78 => constants::TWO_POW_78,
            79 => constants::TWO_POW_79,
            80 => constants::TWO_POW_80,
            81 => constants::TWO_POW_81,
            82 => constants::TWO_POW_82,
            83 => constants::TWO_POW_83,
            84 => constants::TWO_POW_84,
            85 => constants::TWO_POW_85,
            86 => constants::TWO_POW_86,
            87 => constants::TWO_POW_87,
            88 => constants::TWO_POW_88,
            89 => constants::TWO_POW_89,
            90 => constants::TWO_POW_90,
            91 => constants::TWO_POW_91,
            92 => constants::TWO_POW_92,
            93 => constants::TWO_POW_93,
            94 => constants::TWO_POW_94,
            95 => constants::TWO_POW_95,
            96 => constants::TWO_POW_96,
            97 => constants::TWO_POW_97,
            98 => constants::TWO_POW_98,
            99 => constants::TWO_POW_99,
            100 => constants::TWO_POW_100,
            101 => constants::TWO_POW_101,
            102 => constants::TWO_POW_102,
            103 => constants::TWO_POW_103,
            104 => constants::TWO_POW_104,
            105 => constants::TWO_POW_105,
            106 => constants::TWO_POW_106,
            107 => constants::TWO_POW_107,
            108 => constants::TWO_POW_108,
            109 => constants::TWO_POW_109,
            110 => constants::TWO_POW_110,
            111 => constants::TWO_POW_111,
            112 => constants::TWO_POW_112,
            113 => constants::TWO_POW_113,
            114 => constants::TWO_POW_114,
            115 => constants::TWO_POW_115,
            116 => constants::TWO_POW_116,
            117 => constants::TWO_POW_117,
            118 => constants::TWO_POW_118,
            119 => constants::TWO_POW_119,
            120 => constants::TWO_POW_120,
            121 => constants::TWO_POW_121,
            122 => constants::TWO_POW_122,
            123 => constants::TWO_POW_123,
            124 => constants::TWO_POW_124,
            125 => constants::TWO_POW_125,
            126 => constants::TWO_POW_126,
            127 => constants::TWO_POW_127,
            128 => constants::TWO_POW_128,
            129 => constants::TWO_POW_129,
            130 => constants::TWO_POW_130,
            131 => constants::TWO_POW_131,
            132 => constants::TWO_POW_132,
            133 => constants::TWO_POW_133,
            134 => constants::TWO_POW_134,
            135 => constants::TWO_POW_135,
            136 => constants::TWO_POW_136,
            137 => constants::TWO_POW_137,
            138 => constants::TWO_POW_138,
            139 => constants::TWO_POW_139,
            140 => constants::TWO_POW_140,
            141 => constants::TWO_POW_141,
            142 => constants::TWO_POW_142,
            143 => constants::TWO_POW_143,
            144 => constants::TWO_POW_144,
            145 => constants::TWO_POW_145,
            146 => constants::TWO_POW_146,
            147 => constants::TWO_POW_147,
            148 => constants::TWO_POW_148,
            149 => constants::TWO_POW_149,
            150 => constants::TWO_POW_150,
            151 => constants::TWO_POW_151,
            152 => constants::TWO_POW_152,
            153 => constants::TWO_POW_153,
            154 => constants::TWO_POW_154,
            155 => constants::TWO_POW_155,
            156 => constants::TWO_POW_156,
            157 => constants::TWO_POW_157,
            158 => constants::TWO_POW_158,
            159 => constants::TWO_POW_159,
            160 => constants::TWO_POW_160,
            161 => constants::TWO_POW_161,
            162 => constants::TWO_POW_162,
            163 => constants::TWO_POW_163,
            164 => constants::TWO_POW_164,
            165 => constants::TWO_POW_165,
            166 => constants::TWO_POW_166,
            167 => constants::TWO_POW_167,
            168 => constants::TWO_POW_168,
            169 => constants::TWO_POW_169,
            170 => constants::TWO_POW_170,
            171 => constants::TWO_POW_171,
            172 => constants::TWO_POW_172,
            173 => constants::TWO_POW_173,
            174 => constants::TWO_POW_174,
            175 => constants::TWO_POW_175,
            176 => constants::TWO_POW_176,
            177 => constants::TWO_POW_177,
            178 => constants::TWO_POW_178,
            179 => constants::TWO_POW_179,
            180 => constants::TWO_POW_180,
            181 => constants::TWO_POW_181,
            182 => constants::TWO_POW_182,
            183 => constants::TWO_POW_183,
            184 => constants::TWO_POW_184,
            185 => constants::TWO_POW_185,
            186 => constants::TWO_POW_186,
            187 => constants::TWO_POW_187,
            188 => constants::TWO_POW_188,
            189 => constants::TWO_POW_189,
            190 => constants::TWO_POW_190,
            191 => constants::TWO_POW_191,
            192 => constants::TWO_POW_192,
            193 => constants::TWO_POW_193,
            194 => constants::TWO_POW_194,
            195 => constants::TWO_POW_195,
            196 => constants::TWO_POW_196,
            197 => constants::TWO_POW_197,
            198 => constants::TWO_POW_198,
            199 => constants::TWO_POW_199,
            200 => constants::TWO_POW_200,
            201 => constants::TWO_POW_201,
            202 => constants::TWO_POW_202,
            203 => constants::TWO_POW_203,
            204 => constants::TWO_POW_204,
            205 => constants::TWO_POW_205,
            206 => constants::TWO_POW_206,
            207 => constants::TWO_POW_207,
            208 => constants::TWO_POW_208,
            209 => constants::TWO_POW_209,
            210 => constants::TWO_POW_210,
            211 => constants::TWO_POW_211,
            212 => constants::TWO_POW_212,
            213 => constants::TWO_POW_213,
            214 => constants::TWO_POW_214,
            215 => constants::TWO_POW_215,
            216 => constants::TWO_POW_216,
            217 => constants::TWO_POW_217,
            218 => constants::TWO_POW_218,
            219 => constants::TWO_POW_219,
            220 => constants::TWO_POW_220,
            221 => constants::TWO_POW_221,
            222 => constants::TWO_POW_222,
            223 => constants::TWO_POW_223,
            224 => constants::TWO_POW_224,
            225 => constants::TWO_POW_225,
            226 => constants::TWO_POW_226,
            227 => constants::TWO_POW_227,
            228 => constants::TWO_POW_228,
            229 => constants::TWO_POW_229,
            230 => constants::TWO_POW_230,
            231 => constants::TWO_POW_231,
            232 => constants::TWO_POW_232,
            233 => constants::TWO_POW_233,
            234 => constants::TWO_POW_234,
            235 => constants::TWO_POW_235,
            236 => constants::TWO_POW_236,
            237 => constants::TWO_POW_237,
            238 => constants::TWO_POW_238,
            239 => constants::TWO_POW_239,
            240 => constants::TWO_POW_240,
            241 => constants::TWO_POW_241,
            242 => constants::TWO_POW_242,
            243 => constants::TWO_POW_243,
            244 => constants::TWO_POW_244,
            245 => constants::TWO_POW_245,
            246 => constants::TWO_POW_246,
            247 => constants::TWO_POW_247,
            248 => constants::TWO_POW_248,
            249 => constants::TWO_POW_249,
            250 => constants::TWO_POW_250,
            251 => constants::TWO_POW_251,
            252 => constants::TWO_POW_252,
            _ => {
                panic(array![errors::INVALID_INDEX,]);
                0
            },
        }
    }
}

#[cfg(test)]
mod tests {
    // Core imports

    use core::debug::PrintTrait;

    // Local imports

    use super::{Bitmap};

    #[test]
    fn test_helpers_get_bit_at_0() {
        let bitmap = 0;
        let result = Bitmap::get_bit_at(bitmap, 0);
        assert(!result, 'Bitmap: Invalid bit');
    }

    #[test]
    fn test_helpers_get_bit_at_1() {
        let bitmap = 255;
        let result = Bitmap::get_bit_at(bitmap, 1);
        assert(result, 'Bitmap: Invalid bit');
    }

    #[test]
    fn test_helpers_get_bit_at_10() {
        let bitmap = 3071;
        let result = Bitmap::get_bit_at(bitmap, 10);
        assert(!result, 'Bitmap: Invalid bit');
    }

    #[test]
    fn test_helpers_set_bit_at_0() {
        let bitmap = 0;
        let result = Bitmap::set_bit_at(bitmap, 0, true);
        assert(result == 1, 'Bitmap: Invalid bitmap');
        let result = Bitmap::set_bit_at(bitmap, 0, false);
        assert(result == bitmap, 'Bitmap: Invalid bitmap');
    }

    #[test]
    fn test_helpers_set_bit_at_1() {
        let bitmap = 1;
        let result = Bitmap::set_bit_at(bitmap, 1, true);
        assert(result == 3, 'Bitmap: Invalid bitmap');
        let result = Bitmap::set_bit_at(bitmap, 1, false);
        assert(result == bitmap, 'Bitmap: Invalid bitmap');
    }

    #[test]
    fn test_helpers_set_bit_at_10() {
        let bitmap = 3;
        let result = Bitmap::set_bit_at(bitmap, 10, true);
        assert(result == 1027, 'Bitmap: Invalid bitmap');
        let result = Bitmap::set_bit_at(bitmap, 10, false);
        assert(result == bitmap, 'Bitmap: Invalid bitmap');
    }

    #[test]
    #[should_panic(expected: ('Bitmap: invalid index',))]
    fn test_helpers_set_bit_at_253() {
        let bitmap = 0;
        Bitmap::set_bit_at(bitmap, 253, true);
    }
}
