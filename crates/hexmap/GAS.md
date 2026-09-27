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

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), commit `3afa4ec`. Per step =
`(test - bench_walker_17x14_0) / steps`, where the 0-step test (36.5k) covers the dimension check,
the start tile (two `Rng::next_below`) and the constants.

### Library (`Walker::generate`)

| Test | Measured | Budget | Per step |
|---|---:|---:|---:|
| `bench_walker_17x14_0` | 36_481 | 39_000 | |
| `bench_walker_17x14_50` | 301_845 | 317_000 | 5_307 |
| `bench_walker_17x14_200` | 1_001_849 | 1_052_000 | 4_827 |
| `bench_walker_17x14_500` | 2_467_497 | 2_591_000 | 4_862 |
| `bench_walker_17x14_504` | 2_462_993 | 2_587_000 | 4_815 |
| `bench_walker_7x7_50` | 302_475 | 318_000 | |
| `bench_walker_7x7_200` | 995_139 | 1_045_000 | |
| `bench_walker_19x13_200` | 1_008_929 | 1_060_000 | |
| `bench_walker_3x3_50` (every move blocked) | 305_375 | 321_000 | |

Target (< 6k per step on 17x14): met, 4.8k-5.3k. Reference: `origami_map`'s
`test_walker_generate` (18x14, 500 steps, 4 directions, recursive) reports 29_937_342
(`scarb test -p origami_map -f walker`, cairo-test estimate), about 59.9k per step: 12x more.

Winner:

* **Random source**: one pool division by 216 per three moves, the three base-6 digits read from
  a 216-arm table (`match` on the draw, compiled to a jump table). The table is **not inlined**
  (one copy, one call per three moves). The pool is refilled by a counter every 12 draws
  (216^12 < 2^96, the pool stays above 2^32 like `Rng`): no `pool < 2^32` comparison per draw.
* **Move**: doubled column `c = 2x + (y & 1)`, row `y` and one-hot position `2^i`, all felts. Every
  move shifts `c` by a constant (E -2, W +2, NE/SE -1, NW/SW +1), so every bound test is one or two
  felt equalities with no parity branch. The diagonal factors depend on the row parity: the state
  carries the NorthEast factor of the current row parity and of the other one, swapped on every
  vertical move (a rename). A move is one field product.
* **Grid**: the positions of three moves are summed, each once: only the first and the third
  position can coincide (the second is a neighbour of both, a blocked move adds nothing), so one
  felt equality suffices. The sum is ORed into a `u256` grid once per three moves (one conversion,
  one `u256` OR), and the grid is converted to a felt once at the end.
* **Loop**: 18 moves (6 draws) per iteration, two iterations per pool refill, the rest (< 18
  moves) in a tail loop of draws.

### Variants (losers, test-only in `bench_walker.cairo`)

Each variant changes one axis of the winner, 17x14, 504 steps (no tail). They run in a generic
harness (`Mover` trait, the constants ride in the walker struct), so they are compared with the
harness copy of the winner (`bench_walker_variant_winner`, 2_657_173), which costs 7.9 % more
than the library. Variants on the same draws assert the library grid.

| Axis | Variant | Test | Measured | Budget | Per step | vs winner |
|---|---|---|---:|---:|---:|---:|
| | **Winner (harness copy)** | `bench_walker_variant_winner` | 2_657_173 | 2_791_000 | 5_272 | |
| Random | `Rng::next_below(6)` per move | `bench_walker_variant_random_next_below` | 3_916_609 | 4_113_000 | 7_771 | +47.4 % |
| Random | 3-bit digits, rejection of 6 and 7 | `bench_walker_variant_random_octal` | 6_367_516 | 6_686_000 | 12_634 | +139.6 % |
| Random | one draw in `0..36` per two moves (36-arm table) | `bench_walker_variant_random_pairs` | 2_855_509 | 2_999_000 | 5_666 | +7.5 % |
| Move | `(x, y)` incremental, parity bool, per-parity deltas | `bench_walker_variant_move_coords` | 2_706_793 | 2_843_000 | 5_371 | +1.9 % |
| Move | index arithmetic (`DirectionTrait::next`), test `2^i & INTERIOR` | `bench_walker_variant_move_index_mask` | 5_951_005 | 6_249_000 | 11_808 | +124.0 % |
| Move | one-hot, per-parity offset table, interior test = one AND | `bench_walker_variant_move_one_hot_and` | 4_554_917 | 4_783_000 | 9_038 | +71.4 % |
| Grid | OR each step into a `u256`, one conversion at the end | `bench_walker_variant_grid_or_each` | 3_613_075 | 3_794_000 | 7_169 | +36.0 % |
| Grid | OR each step on a felt grid (`u256` round trip) | `bench_walker_variant_grid_or_felt` | 4_466_515 | 4_690_000 | 8_862 | +68.1 % |
| Grid | bit test, add only when unset | `bench_walker_variant_grid_test_add` | 4_516_955 | 4_743_000 | 8_962 | +70.0 % |
| Grid | batch of three, low-limb OR when the batch fits | `bench_walker_variant_grid_limb` | 2_757_218 | 2_896_000 | 5_471 | +3.8 % |
| Loop | 3 moves per iteration | `bench_walker_variant_loop_3` | 3_446_273 | 3_619_000 | 6_838 | +29.7 % |
| Loop | 6 moves per iteration | `bench_walker_variant_loop_6` | 2_972_813 | 3_122_000 | 5_898 | +11.9 % |
| Loop | 12 moves per iteration | `bench_walker_variant_loop_12` | 2_736_083 | 2_873_000 | 5_429 | +3.0 % |
| Loop | 36 moves per iteration (one pool) | `bench_walker_variant_loop_36` | 2_578_173 | 2_708_000 | 5_115 | -3.0 % |
| Loop | 12 moves per iteration, table inlined | `bench_walker_variant_loop_12_inline` | 2_678_963 | 2_813_000 | 5_315 | +0.8 % |
| Loop | 36 moves per iteration, table inlined | `bench_walker_variant_loop_36_inline` | 2_521_053 | 2_648_000 | 5_002 | -5.1 % |
| All | naive: one move per iteration, `next_below`, `(x, y)`, OR each step | `bench_walker_variant_naive` | 6_892_587 | 7_238_000 | 13_676 | +159.4 % |

