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

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), budgets set by the procedure above.
Library: `finders/bfs.cairo`; benchmarks and losing variants: `tests/bench_bfs.cairo`. Every
variant asserts the fixture path length; the library is checked against a scalar queue BFS on
the fixtures, on caves and mazes of 7x7, 17x14 and 19x13, on 3x3, 8x16, 9x15, 25x10, 83x3 and
3x83 boards, and with open edge tiles (entrances, corners, adjacent edge tiles).

### Cost model (measured with `--tracked-resource cairo-steps`)

Sierra gas is close to `100 * steps + 70 * range checks + ~580 * bitwise applications`. Per
operation: a local `bitwise` application is 2 CASM steps plus the builtin (the corelib `&`, `|`
cost more around it); a wide `felt252 -> u256` conversion 14 steps and 3 range checks (~1.6k), a
narrow one (< 2^128) ~6 steps and 1 range check; a checked `u8` operation ~6 steps and 1 range
check; a loop iteration pays `withdraw_gas` and one store per carried value. Steps dominate: in
a 17x14 layer, the 4 wide conversions (doubling, NE/NW, SE/SW, East) are about half of the steps,
the 13 bitwise applications ~40 % of the gas.

* **Forward layer, 17x14: ~19.3k** (110 steps, 12.9 bitwise, 9.6 range checks): dilation with 10
  applications of the local `bitwise`, `& unvisited` (2), target test (1, single limb), 2 limb
  subtractions, the layer stored.
* **Backtracking step, 17x14: ~8.4k** (70 steps, 2.1 bitwise, 2.6 range checks; `search -
  distance` per path tile below).
* **Boards of at most 128 bits** (single limb): ~9.9k per layer, ~6.4k per backtracking step.
* **Fixed cost**: checks, constants, endpoints and hex distance ~55k (near searches, 3 tiles:
  102k-112k on 17x14, 78k-82k on 7x7).

### search

Targets on 17x14 (algorithm minus the 15_040 fixture baseline): EMPTY far 555_000 (target
500_000, +11 %), CAVE far 691_000 (650_000, +6 %), MAZE far 1_504_000 (1_400_000, +7 %),
SERPENTINE far 2_517_000 (2_400_000, +5 %): **not met**, see "Iterations" for what was tried.
UNREACHABLE (248_000 and 251_000) costs less than flooding the component (`reachable` 277_000,
`Caver::keep_component` 284_000): **met**.

| Test | Measured | Budget | Path length | Minus baseline |
|---|---:|---:|---:|---:|
| `bench_bfs_search_empty_near_17x14` | 107_285 | 113_000 | 3 | 92_245 |
| `bench_bfs_search_empty_far_17x14` | 570_033 | 599_000 | 19 | 554_993 |
| `bench_bfs_search_cave_near_17x14` | 112_141 | 118_000 | 3 | 97_101 |
| `bench_bfs_search_cave_far_17x14` | 706_135 | 742_000 | 24 | 691_095 |
| `bench_bfs_search_maze_near_17x14` | 102_815 | 108_000 | 3 | 87_775 |
| `bench_bfs_search_maze_far_17x14` | 1_519_526 | 1_596_000 | 53 | 1_504_486 |
| `bench_bfs_search_serpentine_near_17x14` | 102_295 | 108_000 | 3 | 87_255 |
| `bench_bfs_search_serpentine_far_17x14` | 2_532_090 | 2_659_000 | 90 | 2_517_050 |
| `bench_bfs_search_unreachable_near_17x14` | 266_118 | 280_000 | 0 | 251_078 |
| `bench_bfs_search_unreachable_far_17x14` | 263_320 | 277_000 | 0 | 248_280 |
| `bench_bfs_search_empty_near_7x7` | 82_241 | 87_000 | 3 | 67_201 |
| `bench_bfs_search_empty_far_7x7` | 131_733 | 139_000 | 6 | 116_693 |
| `bench_bfs_search_cave_near_7x7` | 81_521 | 86_000 | 3 | 66_481 |
| `bench_bfs_search_cave_far_7x7` | 131_733 | 139_000 | 6 | 116_693 |
| `bench_bfs_search_maze_near_7x7` | 78_204 | 83_000 | 3 | 63_164 |
| `bench_bfs_search_maze_far_7x7` | 239_984 | 252_000 | 13 | 224_944 |
| `bench_bfs_search_serpentine_near_7x7` | 80_361 | 85_000 | 3 | 65_321 |
| `bench_bfs_search_serpentine_far_7x7` | 257_269 | 271_000 | 14 | 242_229 |
| `bench_bfs_search_unreachable_near_7x7` | 67_873 | 72_000 | 0 | 52_833 |
| `bench_bfs_search_unreachable_far_7x7` | 89_843 | 95_000 | 0 | 74_803 |

`origami_map` for the record (`scarb test -p origami_map -f bfs`, cairo-test estimate): 4x4
medium 1_608_464 (path of 6), 5x4 maze 1_373_230; the hex 7x7 EMPTY far (path of 6, 49 tiles)
costs 131_733, 12x less on a board 3x larger.

### distance

`Bfs::distance` runs the same forward pass without storing the layers or backtracking.

| Test | Measured | Budget | search - distance (backtracking) |
|---|---:|---:|---:|
| `bench_bfs_distance_empty_far_17x14` | 407_159 | 428_000 | 162_874 |
| `bench_bfs_distance_cave_far_17x14` | 501_942 | 528_000 | 204_193 |
| `bench_bfs_distance_maze_far_17x14` | 1_058_347 | 1_112_000 | 461_179 |
| `bench_bfs_distance_serpentine_far_17x14` | 1_774_065 | 1_863_000 | 758_025 |
| `bench_bfs_distance_unreachable_far_17x14` | 259_880 | 273_000 | 3_440 |
| `bench_bfs_distance_empty_far_7x7` | 88_923 | 94_000 | 42_810 |
| `bench_bfs_distance_cave_far_7x7` | 88_923 | 94_000 | 42_810 |
| `bench_bfs_distance_maze_far_7x7` | 154_812 | 163_000 | 85_172 |
| `bench_bfs_distance_serpentine_far_7x7` | 167_851 | 177_000 | 89_418 |
| `bench_bfs_distance_unreachable_far_7x7` | 87_603 | 92_000 | 2_240 |

### reachable

`Bfs::reachable` (frontier flood: the same 12 bitwise applications per layer as
`expand(component) & open`, but on limbs with the local `bitwise`, the loop ending on an empty
frontier instead of a `u256` comparison, single limb on small boards) beats
`Caver::keep_component` on every input; it also adds the open edge tiles next to the component.

| Test | Measured | Budget | `Caver::keep_component` (same input) | Delta |
|---|---:|---:|---:|---:|
| `bench_bfs_reachable_cave_17x14` | 557_039 | 585_000 | 582_223 (budget 612_000) | -4.3 % |
| `bench_bfs_reachable_maze_17x14` | 1_154_583 | 1_213_000 | 1_245_367 (budget 1_308_000) | -7.3 % |
| `bench_bfs_reachable_serpentine_17x14` | 1_908_405 | 2_004_000 | 2_080_829 (budget 2_185_000) | -8.3 % |
| `bench_bfs_reachable_unreachable_17x14` | 276_581 | 291_000 | 283_755 (budget 298_000) | -2.5 % |
| `bench_bfs_reachable_cave_7x7` | 104_253 | 110_000 | 170_115 (budget 179_000) | -38.7 % |
| `bench_bfs_reachable_maze_7x7` | 175_079 | 184_000 | 310_087 (budget 326_000) | -43.5 % |
| `bench_bfs_reachable_serpentine_7x7` | 185_197 | 195_000 | 330_083 (budget 347_000) | -43.9 % |
| `bench_bfs_reachable_unreachable_7x7` | 84_017 | 89_000 | 130_123 (budget 137_000) | -35.4 % |

### tiles_within_range

| Test | Measured | Budget |
|---|---:|---:|
| `bench_bfs_range_3_empty_17x14` | 91_617 | 97_000 |
| `bench_bfs_range_6_empty_17x14` | 159_255 | 168_000 |
| `bench_bfs_range_3_cave_17x14` | 84_507 | 89_000 |
| `bench_bfs_range_6_cave_17x14` | 145_825 | 154_000 |
| `bench_bfs_range_3_maze_17x14` | 90_627 | 96_000 |
| `bench_bfs_range_6_maze_17x14` | 149_575 | 158_000 |
| `bench_bfs_range_3_empty_7x7` | 62_061 | 66_000 |
| `bench_bfs_range_6_empty_7x7` | 92_415 | 98_000 |
| `bench_bfs_range_3_cave_7x7` | 62_061 | 66_000 |
| `bench_bfs_range_6_cave_7x7` | 92_415 | 98_000 |
| `bench_bfs_range_3_maze_7x7` | 62_061 | 66_000 |
| `bench_bfs_range_6_maze_7x7` | 92_415 | 98_000 |

### Variants: layer storage (library: `bench_bfs_search_*_far_17x14`)

`felt_layers`: layers stored as `felt252`, converted back before the backtracking (one wide
conversion per layer). `checkpoints`: only the pairs `L(4m), L(4m+1)` stored, `L(4m+2)` and
`L(4m+3)` rebuilt from them on the way back (`expand(L) & free - L - L_prev`). `recompute`: nothing
stored, each backtracking step replays the forward pass from the start (quadratic).

