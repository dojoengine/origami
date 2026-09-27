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

_To be filled by lot L4._

## L5 Mazer and Digger

_To be filled by lot L5._

## L6 Walker

_To be filled by lot L6._

## L7 Spreader

_To be filled by lot L7._

## L8 Facade

_To be filled by lot L8._
