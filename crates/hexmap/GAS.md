# origami_hexmap gas budgets

Every benchmark is a snforge test carrying `#[available_gas(l2_gas: N)]`: CI fails when a change
makes it more expensive than its budget.

## How to record a budget

1. Run `snforge test --package origami_hexmap bench_<lot> --detailed-resources` and read
   `sierra gas: N`. With Sierra >= 1.7, snforge reports `l2_gas` = Sierra gas, builtins included.
2. Measure **with a loose budget already set** (for example `2 * N`). Adding the attribute changes
   the measured gas of trivial tests by up to +1_420 (fixture baselines: 13_620 -> 15_040), and of
   the other tests by -100 to +920.
3. Set the budget to `ceil(1.05 * measured, 1000)` and add a row to your lot's section below
   (test, measured, budget, commit).
4. A pull request that makes a benchmark more than 5 % cheaper must lower its budget.

Microbenchmarks repeat the operation 100 times in a loop. Per-operation cost =
`(test - baseline) / 100`, where the baseline is `bench_baseline_loop` (the same loop that only
accumulates the counter) unless the table says otherwise. Every loop iteration itself costs 1_270.

Fixture baselines (`bench_baseline_*`, one per fixture): load the constant grid and assert
something trivial. Report `algorithm - baseline`. Each measures 15_040 (budget 16_000).

---

## L0 Foundation

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas).

### Results