| Test | Measured | Budget | vs library search |
|---|---:|---:|---:|
| `bench_bfs_variant_felt_layers_empty_17x14` | 667_943 | 702_000 | +17.2 % |
| `bench_bfs_variant_felt_layers_cave_17x14` | 818_655 | 860_000 | +15.9 % |
| `bench_bfs_variant_felt_layers_maze_17x14` | 1_715_816 | 1_802_000 | +12.9 % |
| `bench_bfs_variant_felt_layers_serpentine_17x14` | 2_837_270 | 2_980_000 | +12.1 % |
| `bench_bfs_variant_checkpoints_empty_17x14` | 966_077 | 1_015_000 | +69.5 % |
| `bench_bfs_variant_checkpoints_cave_17x14` | 1_221_303 | 1_283_000 | +73.0 % |
| `bench_bfs_variant_checkpoints_maze_17x14` | 2_645_944 | 2_779_000 | +74.1 % |
| `bench_bfs_variant_checkpoints_serpentine_17x14` | 4_436_402 | 4_659_000 | +75.2 % |
| `bench_bfs_variant_recompute_empty_17x14` | 4_243_857 | 4_457_000 | +644.5 % |
| `bench_bfs_variant_recompute_cave_17x14` | 6_424_509 | 6_746_000 | +809.8 % |

### Variants: backtracking step (same plain loop, one layer per iteration)

`harness`: library step (neighbour mask of the current tile `2^c * M_parity` converted once,
intersected on the limbs that hold it, lowest bit by one `x & (x - 1)`, identified among the 6
offsets by field equalities in increasing order). `bits`: 6 single-bit tests (`Bits::get`) in
the direction order. `straight`: the last move is tried first with one bit test, the library
step otherwise. `window`: the hit is shifted into a `2W + 3`-bit window (tracked factor
`2^-(c-W-1)`) and a binary search over thresholds finds the highest neighbour (needs `W <= 62`).

| Test | Measured | Budget | vs harness |
|---|---:|---:|---:|
| `bench_bfs_variant_back_harness_empty_17x14` | 653_073 | 686_000 |  |
| `bench_bfs_variant_back_harness_cave_17x14` | 807_525 | 848_000 |  |
| `bench_bfs_variant_back_harness_maze_17x14` | 1_693_586 | 1_779_000 |  |
| `bench_bfs_variant_back_harness_serpentine_17x14` | 2_811_550 | 2_953_000 |  |
| `bench_bfs_variant_back_bits_empty_17x14` | 845_255 | 888_000 | +29.4 % |
| `bench_bfs_variant_back_bits_cave_17x14` | 987_886 | 1_038_000 | +22.3 % |
| `bench_bfs_variant_back_bits_maze_17x14` | 2_209_641 | 2_321_000 | +30.5 % |
| `bench_bfs_variant_back_bits_serpentine_17x14` | 3_393_838 | 3_564_000 | +20.7 % |
| `bench_bfs_variant_back_straight_empty_17x14` | 654_801 | 688_000 | +0.3 % |
| `bench_bfs_variant_back_straight_cave_17x14` | 870_294 | 914_000 | +7.8 % |
| `bench_bfs_variant_back_straight_maze_17x14` | 2_096_317 | 2_202_000 | +23.8 % |
| `bench_bfs_variant_back_straight_serpentine_17x14` | 2_919_346 | 3_066_000 | +3.8 % |
| `bench_bfs_variant_back_window_empty_17x14` | 658_407 | 692_000 | +0.8 % |
| `bench_bfs_variant_back_window_cave_17x14` | 810_320 | 851_000 | +0.3 % |
| `bench_bfs_variant_back_window_maze_17x14` | 1_683_669 | 1_768_000 | -0.6 % |
| `bench_bfs_variant_back_window_serpentine_17x14` | 2_768_869 | 2_908_000 | -1.5 % |

`window` is within 1.5 % of the library step but its step is 999 Sierra statements against 552
(`#[inline(never)]` probes) and it needs `W <= 62`: not kept.

### Variants: target test, set operations (forward pass only, plain loop, one layer per iteration)

`harness`: library choices (layers closer than the hex distance minus one skip the test, single
limb test). `no_gap`: the target is tested on every layer. `free_test`: the target neighbourhood
is tested on the unvisited set instead of the layer. `corelib`: `Layout::expand`, `&` and `-` on
`u256` instead of the local `bitwise` on limbs. `every_two` (against `harness_two`, the same
choices two layers per iteration): the second layer of each pair is tested against the closed
neighbourhood of the target (a layer that touches the neighbourhood is followed by one that holds
the target), then the first one once.

| Test | Measured | Budget | vs harness |
|---|---:|---:|---:|
| `bench_bfs_variant_distance_harness_empty_17x14` | 469_392 | 493_000 |  |
| `bench_bfs_variant_distance_harness_cave_17x14` | 615_538 | 647_000 |  |
| `bench_bfs_variant_distance_harness_maze_17x14` | 1_255_284 | 1_319_000 |  |
| `bench_bfs_variant_distance_harness_serpentine_17x14` | 2_117_758 | 2_224_000 |  |
| `bench_bfs_variant_distance_no_gap_empty_17x14` | 503_204 | 529_000 | +7.2 % |
| `bench_bfs_variant_distance_no_gap_cave_17x14` | 606_394 | 637_000 | -1.5 % |
| `bench_bfs_variant_distance_no_gap_maze_17x14` | 1_278_432 | 1_343_000 | +1.8 % |
| `bench_bfs_variant_distance_no_gap_serpentine_17x14` | 2_127_366 | 2_234_000 | +0.5 % |
| `bench_bfs_variant_distance_free_test_empty_17x14` | 469_602 | 494_000 | +0.0 % |
| `bench_bfs_variant_distance_free_test_cave_17x14` | 622_048 | 654_000 | +1.1 % |
| `bench_bfs_variant_distance_free_test_maze_17x14` | 1_266_894 | 1_331_000 | +0.9 % |
| `bench_bfs_variant_distance_free_test_serpentine_17x14` | 2_141_968 | 2_250_000 | +1.1 % |
| `bench_bfs_variant_distance_corelib_empty_17x14` | 519_092 | 546_000 | +10.6 % |
| `bench_bfs_variant_distance_corelib_cave_17x14` | 686_868 | 722_000 | +11.6 % |
| `bench_bfs_variant_distance_corelib_maze_17x14` | 1_410_054 | 1_481_000 | +12.3 % |
| `bench_bfs_variant_distance_corelib_serpentine_17x14` | 2_383_138 | 2_503_000 | +12.5 % |
| `bench_bfs_variant_distance_harness_two_empty_17x14` | 469_402 | 493_000 |  |
| `bench_bfs_variant_distance_harness_two_cave_17x14` | 584_948 | 615_000 |  |
| `bench_bfs_variant_distance_harness_two_maze_17x14` | 1_202_284 | 1_263_000 |  |
| `bench_bfs_variant_distance_harness_two_serpentine_17x14` | 2_006_168 | 2_107_000 |  |
| `bench_bfs_variant_distance_every_two_empty_17x14` | 467_808 | 492_000 | -0.3 % |
| `bench_bfs_variant_distance_every_two_cave_17x14` | 588_856 | 619_000 | +0.7 % |
| `bench_bfs_variant_distance_every_two_maze_17x14` | 1_172_002 | 1_231_000 | -2.5 % |
| `bench_bfs_variant_distance_every_two_serpentine_17x14` | 1_940_900 | 2_038_000 | -3.3 % |

`every_two` in the library (unrolled loop, the first layer tested alone for adjacent endpoints,
every layer tested for an edge target), measured then reverted: search EMPTY far -0.6 %, CAVE far
+2.2 %, MAZE far -0.6 %, SERPENTINE far -1.2 %, near searches -3 %, 7x7 MAZE far +3.0 %. Below 2 %
on the long paths and worse on CAVE, for a fourth loop instance: not kept.

### Variant: bidirectional (two frontiers expanded in turn, forward pass only)

A new layer can only meet the other frontier (not an older layer), so the test is one AND per
layer. Same number of layers as the library, a two-limb meeting test instead of a single-limb one
after the hex distance, no first/last layer saved; on UNREACHABLE it floods both components.

| Test | Measured | Budget | library `distance` | Delta |
|---|---:|---:|---:|---:|
| `bench_bfs_variant_bidirectional_empty_near_17x14` | 145_358 | 153_000 |  |  |
| `bench_bfs_variant_bidirectional_empty_far_17x14` | 525_110 | 552_000 | 407_159 | +29.0 % |
| `bench_bfs_variant_bidirectional_cave_near_17x14` | 150_158 | 158_000 |  |  |
| `bench_bfs_variant_bidirectional_cave_far_17x14` | 615_510 | 647_000 | 501_942 | +22.6 % |
| `bench_bfs_variant_bidirectional_maze_near_17x14` | 138_788 | 146_000 |  |  |
| `bench_bfs_variant_bidirectional_maze_far_17x14` | 1_295_008 | 1_360_000 | 1_058_347 | +22.4 % |
| `bench_bfs_variant_bidirectional_serpentine_near_17x14` | 139_158 | 147_000 |  |  |
| `bench_bfs_variant_bidirectional_serpentine_far_17x14` | 2_146_182 | 2_254_000 | 1_774_065 | +21.0 % |
| `bench_bfs_variant_bidirectional_unreachable_near_17x14` | 540_224 | 568_000 | 261_778 | +106.4 % |
| `bench_bfs_variant_bidirectional_unreachable_far_17x14` | 617_532 | 649_000 | 259_580 | +137.9 % |