### Loop shape and code size

The faster loop shapes pay in code size. Library walker, 17x14, 500 steps, and Sierra statements
of the walker functions (`generate`, its loops, `triple`; from the test build):

| Moves per iteration | 216-arm table | Gas (500 steps) | Sierra statements |
|---:|---|---:|---:|
| 6 | inlined | 2_645_197 | not measured |
| 6 | call | 2_716_097 | 6_772 |
| 12 | inlined | 2_470_097 | ~22k |
| 12 | call | 2_526_977 | 8_706 |
| **18** | **call (library)** | **2_467_497** | **10_640** |
| 36 | call | 2_406_197 | 16_257 |
| 36 | inlined | 2_349_317 | ~50k |

Each inlined copy of the table is ~2k statements, and each inlined move ~480. The library keeps
18 moves with the table called: 2.4 % cheaper than 12 moves. The 36-move shape saves another
2.5 % for +53 % code, so it is not kept.

### Other measured ideas (library, 17x14, 500 steps, before -> after)

| Idea | Gas | Delta | Verdict |
|---|---|---:|---|
| First cut: `(x, y)` + parity bool, one `Rng::draw(36)` + u8 DivRem per two moves, OR per move on `u128` limbs, 2 moves per iteration | 4_895_373 | | |
| One draw of 216 per three moves (table), counter refill, 3 moves per iteration | 3_926_241 | -19.8 % | kept |
| Doubled column + swapped factors, batch of three with one `u256` OR | 3_036_627 | -22.7 % | kept |
| 6 moves per iteration | 2_645_197 | -12.9 % | kept |
| 12 moves per iteration (table inlined) | 2_470_097 | -6.6 % | superseded |
| 18 moves per iteration, table called (library) | 2_467_497 | -0.1 % | kept: same gas, 10.6k statements instead of 22k |
| Move as a value tuple (all targets computed, one merge) | 2_470_097 -> 2_646_397 | +7.1 % | rejected |
| `a == x \|\| b == y` bound tests as `(a - x) * (b - y) == 0` | 2_470_097 -> 2_473_147 | +0.1 % | rejected |
| East/West bound tests as two equalities instead of one product | 2_467_497 -> 2_468_247 | +0.03 % | rejected |
| Directions as `felt252` instead of `u8` | 2_467_497 -> 2_467_497 | 0 % | rejected (no change) |
| Batch of three, low-limb OR when the batch fits | 2_645_197 -> 2_753_022 | +4.1 % | rejected |
| `step` not inlined | 2_526_977 -> 3_614_097 | +43 % | rejected |
| Three moves (`walk3`) not inlined | 2_470_097 -> 2_959_777 | +20 % | rejected |
| `core::internal::bounded_int::div_rem` for the pool division | 1.94k -> 1.47k per division | -24 % | rejected: unstable feature (`bounded-int-utils`) |

The iteration stopped after two consecutive ideas below 2 % (East/West equalities, `felt252`
directions).

Per-component costs measured on the way (17x14): a loop iteration with a felt counter 1.2k,
`Rng::draw` 4.6k (u128 DivRem 1.9k, the rest is the `pool < 2^32` test and the struct), a move
2.3k and an OR per move 3.2k in the first cut.

## L7 Spreader

_To be filled by lot L7._

## L8 Facade

_To be filled by lot L8._