| Primitive | Test | Measured | Budget | Per op | Design estimate | Verdict |
|---|---|---:|---:|---:|---|---|
| Loop iteration (`u8` decrement, `!= 0`, felt add) | `bench_baseline_loop` | 142_090 | 150_000 | 1_270 |  |  |
| felt252 mul by constant | `bench_felt_mul` | 151_890 | 160_000 | 98 | 0-100 | confirmed |
| felt252_div by a NonZero | `bench_felt_div_nonzero` | 191_490 | 202_000 | 494 | 200-400 | refuted, higher |
| POW table lookup (`span.at`) | `bench_pow_lookup` | 268_990 | 283_000 | 1_269 | (~300 with the lookup) | refuted, higher |
| POW 252-arm `match` (loser) | `bench_pow_match` | 267_720 | 282_000 | 1_256 |  |  |
| `shr_exact`: lookup + product by the INV table (winner) | `bench_shr_exact_inverse_table` | 288_990 | 304_000 | 1_469 |  |  |
| `shr_exact`: lookup + `felt252_div` (loser) | `bench_shr_exact_div` | 339_090 | 357_000 | 1_970 |  |  |
| felt252 -> u256, narrow (< 2^128) | `bench_felt_to_u256_narrow` | 224_040 | 236_000 | 820 | 1.0-1.3k | refuted, lower |
| felt252 -> u256, wide | `bench_felt_to_u256_wide` | 322_990 | 340_000 | 1_809 | 1.0-1.3k | refuted, higher |
| felt252 -> u128 (`try_into`) | `bench_felt_to_u128` | 169_190 | 178_000 | 271 |  |  |
| u256 -> felt252 unchecked (`low + high * 2^128`) | `bench_u256_to_felt_unchecked` | 161_790 | 170_000 | 197 | ~200 | confirmed |
| u256 -> felt252 checked (`try_into`) | `bench_u256_to_felt_checked` | 247_920 | 261_000 | 1_058 |  |  |
| u128 `&` | `bench_u128_and` | 311_690 | 328_000 | 1_696 | 700-800 | refuted, higher |
| u256 `&` | `bench_u256_and` | 410_290 | 431_000 | 2_682 | ~1.5k | refuted, higher |
| u256 `|` | `bench_u256_or` | 410_290 | 431_000 | 2_682 | ~1.5k | refuted, higher |
| u256 checked add | `bench_u256_add` | 337_020 | 354_000 | 1_949 |  |  |
| u256 mul by 2^17 ("shift") | `bench_u256_mul_pow` | 1_538_240 | 1_616_000 | 13_962 | 5-8k | refuted, higher |
| u256 div by 2^17 ("shift") | `bench_u256_div_pow` | 776_990 | 816_000 | 6_349 | 5-10k | confirmed |
| u8 DivRem | `bench_u8_divrem` | 251_880 | 265_000 | 1_098 | 500-900 | refuted, higher |
| u128 DivRem | `bench_u128_divrem` | 298_410 | 314_000 | 1_563 | 500-900 | refuted, higher |
| Bit test, single-limb AND (`Bits::get`) | `bench_bit_test_limb` | 1_131_920 | 1_189_000 | 4_949 | ~1k | refuted, higher |
| Bit test, two u256 divisions (`origami_map`) | `bench_bit_test_divmod` | 3_659_750 | 3_843_000 | 17_588 | 10k+ | refuted, lower |
| Bit set known unset, `+ 2^i` (`Bits::set`) | `bench_bit_set_add` | 345_420 | 363_000 | 2_033 | ~300 | refuted, higher |
| Bit set, limb OR (loser) | `bench_bit_set_or` | 627_780 | 660_000 | 4_857 |  |  |
| popcount SWAR, 180 bits set | `bench_popcount_swar_dense` | 2_045_920 | 2_149_000 | 19_038 |  |  |
| popcount per set bit, 180 bits set | `bench_popcount_sparse_dense` | 53_953_630 | 56_652_000 | 538_115 |  |  |
| popcount SWAR, 8 bits set | `bench_popcount_swar_sparse` | 2_055_380 | 2_159_000 | 19_133 |  |  |
| popcount per set bit, 8 bits set | `bench_popcount_sparse_sparse` | 3_171_490 | 3_331_000 | 30_294 |  |  |
| Poseidon `HashState` (2 updates + finalize) | `bench_poseidon_hash_state` | 441_890 | 464_000 | 2_998 | 1.2-1.5k | refuted, higher |
| Poseidon, one `hades_permutation` (`Rng::mix`) | `bench_poseidon_hades` | 312_590 | 329_000 | 1_705 |  |  |
| Pool draw, constant bound (`Rng::draw`), refills amortised | `bench_rng_draw` | 560_713 | 589_000 | 4_186 | ~0.9k | refuted, higher |
| Pool draw `Rng::next_below(6)` | `bench_rng_next_below` | 597_713 | 628_000 | 4_556 | ~0.9k | refuted, higher |
| `Rng::shuffle6` (one draw + table), refills amortised | `bench_rng_shuffle6` | 738_830 | 776_000 | 5_967 |  |  |
| shuffle6: DivRem 720 + table (winner) | `bench_shuffle6_table` | 498_670 | 524_000 | 3_566 |  |  |
| shuffle6: Fisher-Yates, 5 draws (loser) | `bench_shuffle6_fisher_yates` | 11_459_660 | 12_033_000 | 113_176 |  |  |
| `Felt252Dict` insert (incl. squash share) | `bench_dict_insert` | 695_100 | 730_000 | 5_530 | 2-4k | confirmed |
| `Felt252Dict` get (incl. squash share) | `bench_dict_insert_get` | 984_390 | 1_034_000 | 2_893 | 2-4k | refuted, lower |
| `Array` append | `bench_array_build` | 291_480 | 307_000 | 223 | 200-400 | confirmed |
| `span.at` | `bench_array_span_at` | 388_680 | 409_000 | 972 | 200-400 | refuted, higher |
| `Layout::new` (17x14) | `bench_layout_new` | 871_490 | 916_000 | 7_294 | 1-2k per mask |  |
| `Layout::interior` (17x14) | `bench_layout_interior` | 496_490 | 522_000 | 3_544 | 1-2k | refuted, higher |
| **`expand` (a) felt shifts, border invariant (winner)**, 17x14 | `bench_expand_felt` | 2_077_410 | 2_182_000 | 19_353 |  |  |
| `expand` (a') West shift via felt conversion | `bench_expand_felt_double` | 2_162_810 | 2_271_000 | 20_207 |  |  |
| `expand` (a'') vertical from parity-selected pairs | `bench_expand_felt_vertical` | 2_363_410 | 2_482_000 | 22_213 |  |  |
| `expand` (b) u256 shifts + row/column masks, no invariant | `bench_expand_masks` | 6_547_600 | 6_875_000 | 64_055 | ~3x (a) | confirmed (3.3x) |
| `expand` (c) per-limb u128 set operations | `bench_expand_limbs` | 2_162_810 | 2_271_000 | 20_207 |  |  |
| `expand` (a) on 7x7 | `bench_expand_felt_7x7` | 1_820_930 | 1_912_000 | 16_788 |  |  |
| **`expand_small` (c') single u128 limb, W*H <= 128 (winner)**, 7x7 | `bench_expand_small_7x7` | 953_680 | 1_002_000 | 8_116 |  |  |
| `expand_small` with the West shift via felt | `bench_expand_small_felt_double_7x7` | 1_277_080 | 1_341_000 | 11_350 |  |  |
| BFS layer step: `expand & U`, `U - F'` (winner) | `bench_step_or` | 2_239_260 | 2_352_000 | 20_972 | 15-20k | confirmed (upper end) |
| BFS layer step, sequential AND-and-subtract per direction | `bench_step_sequential` | 5_806_270 | 6_097_000 | 56_642 |  |  |
| `neighbour_mask`: 1 lookup x field multiplier (winner) | `bench_neighbour_mask` | 726_670 | 764_000 | 5_846 |  |  |
| `neighbour_mask`: 6 lookups (loser) | `bench_neighbour_mask_lookups` | 1_507_200 | 1_583_000 | 13_651 |  |  |
| `neighbor` (bounds-checked, one direction) | `bench_neighbor` | 781_230 | 821_000 | 6_391 |  |  |
| `coords` (one u8 DivRem) | `bench_coords` | 251_880 | 265_000 | 1_098 | ~0.5k | refuted, higher |
| `distance`: two DivRem by W + `/2` (winner) | `bench_distance` | 1_088_280 | 1_143_000 | 9_462 | 2-3k | refuted, higher |
| `distance`: one DivRem by 2W per position (loser) | `bench_distance_split` | 1_477_500 | 1_552_000 | 13_354 |  |  |

### Design assumptions (study sections 2.3 and 10)

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | Per-operation costs of section 2.3 | **Changed**: the ordering holds, the absolute values do not. Set operations cost ~2x the estimate (u128 `&` 1.7k, u256 `&`/`\|` 2.7k), a wide felt -> u256 conversion 1.8k, a table lookup 1.3k, a u8/u128 DivRem 1.1k/1.6k, a pool draw 4.2k (not 0.9k), Poseidon `HashState` 3.0k (one bare permutation 1.7k). Felt shifts stay nearly free (mul 0.1k, product by an inverse from the table 1.5k with the lookup). | table above |
| 1a | Rule 1: shift in felt, never shift a u256 | **Confirmed**: u256 mul by 2^k 14.0k, u256 div 6.3k, felt product 0.1k. | `bench_u256_mul_pow`, `bench_u256_div_pow`, `bench_felt_mul` |
| 1b | Rule 2: replace AND/OR by arithmetic when disjointness is known | **Confirmed**: `+ 2^i` 2.0k vs limb OR 4.9k; BFS layer with one final AND 21.0k vs AND-and-subtract per direction 56.6k. | `bench_bit_set_*`, `bench_step_*` |
| 1c | Rule 4: bit test by single-limb AND | **Confirmed**: 4.9k vs 17.6k for two u256 divisions (`origami_map`). | `bench_bit_test_*` |
| 1d | Rule 5: pooled draws beat a Poseidon per draw | **Confirmed**, smaller margin: 4.2k per draw (compare 1.1k + DivRem 1.6k + refill amortised) vs 1.7k-3.0k for the hash alone plus a u256 modulo. `shuffle6` as one draw of 720 + a table: 3.6k vs 113k for a Fisher-Yates. | `bench_rng_*`, `bench_shuffle6_*` |
| 1e | Rule 6: no `Felt252Dict` for sets | **Confirmed**: insert 5.5k, get 2.9k, vs 2.0k to set and 4.9k to test a bitmap bit. | `bench_dict_*` |
| 1f | Per BFS layer ~15-20k | **Confirmed (upper end)**: `expand & U` plus `U - F'` = 21.0k on 17x14; 8.1k + AND on boards of at most 128 bits with `expand_small`. | `bench_step_or`, `bench_expand_small_7x7` |
| 4 | Felt shifts are exact under the border invariant for all `W*H <= 251` | **Confirmed**: `expand` equals the u256-mask reference, which equals a scalar walk of `neighbor`, on all 10 fixtures, on 24 random interior frontiers and on every single interior tile, for 3x3, 7x7, 17x14, 19x13, 25x10, 83x3 and 3x83. The (a) felt form costs 19.4k vs 64.1k for (b) u256 shifts with masks: **3.3x cheaper**, so the invariant is justified. | `tests/properties.cairo`, `bench_expand_*` |
| 5 | Radius-6 hexagon: 15x15 or 16x15 | **15x15 (225 bits), whatever the centre-row parity**. Rows at distance `r` from the centre hold `2R + 1 - r` tiles within the columns of the centre row, so the width is `2R + 3` with the wall ring. `LayoutTrait::hexagon(6)` holds 127 tiles, all interior, exactly the tiles at distance <= 6 from the centre. R = 7 needs 17x17 = 289 bits. | `test_properties_hexagon` |
| 6 | snforge `l2_gas` = Sierra gas; `[scripts] test = "snforge test"` honoured by `scarb test -p` | **Confirmed in the harness**: `l2_gas` equals `sierra gas` on every test, and `scarb test -p origami_hexmap` runs snforge in this workspace (scarb 2.19.4). Equality with gas charged on-chain is not measurable locally; it follows from Sierra-gas metering (Sierra >= 1.7), and these library tests make no syscall. Caveat: the `available_gas` attribute shifts small tests by up to 1.4k. | CI and local runs |

### Library decisions from the measurements

* `LayoutTrait::expand` (felt shifts, 5 u256 set operations, 3 conversions): winner among (a),
  (a'), (a''), (b), (c).
* `LayoutTrait::expand_small`, kept in the library: on boards of at most 128 bits it costs 8.1k vs
  16.8k for `expand` (-52 %).
* `Bits::shr_exact` multiplies by an inverse from a table (1.5k) instead of calling
  `felt252_div` (2.0k).
* `Bits::pow` keeps the constant table (`span.at`). The 252-arm `match` is 13 gas cheaper per
  lookup (-1 %), but it compiles to a 252-entry jump table in every caller. The gain does not pay
  for the code size.
* `Bits::popcount` is the SWAR form (19.0k whatever the density). `popcount_sparse` (one AND per set
  bit: ~3.0k per bit plus ~6k) wins only with at most 4 set bits.
* `GeometryTrait::distance` uses two divisions by `W` (9.5k), not one division by `2W` (13.4k).
* `Rng::mix` is one `hades_permutation` (Starknet `poseidon_hash(x, y)`), 1.7k, instead of a
  `HashState` (3.0k).
* `Rng::shuffle6`: one draw of 720 and a table lookup.
* `neighbour_mask`: `2^i * M_parity`, where `M` is the field sum of the 6 relative offsets
  (5.8k vs 13.7k for 6 lookups).

## L1 Bit-BFS

_To be filled by lot L1._

## L2 A* baseline

_To be filled by lot L2._

## L3 Dial

_To be filled by lot L3._

## L4 Caver

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), budgets set by the procedure above.
Tests in `src/tests/bench_caver.cairo`. Every variant is checked against a scalar reference
automaton (`reference`) on 3x3 to 83x3 boards.

### Library

| Test | Measured | Budget | Note |
|---|---:|---:|---|
| `bench_caver_generate_17x14_order_0` | 27_157 | 29_000 | initial fill only (early return) |
| `bench_caver_generate_17x14_order_1` | 75_727 | 80_000 | + `Layout::new` and 1 generation |
| **`bench_caver_generate_17x14_order_3`** | **146_747** | 155_000 | target < 250k |
| `bench_caver_generate_17x14_order_5` | 218_567 | 230_000 | |
| `bench_caver_generate_19x13_order_3` | 147_247 | 155_000 | |
| `bench_caver_generate_7x7_order_0` | 27_157 | 29_000 | |
| `bench_caver_generate_7x7_order_1` | 53_967 | 57_000 | single-limb path |
| `bench_caver_generate_7x7_order_3` | 86_027 | 91_000 | single-limb path |
| `bench_caver_keep_component_17x14` | 300_925 | 316_000 | cave of `generate(17, 14, 3, 'CAVER')` |
| `bench_caver_keep_component_maze_17x14` | 1_245_367 | 1_308_000 | `MAZE_17X14` fixture |
| `bench_caver_keep_component_serpentine_17x14` | 2_080_829 | 2_185_000 | `SERPENTINE_17X14` fixture |
| `bench_caver_generate_connected_17x14` | 432_232 | 454_000 | `generate` + `keep_component` |

* **One generation, 17x14: 35_710** (`(order_5 - order_1) / 4`), target < 60k. The first
  generation also pays `Layout::new` (about 12.9k with the shift constants and the conversion).
* **One generation, boards <= 128 bits: 16_030** (`(7x7 order_3 - order_1) / 2`).
* Cost of a generation: 10 applications of the bitwise builtin per limb (1 parity split + 9 for the
  adder and the rule), 6 felt -> `u256` conversions (one per neighbour plane), and a few field
  products. The conversions (~1.8k each) are the second cost after the builtin.
* `origami_map` for the record: `Caver::generate(18, 14, 2, seed)` costs about 85_000_000
  (`scarb test -p origami_map -f caver`, cairo-test estimate), about 580x the hex version with one
  more generation.

### Variants (3 generations on the same 17x14 fill, harness baseline 33_740)

Per generation = `(test - bench_caver_variant_baseline_17x14) / 3`. The harness works on `u256`
values, so its library figure (38.8k) is 3k above the library itself; differences below ~0.6k per
generation are within code-layout noise (the same network moved between two helpers moved the total
by 1.8k).

| Variant | Test | Measured | Budget | Per generation | vs library |
|---|---|---:|---:|---:|---:|
| **Library**: parity-free planes, carry-save full count, triple builtin per limb | `bench_caver_variant_library_17x14` | 150_090 | 158_000 | 38_783 | |
| Final stage "at least 2 of `c1, c2, c3, grid`" (same builtin count) | `bench_caver_variant_two_of_four_17x14` | 152_490 | 161_000 | 39_583 | +2.1 % |
| Full count with the last carry folded into the result | `bench_caver_variant_folded_17x14` | 152_490 | 161_000 | 39_583 | +2.1 % |
| Design planes: 4 vertical planes all from the parity halves | `bench_caver_variant_split_planes_17x14` | 151_290 | 159_000 | 39_183 | +1.0 % |
| East plane doubled limb by limb (`overflowing_add`) instead of converted | `bench_caver_variant_east_add_17x14` | 154_770 | 163_000 | 40_343 | +4.0 % |
| Planes from shared sub-terms (`G & G/2`, `G ^ G/2` pairs, like `expand`) | `bench_caver_variant_pairs_17x14` | 162_444 | 171_000 | 42_901 | +10.6 % |
| Same network with corelib `u256` `&`, `^`, `\|` (one application per operator) | `bench_caver_variant_u256_ops_17x14` | 184_512 | 194_000 | 50_257 | +29.6 % |
| Design network (section 2.4): AND-only adders, XOR by field arithmetic, back to `u256` | `bench_caver_variant_design_17x14` | 203_898 | 215_000 | 56_719 | +46.2 % |
| Rule B4/S3 | `bench_caver_variant_b4s3_17x14` | 158_788 | 167_000 | 41_683 | +7.5 % |
| Rule B3/S3 (needs the interior mask) | `bench_caver_variant_b3s3_17x14` | 156_988 | 165_000 | 41_083 | +5.9 % |
| u256 path on 7x7 (baseline `bench_caver_variant_baseline_7x7` 33_050) | `bench_caver_variant_library_u256_7x7` | 152_200 | 160_000 | 39_717 | small path 16_030: -60 % |

Initial fills (17x14, whole test): `bench_caver_fill_half_17x14` 28_097 (budget 30_000, one
permutation output, ~50 %), `bench_caver_fill_sparse_17x14` and `bench_caver_fill_dense_17x14`
31_973 (budget 34_000, AND / OR of two outputs of the same permutation, ~25 % / ~75 %).

Connectivity: flood fill with a run fill after each dilation (`open & ~(open + C)` completes each
reached run toward West by carry propagation):

| Test | Measured | Budget | vs `expand` only |
|---|---:|---:|---:|
| `bench_caver_keep_component_runs_17x14` | 376_836 | 396_000 | +25 % |
| `bench_caver_keep_component_runs_first_17x14` | 380_626 | 400_000 | +26 % |
| `bench_caver_keep_component_runs_maze_17x14` | 1_445_492 | 1_518_000 | +16 % |
| `bench_caver_keep_component_runs_serpentine_17x14` | 1_504_878 | 1_581_000 | -28 % |

### Decisions

* Rule **B4/S2** (born with 4+ floor neighbours, survive with 2+), fill **~50 %**. On 32 seeds
  (17x14, `test_bench_caver_print_stats`): B4/S2 gives 61 % floor at order 3, 1.8 components, 92 %
  of the floor in the largest component, never empty. B4/S3 gives 37 % floor, 81 % in the largest
  component and 3 maps in 32 under 20 % floor. B3/S3 keeps growing (70 % at order 3, 78 % at
  order 5): open fields, not caves. A 25 % fill dies out, a 75 % fill fills the board.
* Carry-save count with the bitwise builtin called directly: one application yields AND, XOR and
  OR, so a full adder is 2 applications and carries are additions of disjoint bitmaps.
* Born tiles need no interior mask: a border tile has at most 3 interior neighbours.
* `u128` single-limb path for boards of at most 128 bits (-60 % per generation).
* `keep_component` stays a separate function: it costs about twice `generate(17, 14, 3)`.

## L5 Mazer and Digger

_To be filled by lot L5._

## L6 Walker

_To be filled by lot L6._

## L7 Spreader

_To be filled by lot L7._

## L8 Facade

_To be filled by lot L8._

## S1 u252

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas). Library: `types/u252.cairo`, benchmarks
and losing variants: `tests/bench_u252.cairo`.

### Representation

`u252` is `struct { value: felt252 }` with the value set `[0, P - 1]`
(`P = 2^251 + 17 * 2^192 + 1`): every felt is a valid `u252`, so `Into<felt252, u252>`,
`Into<u252, felt252>`, `Serde` and `StorePacking<u252, felt252>` are identities with no check and
no invariant to re-establish. The checked operations panic exactly when the true integer result
leaves `[0, P - 1]` (property tests against `u256` on the edges 0, 1, 2^128 - 1, 2^128, 2^251,
P - 1, P - 2 and 36 pseudo-random wide and narrow values, all pairs).

Candidates refused or not viable (scarb 2.19.4):

| Candidate | Result |
|---|---|
| `BoundedInt<0, 2^252 - 1>` or any `MAX >= P` | Refused: `E2008 The value does not fit within the range of type core::felt252` (2^252 - 1 > P). A felt cannot hold 2^252 - 1 either. |
| `BoundedInt<0, 2^251 - 1>` + `AddHelper` (result `<0, 2^252 - 2>`) | Refused: `E2008` (result max > P). |
| `SubHelper` on it (result `<-(2^251 - 1), 2^251 - 1>`) | Compiler panic: `Could not specialize type BoundedInt<-..., ...>` (range size >= P). |
| `bounded_int_div_rem<BoundedInt<0, 2^251 - 1>, BoundedInt<1, 255>>` | Refused: `Could not specialize libfunc bounded_int_div_rem ... unsupported` (quotient must be < 2^128). |
| `bounded_int_constrain` at 2^128 | Refused: both halves must span at most 2^128 values. |
| `downcast<felt252, BoundedInt<0, 2^251 - 1>>` | Refused: `downcast` only targets ranges of at most 2^128 values. |
| `BoundedInt<0, P - 1>` | Type accepted; `upcast` to `felt252` is free (identity), but `upcast<felt252, _>` is refused (the felt252 range is `(-P, P)`) and `downcast` too: it cannot be built from a felt, so it cannot carry the infallible `Into`. |
| `bounded_int_is_zero` | Usable only in corelib: its result type `IsZeroResult` is not visible outside. |
| Bitwise on a 252-bit word | No libfunc: `bitwise` exists only for `u8..u128`. |

Why the checks need two splits: the only sound range proof on a full-range felt is the
`felt252 -> u256` split (`u128s_from_felt252`: 1 range check below 2^128, 3 above, measured 820 and
1_611 per op). For `[0, P - 1]`, `a + b` and `a + b - P` are the same field element, so the sum
alone cannot reveal the overflow; with the split of one operand it can (`a + b` wraps iff the
field sum is below `a`). The same holds for `[0, 2^251 - 1]` (`2 * MAX > P`), which in addition
pays a split on every `TryInto<felt252>` (2_281).

### Results

Per op = (test - baseline) / 100, the baseline being the test that builds the same operands.

| Operation | Test | Measured | Budget | Per op |
|---|---|---:|---:|---:|
| _Baselines_ | | | | |
| Loop only | `bench_u252_baseline_loop` | 141_990 | 150_000 |  |
| Two wide felts `fa(n)`, `fb(n)` | `bench_u252_baseline_felt` | 211_290 | 222_000 |  |
| One wide felt `fc(n)` | `bench_u252_baseline_shift` | 171_690 | 181_000 |  |
| One narrow felt | `bench_u252_baseline_narrow` | 161_790 | 170_000 |  |
| Two `u256` (both limbs vary) | `bench_u252_baseline_u256` | 338_010 | 355_000 |  |
| One `u256` | `bench_u252_baseline_shift_u256` | 235_050 | 247_000 |  |
| Two `u128` | `bench_u252_baseline_u128` | 244_950 | 258_000 |  |
| One `u128` | `bench_u252_baseline_u128_one` | 188_520 | 198_000 |  |
| _Checked add_ | | | | |
| `u256 +` | `bench_u252_add_u256` | 523_140 | 550_000 | 1_851 |
| `u128 +` | `bench_u252_add_u128` | 271_680 | 286_000 | 267 |
| `felt252 +` (unchecked) | `bench_u252_add_felt` | 211_290 | 222_000 | 0 |
| **`u252 +`: `split(a + b) >= split(a)` (winner)** | `bench_u252_add` | 633_490 | 666_000 | 4_222 |
| `u252 +`, narrow operands | `bench_u252_add_narrow` | 460_490 | 484_000 | 2_987 |
| `u252 +` via `split(a) + split(b) < P` (loser) | `bench_u252_add_via_sum` | 848_490 | 891_000 | 6_372 |
| `[0, 2^251 - 1]` add (two splits, high limb < 2^123) | `bench_u251_add` | 818_490 | 860_000 | 6_072 |
| _Checked sub_ | | | | |
| `u256 -` | `bench_u252_sub_u256` | 531_060 | 558_000 | 1_930 |
| `u128 -` | `bench_u252_sub_u128` | 271_680 | 286_000 | 267 |
| **`u252 -`: `split(a - b) <= split(a)` (winner)** | `bench_u252_sub` | 633_490 | 666_000 | 4_222 |
| `u252 -` via `split(a) >= split(b)` (loser) | `bench_u252_sub_via_operands` | 653_490 | 687_000 | 4_422 |
| `[0, 2^251 - 1]` sub | `bench_u251_sub` | 653_490 | 687_000 | 4_422 |
| _Wrapping add and sub_ | | | | |
| `u256` `wrapping_add` | `bench_u252_wrapping_add_u256` | 503_340 | 529_000 | 1_653 |
| `u128` `wrapping_add` | `bench_u252_wrapping_add_u128` | 322_170 | 339_000 | 772 |
| **`u252` `wrapping_add` (mod P, field add)** | `bench_u252_wrapping_add` | 211_290 | 222_000 | 0 |
| **`u252` `wrapping_sub` (mod P, field sub)** | `bench_u252_wrapping_sub` | 211_290 | 222_000 | 0 |
| _Left shift by 17 (checked)_ | | | | |
| `u256 * 2^17` | `bench_u252_shl_u256` | 1_631_300 | 1_713_000 | 13_962 |
| `felt252 * 2^17` (`Bits::shl`, unchecked) | `bench_u252_shl_felt` | 318_690 | 335_000 | 1_470 |
| **`u252::shl`: low bits of the canonical product (winner)** | `bench_u252_shl` | 689_010 | 724_000 | 5_173 |
| `u252::shl` by 145 (high-limb branch), narrow operand | `bench_u252_shl_high` | 719_010 | 755_000 | 5_572 |
| `u252::shl`, low limb times `2^-k` cast to `u128` (loser) | `bench_u252_shl_inv_cast` | 729_490 | 766_000 | 5_578 |
| `u252::shl`, mask split to `u256` + two-limb AND (loser) | `bench_u252_shl_mask_u256` | 872_510 | 917_000 | 7_008 |
| `u252::shl` via `u256` overflowing product (loser) | `bench_u252_shl_via_u256` | 2_067_490 | 2_171_000 | 18_958 |
| _Right shift by 17 (the exact tests include one felt mul, 98)_ | | | | |
| `u256 / 2^17` (floor) | `bench_u252_shr_u256` | 870_050 | 914_000 | 6_350 |
| `felt252 * 2^-17` (`Bits::shr_exact`, unchecked) | `bench_u252_shr_exact_felt` | 328_590 | 346_000 | 1_569 |
| **`u252::shr_exact`: low limb times `2^-k` cast to `u128` (winner)** | `bench_u252_shr_exact` | 602_490 | 633_000 | 4_308 |
| `u252::shr_exact`, mask cast + limb AND (loser) | `bench_u252_shr_exact_and` | 836_010 | 878_000 | 6_643 |
| **`u252::shr` (floor): dropped bits by limb AND, exact field division** | `bench_u252_shr` | 826_010 | 868_000 | 6_543 |
| _DivRem by 7_ | | | | |
| `u256` DivRem | `bench_u252_divrem_u256` | 879_950 | 924_000 | 6_449 |
| `u128` DivRem | `bench_u252_divrem_u128` | 344_940 | 363_000 | 1_564 |
| **`u252::div_rem`: split + `u256` DivRem (winner)** | `bench_u252_divrem` | 1_038_490 | 1_091_000 | 8_668 |
| `u252::div_rem`: 4 `u128` DivRem + `felt252_div` (loser) | `bench_u252_divrem_felt` | 1_287_490 | 1_352_000 | 11_158 |
| _Checked mul (wide x small)_ | | | | |
| `u256 *` | `bench_u252_mul_u256` | 1_738_220 | 1_826_000 | 14_002 |
| `felt252 *` (unchecked) | `bench_u252_mul_felt` | 238_020 | 250_000 | 267 |
| **`u252 *`: two `u128` wide products (winner)** | `bench_u252_mul` | 1_302_490 | 1_368_000 | 10_912 |
| `u252 *`, narrow x narrow | `bench_u252_mul_narrow` | 1_156_490 | 1_215_000 | 9_947 |
| `u252 *` via `u256` overflowing product (loser) | `bench_u252_mul_u256_product` | 1_986_020 | 2_086_000 | 17_747 |
| _Comparisons_ | | | | |
| `u256 ==` | `bench_u252_eq_u256` | 420_180 | 442_000 | 822 |
| `felt252 ==` | `bench_u252_eq_felt` | 240_990 | 254_000 | 297 |
| **`u252 ==`** | `bench_u252_eq` | 240_990 | 254_000 | 297 |
| `u256 <` | `bench_u252_lt_u256` | 427_110 | 449_000 | 891 |
| `u128 <` | `bench_u252_lt_u128` | 321_180 | 338_000 | 762 |
| **`u252 <`: two splits + `u256 <` (winner)** | `bench_u252_lt` | 644_490 | 677_000 | 4_332 |
| `u252 <`, narrow operands | `bench_u252_lt_narrow` | 520_400 | 547_000 | 3_586 |
| `u252 <`, limbs compared by hand (loser) | `bench_u252_lt_manual` | 661_490 | 695_000 | 4_502 |
| `[0, 2^251 - 1]` `<` | `bench_u251_lt` | 644_490 | 677_000 | 4_332 |
| **`u252 <=`** | `bench_u252_le` | 664_490 | 698_000 | 4_532 |
| `felt252 == 0` | `bench_u252_is_zero_felt` | 201_390 | 212_000 | 297 |
| **`u252::is_zero`** | `bench_u252_is_zero` | 201_390 | 212_000 | 297 |
| _Bitwise_ | | | | |
| `u128 &` | `bench_u252_and_u128` | 394_850 | 415_000 | 1_499 |
| `u256 &` | `bench_u252_and_u256` | 576_610 | 606_000 | 2_386 |
| `u256 \|` | `bench_u252_or_u256` | 576_610 | 606_000 | 2_386 |
| `u256 ^` | `bench_u252_xor_u256` | 576_610 | 606_000 | 2_386 |
| **`u252 &`** (two splits, join) | `bench_u252_and` | 821_690 | 863_000 | 6_104 |
| **`u252 \|`** (two splits, `< P` check, join) | `bench_u252_or` | 911_510 | 958_000 | 7_002 |
| **`u252 ^`** (two splits, `< P` check, join) | `bench_u252_xor` | 911_510 | 958_000 | 7_002 |
| Bit test, `u256` (`Bits::get`) | `bench_u252_bit_test_u256` | 776_540 | 816_000 | 5_415 |
| **Bit test, `u252::bit`** (split + `Bits::get`) | `bench_u252_bit_test` | 884_080 | 929_000 | 7_124 |
| Bit set known unset, felt `+ 2^i` (`Bits::set`) | `bench_u252_bit_set_felt` | 421_650 | 443_000 | 2_500 |
| **Bit set, `u252::set_bit`** (split, limb test, `< P` check) | `bench_u252_bit_set` | 929_060 | 976_000 | 7_574 |
| _Conversions, Serde, storage_ | | | | |
| **`felt252 -> u252` and back (`Into`, both ways)** | `bench_u252_from_felt` | 171_690 | 181_000 | 0 |
| `u252 -> u256` (`Into`), wide | `bench_u252_to_u256` | 332_790 | 350_000 | 1_611 |
| `u252 -> u256` (`Into`), narrow | `bench_u252_to_u256_narrow` | 243_740 | 256_000 | 820 |
| `u256 -> u252` (`TryInto`, `< P`) | `bench_u252_from_u256` | 340_980 | 359_000 | 1_059 |
| `u128 -> u252` (`Into`) | `bench_u252_from_u128` | 188_520 | 198_000 | 0 |
| `u252 -> u128` (`TryInto`) | `bench_u252_to_u128` | 188_890 | 199_000 | 271 |
| `u8 -> u252` (`Into`, the test adds 1) | `bench_u252_from_u8` | 151_890 | 160_000 | 99 |
| `u252 -> u8` (`TryInto`, the test adds 1) | `bench_u252_to_u8` | 205_350 | 216_000 | 634 |
| `felt252 -> [0, 2^251 - 1]` (`TryInto`: split + high < 2^123) | `bench_u251_from_felt` | 399_790 | 420_000 | 2_281 |
| `u256` Serde round trip | `bench_u252_serde_u256` | 439_050 | 462_000 | 2_040 |
| **`u252` Serde round trip (no range check)** | `bench_u252_serde` | 231_790 | 244_000 | 601 |
| **`u252` `StorePacking` round trip** | `bench_u252_store_packing` | 171_690 | 181_000 | 0 |
| _`Layout::expand` and BFS layer step, 17x14 (per op = (test - loop) / 100)_ | | | | |
| `expand` on `u256` (library) | `bench_u252_expand_u256` | 2_077_410 | 2_182_000 | 19_354 |
| `expand` on `u252` (bench copy) | `bench_u252_expand` | 2_246_500 | 2_359_000 | 21_045 |
| BFS step on `u256`: `expand & U`, `U - F'` (library) | `bench_u252_step_u256` | 2_239_260 | 2_352_000 | 20_973 |
| BFS step on `u252`: `u252 &`, `wrapping_sub` | `bench_u252_step` | 2_404_340 | 2_525_000 | 22_624 |
| BFS step on `u252`, fused: one split of `U`, one join | `bench_u252_step_fused` | 2_292_340 | 2_407_000 | 21_504 |

### Verdict

* **Where `u252` removes the `u256` overhead**: everything that stays a field operation.
  `Into` both ways, `StorePacking` and `wrapping_add`/`wrapping_sub` (modulo P) cost 0 (`u256`:
  1.6k for a wrapping add); `==` and `is_zero` 0.3k (`u256 ==`: 0.8k); `Serde` 0.6k (`u256`:
  2.0k); unchecked shifts stay felt products (1.5k with the table lookup, `u256 * 2^17`: 14.0k).
  Checked left shift 5.2k and checked mul 10.9k beat `u256` (14.0k both); checked exact right shift
  4.3k beats the `u256` division (6.4k).
* **Where it cannot**: every operation that needs the integer order or the bits pays one
  `felt252 -> u256` split per operand (0.8k narrow, 1.6k wide). Checked add/sub 4.2k vs 1.9k,
  `<` 4.3k vs 0.9k, `&` 6.1k and `|`/`^` 7.0k vs 2.4k, bit test 7.1k vs 5.4k, DivRem 8.7k vs 6.4k,
  floor right shift 6.5k vs 6.4k. No libfunc offers a cheaper range proof or a wider bitwise.
* **Cost of the infallible `Into`**: nothing for the conversions themselves; compared with a
  `[0, 2^251 - 1]` type the checked add is even cheaper (4.2k vs 6.1k: the overflow test is one
  comparison with an operand, instead of a sum of two splits), sub and `<` are equal, and the
  2^251 type pays 2.3k on every `TryInto<felt252>` and `Serde` read.
* **Bitmaps**: `expand` on `u252` costs 21.0k vs 19.4k (+9 %) and the BFS layer 22.6k vs 21.0k
  (+8 %), 21.5k (+2.5 %) when fused. The set operations stay `u256` inside `expand`; a `u252`
  frontier only adds a split and a join. `expand_small` (8.1k on 7x7, one `u128` limb) is out of
  reach of any 252-bit form. `helpers/bits.cairo` and `helpers/layout.cairo` stay on `u256`
  with felt shifts; `u252` is worth using for counters, storage and APIs that convert to and from
  `felt252`, not for the set algebra.