### Variant: two-limb path on boards of at most 128 bits (library: single limb)

| Test | Measured | Budget | library (single limb) | Library delta |
|---|---:|---:|---:|---:|
| `bench_bfs_variant_wide_empty_far_7x7` | 193_861 | 204_000 | 131_733 | -32.0 % |
| `bench_bfs_variant_wide_cave_far_7x7` | 193_861 | 204_000 | 131_733 | -32.0 % |
| `bench_bfs_variant_wide_maze_far_7x7` | 373_308 | 392_000 | 239_984 | -35.7 % |
| `bench_bfs_variant_wide_serpentine_far_7x7` | 402_771 | 423_000 | 257_269 | -36.1 % |
| `bench_bfs_variant_wide_unreachable_far_7x7` | 143_651 | 151_000 | 89_843 | -37.5 % |

### Variant: scalar queue BFS (bitmap visited set, parents in a `Felt252Dict`, baseline to beat)

| Test | Measured | Budget | library search | Ratio |
|---|---:|---:|---:|---:|
| `bench_bfs_variant_scalar_empty_near_17x14` | 3_773_885 | 3_963_000 | 107_285 | 35.2x |
| `bench_bfs_variant_scalar_empty_far_17x14` | 17_282_104 | 18_147_000 | 570_033 | 30.3x |
| `bench_bfs_variant_scalar_cave_near_17x14` | 1_949_686 | 2_048_000 | 112_141 | 17.4x |
| `bench_bfs_variant_scalar_cave_far_17x14` | 12_389_976 | 13_010_000 | 706_135 | 17.5x |
| `bench_bfs_variant_scalar_maze_near_17x14` | 391_163 | 411_000 | 102_815 | 3.8x |
| `bench_bfs_variant_scalar_maze_far_17x14` | 7_826_466 | 8_218_000 | 1_519_526 | 5.2x |
| `bench_bfs_variant_scalar_serpentine_near_17x14` | 474_320 | 499_000 | 102_295 | 4.6x |
| `bench_bfs_variant_scalar_serpentine_far_17x14` | 8_209_741 | 8_621_000 | 2_532_090 | 3.2x |
| `bench_bfs_variant_scalar_unreachable_near_17x14` | 7_993_463 | 8_394_000 | 266_118 | 30.0x |
| `bench_bfs_variant_scalar_unreachable_far_17x14` | 7_994_033 | 8_394_000 | 263_320 | 30.4x |
| `bench_bfs_variant_scalar_empty_near_7x7` | 1_845_052 | 1_938_000 | 82_241 | 22.4x |
| `bench_bfs_variant_scalar_empty_far_7x7` | 2_258_243 | 2_372_000 | 131_733 | 17.1x |
| `bench_bfs_variant_scalar_cave_near_7x7` | 1_909_050 | 2_005_000 | 81_521 | 23.4x |
| `bench_bfs_variant_scalar_cave_far_7x7` | 2_068_418 | 2_172_000 | 131_733 | 15.7x |
| `bench_bfs_variant_scalar_maze_near_7x7` | 555_507 | 584_000 | 78_204 | 7.1x |
| `bench_bfs_variant_scalar_maze_far_7x7` | 1_321_244 | 1_388_000 | 239_984 | 5.5x |
| `bench_bfs_variant_scalar_serpentine_near_7x7` | 555_667 | 584_000 | 80_361 | 6.9x |
| `bench_bfs_variant_scalar_serpentine_far_7x7` | 1_420_993 | 1_493_000 | 257_269 | 5.5x |
| `bench_bfs_variant_scalar_unreachable_near_7x7` | 907_481 | 953_000 | 67_873 | 13.4x |
| `bench_bfs_variant_scalar_unreachable_far_7x7` | 907_481 | 953_000 | 89_843 | 10.1x |

### Iterations on the library (search, far pairs, 17x14)

| Version | EMPTY | CAVE | MAZE | SERPENTINE |
|---|---:|---:|---:|---:|
| v1: local `bitwise`, first layer = start neighbourhood, stop on the target neighbourhood, lowest-bit backtracking on `u256` | 706_994 | 871_747 | 1_918_927 | 3_223_148 |
| v2: + hex distance skip, single-limb target test, window backtracking with limb selection | 686_749 | 872_528 | 1_874_418 | 3_118_044 |
| v3: up/down as `(2P - Pe) * 2^(W-1)` and `* 2^-(W+1)` (2 constants), lowest-bit backtracking | 649_663 | 828_665 | 1_779_596 | 2_970_120 |
| v4: layer loops x2, backtracking x4 with `multi_pop_back`, boxed constants, limb from the conversion | 586_719 | 733_755 | 1_570_872 | 2_632_527 |
| v5: 3 shared table lookups for the masks, precomputed `W +- 1`, high-limb-only case | 579_893 | 727_935 | 1_553_296 | 2_599_170 |
| v6: straight-first backtracking (state of 8 values, turn not inlined) | 579_401 | 771_074 | 1_829_767 | 2_666_636 |
| v7: layer loops x4 (remainder in a second loop: +8k on every near search) | 581_833 | 723_925 | 1_523_556 | 2_535_100 |
| v8: layer loops x4, one loop with a felt counter | 576_193 | 715_725 | 1_517_416 | 2_532_660 |
| v8 with loops x8 (+19 % Sierra, 27_587 statements for `search` against 23_107) | 571_053 | 707_715 | 1_498_926 | 2_503_390 |
| v9: backtracking tail without a loop (<= 3 layers) | 569_453 | 705_555 | 1_518_046 | 2_529_810 |
| v10: single-limb path, offset identification shared by value (regression) | 582_833 | 722_135 | 1_561_126 | 2_602_490 |
| **v11 = library: shared identification through the `Box`** | **570_033** | **706_135** | **1_519_526** | **2_532_090** |
| v12: target tested every two layers (reverted, see above) | 566_866 | 721_556 | 1_510_494 | 2_501_945 |

Doubling of the frontier (v7 shape, x4): `felt -> u256` conversion 2_536_700 (kept),
`u128_overflowing_add` match 2_546_070 (deprecated), `OverflowingAdd` trait 2_590_170
(SERPENTINE). Layer constants boxed or by snapshot: equal (2_536_700 / 2_535_100), snapshot kept.
Loops x2: 20_867 statements for `search` (+2.4 % gas on SERPENTINE in the v7 shape). The iteration
stopped after three consecutive ideas below 2 % (loops x8, window backtracking, `every_two`).

### Decisions

* **Layers**: one hex dilation per layer on two `u128` limbs with the local `bitwise` (AND, XOR
  and OR in one application), up/down from `X = 2P - Pe` (`P` the frontier and its West
  neighbours, `Pe` its even rows) with 2 constants, the frontier doubled by a `felt252` product
  and converted. Stored as `Array<u256>`.
* **Endpoints outside the loop**: the first layer is the closed neighbourhood of the start, the
  loop stops on the first layer that touches the open interior neighbours of the target (2
  dilations fewer per search). Open edge tiles are endpoints only: the loop runs on interior tiles.
* **Target test**: skipped on the layers closer than the hex distance minus one, then one
  single-limb AND per layer (`LowGoal` / `HighGoal`, two limbs only when the neighbourhood spans
  both).
* **Backtracking**: neighbour mask `2^c * M_parity` (one product), intersected on the limb(s)
  given by the conversion, lowest bit, identified among the 6 offsets in increasing order; 4 layers
  per iteration (`multi_pop_back`), the constants in a `Box`, the last 3 layers without a loop.
* **Single `u128` limb** on boards of at most 128 bits: -32 % to -37 % on 7x7.
* **Loops unrolled 4 times**: x8 saves 1.2 % for +19 % code.
* `Bfs::distance` added (forward pass only, 70 % of `search` on SERPENTINE, 71 % on EMPTY).
* `Bfs::reachable` = `tiles_within_range(.., 255)`; it could replace `Caver::keep_component`.

## L2 A* baseline

_To be filled by lot L2._

## L3 Dial

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas). Library: `finders/dial.cairo`, benchmarks,
harness and losing variants: `tests/bench_dial.cairo`. Every result is checked against a scalar
Dijkstra (`dijkstra`, test-only): equal total cost, valid path (adjacent tiles, walkable, no edge tile
but the target), on the 10 fixtures, random caves (17x14, 19x13), 3x3, open edge tiles and 0 to 3
pseudo-random cost classes. With no class, the path length equals the scalar BFS of
`tests/variants.cairo`.

Cost maps of the benchmarks (`*_COST_2`, `*_COST_3`, generated offline): 2 classes over 30 % of the
floor (18 % cost 2, 10 % cost 3); `*_CLASS_2`, `*_COST_3`, `*_CLASS_4` split them into 3 classes.
Far pairs of `tests/fixtures.cairo`.

### Library

| Test | Measured | Budget | Path tiles | Path cost |
|---|---:|---:|---:|---:|
| `bench_dial_baseline_17x14` (fixture + costs only) | 13_720 | 15_000 | | |
| `bench_dial_empty_17x14` | 1_184_765 | 1_245_000 | 20 | 20 |
| **`bench_dial_cave_17x14`** (target < 1.5M) | **1_427_654** | 1_500_000 | 24 | 25 |
| `bench_dial_cave_17x14_near` | 289_645 | 305_000 | 4 | 4 |
| `bench_dial_maze_17x14` | 3_364_897 | 3_534_000 | 53 | 74 |
| `bench_dial_serpentine_17x14` | 5_094_739 | 5_350_000 | 90 | 125 |
| `bench_dial_unreachable_17x14` (floods the component) | 681_530 | 716_000 | 0 | |
| `bench_dial_cave_17x14_classes_0` (unit-cost loop) | 938_551 | 986_000 | 24 | 24 |
| `bench_dial_cave_17x14_classes_1` | 1_393_694 | 1_464_000 | 24 | 25 |
| `bench_dial_cave_17x14_classes_3` | 1_464_174 | 1_538_000 | 24 | |
| `bench_dial_empty_17x14_classes_0` | 763_597 | 802_000 | 19 | 19 |
| `bench_dial_maze_17x14_classes_0` | 2_005_148 | 2_106_000 | 53 | 53 |
| `bench_dial_serpentine_17x14_classes_0` | 3_293_977 | 3_459_000 | 90 | 90 |
| `bench_dial_cave_7x7` (`u128` path) | 298_947 | 314_000 | | |
| `bench_dial_cave_7x7_classes_0` (`u128` path) | 175_278 | 185_000 | | |
| `bench_dial_field_cave_17x14_budget_8` | 335_705 | 353_000 | | |

### Per time step and per path tile

A time step settles one bucket: dilation intersected with the unvisited set (12 applications of the
bitwise builtin on `u256`, 6 on `u128`), one AND per class, target test, bucket ring. Measured on
`field_of_movement` (same loop, no layer storage, no target test) from tile 110 of `EMPTY_17X14`,
`(budget 8 - budget 2) / 6`; 7x7 from tile 8, `(budget 4 - budget 1) / 3`.

| Classes | 17x14 budget 2 | 17x14 budget 8 | **Per time step, 17x14** (target < 40k) | Per time step, 7x7 (`u128`) |
|---:|---:|---:|---:|---:|
| 0 (unit-cost loop, no buckets) | 89_901 | 248_637 | 26_456 | 13_548 |
| 1 | 118_199 | 331_801 | 35_600 | |
| 2 | 126_717 | 347_555 | **36_806** | 20_544 |
| 3 | 134_645 | 362_719 | 38_012 | |

Budgets: `bench_dial_field_empty_17x14[_classes_k]_budget_{2,8}` and
`bench_dial_field_empty_7x7_classes_{0,2}_budget_{1,4}` (48_787 / 89_431 and 69_315 / 130_947).

Per path tile (backtracking: neighbour mask of the tile times the layer at `d - cost`, lowest bit,
direction by field comparisons, cost by one test of the "any class" plane, two more for the tiles of
cost 3 and 4):

* Harness, measured (`bench_dial_variant_backtrack_twice - _once`, 24 tiles): 20_049 per tile with 2
  classes, 18_089 with unit costs. The harness copy is slower than the library (below).
* Library, derived: `(search - setup - steps x per step) / tiles` with the harness setup (80_994)
  gives about 10k per tile with unit costs (`classes_0`, 23 steps) and about 19k with 2 classes
  (24 steps).
* Microbenchmarks (per op, loop baseline 145_020): one backtracking step 9_587 (South-East hit,
  first comparison) to 10_604 (North-West, last comparison); cost of a class-3 tile 5_199 (3
  applications); lowest-bit extraction 2_138.

Reference `origami_map` (`scarb test -p origami_map -f dijkstra`, cairo-test estimate, unit costs,
4 directions): `test_dijkstra_search_large` (18x14, 17-tile path) 22_826_630, medium (4x4) 2_292_184.
It has no weighted search.

### Variants (CAVE 17x14 far pair, 2 classes, harness)

The variants run in a harness copy of the library on `u256` (`search_winner`, interior endpoints),
which costs 7 % more than the library; each changes one building block. All of them return a path of
the oracle cost (`test_dial_variants_*`), and the harness winner returns the library path.

| Axis | Variant | Test | Measured | Budget | vs winner |
|---|---|---|---:|---:|---:|
| | **Winner (harness copy)**: felt bucket ring in locals, `N = E & U` then `N & C_k`, all layers stored, mask backtracking | `bench_dial_variant_winner_17x14` | 1_531_397 | 1_608_000 | |
| Bucket ring | fixed-size array `[felt252; 4]`, destructured and rebuilt | `bench_dial_variant_fixed_ring_17x14` | 1_510_831 | 1_587_000 | -1.3 % |
| Bucket ring | `Array<felt252>` rebuilt every step | `bench_dial_variant_array_ring_17x14` | 2_066_911 | 2_171_000 | +35.0 % |
| Class masking | unvisited set partitioned by class once (`U_k`), `E & U_k`, removal by subtraction | `bench_dial_variant_partition_17x14` | 1_762_061 | 1_851_000 | +15.1 % |
| Set operations | corelib (`Layout::expand`, `u256` `&`, `-`) | `bench_dial_variant_corelib_17x14` | 1_581_216 | 1_661_000 | +3.3 % |
| Layers | only the non-empty layers with their times, backtracking by `pop_back` | `bench_dial_variant_sparse_layers_17x14` | 1_522_711 | 1_599_000 | -0.6 % |
| Backtracking | 6 single-bit tests in fixed direction order, cost by plane bit tests | `bench_dial_variant_bit_tests_17x14` | 2_151_563 | 2_260_000 | +40.5 % |
| Unit costs | winner forward loop with no class (buckets) vs the unit loop (1_077_885) | `bench_dial_variant_unit_buckets_17x14` | 1_350_895 | 1_419_000 | +25.3 % |
| Width | `u256` harness on CAVE 7x7 vs the library `u128` path (298_947) | `bench_dial_variant_u256_7x7` | 469_062 | 493_000 | +56.9 % |
| Baseline | scalar Dijkstra, binary heap in a `Felt252Dict`, parents in a dictionary | `bench_dial_variant_dijkstra_heap_17x14` | 25_902_461 | 27_198_000 | library x18.1 cheaper |
| Baseline | same, EMPTY 17x14 (library 1_184_765) | `bench_dial_variant_dijkstra_heap_empty_17x14` | 37_706_695 | 39_593_000 | x31.8 |
| Baseline | same, MAZE 17x14 (library 3_364_897) | `bench_dial_variant_dijkstra_heap_maze_17x14` | 13_463_407 | 14_137_000 | x4.0 |
| Baseline | same, CAVE 7x7 (library 298_947) | `bench_dial_variant_dijkstra_heap_7x7` | 3_914_230 | 4_110_000 | x13.1 |

Harness pieces: `bench_dial_variant_setup_17x14` 80_994 (budget 86_000),
`bench_dial_variant_forward_only_17x14` 1_031_141 (1_083_000), backtracking once / twice 1_515_011 /
1_996_181 (1_591_000 / 2_096_000), unit 1_077_985 / 1_512_138 (1_132_000 / 1_588_000), bit tests
twice 3_269_485 (3_433_000), `bench_dial_variant_unit_winner_17x14` 1_077_885 (1_132_000).

Microbenchmarks (100 repetitions, per op = (test - `bench_dial_micro_loop` 145_020) / 100):

| Operation | Test | Measured | Budget | Per op |
|---|---|---:|---:|---:|
| One bitwise application (`u128` AND) | `bench_dial_micro_and_limb` | 317_130 | 333_000 | 1_721 |
| `u256` AND, one application per limb | `bench_dial_micro_and_triple` | 426_030 | 448_000 | 2_810 |
| `u128` checked sub | `bench_dial_micro_limb_sub` | 194_130 | 204_000 | 491 |
| felt -> `u256` (wide) | `bench_dial_micro_felt_to_u256` | 322_890 | 340_000 | 1_779 |
| Dilation + AND, local triple (library) | `bench_dial_micro_expand_triple` | 2_232_020 | 2_344_000 | 20_870 |
| Dilation + AND, `Layout::expand` + `u256 &` | `bench_dial_micro_expand_corelib` | 2_258_020 | 2_371_000 | 21_130 |
| Backtracking step, South-East hit | `bench_dial_micro_step_mask` | 1_103_760 | 1_159_000 | 9_587 |
| Backtracking step, North-West hit | `bench_dial_micro_step_mask_north_west` | 1_205_440 | 1_266_000 | 10_604 |
| Cost of a class-3 tile | `bench_dial_micro_cost` | 664_882 | 699_000 | 5_199 |
| Lowest bit of a limb | `bench_dial_micro_lowest` | 358_790 | 377_000 | 2_138 |
| Felt product + equality | `bench_dial_micro_felt_eq` | 194_780 | 205_000 | 498 |
| `span.at` on `Array<u256>` | `bench_dial_micro_span_at` | 132_090 | 139_000 | below the loop baseline |

### Library iterations (library tests, before -> after)

| Step | CAVE far, 2 classes | CAVE far, unit | CAVE 7x7, 2 classes |
|---|---:|---:|---:|
| First cut: `u256` buckets, `Layout::expand` + AND, cost by 2 plane tests, mask converted to `u256` | 1_581_334 | 1_223_325 | 461_371 |
| Local dilation with the bitwise triple | 1_563_884 | 1_376_315 | 450_361 |
| Felt buckets, unit-cost loop, single-limb mask (`try_into`), "any class" plane first | 1_440_654 | 930_321 | 413_779 |
| Generic `Set<T>`, `u128` path (helpers `#[inline]` only) | 1_477_644 | 984_241 | 311_537 |
| Helpers inlined by hand (generic functions cannot be `inline(always)`) | 1_459_534 | 962_841 | 306_907 |
| Class planes built from `u256` (3 conversions instead of 6), limb bounds by value | 1_436_714 | 944_861 | 299_297 |
| Bucket ring as a fixed-size array | 1_432_634 | 944_861 | 298_217 |
| Backtracking constants in a `Box` | **1_427_654** | **938_551** | **298_947** |

The iteration stopped after two consecutive ideas below 2 % (fixed ring -0.3 %, `Box` -0.35 %).
The generic form costs +0.7 % on unit costs 17x14 against the last non-generic version (938_551 vs
930_321) and saves 28 % on 7x7.

Sierra code size (non-specialized `finders::dial` functions of the test build): 16_170 statements;
the `u128` instances are 6_316 of them (`u256`: 6_827). The fixed ring is also smaller than the ring
in locals (16_170 vs 16_304 statements).

### Decisions

* **Tile costs make the first arrival final**: a tile is scheduled once, in the bucket `t + cost`, and
  leaves the unvisited set when scheduled, not when settled. No stale bucket entries, no AND at pop
  time, and the search stops when the target is *scheduled*.
* **Classes**: `N = dilation & U`, then one AND per non-empty class, class 1 by subtraction.
  Partitioning `U` by class once is 15 % more (same number of ANDs, 3 more subtractions per step).
  Overlapping class bitmaps: **the highest class wins** (partition at setup, 1 AND per class).
* **Buckets**: 4 felts in a fixed-size array; the scheduled sets are disjoint, so union = addition and
  "all empty" = one sum. A `u256` ring pays 2 limb additions per class per step (0.5k each); the
  felt ring pays one wide conversion (1.8k) per step.
* **Unit costs** take a separate loop without buckets (-25 %).
* **`u128` path** for boards of at most 128 bits (-36 % on 7x7), shared code through `Set<T>`.
* **Layers**: every time step stored (empty ones as 0), read by index. Sparse storage is 0.6 %
  cheaper in the harness, below the threshold, and adds a times array.
* **Backtracking**: neighbour mask `2^v * M_parity` narrowed to the limb that holds it (`try_into`,
  0.3k, instead of a 1.8k conversion), one AND, lowest bit, direction by field comparisons. 6 single
  bit tests are 40 % more.
* **Edge endpoints**: an edge start is seeded with its open interior neighbours (scalar), an edge
  target is added to the unvisited set and never expanded, its predecessor found by a scalar scan.
  `field_of_movement` keeps open edge tiles in the unvisited set and ANDs the frontier with the
  interior only when the grid has open edge tiles.

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

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), seed `'SEED'` unless stated. "Per tile"
divides by the open tiles of the result (the dug tiles for the digger, entrance included).

### Library

| Test | Measured | Budget | Tiles | Per tile |
|---|---:|---:|---:|---:|
| `bench_mazer_17x14_order_0` (target < 3M) | 2_875_890 | 3_020_000 | 89 | 32_314 |
| `bench_mazer_17x14_order_1` | 1_826_661 | 1_918_000 | 46 | 39_710 |
| `bench_mazer_17x14_order_0_seeds` (seeds 0..7) | 23_573_184 | 24_752_000 | 729 | 32_336 |
| `bench_mazer_17x14_order_1_seeds` (seeds 0..7) | 14_796_998 | 15_537_000 | 385 | 38_434 |
| `bench_mazer_7x7_order_0` | 524_603 | 551_000 | | |
| `bench_mazer_19x13_order_0` | 3_167_395 | 3_326_000 | | |
| `bench_digger_corridor_17x14` (3x2 room, entrance (3, 0)) | 314_852 | 331_000 | 9 | 34_984 |
| `bench_digger_maze_17x14` (same) | 3_229_661 | 3_392_000 | 90 | 35_885 |

Reference `origami_map` (cairo-test "gas usage est.", 18x14, 4 directions): maze order 0
27_966_300 (122 tiles, 229k per tile), order 1 29_823_584 (105 tiles, 284k per tile); digger
corridor 1_486_492, maze 3_957_108 (order 0) and 4_216_884 (order 1). The hex maze costs about
7x less per tile.

### Variants (`tests/bench_mazer.cairo`)

The variants share a base: the library carve rule dispatched at runtime (`CarverTrait::carve`),
recursion, `u256` maze, `(x, y)` tracked incrementally, one draw of the 6 orders of the forward
directions. Each changes one choice. The first group produces the same maze as the library
(checked by `test_bench_mazer_variants_same_maze`); the second changes the draws and is compared
per tile over 8 seeds.

| Variant | Test | Measured | Budget | Per tile | vs base |
|---|---|---:|---:|---:|---:|
| **Library: per-direction code (`Heading`), static turns (winner)** | `bench_mazer_17x14_order_0` | 2_875_890 | 3_020_000 | 32_314 | -4.4 % |
| Base: runtime direction dispatch | `bench_mazer_variant_base_17x14` | 3_006_900 | 3_158_000 | 33_785 | |
| Base, order 1 (library: 1_826_661, -5.3 %) | `bench_mazer_variant_base_17x14_order_1` | 1_928_381 | 2_025_000 | 41_921 | |
| Explicit stack (`Felt252Dict<Nullable<Frame>>`) | `bench_mazer_variant_stack_17x14` | 4_543_190 | 4_771_000 | 51_047 | +51.1 % |
| Per-neighbour bit tests (`Bits::get`, early exit) | `bench_mazer_variant_bits_17x14` | 9_633_733 | 10_116_000 | 108_244 | +220.4 % |
| Maze kept as `felt252`, set by addition | `bench_mazer_variant_felt_17x14` | 3_064_030 | 3_218_000 | 34_427 | +1.9 % |
| Index tracked, `(x, y)` by `DivRem` once per tile | `bench_mazer_variant_divrem_17x14` | 3_379_210 | 3_549_000 | 37_969 | +12.4 % |
| Base, 8 seeds (729 tiles) | `bench_mazer_variant_base_17x14_seeds` | 24_663_054 | 25_897_000 | 33_831 | |
| One draw of 3, rotation of (L, F, R) (719 tiles) | `bench_mazer_variant_rotation_17x14_seeds` | 23_167_600 | 24_326_000 | 32_222 | -4.8 % |
| Lazy draws: 3, then 2 if the first fails (726 tiles) | `bench_mazer_variant_lazy_17x14_seeds` | 26_386_034 | 27_706_000 | 36_344 | +7.4 % |
| `Rng::shuffle6` per tile, non forward skipped (727 tiles) | `bench_mazer_variant_shuffle_17x14_seeds` | 73_624_530 | 77_306_000 | 101_272 | +199.4 % |

Formulations measured while iterating on the library (not kept as tests; same maze, order 0 /
order 1 on 17x14):

| Formulation | Order 0 | Order 1 |
|---|---:|---:|
| v1: `u8` direction codes (`match` compiles to compare chains), `u8` coordinates, `@Carver` | 3_535_390 | 2_467_011 |
| v1 with one `u256` AND instead of two short-circuit `u128` ANDs | 3_558_127 | 2_481_586 |
| v1 with `Box<Carver>` | 3_498_920 | 2_446_911 |
| v2: `Direction` enum (jump table), `felt252` coordinates, precomputed closed masks | 2_973_530 | 1_861_331 |
| v2 with the AND restricted to the limbs the mask touches (extra branches) | 3_197_064 | 1_987_572 |
| **v3 = library: v2 + per-direction code (`Heading`)** | **2_875_890** | **1_826_661** |
| v3 with `@Carver` instead of `Box<Carver>` | 3_050_080 | 1_918_431 |
| v3 with each `Heading` calling `branch` directly (no `match` on the direction per tile) | 2_895_700 | 1_848_571 |
| v3 with the rotation order, per tile over 8 seeds (719 / 397 tiles) | 31_772 | 38_007 |

Microbenchmarks on v1 / v2 (per call, loop baseline subtracted): v1 `next` 2.3k, `step` 1.2k,
`mask` 2.7k, successful carve 13.2k; v2 `locate` 2.1k, `mask` 1.0k, successful carve 10.2k,
failed carve 8.4k, draw of 6 + order selection 6.2k. The two felt-to-`u256` conversions (1.8k
each) and the AND dominate a carve.

### Library decisions

* Carve test: **one mask test** `maze & 2^c * K`, where `K` is a field constant of the direction
  and parity (closed neighbourhood of the candidate minus `c`, order 1: ball of radius 2 minus `c`
  and the three tiles behind it). 3.2x cheaper than per-neighbour bit tests on the same base.
* **Forward cone**: only the 3 forward neighbours of a tile are candidates, and a carved middle
  candidate excludes both sides (a carved side excludes the middle) without a test.
* **Recursion**, not an explicit stack: Cairo arrays cannot pop from the back, and a dictionary
  stack costs +51 %.
* Maze kept as `u256` (two limb additions per carve) rather than a felt converted before every
  test (+1.9 %).
* `(x, y)` as felts tracked incrementally (+12.4 % with `DivRem`). They are needed for the
  interior test: the mask cannot detect border candidates, because the neighbours of an
  interior tile next to the border are border tiles.
* One uniform draw of the 6 orders per tile. The rotation order is 1.7 % cheaper per tile in the
  library (4.8 % on the base, whose turns cost a `match`), below the 2 % threshold, and it biases
  the side order (right before left in 2 orders out of 3), so it is not used. Lazy draws and
  `shuffle6` lose.
* Constants in a `Box<Carver>`: 6 % cheaper than a snapshot through the recursion.

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

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas).

### Method: mean and max over 256 seeds

The cost of a draw depends on the seed, so every benchmark of `bench_spreader.cairo` is a fuzz
test (`#[fuzzer(runs: N, seed: 7)]`, argument `k: u16`, seed `'SEED' + k`): snforge reports the
max, min and mean of `l2_gas` over the runs. Per call = run - 67_351, the mean of
`bench_spreader_baseline` (the same harness around a trivial body; its runs range from 49_990 to
68_560, so a per-call max is exact to about -17k/+1k). `#[available_gas]` applies to every run,
so each budget is `ceil(1.05 * max run, 1000)`: CI fails when any of the seeds gets more expensive.
The library and its `u256`-only variant run 256 seeds in CI; the losers run 32 seeds in CI, and their
256-seed figures below come from the same tests with `runs: 256` (measured once). `first version`
is PR #130 before the audit, measured with the same harness at its commit.

Fixtures: EMPTY/CAVE/MAZE 17x14 and 7x7 (shared fixtures), and, for audit A2 finding 1:
SPARSE2_10X25 (2 walkable tiles in opposite corners of a 250-bit board), SPARSE5_17X14 (5 walkable
tiles of 238) and D30_17X14 (71 random interior tiles, 30 % of the board). The 7x7 fixtures have at
most 25 walkable tiles: count 60 does not apply, and MAZE_7X7 uses count 16 (all its tiles).

### Algorithm (after audit A2)

`Spreader::generate` chooses `k = min(count, walkable - count)` tiles (complement trick) by
**radix select on random keys**: every tile gets a random key, one bit per Poseidon word, and the
`k` tiles with the smallest keys are chosen, ties broken uniformly. Each level splits the current
class with one word (`Z = S & word`, one popcount): if `k <= |Z|` the choice continues in `Z`,
otherwise `Z` is taken whole and the choice continues in `S - Z`. A class of at most 8 tiles is
finished at once: a uniform `k`-subset of its ranks from a 511-entry table (every mask of up to 8
bits, grouped by size and popcount), deposited on the class by a walk of at most 8 steps. About
`log2(n / 8)` levels (4 to 5 on 17x14), whatever the seed. Small counts are picked one by one when
that is cheaper (`prefer_picks`, a cost rule from the measurements below): at most 2 rejection trials
when the set covers at least 30 % of the board, then a select of a random rank from byte counts
(SWAR prefix sums, updated at every removal), or a walk on sets of at most 8 tiles.

Every loop is bounded: at most 12 levels (more than 8 tiles left after 12 levels has probability
below `4096 * C(251, 9) * 2^-108 < 2^-42`), at most 8 deposit steps, at most 125 picks of at most 2 trials and one select (no
loop) or a walk of at most 7 steps, at most 7 walk steps per limb elsewhere.

### Uniformity and bias

Every decision depends only on counts and on random bits, so the output law is invariant under any
permutation of the walkable tiles: uniform among the `count`-subsets, up to the random sources.
Exact bounds (doc of `generate`, tests `test_spreader_bias_*`):

| Source | Bound | Proof |
|---|---|---|
| Key words: Poseidon outputs, uniform below `P = 2^251 + 17 * 2^192 + 1`, used as 251 fair bits | `(17 * 2^192 + 1) / P < 2^-54.9` per word, at most 12 words: `< 2^-51.3` | `test_spreader_bias_field_bits` checks `P - 1 = 2^251 + 17 * 2^192` and the ratio against `2^-54`/`2^-55` |
| `Rng` draws: mixed radix digits of a 128-bit pool refilled below 2^32 | `2^-24` per pool (bounds of one pool multiply to less than `2^96 * 251 < 2^104`), one pool per call in practice; worst case one pool per draw, at most 375 draws: `< 2^-15.4` | `test_spreader_bias_pool` checks the refill threshold, every bound `<= 251` (table groups `<= 70`) and `2^96 * 251 < 2^104` |

The `2^-125` of the audit note holds for the first draw of a pool only; later draws of the same
pool see a smaller pool, hence the `2^-24` per pool. Statistical tests (per-tile bounds and a
sum-of-squares bound, 180 to 1000 seeds) cover the u128 and u256 radix, the complement, the dense
and sparse picks, the subset table and the sparse grids of the audit; a mutation that always
takes the first mask of the table fails three of them.

### Per call, mean / max over 256 seeds

| Fixture | count | **winner (radix)** | first version (PR #130 v1) | one-round mask | plain rejection | selection sampling (design) | rank (Floyd) | winner without u128 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| CAVE_17X14 | 1 | 86k / 137k | 64k / 139k | 91k / 155k | 55k / 128k | 646k / 1225k | 634k / 1238k |  |
| CAVE_17X14 | 5 | 206k / 273k | 138k / 270k | 175k / 296k | 139k / 270k | 1044k / 1227k | 1115k / 1297k |  |
| CAVE_17X14 | 20 | **191k / 241k** | 177k / 465k | 197k / 1100k | 474k / 681k | 1183k / 1233k | 1467k / 1518k |  |
| CAVE_17X14 | 60 | 199k / 255k | 201k / 536k | 243k / 683k | 1662k / 2159k | 1239k / 1251k | 2090k / 2106k |  |
| EMPTY_17X14 | 1 | 74k / 136k | 58k / 82k | 86k / 116k | 48k / 71k | 796k / 1638k | 912k / 1687k |  |
| EMPTY_17X14 | 5 | 192k / 319k | 127k / 207k | 149k / 227k | 111k / 190k | 1399k / 1673k | 1474k / 1746k |  |
| EMPTY_17X14 | 20 | 208k / 282k | 196k / 429k | 219k / 387k | 361k / 489k | 1610k / 1679k | 1897k / 1970k |  |
| EMPTY_17X14 | 60 | 207k / 275k | 194k / 683k | 217k / 632k | 1155k / 1433k | 1677k / 1697k | 2543k / 2563k |  |
| MAZE_17X14 | 1 | 95k / 137k | 71k / 183k | 98k / 175k | 61k / 170k | 446k / 870k | 491k / 886k |  |
| MAZE_17X14 | 5 | 191k / 242k | 163k / 300k | 212k / 348k | 176k / 363k | 737k / 872k | 815k / 944k |  |
| MAZE_17X14 | 20 | 181k / 251k | 187k / 575k | 232k / 888k | 668k / 1051k | 849k / 878k | 1134k / 1165k |  |
| MAZE_17X14 | 60 | 184k / 247k | 212k / 617k | 259k / 780k | 1126k / 1537k | 867k / 886k | 1323k / 1342k |  |
| CAVE_7X7 | 1 | 75k / 109k | 61k / 131k | 96k / 184k | 56k / 136k | 141k / 244k | 167k / 264k | 84k / 130k |
| CAVE_7X7 | 5 | 113k / 167k | 114k / 251k | 148k / 588k | 160k / 336k | 218k / 246k | 293k / 322k | 134k / 201k |
| CAVE_7X7 | 20 | 115k / 152k | 101k / 211k | 153k / 921k | 107k / 232k | 195k / 245k | 250k / 293k | 136k / 183k |
| EMPTY_7X7 | 1 | 74k / 109k | 60k / 114k | 94k / 184k | 55k / 117k | 158k / 262k | 178k / 282k | 82k / 130k |
| EMPTY_7X7 | 5 | 117k / 167k | 112k / 213k | 149k / 588k | 151k / 336k | 233k / 264k | 310k / 340k | 139k / 201k |
| EMPTY_7X7 | 20 | 117k / 167k | 112k / 214k | 149k / 588k | 151k / 336k | 233k / 264k | 310k / 341k | 139k / 202k |
| MAZE_7X7 | 1 | 83k / 109k | 68k / 168k | 153k / 1155k | 65k / 180k | 118k / 182k | 132k / 201k | 95k / 130k |
| MAZE_7X7 | 5 | 102k / 146k | 115k / 309k | 154k / 751k | 220k / 451k | 166k / 183k | 242k / 259k | 119k / 174k |
| MAZE_7X7 | 16 | 38k / 39k | 40k / 42k | 69k / 71k | 32k / 33k | 36k / 38k | 42k / 43k | 39k / 40k |
| D30_17X14 | 1 | 110k / 111k | 80k / 258k |  | 70k / 244k |  |  |  |
| D30_17X14 | 5 | 183k / 239k | 152k / 390k |  | 217k / 568k |  |  |  |
| D30_17X14 | 20 | 173k / 230k | 198k / 533k |  | 894k / 1448k |  |  |  |
| D30_17X14 | 60 | 175k / 247k | 174k / 472k |  | 469k / 824k |  |  |  |
| SPARSE5_17X14 | 1 | 72k / 82k | 542k / 2874k |  | 522k / 2803k |  |  |  |
| SPARSE5_17X14 | 2 | 76k / 83k | 1134k / 3969k |  | 1103k / 3875k |  |  |  |
| SPARSE2_10X25 | 1 | 64k / 68k | 1331k / 9265k |  | 1294k / 9053k |  |  |  |

Targets met: 20 objects on CAVE_17X14 cost at most **241k** over 256 seeds (target 300k, first
version 465k), and no row exceeds 1.84x its mean (target 3x; first version up to 6.96x, and
unbounded: finding 1 reproduced at 9.3M on SPARSE2_10X25). The price is the mean of small counts
on dense boards: count 1 costs 10-30k more than the first version (dimension/grid checks, the
dispatch rule, byte counts after two missed trials), count 5 on EMPTY/CAVE 17x14 about 60k more;
counts 20 and 60 cost about the same (-13 % to +14 %). The one-round mask and plain rejection of the first
bench file keep their unbounded tails (up to 1.2M and 9.1M).

### Microbenchmarks (10 repetitions, per op = (test - `bench_spreader_micro_loop`) / 10)

| Operation | Test | Per op |
|---|---|---:|
| Radix level on `u256` (Poseidon word, AND, popcount) | `bench_spreader_micro_level_u256` | 21_438 |
| Radix level on `u128` | `bench_spreader_micro_level_u128` | 15_852 |
| popcount `u256`, two `u128` SWAR then one byte-sum (winner) | `bench_spreader_micro_popcount_limbs` | 16_521 |
| popcount `u256`, `Bits::popcount` (loser) | `bench_spreader_micro_popcount_bits` | 19_971 |
| popcount `u128` | `bench_spreader_micro_popcount_u128` | 11_818 |
| Byte counts of a `u256` set (both limbs) | `bench_spreader_micro_counts_u256` | 22_811 |
| Select from byte counts, `u256` | `bench_spreader_micro_select_u256` | 32_484 |
| Select from byte counts, `u128` | `bench_spreader_micro_select_u128` | 25_339 |
| Walk to rank 7, `u256` | `bench_spreader_micro_walk_u256` | 33_641 |
| Deposit a mask on a 5-tile class, `u256` | `bench_spreader_micro_deposit_u256` | 29_456 |
| One rejection trial (draw, probe) | `bench_spreader_micro_trial` | 9_336 |

### Radix or picks

Measured on counts 1 to 5 (256 seeds, per-call mean, trials from a hit rate of 1/2): all picks
versus all radix (count 1 always picks), CAVE_17X14
77/115/154/192/232k vs 77/195/197/196/198k, EMPTY_17X14 66/94/122/152/182k vs 66/208/210/209/207k,
MAZE_17X14 101/144/188/231/274k vs 101/182/183/183/183k, CAVE_7X7 78/114/150/186/222k vs
78/105/107/109/106k. A pick costs about 30k (set covering 2/3 of the board), 38k (1/2), 42k
(less); a radix level 25k (`u256`) or 16k (`u128`); the table 30k. `prefer_picks` compares
`k * pick` with `levels * level + table`, `levels = ceil(log2(n / 8))`, for `k <= 5`.

### Explored after the audit and dropped (measured, 256 seeds)

| Design | CAVE_17X14 20: mean / max | Why dropped |
|---|---:|---|
| First version + bounded fix-up: rejection capped at 4 trials, then select (recursive rounds of Bernoulli masks, 5 rounds) | 195k / 354k | max above target; tail from chained mask rounds |
| Same, select in field arithmetic and felt accumulation | 182k / 342k | idem |
| Same, byte counts kept across picks, rounds capped at 3 or 4, thresholds swept (5 configurations) | 202k-214k / 355k-433k | idem: a round costs ~48k and a 256-seed tail chains 3-4 of them |
| Radix select, all small counts by radix | 190k / 241k | small counts 2-5 up to 2x more expensive than picks on dense boards |
| Rejection trials from a hit rate of 1/2 (instead of 30 %) | 191k / 241k | count 1 on MAZE_17X14 110k (95k with 30 %) |

### Library decisions

* Radix select on random keys, subset table for the last class of at most 8 tiles, picks for the
  small counts when cheaper, complement trick, `u128` path on boards of at most 128 bits (-3 % to
  -16 % on 7x7 against the same algorithm on `u256`).
* Byte counts (SWAR prefix sums) built once per pick phase and updated in the field at every
  removal; select without a loop.
* `BitSetTrait<u256>::popcount` sums the byte counts of both limbs before one byte-sum: 16.5k vs
  20.0k for `Bits::popcount`.

### Budgets

Measured at the commit of this pull request: per-run max for the fuzz tests (harness included),
single run for the microbenchmarks; budget = `ceil(1.05 * measured, 1000)`.

<details><summary>141 benchmarks</summary>

| Test | runs | Measured (max run) | Budget |
|---|---:|---:|---:|
| `bench_spreader_baseline` | 256 | 68_560 | 72_000 |
| `bench_spreader_floyd_cave_17x14_1` | 32 | 1_287_136 | 1_352_000 |
| `bench_spreader_floyd_cave_17x14_20` | 32 | 1_584_586 | 1_664_000 |
| `bench_spreader_floyd_cave_17x14_5` | 32 | 1_363_860 | 1_433_000 |
| `bench_spreader_floyd_cave_17x14_60` | 32 | 2_172_349 | 2_281_000 |
| `bench_spreader_floyd_cave_7x7_1` | 32 | 331_390 | 348_000 |
| `bench_spreader_floyd_cave_7x7_20` | 32 | 360_696 | 379_000 |
| `bench_spreader_floyd_cave_7x7_5` | 32 | 389_602 | 410_000 |
| `bench_spreader_floyd_empty_17x14_1` | 32 | 1_754_092 | 1_842_000 |
| `bench_spreader_floyd_empty_17x14_20` | 32 | 2_037_130 | 2_139_000 |
| `bench_spreader_floyd_empty_17x14_5` | 32 | 1_785_536 | 1_875_000 |
| `bench_spreader_floyd_empty_17x14_60` | 32 | 2_630_643 | 2_763_000 |
| `bench_spreader_floyd_empty_7x7_1` | 32 | 349_402 | 367_000 |
| `bench_spreader_floyd_empty_7x7_20` | 32 | 407_914 | 429_000 |
| `bench_spreader_floyd_empty_7x7_5` | 32 | 407_814 | 429_000 |
| `bench_spreader_floyd_maze_17x14_1` | 32 | 953_264 | 1_001_000 |
| `bench_spreader_floyd_maze_17x14_20` | 32 | 1_231_752 | 1_294_000 |
| `bench_spreader_floyd_maze_17x14_5` | 32 | 1_011_676 | 1_063_000 |
| `bench_spreader_floyd_maze_17x14_60` | 32 | 1_409_319 | 1_480_000 |
| `bench_spreader_floyd_maze_7x7_1` | 32 | 268_348 | 282_000 |
| `bench_spreader_floyd_maze_7x7_16` | 32 | 110_728 | 117_000 |
| `bench_spreader_floyd_maze_7x7_5` | 32 | 326_510 | 343_000 |
| `bench_spreader_generate_cave_17x14_1` | 256 | 204_839 | 216_000 |
| `bench_spreader_generate_cave_17x14_20` | 256 | 308_848 | 325_000 |
| `bench_spreader_generate_cave_17x14_5` | 256 | 340_087 | 358_000 |
| `bench_spreader_generate_cave_17x14_60` | 256 | 322_711 | 339_000 |
| `bench_spreader_generate_cave_7x7_1` | 256 | 176_831 | 186_000 |
| `bench_spreader_generate_cave_7x7_20` | 256 | 219_394 | 231_000 |
| `bench_spreader_generate_cave_7x7_5` | 256 | 234_194 | 246_000 |
| `bench_spreader_generate_d30_17x14_1` | 256 | 178_633 | 188_000 |
| `bench_spreader_generate_d30_17x14_20` | 256 | 297_136 | 312_000 |
| `bench_spreader_generate_d30_17x14_5` | 256 | 306_469 | 322_000 |
| `bench_spreader_generate_d30_17x14_60` | 256 | 314_275 | 330_000 |
| `bench_spreader_generate_empty_17x14_1` | 256 | 203_769 | 214_000 |
| `bench_spreader_generate_empty_17x14_20` | 256 | 349_586 | 368_000 |
| `bench_spreader_generate_empty_17x14_5` | 256 | 386_026 | 406_000 |
| `bench_spreader_generate_empty_17x14_60` | 256 | 342_340 | 360_000 |
| `bench_spreader_generate_empty_7x7_1` | 256 | 176_841 | 186_000 |
| `bench_spreader_generate_empty_7x7_20` | 256 | 234_544 | 247_000 |
| `bench_spreader_generate_empty_7x7_5` | 256 | 234_204 | 246_000 |
| `bench_spreader_generate_maze_17x14_1` | 256 | 204_839 | 216_000 |
| `bench_spreader_generate_maze_17x14_20` | 256 | 317_978 | 334_000 |
| `bench_spreader_generate_maze_17x14_5` | 256 | 309_009 | 325_000 |
| `bench_spreader_generate_maze_17x14_60` | 256 | 314_372 | 331_000 |
| `bench_spreader_generate_maze_7x7_1` | 256 | 176_201 | 186_000 |
| `bench_spreader_generate_maze_7x7_16` | 256 | 106_509 | 112_000 |
| `bench_spreader_generate_maze_7x7_5` | 256 | 213_251 | 224_000 |
| `bench_spreader_generate_sparse2_10x25_1` | 256 | 135_256 | 143_000 |
| `bench_spreader_generate_sparse5_17x14_1` | 256 | 149_625 | 158_000 |
| `bench_spreader_generate_sparse5_17x14_2` | 256 | 149_865 | 158_000 |
| `bench_spreader_mask_cave_17x14_1` | 32 | 172_664 | 182_000 |
| `bench_spreader_mask_cave_17x14_20` | 32 | 655_847 | 689_000 |
| `bench_spreader_mask_cave_17x14_5` | 32 | 363_809 | 382_000 |
| `bench_spreader_mask_cave_17x14_60` | 32 | 596_992 | 627_000 |
| `bench_spreader_mask_cave_7x7_1` | 32 | 241_625 | 254_000 |
| `bench_spreader_mask_cave_7x7_20` | 32 | 433_615 | 456_000 |
| `bench_spreader_mask_cave_7x7_5` | 32 | 655_338 | 689_000 |
| `bench_spreader_mask_empty_17x14_1` | 32 | 162_741 | 171_000 |
| `bench_spreader_mask_empty_17x14_20` | 32 | 395_920 | 416_000 |
| `bench_spreader_mask_empty_17x14_5` | 32 | 262_878 | 277_000 |
| `bench_spreader_mask_empty_17x14_60` | 32 | 594_005 | 624_000 |
| `bench_spreader_mask_empty_7x7_1` | 32 | 241_625 | 254_000 |
| `bench_spreader_mask_empty_7x7_20` | 32 | 655_338 | 689_000 |
| `bench_spreader_mask_empty_7x7_5` | 32 | 655_338 | 689_000 |
| `bench_spreader_mask_maze_17x14_1` | 32 | 192_760 | 203_000 |
| `bench_spreader_mask_maze_17x14_20` | 32 | 895_807 | 941_000 |
| `bench_spreader_mask_maze_17x14_5` | 32 | 364_809 | 384_000 |
| `bench_spreader_mask_maze_17x14_60` | 32 | 565_486 | 594_000 |
| `bench_spreader_mask_maze_7x7_1` | 32 | 1_222_100 | 1_284_000 |
| `bench_spreader_mask_maze_7x7_16` | 32 | 137_924 | 145_000 |
| `bench_spreader_mask_maze_7x7_5` | 32 | 507_113 | 533_000 |
| `bench_spreader_micro_counts_u256` |  | 259_130 | 273_000 |
| `bench_spreader_micro_deposit_u256` |  | 325_580 | 342_000 |
| `bench_spreader_micro_level_u128` |  | 189_540 | 200_000 |
| `bench_spreader_micro_level_u256` |  | 245_400 | 258_000 |
| `bench_spreader_micro_loop` |  | 31_020 | 33_000 |
| `bench_spreader_micro_popcount_bits` |  | 230_730 | 243_000 |
| `bench_spreader_micro_popcount_limbs` |  | 196_230 | 207_000 |
| `bench_spreader_micro_popcount_u128` |  | 149_200 | 157_000 |
| `bench_spreader_micro_select_u128` |  | 284_409 | 299_000 |
| `bench_spreader_micro_select_u256` |  | 355_868 | 374_000 |
| `bench_spreader_micro_trial` |  | 124_381 | 131_000 |
| `bench_spreader_micro_walk_u256` |  | 367_430 | 386_000 |
| `bench_spreader_reject_cave_17x14_1` | 32 | 145_011 | 153_000 |
| `bench_spreader_reject_cave_17x14_20` | 32 | 688_422 | 723_000 |
| `bench_spreader_reject_cave_17x14_5` | 32 | 286_541 | 301_000 |
| `bench_spreader_reject_cave_17x14_60` | 32 | 1_983_195 | 2_083_000 |
| `bench_spreader_reject_cave_7x7_1` | 32 | 144_261 | 152_000 |
| `bench_spreader_reject_cave_7x7_20` | 32 | 299_827 | 315_000 |
| `bench_spreader_reject_cave_7x7_5` | 32 | 344_079 | 362_000 |
| `bench_spreader_reject_d30_17x14_1` | 32 | 185_203 | 195_000 |
| `bench_spreader_reject_d30_17x14_20` | 32 | 1_361_345 | 1_430_000 |
| `bench_spreader_reject_d30_17x14_5` | 32 | 429_414 | 451_000 |
| `bench_spreader_reject_d30_17x14_60` | 32 | 749_106 | 787_000 |
| `bench_spreader_reject_empty_17x14_1` | 32 | 134_838 | 142_000 |
| `bench_spreader_reject_empty_17x14_20` | 32 | 523_752 | 550_000 |
| `bench_spreader_reject_empty_17x14_5` | 32 | 246_099 | 259_000 |
| `bench_spreader_reject_empty_17x14_60` | 32 | 1_348_964 | 1_417_000 |
| `bench_spreader_reject_empty_7x7_1` | 32 | 144_261 | 152_000 |
| `bench_spreader_reject_empty_7x7_20` | 32 | 344_059 | 362_000 |
| `bench_spreader_reject_empty_7x7_5` | 32 | 344_079 | 362_000 |
| `bench_spreader_reject_maze_17x14_1` | 32 | 175_280 | 185_000 |
| `bench_spreader_reject_maze_17x14_20` | 32 | 995_014 | 1_045_000 |
| `bench_spreader_reject_maze_17x14_5` | 32 | 356_752 | 375_000 |
| `bench_spreader_reject_maze_17x14_60` | 32 | 1_579_803 | 1_659_000 |
| `bench_spreader_reject_maze_7x7_1` | 32 | 174_030 | 183_000 |
| `bench_spreader_reject_maze_7x7_16` | 32 | 100_078 | 106_000 |
| `bench_spreader_reject_maze_7x7_5` | 32 | 393_694 | 414_000 |
| `bench_spreader_reject_sparse2_10x25_1` | 32 | 3_588_489 | 3_768_000 |
| `bench_spreader_reject_sparse5_17x14_1` | 32 | 1_536_000 | 1_613_000 |
| `bench_spreader_reject_sparse5_17x14_2` | 32 | 2_136_781 | 2_244_000 |
| `bench_spreader_selection_cave_17x14_1` | 32 | 1_292_139 | 1_357_000 |
| `bench_spreader_selection_cave_17x14_20` | 32 | 1_300_499 | 1_366_000 |
| `bench_spreader_selection_cave_17x14_5` | 32 | 1_293_899 | 1_359_000 |
| `bench_spreader_selection_cave_17x14_60` | 32 | 1_318_099 | 1_385_000 |
| `bench_spreader_selection_cave_7x7_1` | 32 | 311_618 | 328_000 |
| `bench_spreader_selection_cave_7x7_20` | 32 | 312_478 | 329_000 |
| `bench_spreader_selection_cave_7x7_5` | 32 | 313_378 | 330_000 |
| `bench_spreader_selection_empty_17x14_1` | 32 | 1_633_907 | 1_716_000 |
| `bench_spreader_selection_empty_17x14_20` | 32 | 1_746_830 | 1_835_000 |
| `bench_spreader_selection_empty_17x14_5` | 32 | 1_740_230 | 1_828_000 |
| `bench_spreader_selection_empty_17x14_60` | 32 | 1_764_430 | 1_853_000 |
| `bench_spreader_selection_empty_7x7_1` | 32 | 329_504 | 346_000 |
| `bench_spreader_selection_empty_7x7_20` | 32 | 331_244 | 348_000 |
| `bench_spreader_selection_empty_7x7_5` | 32 | 331_264 | 348_000 |
| `bench_spreader_selection_maze_17x14_1` | 32 | 928_326 | 975_000 |
| `bench_spreader_selection_maze_17x14_20` | 32 | 945_629 | 993_000 |
| `bench_spreader_selection_maze_17x14_5` | 32 | 939_029 | 986_000 |
| `bench_spreader_selection_maze_17x14_60` | 32 | 952_920 | 1_001_000 |
| `bench_spreader_selection_maze_7x7_1` | 32 | 249_017 | 262_000 |
| `bench_spreader_selection_maze_7x7_16` | 32 | 104_988 | 111_000 |
| `bench_spreader_selection_maze_7x7_5` | 32 | 250_777 | 264_000 |
| `bench_spreader_u256_cave_7x7_1` | 256 | 197_819 | 208_000 |
| `bench_spreader_u256_cave_7x7_20` | 256 | 250_419 | 263_000 |
| `bench_spreader_u256_cave_7x7_5` | 256 | 268_581 | 283_000 |
| `bench_spreader_u256_empty_7x7_1` | 256 | 197_829 | 208_000 |
| `bench_spreader_u256_empty_7x7_20` | 256 | 269_131 | 283_000 |
| `bench_spreader_u256_empty_7x7_5` | 256 | 268_591 | 283_000 |
| `bench_spreader_u256_maze_7x7_1` | 256 | 197_189 | 208_000 |
| `bench_spreader_u256_maze_7x7_16` | 256 | 107_318 | 113_000 |
| `bench_spreader_u256_maze_7x7_5` | 256 | 241_726 | 254_000 |

</details>

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
