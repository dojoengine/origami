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

CI (lot P1): the pull-request job runs `snforge test --package origami_hexmap --fuzzer-runs 64`:
the library fuzz benchmarks (`bench_spreader_generate_*`) take their number of runs from the
command line and their budgets, max over 256 seeds, hold on any subset; the losers of
`bench_spreader.cairo` are `#[ignore]`d. The non-blocking job `hexmap-full` runs everything on
pushes to `main`: `snforge test --package origami_hexmap --include-ignored` (256 seeds by default).
Measure a lot with the same command and a filter, `--include-ignored` for the losers.

The lot sections below record the measurements of their lot. Lot P1 refreshed their `Measured`
and `Budget` columns (and the L0 per-operation column) at its commit; the other derived figures
(per tile, per step, deltas, iteration tables) are the lots' own: section P1 has the current ones.

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
| popcount, 180 bits set (P1: byte counts per limb, `bounded_int` byte sum) | `bench_popcount_swar_dense` | 1_486_920 | 1_562_000 | 13_448 |  |  |
| popcount per set bit, 180 bits set | `bench_popcount_sparse_dense` | 53_953_630 | 56_652_000 | 538_115 |  |  |
| popcount, 8 bits set (P1: byte counts per limb, `bounded_int` byte sum) | `bench_popcount_swar_sparse` | 1_496_380 | 1_572_000 | 13_543 |  |  |
| popcount per set bit, 8 bits set | `bench_popcount_sparse_sparse` | 3_171_490 | 3_331_000 | 30_294 |  |  |
| Poseidon `HashState` (2 updates + finalize) | `bench_poseidon_hash_state` | 441_890 | 464_000 | 2_998 | 1.2-1.5k | refuted, higher |
| Poseidon, one `hades_permutation` (`Rng::mix`) | `bench_poseidon_hades` | 312_590 | 329_000 | 1_705 |  |  |
| Pool draw, constant bound (`Rng::draw`), refills amortised | `bench_rng_draw` | 562_744 | 589_000 | 4_206 | ~0.9k | refuted, higher |
| Pool draw `Rng::next_below(6)` | `bench_rng_next_below` | 515_744 | 542_000 | 3_736 | ~0.9k | refuted, higher |
| `Rng::shuffle6` (one draw + table), refills amortised | `bench_rng_shuffle6` | 718_985 | 776_000 | 5_769 |  |  |
| shuffle6: DivRem 720 + table (winner) | `bench_shuffle6_table` | 498_670 | 524_000 | 3_566 |  |  |
| shuffle6: Fisher-Yates, 5 draws (loser) | `bench_shuffle6_fisher_yates` | 11_459_660 | 12_033_000 | 113_176 |  |  |
| `Felt252Dict` insert (incl. squash share) | `bench_dict_insert` | 695_100 | 730_000 | 5_530 | 2-4k | confirmed |
| `Felt252Dict` get (incl. squash share) | `bench_dict_insert_get` | 984_390 | 1_034_000 | 2_893 | 2-4k | refuted, lower |
| `Array` append | `bench_array_build` | 291_480 | 307_000 | 223 | 200-400 | confirmed |
| `span.at` | `bench_array_span_at` | 388_680 | 409_000 | 972 | 200-400 | refuted, higher |
| `Layout::new` (17x14) | `bench_layout_new` | 871_490 | 916_000 | 7_294 | 1-2k per mask |  |
| `Layout::interior` (17x14) | `bench_layout_interior` | 496_490 | 522_000 | 3_544 | 1-2k | refuted, higher |
| **`expand` (a) felt shifts, border invariant (winner)**, 17x14 | `bench_expand_felt` | 2_003_410 | 2_182_000 | 18_613 |  |  |
| `expand` (a') West shift via felt conversion | `bench_expand_felt_double` | 2_162_810 | 2_271_000 | 20_207 |  |  |
| `expand` (a'') vertical from parity-selected pairs | `bench_expand_felt_vertical` | 2_363_410 | 2_482_000 | 22_213 |  |  |
| `expand` (b) u256 shifts + row/column masks, no invariant | `bench_expand_masks` | 6_547_600 | 6_875_000 | 64_055 | ~3x (a) | confirmed (3.3x) |
| `expand` (c) per-limb u128 set operations | `bench_expand_limbs` | 2_162_810 | 2_271_000 | 20_207 |  |  |
| `expand` (a) on 7x7 | `bench_expand_felt_7x7` | 1_685_930 | 1_771_000 | 15_438 |  |  |
| **`expand_small` (c') single u128 limb, W*H <= 128 (winner)**, 7x7 | `bench_expand_small_7x7` | 923_680 | 1_002_000 | 7_816 |  |  |
| `expand_small` with the West shift via felt | `bench_expand_small_felt_double_7x7` | 1_277_080 | 1_341_000 | 11_350 |  |  |
| BFS layer step: `expand & U`, `U - F'` (winner) | `bench_step_or` | 2_104_260 | 2_210_000 | 19_622 | 15-20k | confirmed (upper end) |
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
frontier instead of a `u256` comparison, single limb on small boards) beat the L4
`Caver::keep_component` on every input (-2.5 % to -8.3 % on 17x14, -35 % to -44 % on 7x7); it also
adds the open edge tiles next to the component. Since P1, `Caver::keep_component` runs the same
flood (`BfsInternal::component`, no endpoint checks, no edge tiles): the column below.

| Test | Measured | Budget | `Caver::keep_component` (same input; since P1 the same flood without the checks) | Delta |
|---|---:|---:|---:|---:|
| `bench_bfs_reachable_cave_17x14` | 538_169 | 585_000 | 535_769 (budget 563_000) | +0.4 % |
| `bench_bfs_reachable_maze_17x14` | 1_115_413 | 1_213_000 | 1_113_013 (budget 1_169_000) | +0.2 % |
| `bench_bfs_reachable_serpentine_17x14` | 1_843_335 | 2_004_000 | 1_840_935 (budget 1_933_000) | +0.1 % |
| `bench_bfs_reachable_unreachable_17x14` | 266_811 | 291_000 | 264_411 (budget 278_000) | +0.9 % |
| `bench_bfs_reachable_cave_7x7` | 99_453 | 110_000 | 97_253 (budget 103_000) | +2.3 % |
| `bench_bfs_reachable_maze_7x7` | 166_779 | 184_000 | 164_579 (budget 173_000) | +1.3 % |
| `bench_bfs_reachable_serpentine_7x7` | 176_397 | 195_000 | 174_197 (budget 183_000) | +1.3 % |
| `bench_bfs_reachable_unreachable_7x7` | 80_217 | 89_000 | 78_017 (budget 82_000) | +2.8 % |

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

## L2 A*

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), budgets set by the procedure above.
Everything is test-only in `tests/bench_astar.cairo`: **no A\* formulation beats `Bfs::search`
by more than 5 % on a realistic class of inputs**, so `finders/astar.cairo` is not declared and
nothing is exported. Every search is checked against `Bfs::search` (same length, valid path) on
the fixtures, samples of CAVE, MAZE, EMPTY and SERPENTINE, 3 random caves (17x14, 19x13, 7x7), 3
mazes, 3x3, 8x16, 9x15, 25x10, 83x3, 3x83, open edge tiles (entrances, corners, a whole open row,
a closed entrance, `Digger` corridors and mazes); `Astar::search` also has the panics of
`Bfs::search`. The greedy search is checked for validity only (not shortest).

Pairs: the fixtures of `bench_bfs.cairo`, plus pairs from the centre of EMPTY 17x14 (110) and
from a cave tile of CAVE 17x14 (104) at hex distance 1, 2, 5 and 10 (on CAVE the walls lengthen
the path to 7 and 12). `Bfs::search` of the fixture pairs is the L1 library figure above;
the extra pairs have their own `bench_astar_bfs_*` benchmarks.

### Formulations

* **`Astar::search` (bitmap buckets, the best one).** With unit costs and the hex distance as
  heuristic, a neighbour's `f` is the parent's `f` plus 0, 1 or 2, so only three buckets are
  live (`f`, `f + 1`, `f + 2`), each two `u128` limbs. The directions that bring a tile closer or
  take it away depend only on the signs of the cube offset to the target (12 cases): the
  neighbours are split into the three classes by 3 field products (`2^i * M_class`), converted
  to one limb when the neighbourhood fits in it, and one AND with the unclosed set each. The
  closer neighbours of the last expanded tile are expanded first (tie-break towards the smaller
  `h`), then the bucket `f` by lowest bit; the index of a popped bit is `LOG[bit mod 131]` (2 is a
  primitive root of 131). Stale copies in the later buckets are dropped by one AND when a bucket
  becomes current. The search stops when the target enters the bucket `f`. The path is rebuilt
  from the list of expanded tiles walked backwards once (a tile popped as a closer neighbour of
  the previous entry follows it, the others take the last expanded neighbour at depth `g - 1`).
  Same contract as `Bfs::search`, edge endpoints included.
* **Other open lists** (same expansion and classes, entries `f << 16 | h << 8 | position`, lazy
  deletion of closed tiles): binary heap in a `Felt252Dict` (`variant_heap`), array kept sorted
  by one copy per insertion (`variant_sorted`; a heap in an immutable `Array` would copy the array
  on every swap), unsorted array scanned for the minimum and rebuilt (`variant_scan`).
* **Greedy best-first** (`variant_greedy`, not shortest): buckets by `h` in a `Felt252Dict`, the
  closer class first, every tile pushed once.
* **BFS pruned by the hex distance** (`variant_pruned`): layer `i` is intersected with the ball of
  radius `bound - i` around the target (balls by dilating the target on the empty interior),
  iterative deepening on `bound` from the hex distance, backtracking by `BfsInternal::backtrack`.

### `Astar::search` against `Bfs::search`

`BFS layers / tiles`: layers of `Bfs::search` and tiles in them. `Per expanded tile`: gas divided
by the expanded tiles (fixed cost included); the marginal cost is 35.5k per expanded tile (EMPTY
d5 -> d10, path tiles included). A BFS layer costs 19.3k on 17x14 whatever its size (3.2k per
tile touched on EMPTY far).

| Pair | Path | `Bfs::search` | BFS layers / tiles | **`Astar::search`** | vs BFS | Expanded | Per expanded tile |
|---|---:|---:|---:|---:|---:|---:|---:|
| EMPTY NEAR 17x14 | 3 | 107_285 | 2 / 19 | 132_457 | +23.5 % | 3 | 44_152 |
| EMPTY FAR 17x14 | 19 | 570_033 | 18 / 178 | 661_956 | +16.1 % | 19 | 34_839 |
| CAVE NEAR 17x14 | 3 | 112_141 | 2 / 11 | 131_292 | +17.1 % | 3 | 43_764 |
| CAVE FAR 17x14 | 24 | 706_135 | 23 / 130 | 2_806_132 | +297.4 % | 69 | 40_668 |
| MAZE NEAR 17x14 | 3 | 102_815 | 2 / 3 | 123_382 | +20.0 % | 3 | 41_127 |
| MAZE FAR 17x14 | 53 | 1_519_526 | 52 / 91 | 3_562_373 | +134.4 % | 90 | 39_581 |
| SERPENTINE NEAR 17x14 | 3 | 102_295 | 2 / 5 | 123_302 | +20.5 % | 3 | 41_100 |
| SERPENTINE FAR 17x14 | 90 | 2_532_090 | 89 / 94 | 4_001_051 | +58.0 % | 94 | 42_564 |
| UNREACHABLE NEAR 17x14 | 0 | 266_118 | 10 / 84 | 3_038_427 | +1041.8 % | 84 | 36_171 |
| UNREACHABLE FAR 17x14 | 0 | 263_320 | 12 / 84 | 2_862_550 | +987.1 % | 84 | 34_077 |
| EMPTY NEAR 7x7 | 3 | 82_241 | 2 / 13 | 121_042 | +47.2 % | 3 | 40_347 |
| EMPTY FAR 7x7 | 6 | 131_733 | 5 / 23 | 218_654 | +66.0 % | 6 | 36_442 |
| CAVE NEAR 7x7 | 3 | 81_521 | 2 / 18 | 120_172 | +47.4 % | 3 | 40_057 |
| CAVE FAR 7x7 | 6 | 131_733 | 5 / 22 | 218_654 | +66.0 % | 6 | 36_442 |
| MAZE NEAR 7x7 | 3 | 78_204 | 2 / 5 | 130_828 | +67.3 % | 3 | 43_609 |
| MAZE FAR 7x7 | 13 | 239_984 | 12 / 15 | 622_646 | +159.5 % | 15 | 41_509 |
| SERPENTINE NEAR 7x7 | 3 | 80_361 | 2 / 5 | 120_112 | +49.5 % | 3 | 40_037 |
| SERPENTINE FAR 7x7 | 14 | 257_269 | 13 / 16 | 628_832 | +144.4 % | 16 | 39_302 |
| UNREACHABLE NEAR 7x7 | 0 | 67_873 | 3 / 10 | 393_652 | +480.0 % | 10 | 39_365 |
| UNREACHABLE FAR 7x7 | 0 | 89_843 | 5 / 10 | 368_820 | +310.5 % | 10 | 36_882 |
| EMPTY D1 17x14 | 1 | 62_023 | 1 / 7 | 57_141 | -7.9 % | 1 | 57_141 |
| EMPTY D2 17x14 | 2 | 79_109 | 1 / 7 | 98_018 | +23.9 % | 2 | 49_009 |
| EMPTY D5 17x14 | 5 | 165_609 | 4 / 61 | 203_385 | +22.8 % | 5 | 40_677 |
| EMPTY D10 17x14 | 10 | 313_179 | 9 / 176 | 380_930 | +21.6 % | 10 | 38_093 |
| CAVE D1 17x14 | 1 | 60_350 | 1 / 7 | 56_351 | -6.6 % | 1 | 56_351 |
| CAVE D2 17x14 | 2 | 77_756 | 1 / 7 | 94_598 | +21.7 % | 2 | 47_299 |
| CAVE D5 17x14 | 7 | 221_088 | 6 / 34 | 625_567 | +182.9 % | 15 | 41_704 |
| CAVE D10 17x14 | 12 | 371_744 | 11 / 65 | 900_830 | +142.3 % | 22 | 40_946 |

### Other formulations

Gas (ratio to `Bfs::search`), tiles expanded by the heap (the sorted and scanned arrays expand the
same tiles), tiles expanded by the greedy search and its path length, rounds of the pruned BFS.

| Pair | dict heap | sorted array | unsorted scan | heap expanded | greedy | greedy expanded / path | pruned BFS | pruned rounds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| EMPTY NEAR 17x14 | 526_980 (4.9x) | 449_400 (4.2x) | 398_470 (3.7x) | 3 | 229_457 (2.1x) | 3 / 3 | 182_424 (1.7x) | 1 |
| EMPTY FAR 17x14 | 3_964_506 (7.0x) | 6_269_976 (11.0x) | 4_711_706 (8.3x) | 19 | 1_125_953 (2.0x) | 19 / 19 | 1_132_860 (2.0x) | 1 |
| CAVE NEAR 17x14 | 473_914 (4.2x) | 392_184 (3.5x) | 368_244 (3.3x) | 3 | 237_247 (2.1x) | 3 / 3 | 198_417 (1.8x) | 1 |
| CAVE FAR 17x14 | 13_438_391 (19.0x) | 12_255_881 (17.4x) | 18_318_801 (25.9x) | 69 | 2_846_397 (4.0x) | 53 / 29 | 5_924_221 (8.4x) | 22 |
| MAZE NEAR 17x14 | 243_163 (2.4x) | 219_743 (2.1x) | 234_523 (2.3x) | 3 | 207_117 (2.0x) | 3 / 3 | 180_474 (1.8x) | 1 |
| MAZE FAR 17x14 | 7_420_844 (4.9x) | 6_230_994 (4.1x) | 7_242_454 (4.8x) | 90 | 4_287_755 (2.8x) | 81 / 53 | 30_241_295 (19.9x) | 39 |
| SERPENTINE NEAR 17x14 | 280_186 (2.7x) | 237_936 (2.3x) | 254_676 (2.5x) | 3 | 215_477 (2.1x) | 3 / 3 | 180_634 (1.8x) | 1 |
| SERPENTINE FAR 17x14 | 7_021_471 (2.8x) | 6_385_261 (2.5x) | 7_184_491 (2.8x) | 94 | 4_983_388 (2.0x) | 94 / 90 | 100_641_557 (39.7x) | 81 |
| UNREACHABLE NEAR 17x14 | 18_717_394 (70.3x) | 17_377_224 (65.3x) | 35_567_134 (133.7x) | 84 | 3_878_363 (14.6x) | 84 / 0 | 3_749_462 (14.1x) | 19 |
| UNREACHABLE FAR 17x14 | 21_851_214 (83.0x) | 28_371_344 (107.7x) | 60_003_474 (227.9x) | 84 | 3_863_143 (14.7x) | 84 / 0 | 3_040_664 (11.5x) | 7 |
| EMPTY NEAR 7x7 | 484_117 (5.9x) | 405_967 (4.9x) | 373_777 (4.5x) | 3 | 221_327 (2.7x) | 3 / 3 | 176_944 (2.2x) | 1 |
| EMPTY FAR 7x7 | 932_187 (7.1x) | 862_897 (6.6x) | 773_997 (5.9x) | 6 | 371_940 (2.8x) | 6 / 6 | 340_814 (2.6x) | 1 |
| CAVE NEAR 7x7 | 514_800 (6.3x) | 436_250 (5.4x) | 387_040 (4.7x) | 3 | 223_437 (2.7x) | 3 / 3 | 176_214 (2.2x) | 1 |
| CAVE FAR 7x7 | 886_461 (6.7x) | 768_271 (5.8x) | 720_191 (5.5x) | 6 | 368_750 (2.8x) | 6 / 6 | 341_564 (2.6x) | 1 |
| MAZE NEAR 7x7 | 278_516 (3.6x) | 236_266 (3.0x) | 253_006 (3.2x) | 3 | 214_307 (2.7x) | 3 / 3 | 201_826 (2.6x) | 2 |
| MAZE FAR 7x7 | 1_108_731 (4.6x) | 996_071 (4.2x) | 1_110_001 (4.6x) | 15 | 822_409 (3.4x) | 15 / 13 | 1_930_180 (8.0x) | 12 |
| SERPENTINE NEAR 7x7 | 277_076 (3.4x) | 234_826 (2.9x) | 251_566 (3.1x) | 3 | 211_867 (2.6x) | 3 / 3 | 176_194 (2.2x) | 1 |
| SERPENTINE FAR 7x7 | 1_315_077 (5.1x) | 1_134_927 (4.4x) | 1_301_137 (5.1x) | 16 | 857_620 (3.3x) | 16 / 14 | 2_271_018 (8.8x) | 9 |
| UNREACHABLE NEAR 7x7 | 1_345_264 (19.8x) | 1_005_804 (14.8x) | 1_407_464 (20.7x) | 10 | 507_639 (7.5x) | 10 / 0 | 452_488 (6.7x) | 5 |
| UNREACHABLE FAR 7x7 | 1_338_894 (14.9x) | 1_002_184 (11.2x) | 1_366_464 (15.2x) | 10 | 517_589 (5.8x) | 10 / 0 | 550_408 (6.1x) | 3 |
| EMPTY D1 17x14 | 100_685 (1.6x) | 91_045 (1.5x) | 91_045 (1.5x) | 1 | 104_395 (1.7x) | 1 / 1 | 143_193 (2.3x) | 2 |
| EMPTY D2 17x14 | 305_194 (3.9x) | 249_704 (3.2x) | 238_494 (3.0x) | 2 | 173_146 (2.2x) | 2 / 2 | 139_117 (1.8x) | 1 |
| EMPTY D5 17x14 | 965_682 (5.8x) | 959_462 (5.8x) | 766_732 (4.6x) | 5 | 348_399 (2.1x) | 5 / 5 | 316_814 (1.9x) | 1 |
| EMPTY D10 17x14 | 2_216_722 (7.1x) | 3_057_872 (9.8x) | 2_061_722 (6.6x) | 10 | 640_474 (2.0x) | 10 / 10 | 620_594 (2.0x) | 1 |
| CAVE D1 17x14 | 100_685 (1.7x) | 91_045 (1.5x) | 91_045 (1.5x) | 1 | 104_395 (1.7x) | 1 / 1 | 140_823 (2.3x) | 2 |
| CAVE D2 17x14 | 304_124 (3.9x) | 248_634 (3.2x) | 237_424 (3.1x) | 2 | 172_026 (2.2x) | 2 / 2 | 131_187 (1.7x) | 1 |
| CAVE D5 17x14 | 1_673_960 (7.6x) | 1_724_180 (7.8x) | 1_582_350 (7.2x) | 10 | 509_132 (2.3x) | 8 / 7 | 565_461 (2.6x) | 3 |
| CAVE D10 17x14 | 3_130_890 (8.4x) | 3_557_340 (9.6x) | 3_497_470 (9.4x) | 18 | 927_990 (2.5x) | 16 / 13 | 898_735 (2.4x) | 3 |

### Where the gas goes (microbenchmarks)

100 positions (119 down to 20 of 17x14, target 202), per op = `(test - bench_astar_micro_loop) /
100`; `log2` and `expand` also subtract the `POW128` lookup of `bench_astar_micro_bit`.

| Piece | Test | Measured | Budget | Per op |
|---|---|---:|---:|---:|
| Loop | `bench_astar_micro_loop` | 173_756 | 183_000 | |
| `POW128` lookup | `bench_astar_micro_bit` | 300_756 | 316_000 | 1_270 |
| Index of a one-hot limb (`LOG[bit mod 131]`, `bounded_int` division) | `bench_astar_micro_log2` | 528_756 | 556_000 | 2_280 |
| Coordinates, `u8` `DivRem` by `2W` (loser) | `bench_astar_micro_coords` | 477_206 | 502_000 | 3_035 |
| **Coordinates, `bounded_int` division and sign** | `bench_astar_micro_coords_bounded` | 455_056 | 478_000 | 2_813 |
| Classes with checked `u8` operations (loser), coordinates excluded | `bench_astar_micro_classes` | 1_165_186 | 1_224_000 | 6_880 |
| **Classes with `bounded_int` sums, differences and signs**, coordinates excluded | `bench_astar_micro_classes_bounded` | 882_416 | 927_000 | 4_274 |
| **Whole expansion** (index, coordinates, classes, 3 products, limb conversions, 7 to 12 bitwise, bucket updates) | `bench_astar_micro_expand` | 2_514_322 | 2_641_000 | 22_136 |

Per expanded tile, `Astar::search` pays the expansion (22.1k) plus 13k for the pop, the log, the
loop and the backtracking: 35.5k, about 320 CASM steps (`--tracked-resource cairo-steps`: 319
steps, 33 range checks, 9 bitwise applications per tile). A BFS layer is 110 steps and advances
the whole frontier. Even on EMPTY, where A* expands exactly the path, one expansion (35.5k) costs
more than one BFS layer plus one backtracking step (19.3k + 8.4k).

### Iterations on `Astar::search`

| Version | EMPTY far | CAVE far | EMPTY near | EMPTY d5 |
|---|---:|---:|---:|---:|
| v1: buckets as limb pairs in structs, classes by checked `u8` operations, `f` in `u8` | 854_603 | 3_364_829 | 148_079 | 241_697 |
| v2: buckets as 10 `u128` locals, constants in a `Box`, classes on one limb when the neighbourhood fits (`try_into` instead of 3 wide conversions, 7 bitwise instead of 12) | 742_588 | 3_024_334 | 143_529 | 225_727 |
| v3: classes and coordinates with `bounded_int`, `h`, `g`, `f` as felts | 670_788 | 2_730_794 | 135_849 | 207_327 |
| v4: state in a struct, step inlined, loop unrolled twice | 676_856 | 2_765_412 | 132_877 | 205_485 |
| **v5 = final: chained backtracking** (a closer neighbour of the previous entry skips the neighbour scan) | **661_956** | **2_806_132** | **132_457** | **203_385** |

v4 (+0.9 % / -2.2 %) and v5 (-2.2 % / +1.5 %) are two consecutive ideas under 2 %: the iteration
stopped. Not tried: coordinates carried along the chain of closer neighbours instead of the index
and the division. Its measured ceiling (index 2.3k + coordinates 2.8k per expansion, all 19
expansions) takes EMPTY far to 565k at best, -0.8 % against `Bfs::search`: under 5 %.

The tie-break matters on caves: the heap, which orders a bucket exactly by `h`, expands 10 and 18
tiles on CAVE d5 and d10 where the buckets expand 15 and 22 (69 both on CAVE far). With the
heap's counts, the buckets would still cost about 380k and 660k (26k + 35.5k per expanded tile)
against 221k and 372k.

### Sierra code size

Statements of the function and every function it calls, test build.

| Formulation | Statements |
|---|---:|
| `Bfs::search` | 23_061 |
| **`Astar::search`** (bitmap buckets) | 11_552 |
| `variant_heap` (`search_queue` with `DictHeap`) | 7_918 |
| `variant_sorted` | 6_824 |
| `variant_scan` | 7_030 |
| `variant_greedy` | 6_269 |
| `variant_pruned` | 10_688 |

### Reference `origami_map`

`scarb test -p origami_map -f astar` (cairo-test estimate, square grid, 4 directions):
`test_astar_search_large` (18x14, 17-tile path) 17_888_210, `test_astar_search_medium` (4x4, 7
tiles) 2_399_452. `Astar::search` on EMPTY far 17x14 (19 tiles) costs 661_956, 27x less; on CAVE
far (24 tiles, 69 expanded) 2_806_132, 6.4x less.

### Decision

* **Not exported.** `Astar::search` loses to `Bfs::search` on every realistic class: +16 % to
  +24 % on open boards (EMPTY far, d2 to d10, near pairs), +17 % to +297 % on caves, +20 % to
  +160 % on mazes and serpentines, 4x to 11x on unreachable targets (it closes the whole
  component tile by tile, the BFS floods it by layers). Boards of at most 128 bits are worse still
  (+47 % to +480 %): the BFS has a single-limb path there.
* **Only adjacent endpoints** favour it: -7.9 % (EMPTY d1) and -6.6 % (CAVE d1). The gain is the
  prologue (no dilation constants: about 26k of fixed cost against about 55k), not the search; one
  step is not a realistic search class.
* **Open lists**: the bitmap buckets win. A `Felt252Dict` heap, a sorted array and a scanned array
  pay a push per neighbour and an index per popped entry: 1.5x to 228x the BFS.
* **Greedy best-first** is not cheaper to run: 1.7x to 15x the BFS, paths 21 % (CAVE far, 29 vs
  24) and 8 % (CAVE d10, 13 vs 12) longer.
* **Pruned BFS**: pruning does not reduce the number of layers, which is what a BFS pays for, and
  the balls cost one dilation each: 1.7x to 40x the BFS (iterative deepening repeats the search
  81 times on SERPENTINE far).

### Budgets

Measured: the tables above; budget = `ceil(1.05 * measured, 1000)`.

| Pair (`bench_astar_<column>_<pair>`) | `search` | `variant_heap` | `variant_sorted` | `variant_scan` | `variant_greedy` | `variant_pruned` |
|---|---:|---:|---:|---:|---:|---:|
| `empty_near_17x14` | 140_000 | 554_000 | 472_000 | 419_000 | 241_000 | 192_000 |
| `empty_far_17x14` | 696_000 | 4_163_000 | 6_584_000 | 4_948_000 | 1_183_000 | 1_190_000 |
| `cave_near_17x14` | 138_000 | 498_000 | 412_000 | 387_000 | 250_000 | 209_000 |
| `cave_far_17x14` | 2_947_000 | 14_111_000 | 12_869_000 | 19_235_000 | 2_989_000 | 6_221_000 |
| `maze_near_17x14` | 130_000 | 256_000 | 231_000 | 247_000 | 218_000 | 190_000 |
| `maze_far_17x14` | 3_741_000 | 7_792_000 | 6_543_000 | 7_605_000 | 4_503_000 | 31_754_000 |
| `serpentine_near_17x14` | 130_000 | 295_000 | 250_000 | 268_000 | 227_000 | 190_000 |
| `serpentine_far_17x14` | 4_202_000 | 7_373_000 | 6_705_000 | 7_544_000 | 5_233_000 | 105_674_000 |
| `unreachable_near_17x14` | 3_191_000 | 19_654_000 | 18_247_000 | 37_346_000 | 4_073_000 | 3_937_000 |
| `unreachable_far_17x14` | 3_006_000 | 22_944_000 | 29_790_000 | 63_004_000 | 4_057_000 | 3_193_000 |
| `empty_near_7x7` | 128_000 | 509_000 | 427_000 | 393_000 | 233_000 | 186_000 |
| `empty_far_7x7` | 230_000 | 979_000 | 907_000 | 813_000 | 391_000 | 358_000 |
| `cave_near_7x7` | 127_000 | 541_000 | 459_000 | 407_000 | 235_000 | 186_000 |
| `cave_far_7x7` | 230_000 | 931_000 | 807_000 | 757_000 | 388_000 | 359_000 |
| `maze_near_7x7` | 138_000 | 293_000 | 249_000 | 266_000 | 226_000 | 212_000 |
| `maze_far_7x7` | 654_000 | 1_165_000 | 1_046_000 | 1_166_000 | 864_000 | 2_027_000 |
| `serpentine_near_7x7` | 127_000 | 291_000 | 247_000 | 265_000 | 223_000 | 186_000 |
| `serpentine_far_7x7` | 661_000 | 1_381_000 | 1_192_000 | 1_367_000 | 901_000 | 2_385_000 |
| `unreachable_near_7x7` | 414_000 | 1_413_000 | 1_057_000 | 1_478_000 | 534_000 | 476_000 |
| `unreachable_far_7x7` | 388_000 | 1_406_000 | 1_053_000 | 1_435_000 | 544_000 | 578_000 |
| `empty_d1_17x14` | 60_000 | 106_000 | 96_000 | 96_000 | 110_000 | 151_000 |
| `empty_d2_17x14` | 103_000 | 321_000 | 263_000 | 251_000 | 182_000 | 147_000 |
| `empty_d5_17x14` | 214_000 | 1_014_000 | 1_008_000 | 806_000 | 366_000 | 333_000 |
| `empty_d10_17x14` | 400_000 | 2_328_000 | 3_211_000 | 2_165_000 | 673_000 | 652_000 |
| `cave_d1_17x14` | 60_000 | 106_000 | 96_000 | 96_000 | 110_000 | 148_000 |
| `cave_d2_17x14` | 100_000 | 320_000 | 262_000 | 250_000 | 181_000 | 138_000 |
| `cave_d5_17x14` | 657_000 | 1_758_000 | 1_811_000 | 1_662_000 | 535_000 | 594_000 |
| `cave_d10_17x14` | 946_000 | 3_288_000 | 3_736_000 | 3_673_000 | 975_000 | 944_000 |

| Test | Measured | Budget |
|---|---:|---:|
| `bench_astar_bfs_empty_d1_17x14` | 62_023 | 66_000 |
| `bench_astar_bfs_empty_d2_17x14` | 79_109 | 84_000 |
| `bench_astar_bfs_empty_d5_17x14` | 165_609 | 174_000 |
| `bench_astar_bfs_empty_d10_17x14` | 313_179 | 329_000 |
| `bench_astar_bfs_cave_d1_17x14` | 60_350 | 64_000 |
| `bench_astar_bfs_cave_d2_17x14` | 77_756 | 82_000 |
| `bench_astar_bfs_cave_d5_17x14` | 221_088 | 233_000 |
| `bench_astar_bfs_cave_d10_17x14` | 371_744 | 391_000 |

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
| `bench_dial_empty_17x14` | 1_167_355 | 1_245_000 | 20 | 20 |
| **`bench_dial_cave_17x14`** (target < 1.5M) | **1_406_744** | 1_500_000 | 24 | 25 |
| `bench_dial_cave_17x14_near` | 283_435 | 305_000 | 4 | 4 |
| `bench_dial_maze_17x14` | 3_318_087 | 3_534_000 | 53 | 74 |
| `bench_dial_serpentine_17x14` | 5_027_629 | 5_350_000 | 90 | 125 |
| `bench_dial_unreachable_17x14` (floods the component) | 666_920 | 716_000 | 0 | |
| `bench_dial_cave_17x14_classes_0` (unit-cost loop) | 918_341 | 986_000 | 24 | 24 |
| `bench_dial_cave_17x14_classes_1` | 1_372_784 | 1_464_000 | 24 | 25 |
| `bench_dial_cave_17x14_classes_3` | 1_443_264 | 1_538_000 | 24 | |
| `bench_dial_empty_17x14_classes_0` | 746_887 | 802_000 | 19 | 19 |
| `bench_dial_maze_17x14_classes_0` | 1_964_638 | 2_106_000 | 53 | 53 |
| `bench_dial_serpentine_17x14_classes_0` | 3_227_567 | 3_459_000 | 90 | 90 |
| `bench_dial_cave_7x7` (`u128` path) | 290_637 | 314_000 | | |
| `bench_dial_cave_7x7_classes_0` (`u128` path) | 167_668 | 185_000 | | |
| `bench_dial_field_cave_17x14_budget_8` | 326_895 | 353_000 | | |

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
| `bench_caver_generate_17x14_order_1` | 72_717 | 80_000 | + `Layout::new` and 1 generation |
| **`bench_caver_generate_17x14_order_3`** | **143_737** | 155_000 | target < 250k |
| `bench_caver_generate_17x14_order_5` | 215_557 | 230_000 | |
| `bench_caver_generate_19x13_order_3` | 144_237 | 155_000 | |
| `bench_caver_generate_7x7_order_0` | 27_157 | 29_000 | |
| `bench_caver_generate_7x7_order_1` | 50_957 | 54_000 | single-limb path |
| `bench_caver_generate_7x7_order_3` | 83_017 | 91_000 | single-limb path |
| `bench_caver_keep_component_17x14` | 284_161 | 299_000 | cave of `generate(17, 14, 3, 'CAVER')` |
| `bench_caver_keep_component_maze_17x14` | 1_113_013 | 1_169_000 | `MAZE_17X14` fixture |
| `bench_caver_keep_component_serpentine_17x14` | 1_840_935 | 1_933_000 | `SERPENTINE_17X14` fixture |
| `bench_caver_generate_connected_17x14` | 412_358 | 454_000 | `generate` + `keep_component` |

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
| `bench_mazer_17x14_order_0` (target < 3M) | 2_900_244 | 3_020_000 | 89 | 32_314 |
| `bench_mazer_17x14_order_1` | 1_499_695 | 1_575_000 | 46 | 39_710 |
| `bench_mazer_17x14_order_0_seeds` (seeds 0..7) | 23_068_131 | 24_752_000 | 729 | 32_336 |
| `bench_mazer_17x14_order_1_seeds` (seeds 0..7) | 13_857_147 | 14_551_000 | 385 | 38_434 |
| `bench_mazer_7x7_order_0` | 516_043 | 551_000 | | |
| `bench_mazer_19x13_order_0` | 2_890_702 | 3_036_000 | | |
| `bench_digger_corridor_17x14` (3x2 room, entrance (3, 0)) | 310_722 | 331_000 | 9 | 34_984 |
| `bench_digger_maze_17x14` (same) | 3_094_676 | 3_392_000 | 90 | 35_885 |

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
| **Library: per-direction code (`Heading`), static turns (winner)** | `bench_mazer_17x14_order_0` | 2_900_244 | 3_020_000 | 32_314 | -4.4 % |
| Base: runtime direction dispatch | `bench_mazer_variant_base_17x14` | 3_075_284 | 3_158_000 | 33_785 | |
| Base, order 1 (library: 1_826_661, -5.3 %) | `bench_mazer_variant_base_17x14_order_1` | 1_590_225 | 1_670_000 | 41_921 | |
| Explicit stack (`Felt252Dict<Nullable<Frame>>`) | `bench_mazer_variant_stack_17x14` | 4_650_884 | 4_771_000 | 51_047 | +51.1 % |
| Per-neighbour bit tests (`Bits::get`, early exit) | `bench_mazer_variant_bits_17x14` | 9_758_598 | 10_116_000 | 108_244 | +220.4 % |
| Maze kept as `felt252`, set by addition | `bench_mazer_variant_felt_17x14` | 3_129_874 | 3_218_000 | 34_427 | +1.9 % |
| Index tracked, `(x, y)` by `DivRem` once per tile | `bench_mazer_variant_divrem_17x14` | 3_451_774 | 3_549_000 | 37_969 | +12.4 % |
| Base, 8 seeds (729 tiles) | `bench_mazer_variant_base_17x14_seeds` | 24_490_061 | 25_897_000 | 33_831 | |
| One draw of 3, rotation of (L, F, R) (719 tiles) | `bench_mazer_variant_rotation_17x14_seeds` | 23_063_045 | 24_326_000 | 32_222 | -4.8 % |
| Lazy draws: 3, then 2 if the first fails (726 tiles) | `bench_mazer_variant_lazy_17x14_seeds` | 26_181_248 | 27_706_000 | 36_344 | +7.4 % |
| `Rng::shuffle6` per tile, non forward skipped (727 tiles) | `bench_mazer_variant_shuffle_17x14_seeds` | 72_986_841 | 77_306_000 | 101_272 | +199.4 % |

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
| `bench_walker_17x14_0` | 34_901 | 39_000 | |
| `bench_walker_17x14_50` | 294_005 | 317_000 | 5_307 |
| `bench_walker_17x14_200` | 970_779 | 1_052_000 | 4_827 |
| `bench_walker_17x14_500` | 2_411_657 | 2_591_000 | 4_862 |
| `bench_walker_17x14_504` | 2_406_413 | 2_587_000 | 4_815 |
| `bench_walker_7x7_50` | 294_305 | 318_000 | |
| `bench_walker_7x7_200` | 962_659 | 1_045_000 | |
| `bench_walker_19x13_200` | 972_589 | 1_060_000 | |
| `bench_walker_3x3_50` (every move blocked) | 297_365 | 321_000 | |

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
| | **Winner (harness copy)** | `bench_walker_variant_winner` | 2_655_493 | 2_791_000 | 5_272 | |
| Random | `Rng::next_below(6)` per move | `bench_walker_variant_random_next_below` | 3_500_126 | 3_676_000 | 7_771 | +47.4 % |
| Random | 3-bit digits, rejection of 6 and 7 | `bench_walker_variant_random_octal` | 6_365_836 | 6_686_000 | 12_634 | +139.6 % |
| Random | one draw in `0..36` per two moves (36-arm table) | `bench_walker_variant_random_pairs` | 2_853_829 | 2_999_000 | 5_666 | +7.5 % |
| Move | `(x, y)` incremental, parity bool, per-parity deltas | `bench_walker_variant_move_coords` | 2_705_113 | 2_843_000 | 5_371 | +1.9 % |
| Move | index arithmetic (`DirectionTrait::next`), test `2^i & INTERIOR` | `bench_walker_variant_move_index_mask` | 5_949_325 | 6_249_000 | 11_808 | +124.0 % |
| Move | one-hot, per-parity offset table, interior test = one AND | `bench_walker_variant_move_one_hot_and` | 4_553_237 | 4_783_000 | 9_038 | +71.4 % |
| Grid | OR each step into a `u256`, one conversion at the end | `bench_walker_variant_grid_or_each` | 3_611_395 | 3_794_000 | 7_169 | +36.0 % |
| Grid | OR each step on a felt grid (`u256` round trip) | `bench_walker_variant_grid_or_felt` | 4_464_835 | 4_690_000 | 8_862 | +68.1 % |
| Grid | bit test, add only when unset | `bench_walker_variant_grid_test_add` | 4_515_275 | 4_743_000 | 8_962 | +70.0 % |
| Grid | batch of three, low-limb OR when the batch fits | `bench_walker_variant_grid_limb` | 2_755_538 | 2_896_000 | 5_471 | +3.8 % |
| Loop | 3 moves per iteration | `bench_walker_variant_loop_3` | 3_444_593 | 3_619_000 | 6_838 | +29.7 % |
| Loop | 6 moves per iteration | `bench_walker_variant_loop_6` | 2_971_133 | 3_122_000 | 5_898 | +11.9 % |
| Loop | 12 moves per iteration | `bench_walker_variant_loop_12` | 2_734_403 | 2_873_000 | 5_429 | +3.0 % |
| Loop | 36 moves per iteration (one pool) | `bench_walker_variant_loop_36` | 2_576_493 | 2_708_000 | 5_115 | -3.0 % |
| Loop | 12 moves per iteration, table inlined | `bench_walker_variant_loop_12_inline` | 2_677_283 | 2_813_000 | 5_315 | +0.8 % |
| Loop | 36 moves per iteration, table inlined | `bench_walker_variant_loop_36_inline` | 2_519_373 | 2_648_000 | 5_002 | -5.1 % |
| All | naive: one move per iteration, `next_below`, `(x, y)`, OR each step | `bench_walker_variant_naive` | 6_422_084 | 6_744_000 | 13_676 | +159.4 % |

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
The library runs 256 seeds (64 in the pull-request CI job since P1, see the top of this file); the
losers run 32 seeds (`#[ignore]`d since P1), and their 256-seed figures below come from the same
tests with `runs: 256` (measured once). `first version`
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
| `bench_spreader_floyd_cave_17x14_1` | 32 | 1_281_546 | 1_352_000 |
| `bench_spreader_floyd_cave_17x14_20` | 32 | 1_580_827 | 1_664_000 |
| `bench_spreader_floyd_cave_17x14_5` | 32 | 1_358_270 | 1_433_000 |
| `bench_spreader_floyd_cave_17x14_60` | 32 | 2_171_021 | 2_281_000 |
| `bench_spreader_floyd_cave_7x7_1` | 32 | 325_800 | 348_000 |
| `bench_spreader_floyd_cave_7x7_20` | 32 | 355_106 | 379_000 |
| `bench_spreader_floyd_cave_7x7_5` | 32 | 384_012 | 410_000 |
| `bench_spreader_floyd_empty_17x14_1` | 32 | 1_748_502 | 1_842_000 |
| `bench_spreader_floyd_empty_17x14_20` | 32 | 2_034_321 | 2_139_000 |
| `bench_spreader_floyd_empty_17x14_5` | 32 | 1_779_946 | 1_875_000 |
| `bench_spreader_floyd_empty_17x14_60` | 32 | 2_630_465 | 2_763_000 |
| `bench_spreader_floyd_empty_7x7_1` | 32 | 343_812 | 367_000 |
| `bench_spreader_floyd_empty_7x7_20` | 32 | 402_324 | 429_000 |
| `bench_spreader_floyd_empty_7x7_5` | 32 | 402_224 | 429_000 |
| `bench_spreader_floyd_maze_17x14_1` | 32 | 947_674 | 1_001_000 |
| `bench_spreader_floyd_maze_17x14_20` | 32 | 1_226_762 | 1_294_000 |
| `bench_spreader_floyd_maze_17x14_5` | 32 | 1_006_086 | 1_063_000 |
| `bench_spreader_floyd_maze_17x14_60` | 32 | 1_405_360 | 1_480_000 |
| `bench_spreader_floyd_maze_7x7_1` | 32 | 262_758 | 282_000 |
| `bench_spreader_floyd_maze_7x7_16` | 32 | 105_138 | 111_000 |
| `bench_spreader_floyd_maze_7x7_5` | 32 | 320_920 | 343_000 |
| `bench_spreader_generate_cave_17x14_1` | 256 | 186_639 | 196_000 |
| `bench_spreader_generate_cave_17x14_20` | 256 | 291_588 | 307_000 |
| `bench_spreader_generate_cave_17x14_5` | 256 | 320_687 | 337_000 |
| `bench_spreader_generate_cave_17x14_60` | 256 | 305_451 | 321_000 |
| `bench_spreader_generate_cave_7x7_1` | 256 | 161_121 | 170_000 |
| `bench_spreader_generate_cave_7x7_20` | 256 | 208_954 | 231_000 |
| `bench_spreader_generate_cave_7x7_5` | 256 | 221_614 | 233_000 |
| `bench_spreader_generate_d30_17x14_1` | 256 | 162_113 | 171_000 |
| `bench_spreader_generate_d30_17x14_20` | 256 | 282_016 | 297_000 |
| `bench_spreader_generate_d30_17x14_5` | 256 | 291_349 | 322_000 |
| `bench_spreader_generate_d30_17x14_60` | 256 | 297_015 | 312_000 |
| `bench_spreader_generate_empty_17x14_1` | 256 | 186_639 | 196_000 |
| `bench_spreader_generate_empty_17x14_20` | 256 | 330_186 | 347_000 |
| `bench_spreader_generate_empty_17x14_5` | 256 | 361_304 | 380_000 |
| `bench_spreader_generate_empty_17x14_60` | 256 | 322_940 | 340_000 |
| `bench_spreader_generate_empty_7x7_1` | 256 | 161_121 | 170_000 |
| `bench_spreader_generate_empty_7x7_20` | 256 | 221_964 | 234_000 |
| `bench_spreader_generate_empty_7x7_5` | 256 | 221_624 | 233_000 |
| `bench_spreader_generate_maze_17x14_1` | 256 | 186_639 | 196_000 |
| `bench_spreader_generate_maze_17x14_20` | 256 | 300_718 | 316_000 |
| `bench_spreader_generate_maze_17x14_5` | 256 | 291_749 | 307_000 |
| `bench_spreader_generate_maze_17x14_60` | 256 | 297_112 | 312_000 |
| `bench_spreader_generate_maze_7x7_1` | 256 | 161_121 | 170_000 |
| `bench_spreader_generate_maze_7x7_16` | 256 | 103_059 | 112_000 |
| `bench_spreader_generate_maze_7x7_5` | 256 | 202_811 | 224_000 |
| `bench_spreader_generate_sparse2_10x25_1` | 256 | 131_176 | 143_000 |
| `bench_spreader_generate_sparse5_17x14_1` | 256 | 145_545 | 158_000 |
| `bench_spreader_generate_sparse5_17x14_2` | 256 | 145_445 | 158_000 |
| `bench_spreader_mask_cave_17x14_1` | 32 | 161_484 | 170_000 |
| `bench_spreader_mask_cave_17x14_20` | 32 | 785_220 | 825_000 |
| `bench_spreader_mask_cave_17x14_5` | 32 | 323_110 | 340_000 |
| `bench_spreader_mask_cave_17x14_60` | 32 | 632_676 | 665_000 |
| `bench_spreader_mask_cave_7x7_1` | 32 | 230_445 | 254_000 |
| `bench_spreader_mask_cave_7x7_20` | 32 | 394_867 | 415_000 |
| `bench_spreader_mask_cave_7x7_5` | 32 | 557_052 | 585_000 |
| `bench_spreader_mask_empty_17x14_1` | 32 | 151_561 | 160_000 |
| `bench_spreader_mask_empty_17x14_20` | 32 | 407_537 | 416_000 |
| `bench_spreader_mask_empty_17x14_5` | 32 | 262_322 | 277_000 |
| `bench_spreader_mask_empty_17x14_60` | 32 | 584_776 | 624_000 |
| `bench_spreader_mask_empty_7x7_1` | 32 | 230_445 | 254_000 |
| `bench_spreader_mask_empty_7x7_20` | 32 | 557_052 | 585_000 |
| `bench_spreader_mask_empty_7x7_5` | 32 | 557_052 | 585_000 |
| `bench_spreader_mask_maze_17x14_1` | 32 | 181_580 | 191_000 |
| `bench_spreader_mask_maze_17x14_20` | 32 | 974_065 | 1_023_000 |
| `bench_spreader_mask_maze_17x14_5` | 32 | 385_599 | 405_000 |
| `bench_spreader_mask_maze_17x14_60` | 32 | 737_190 | 775_000 |
| `bench_spreader_mask_maze_7x7_1` | 32 | 873_538 | 918_000 |
| `bench_spreader_mask_maze_7x7_16` | 32 | 126_744 | 134_000 |
| `bench_spreader_mask_maze_7x7_5` | 32 | 484_547 | 533_000 |
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
| `bench_spreader_micro_trial` |  | 118_012 | 124_000 |
| `bench_spreader_micro_walk_u256` |  | 367_430 | 386_000 |
| `bench_spreader_reject_cave_17x14_1` | 32 | 139_421 | 153_000 |
| `bench_spreader_reject_cave_17x14_20` | 32 | 688_484 | 723_000 |
| `bench_spreader_reject_cave_17x14_5` | 32 | 323_594 | 340_000 |
| `bench_spreader_reject_cave_17x14_60` | 32 | 2_055_050 | 2_083_000 |
| `bench_spreader_reject_cave_7x7_1` | 32 | 138_671 | 152_000 |
| `bench_spreader_reject_cave_7x7_20` | 32 | 234_699 | 247_000 |
| `bench_spreader_reject_cave_7x7_5` | 32 | 328_566 | 362_000 |
| `bench_spreader_reject_d30_17x14_1` | 32 | 179_613 | 195_000 |
| `bench_spreader_reject_d30_17x14_20` | 32 | 1_284_925 | 1_350_000 |
| `bench_spreader_reject_d30_17x14_5` | 32 | 364_036 | 383_000 |
| `bench_spreader_reject_d30_17x14_60` | 32 | 728_322 | 787_000 |
| `bench_spreader_reject_empty_17x14_1` | 32 | 129_248 | 142_000 |
| `bench_spreader_reject_empty_17x14_20` | 32 | 512_891 | 550_000 |
| `bench_spreader_reject_empty_17x14_5` | 32 | 210_740 | 222_000 |
| `bench_spreader_reject_empty_17x14_60` | 32 | 1_407_494 | 1_417_000 |
| `bench_spreader_reject_empty_7x7_1` | 32 | 138_671 | 152_000 |
| `bench_spreader_reject_empty_7x7_20` | 32 | 278_931 | 293_000 |
| `bench_spreader_reject_empty_7x7_5` | 32 | 278_951 | 293_000 |
| `bench_spreader_reject_maze_17x14_1` | 32 | 169_690 | 185_000 |
| `bench_spreader_reject_maze_17x14_20` | 32 | 954_585 | 1_045_000 |
| `bench_spreader_reject_maze_17x14_5` | 32 | 342_440 | 375_000 |
| `bench_spreader_reject_maze_17x14_60` | 32 | 1_541_086 | 1_659_000 |
| `bench_spreader_reject_maze_7x7_1` | 32 | 168_440 | 183_000 |
| `bench_spreader_reject_maze_7x7_16` | 32 | 94_488 | 100_000 |
| `bench_spreader_reject_maze_7x7_5` | 32 | 420_074 | 442_000 |
| `bench_spreader_reject_sparse2_10x25_1` | 32 | 4_507_725 | 4_734_000 |
| `bench_spreader_reject_sparse5_17x14_1` | 32 | 1_057_529 | 1_111_000 |
| `bench_spreader_reject_sparse5_17x14_2` | 32 | 2_426_823 | 2_549_000 |
| `bench_spreader_selection_cave_17x14_1` | 32 | 1_258_901 | 1_357_000 |
| `bench_spreader_selection_cave_17x14_20` | 32 | 1_303_033 | 1_366_000 |
| `bench_spreader_selection_cave_17x14_5` | 32 | 1_290_243 | 1_359_000 |
| `bench_spreader_selection_cave_17x14_60` | 32 | 1_320_633 | 1_385_000 |
| `bench_spreader_selection_cave_7x7_1` | 32 | 308_059 | 328_000 |
| `bench_spreader_selection_cave_7x7_20` | 32 | 308_919 | 329_000 |
| `bench_spreader_selection_cave_7x7_5` | 32 | 309_819 | 330_000 |
| `bench_spreader_selection_empty_17x14_1` | 32 | 1_743_035 | 1_831_000 |
| `bench_spreader_selection_empty_17x14_20` | 32 | 1_751_395 | 1_835_000 |
| `bench_spreader_selection_empty_17x14_5` | 32 | 1_744_795 | 1_828_000 |
| `bench_spreader_selection_empty_17x14_60` | 32 | 1_768_995 | 1_853_000 |
| `bench_spreader_selection_empty_7x7_1` | 32 | 317_002 | 346_000 |
| `bench_spreader_selection_empty_7x7_20` | 32 | 327_685 | 348_000 |
| `bench_spreader_selection_empty_7x7_5` | 32 | 327_705 | 348_000 |
| `bench_spreader_selection_maze_17x14_1` | 32 | 937_772 | 975_000 |
| `bench_spreader_selection_maze_17x14_20` | 32 | 946_132 | 993_000 |
| `bench_spreader_selection_maze_17x14_5` | 32 | 939_532 | 986_000 |
| `bench_spreader_selection_maze_17x14_60` | 32 | 951_392 | 1_001_000 |
| `bench_spreader_selection_maze_7x7_1` | 32 | 243_427 | 262_000 |
| `bench_spreader_selection_maze_7x7_16` | 32 | 99_398 | 105_000 |
| `bench_spreader_selection_maze_7x7_5` | 32 | 245_187 | 264_000 |
| `bench_spreader_u256_cave_7x7_1` | 256 | 183_409 | 193_000 |
| `bench_spreader_u256_cave_7x7_20` | 256 | 242_119 | 263_000 |
| `bench_spreader_u256_cave_7x7_5` | 256 | 258_141 | 283_000 |
| `bench_spreader_u256_empty_7x7_1` | 256 | 183_409 | 193_000 |
| `bench_spreader_u256_empty_7x7_20` | 256 | 258_691 | 283_000 |
| `bench_spreader_u256_empty_7x7_5` | 256 | 258_151 | 283_000 |
| `bench_spreader_u256_maze_7x7_1` | 256 | 183_409 | 193_000 |
| `bench_spreader_u256_maze_7x7_16` | 256 | 106_008 | 113_000 |
| `bench_spreader_u256_maze_7x7_5` | 256 | 233_426 | 254_000 |

</details>

## L8 Facade

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas). Library: `map.cairo`, benchmarks and
losing variants: `tests/bench_map.cairo`. Budgets: `ceil(1.05 * measured, 1000)`.

### Facade overhead (17x14 fixtures, facade vs direct library call on the same inputs)

Every method is `#[inline]` and forwards to one call: the overhead is zero. `hex_distance`,
`neighbor` and `is_walkable` are measured over 100 iterations with varying positions (constant
inputs are folded by the compiler); per call = `(test - bench_map_loop_baseline) / 100`, baseline
142_090.

| Function | Facade | Direct | Delta |
|---|---:|---:|---:|
| `new_empty` | 18_480 | 18_480 | +0 |
| `new_maze` | 2_873_670 | 2_873_670 | +0 |
| `new_cave` | 144_927 | 144_927 | +0 |
| `new_random_walk` | 999_629 | 999_629 | +0 |
| `new_hexagon` | 125_770 | 125_770 | +0 |
| `open_with_corridor` | 63_018 | 63_018 | +0 |
| `open_with_maze` | 61_858 | 61_858 | +0 |
| `keep_component` | 555_119 | 555_119 | +0 |
| `compute_distribution` | 206_868 | 206_868 | +0 |
| `search_path` | 706_135 | 706_135 | +0 |
| `search_path_weighted` | 1_427_654 | 1_427_654 | +0 |
| `field_of_movement` | 261_829 | 261_829 | +0 |
| `distance_to` | 501_642 | 501_642 | +0 |
| `reachable` | 555_119 | 555_119 | +0 |
| `range` | 103_793 | 103_793 | +0 |
| `hex_distance` | 1_088_280 | 1_088_280 | +0 |
| `neighbor` | 781_230 | 781_230 | +0 |
| `is_walkable` | 797_080 | 849_980 | -52_900 |

Per call: `hex_distance` 9_461, `neighbor` 6_391, `is_walkable` 6_549 (the direct loop
re-converts the constant fixture: 7_078). These three queries now check their positions against
`W * H` (audit A4): see the F1 section for the current figures and budgets.

### `keep_component`: `Bfs::reachable` (library) vs `Caver::keep_component`

| Input | `Bfs::reachable` | `Caver::keep_component` | Delta |
|---|---:|---:|---:|
| CAVE 17x14 | 555_119 | 580_303 | -4.3 % |
| MAZE 17x14 | 1_152_663 | 1_243_447 | -7.3 % |
| CAVE 7x7 | 102_333 | 168_195 | -39.2 % |

`Bfs::reachable` also keeps the open edge tiles next to the component (entrances); on grids
without open edge tiles both return the same bitmap (`test_map_keep_component`).

### `ring`: one flood (library) vs two `range` calls

The library floods `radius - 2` layers, which returns the balls of radius `radius - 1` and
`radius - 2`; one dilation of the first gives the interior ring, and the open edge tiles next to
the first ball but not to the second are the edge tiles of the ring (one more dilation, only when
the grid has open edge tiles). An open edge centre falls back to two `range` calls.

| Input | One flood | Two `range` | Delta |
|---|---:|---:|---:|
| CAVE 17x14, radius 4 | 99_903 | 176_300 | -43.3 % |
| CAVE 7x7, radius 2 | 46_403 | 79_688 | -41.8 % |
| CAVE 17x14 + corridor from 8 (open edge), radius 4, corridor included | 167_673 | 269_474 | -37.8 % |

A first version (one flood of `radius - 1` layers, two `range` calls whenever the grid had an open
edge tile) measured 102_703 on CAVE 17x14: the current form is 2.7 % cheaper there and removes the
fallback on opened maps.

### End-to-end scenario

`new_cave(3)` + `keep_component` + `open_with_corridor(order 0)` + `compute_distribution(10)` +
`search_path` from the entrance. 17x14: seed `'SEED'`, keep 113, entrance 8, target 202 (path of
15). 7x7: seed `'ORIGAMI'`, keep 24, entrance 27, target 8 (path of 6). One test per prefix; step =
difference of two consecutive prefixes.

| Step | 17x14 prefix | 17x14 step | 7x7 prefix | 7x7 step |
|---|---:|---:|---:|---:|
| `new_cave` | 144_927 | 144_927 | 83_807 | 83_807 |
| `keep_component` | 334_234 | 189_307 | 141_856 | 58_049 |
| `open_with_corridor` | 497_448 | 163_214 | 189_617 | 47_761 |
| `compute_distribution(10)` | 686_493 | 189_045 | 308_662 | 119_045 |
| `search_path` (total) | 1_162_931 | 476_438 | 485_618 | 176_956 |

`origami_map` 18x14, same scenario without `keep_component` (cave order 3 on
`Seeder::shuffle('S33D', 'S33D')`, corridor from 1, 10 objects, path from 1 to 196 of 25 steps),
`scarb test -p origami_map` (cairo-test estimate), test not committed:

| Step | Prefix | Step |
|---|---:|---:|
| `new_cave` | 126_037_752 | 126_037_752 |
| `open_with_corridor` | 126_097_488 | 59_736 |
| `compute_distribution(10)` | 135_055_980 | 8_958_492 |
| `search_path` (total) | 145_829_152 | 10_773_172 |

The hex scenario costs 1.16M on 17x14, 125x less.

### Budgets

| Test | Measured | Budget |
|---|---:|---:|
| `bench_map_compute_distribution` | 206_868 | 218_000 |
| `bench_map_direct_compute_distribution` | 206_868 | 218_000 |
| `bench_map_direct_distance_to` | 501_642 | 527_000 |
| `bench_map_direct_field_of_movement` | 261_829 | 275_000 |
| `bench_map_direct_hex_distance` | 1_088_280 | 1_143_000 |
| `bench_map_direct_is_walkable` | 849_980 | 893_000 |
| `bench_map_direct_keep_component` | 555_119 | 583_000 |
| `bench_map_direct_neighbor` | 781_230 | 821_000 |
| `bench_map_direct_new_cave` | 144_927 | 153_000 |
| `bench_map_direct_new_empty` | 18_480 | 20_000 |
| `bench_map_direct_new_hexagon` | 125_770 | 133_000 |
| `bench_map_direct_new_maze` | 2_873_670 | 3_018_000 |
| `bench_map_direct_new_random_walk` | 999_629 | 1_050_000 |
| `bench_map_direct_open_with_corridor` | 63_018 | 67_000 |
| `bench_map_direct_open_with_maze` | 61_858 | 65_000 |
| `bench_map_direct_range` | 103_793 | 109_000 |
| `bench_map_direct_reachable` | 555_119 | 583_000 |
| `bench_map_direct_search_path` | 706_135 | 742_000 |
| `bench_map_direct_search_path_weighted` | 1_427_654 | 1_500_000 |
| `bench_map_distance_to` | 501_642 | 527_000 |
| `bench_map_field_of_movement` | 261_829 | 275_000 |
| `bench_map_hex_distance` | 1_088_280 | 1_143_000 |
| `bench_map_is_walkable` | 797_080 | 837_000 |
| `bench_map_keep_component` | 555_119 | 583_000 |
| `bench_map_keep_component_7x7` | 102_333 | 108_000 |
| `bench_map_keep_component_maze` | 1_152_663 | 1_211_000 |
| `bench_map_loop_baseline` | 142_090 | 150_000 |
| `bench_map_neighbor` | 781_230 | 821_000 |
| `bench_map_new_cave` | 144_927 | 153_000 |
| `bench_map_new_empty` | 18_480 | 20_000 |
| `bench_map_new_hexagon` | 125_770 | 133_000 |
| `bench_map_new_maze` | 2_873_670 | 3_018_000 |
| `bench_map_new_random_walk` | 999_629 | 1_050_000 |
| `bench_map_open_with_corridor` | 63_018 | 67_000 |
| `bench_map_open_with_maze` | 61_858 | 65_000 |
| `bench_map_range` | 103_793 | 109_000 |
| `bench_map_reachable` | 555_119 | 583_000 |
| `bench_map_ring` | 99_903 | 105_000 |
| `bench_map_ring_7x7` | 46_403 | 49_000 |
| `bench_map_ring_open_edge` | 167_673 | 177_000 |
| `bench_map_scenario_17x14_1_cave` | 144_927 | 153_000 |
| `bench_map_scenario_17x14_2_keep` | 334_234 | 351_000 |
| `bench_map_scenario_17x14_3_corridor` | 497_448 | 523_000 |
| `bench_map_scenario_17x14_4_distribution` | 686_493 | 721_000 |
| `bench_map_scenario_17x14_5_total` | 1_162_931 | 1_222_000 |
| `bench_map_scenario_7x7_1_cave` | 83_807 | 88_000 |
| `bench_map_scenario_7x7_2_keep` | 141_856 | 149_000 |
| `bench_map_scenario_7x7_3_corridor` | 189_617 | 200_000 |
| `bench_map_scenario_7x7_4_distribution` | 308_662 | 325_000 |
| `bench_map_scenario_7x7_5_total` | 485_618 | 510_000 |
| `bench_map_search_path` | 706_135 | 742_000 |
| `bench_map_search_path_weighted` | 1_427_654 | 1_500_000 |
| `bench_map_variant_keep_component_caver` | 580_303 | 610_000 |
| `bench_map_variant_keep_component_caver_7x7` | 168_195 | 177_000 |
| `bench_map_variant_keep_component_caver_maze` | 1_243_447 | 1_306_000 |
| `bench_map_variant_ring_two_ranges` | 176_300 | 186_000 |
| `bench_map_variant_ring_two_ranges_7x7` | 79_688 | 84_000 |
| `bench_map_variant_ring_two_ranges_open_edge` | 269_474 | 283_000 |

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
| `expand` on `u256` (library) | `bench_u252_expand_u256` | 2_003_410 | 2_182_000 | 18_614 |
| `expand` on `u252` (bench copy) | `bench_u252_expand` | 2_246_500 | 2_359_000 | 21_045 |
| BFS step on `u256`: `expand & U`, `U - F'` (library) | `bench_u252_step_u256` | 2_104_260 | 2_210_000 | 19_623 |
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

## P1 Commons

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas). "Before" is `main` at `7adb9c4` (all lots
L0-L7 and S1 merged), "after" is the head of the P1 pull request (rebased on the L8 facade); both from
`snforge test --package origami_hexmap --include-ignored --detailed-resources` (256 seeds).

### Shared primitives

| Helper | Origin | Used by |
|---|---|---|
| `Bits::bitwise` (AND, XOR, OR from one application, wrapper of the private libfunc), `Bits::and` / `or` / `xor` on `u256` limbs | L4, L1, L3 local `extern fn` | `Layout`, `Bfs`, `Dial`, `Caver`, benches |
| `Bits::popcount` (byte counts of both limbs summed, one byte sum), `Bits::popcount_small`, `Bits::byte_counts` | L7 | `Spreader`, tests |
| `Bits::top_byte`, `Bits::low_byte` (`bounded_int` divisions by 2^120 and 256) | P1 | `Bits::popcount`, `Spreader` |
| `Set<T>` (`WideSet` on `u256`, `SmallSet` on `u128`) | L3 | `Dial` |
| `Layout::with_interior` (layout and interior from 3 shared lookups) | L1 `constants` | `Bfs`, `Dial`, `Caver` |
| `Dilation` (4 constants) and `Dilation::dilate` / `expand_small`: the L1 dilation, up/down from `X = 2P - Pe` with one product each; `Layout::expand` / `expand_small` now run it | L1 `BfsInternal::expand` | `Bfs`, `Dial`, `Layout::expand` |
| `Layout::edge_neighbours`, `Layout::neighbour_in` (edge endpoints) | L1 `around_edge` / `enter`, L3 `seeds` / edge scan | `Bfs`, `Dial` |
| `BfsInternal::component` (flood of `Bfs::reachable` without the checks) | L1 | `Caver::keep_component` |
| `Rng::draw_byte`, `Rng::draw6`, `Rng::split216` (`bounded_int` divisions), refill below 2^64 | L6, P1 | `Spreader`, `Mazer`, `Digger`, `Walker` |

Kept local: the byte-count select of `Spreader` (one module uses it), the `Frontier<T>` dilation
and backtracking masks of `Dial` (they need the `Dilation`), the walker's pool loop (locals, both
limbs of every permutation, `Rng::split216`). `BfsInternal::and`, `expand` and `expand_small`
remained as one-line delegations to `Bits::and` and `Dilation` for `map.cairo` (L8); F1 removed
them, the facade calls `Bits::and` and `Dilation::dilate` / `expand_small` directly.

### Microbenchmarks (per op = (test - loop) / 100, loop 142_090)

| Operation | Test | Measured | Budget | Per op | Before |
|---|---|---:|---:|---:|---:|
| u128 DivRem by 6 | `bench_u128_divrem` | 298_410 | 314_000 | 1_563 | |
| **`bounded_int::div_rem` u128 by `UnitInt<6>`** | `bench_u128_divrem_bounded` | 251_880 | 265_000 | 1_098 | |
| **`bounded_int::div_rem` u128 by a runtime `NonZero<u8>`** | `bench_u128_divrem_bounded_byte` | 251_880 | 265_000 | 1_098 | |
| u8 DivRem by 17 | `bench_u8_divrem` | 251_880 | 265_000 | 1_098 | |
| `bounded_int::div_rem` u8 by `NonZero<u8>` (loser: equal) | `bench_u8_divrem_bounded` | 251_880 | 265_000 | 1_098 | |
| `Rng::draw(6)`, generic `u128` bound | `bench_rng_draw` | 562_744 | 589_000 | 4_206 | 4_186 |
| **`Rng::draw6`** | `bench_rng_draw6` | 515_744 | 542_000 | 3_737 | |
| **`Rng::next_below(6)`** (`draw_byte`) | `bench_rng_next_below` | 515_744 | 542_000 | 3_737 | 4_556 |
| `Rng::draw6` with a counter refill (loser: needs a third field) | `bench_rng_draw6_counter` | 490_295 | 515_000 | 3_482 | |
| `Rng::shuffle6` | `bench_rng_shuffle6` | 718_985 | 776_000 | 5_769 | 5_967 |
| `Bits::popcount`, 180 / 8 bits set | `bench_popcount_swar_dense` / `_sparse` | 1_486_920 / 1_496_380 | 1_562_000 / 1_572_000 | 13_448 / 13_543 | 19_038 / 19_133 |
| `Layout::expand`, 17x14 / 7x7 | `bench_expand_felt` / `_7x7` | 2_003_410 / 1_685_930 | 2_182_000 / 1_771_000 | 18_613 / 15_438 | 19_353 / 16_788 |
| `Layout::expand_small`, 7x7 | `bench_expand_small_7x7` | 923_680 | 1_002_000 | 7_816 | 8_116 |
| BFS layer step `expand & U`, `U - F'` | `bench_step_or` | 2_104_260 | 2_210_000 | 19_622 | 20_972 |

`bench_rng_draw` is 20 gas per draw dearer: the pool refilled below 2^64 serves about 24 draws
of 6 instead of 37 (one more permutation per 100 draws). The spreader micro table of L7 moves the
same way: level `u256` 21_438 -> 19_298, level `u128` 15_852 -> 13_712, popcount `u256` 16_521 ->
14_381, `u128` 11_818 -> 9_678, counts 22_811 -> 21_941, select `u256` 32_484 -> 30_721, `u128`
25_339 -> 23_659, trial 9_336 -> 8_699 (`draw_byte`); walk and deposit unchanged.

### Rng: bias, pools and draws

* **Refill threshold 2^64** (was 2^32): the draws of one pool are within `2^64 * B / 2^128` of
  independent draws, `2^-56` for `B <= 251` (was `2^-24`), `2^-54.5` for `shuffle6`. Cost on the
  generators, same code with the threshold only changed (mazer, 8 seeds): order 0 31_868 ->
  31_881 per carved tile (+0.04 %), order 1 37_967 -> 37_590: below the 2 % limit, adopted.
* **All the outputs of a permutation**: a spare pool in `Rng` (the high limb) is one more field
  carried through the recursions of `Mazer` and `Digger`: +1.9 % (order 0) and +3.0 % (order 1)
  per carved tile against the 2-field `Rng` (32_499 vs 31_881, 38_731 vs 37_590): not kept. The
  walker, whose pool lives in locals, draws 6 triples from each limb of every permutation.
* **Counter refill** (a felt counter instead of `pool < 2^64`): -6.8 % per draw in isolation
  (3_482 vs 3_737) but a third field: not kept, same reason.
* **`bounded_int::div_rem`** (owner decision): -30 % per division by a constant or by a runtime
  `NonZero<u8>` bound, the quotient and the remainder need no conversion. Kept in `draw_byte`,
  `draw6`, `shuffle6`, `split216`, `top_byte`, `low_byte`. u8 by u8 (coordinates, parity,
  distance) costs the same: not used there.

### Generators after the stream change (per unit)

| Benchmark | Before | After | Delta |
|---|---:|---:|---:|
| Mazer 17x14 order 0, 8 seeds, per tile | 32_336 (729 tiles) | 31_862 (724 tiles) | -1.5 % |
| Mazer 17x14 order 1, 8 seeds, per tile | 38_434 (385 tiles) | 37_553 (369 tiles) | -2.3 % |
| Mazer 17x14 order 0, `'SEED'`, per tile | 32_314 (89 tiles) | 32_225 (90 tiles) | -0.3 % |
| Mazer 17x14 order 1, `'SEED'`, per tile | 39_710 (46 tiles) | 37_492 (40 tiles) | -5.6 % |
| Digger corridor, per tile | 34_984 (9 tiles) | 34_525 (9 tiles) | -1.3 % |
| Digger maze, per tile | 35_885 (90 tiles) | 35_167 (88 tiles) | -2.0 % |
| Walker 17x14, 500 steps, per step | 4_862 | 4_754 | -2.2 % |

`bench_mazer_17x14_order_0` (one seed) costs 0.8 % more than before: its maze has 90 tiles
instead of 89; per tile it is 0.3 % cheaper.

### Variants measured and not kept

| Variant | Measured | Verdict |
|---|---|---|
| `Bfs` carrying the 7-field `Layout` in its loops instead of the 4-field `Dilation` | +0.4 % (17x14 far searches) to +2.6 % (7x7 ranges) | `Dilation` kept |
| `Caver::keep_component` through `Bfs::reachable` (checks, endpoint, edge tiles) | cave 300_925 -> 305_194 (+1.4 %), maze -5.2 %, serpentine -6.3 % | `BfsInternal::component` kept: -5.6 %, -10.6 %, -11.5 % |
| `Dial` target test skipped while `time < hex distance - 1` (L3 deferred item) | +0.5 % to +3.8 % (CAVE far 1_406_744 -> 1_440_828, SERPENTINE unit 3_227_567 -> 3_348_820): the `u32` comparison per step costs more than the single-limb test it saves | not kept |
| Spare pool in `Rng`, counter refill | see above | not kept |
| `bounded_int` u8 by u8 | equal | not used |

The L4 `keep_component` (dilation of the whole component, corelib operators) stays in
`bench_caver.cairo` as `keep_component_dilation`: `bench_caver_variant_keep_component_dilation_17x14`
300_162 (budget 316_000). The L0 `Layout::expand` / `expand_small` stay in `tests/variants.cairo`
(`Variants::expand_felt`, `expand_small_corelib`) for the loser benchmarks that used them.

### Not reached

* **L1 search targets on 17x14** (EMPTY far 500k, CAVE 650k, MAZE 1.4M, SERPENTINE 2.4M): the
  search benchmarks are unchanged by P1 (the promoted dilation is the L1 one, carried by the same
  4 constants). A layer is 12 bitwise applications and 4 wide felt -> `u256` conversions; the
  limb-aligned East shift needs a wall at bits 127 and 128 (not the case on 17x14: tile 128 is
  interior), and the doubling by `u128` additions was measured slower by L1.
* **Caver conversions per generation** (6 per generation): each neighbour plane crosses the limb
  boundary; the limb-wise East plane was measured +4 % by L4. No new formulation found.
* **Spreader `deposit`** (5.9k per step): unchanged; a mask walk over the set bits of the mask
  saves at most one `u8` division per step (1.1k) and adds a lowest-bit extraction per chosen
  rank. Not implemented.

### CI time

| Job | Before | After |
|---|---:|---:|
| `Test origami_hexmap` (pull requests) | 8m23s | 4m0s |
| Local, fresh build, same command | 7m55s | 2m46s |

The 100 spreader losers (`#[ignore]`) and the library fuzz benchmarks on 256 seeds run in the
non-blocking `hexmap-full` job on pushes to `main` (about 9m20s locally).

### L8 facade (merged during P1)

The `HexMap` facade (`eb0f4b1`) merged while P1 was open; its benchmarks move with the libraries
it calls. Figures of the L8 section against P1 (budgets in `tests/bench_map.cairo`, not changed
here: that file belongs to L8):

| Test | L8 | P1 | Delta | Budget |
|---|---:|---:|---:|---:|
| `bench_map_compute_distribution` | 206_868 | 193_168 | -6.6 % | 218_000 |
| `bench_map_field_of_movement` | 261_829 | 254_419 | -2.8 % | 275_000 |
| `bench_map_keep_component` | 555_119 | 536_249 | -3.4 % | 583_000 |
| `bench_map_keep_component_7x7` | 102_333 | 97_533 | -4.7 % | 108_000 |
| `bench_map_keep_component_maze` | 1_152_663 | 1_113_493 | -3.4 % | 1_211_000 |
| `bench_map_new_cave` | 144_927 | 141_917 | -2.1 % | 153_000 |
| `bench_map_new_maze` | 2_873_670 | 2_898_024 | +0.8 % | 3_018_000 |
| `bench_map_new_random_walk` | 999_629 | 968_559 | -3.1 % | 1_050_000 |
| `bench_map_reachable` | 555_119 | 536_249 | -3.4 % | 583_000 |
| `bench_map_scenario_17x14_1_cave` | 144_927 | 141_917 | -2.1 % | 153_000 |
| `bench_map_scenario_17x14_2_keep` | 334_234 | 324_254 | -3.0 % | 351_000 |
| `bench_map_scenario_17x14_3_corridor` | 497_448 | 485_218 | -2.5 % | 523_000 |
| `bench_map_scenario_17x14_4_distribution` | 686_493 | 661_983 | -3.6 % | 721_000 |
| `bench_map_scenario_17x14_5_total` | 1_162_931 | 1_138_321 | -2.1 % | 1_222_000 |
| `bench_map_scenario_7x7_1_cave` | 83_807 | 80_797 | -3.6 % | 88_000 |
| `bench_map_scenario_7x7_2_keep` | 141_856 | 135_546 | -4.4 % | 149_000 |
| `bench_map_scenario_7x7_3_corridor` | 189_617 | 183_307 | -3.3 % | 200_000 |
| `bench_map_scenario_7x7_4_distribution` | 308_662 | 294_602 | -4.6 % | 325_000 |
| `bench_map_scenario_7x7_5_total` | 485_618 | 471_458 | -2.9 % | 510_000 |
| `bench_map_search_path_weighted` | 1_427_654 | 1_406_744 | -1.5 % | 1_500_000 |
| `bench_map_variant_keep_component_caver` | 580_303 | 533_849 | -8.0 % | 610_000 |
| `bench_map_variant_keep_component_caver_7x7` | 168_195 | 95_333 | -43.3 % | 177_000 |
| `bench_map_variant_keep_component_caver_maze` | 1_243_447 | 1_111_093 | -10.6 % | 1_306_000 |

`bench_map_new_maze` costs 0.8 % more: the mazer carves 90 tiles instead of 89 on `'SEED'`. The
`Caver::keep_component` variant of the facade (`bench_map_variant_keep_component_caver*`) is now
0.4 % to 2.3 % cheaper than `Bfs::reachable`, which the facade calls (it also adds the open edge
tiles).

### Before / after, every library benchmark

#### L1 Bfs

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_bfs_distance_cave_far_17x14` | 501_942 | 501_942 | +0.0 % |
| `bench_bfs_distance_cave_far_7x7` | 88_923 | 88_923 | +0.0 % |
| `bench_bfs_distance_empty_far_17x14` | 407_159 | 407_159 | +0.0 % |
| `bench_bfs_distance_empty_far_7x7` | 88_923 | 88_923 | +0.0 % |
| `bench_bfs_distance_maze_far_17x14` | 1_058_347 | 1_058_347 | +0.0 % |
| `bench_bfs_distance_maze_far_7x7` | 154_812 | 154_812 | +0.0 % |
| `bench_bfs_distance_serpentine_far_17x14` | 1_774_065 | 1_774_065 | +0.0 % |
| `bench_bfs_distance_serpentine_far_7x7` | 167_851 | 167_851 | +0.0 % |
| `bench_bfs_distance_unreachable_far_17x14` | 259_880 | 259_880 | +0.0 % |
| `bench_bfs_distance_unreachable_far_17x14_library` | 259_580 | 259_580 | +0.0 % |
| `bench_bfs_distance_unreachable_far_7x7` | 87_603 | 87_603 | +0.0 % |
| `bench_bfs_distance_unreachable_near_17x14_library` | 261_778 | 261_778 | +0.0 % |
| `bench_bfs_keep_component_cave_17x14` | 582_223 | 535_769 | -8.0 % |
| `bench_bfs_keep_component_cave_7x7` | 170_115 | 97_253 | -42.8 % |
| `bench_bfs_keep_component_maze_17x14` | 1_245_367 | 1_113_013 | -10.6 % |
| `bench_bfs_keep_component_maze_7x7` | 310_087 | 164_579 | -46.9 % |
| `bench_bfs_keep_component_serpentine_17x14` | 2_080_829 | 1_840_935 | -11.5 % |
| `bench_bfs_keep_component_serpentine_7x7` | 330_083 | 174_197 | -47.2 % |
| `bench_bfs_keep_component_unreachable_17x14` | 283_755 | 264_411 | -6.8 % |
| `bench_bfs_keep_component_unreachable_7x7` | 130_123 | 78_017 | -40.0 % |
| `bench_bfs_range_3_cave_17x14` | 84_507 | 84_507 | +0.0 % |
| `bench_bfs_range_3_cave_7x7` | 62_061 | 62_061 | +0.0 % |
| `bench_bfs_range_3_empty_17x14` | 91_617 | 91_617 | +0.0 % |
| `bench_bfs_range_3_empty_7x7` | 62_061 | 62_061 | +0.0 % |
| `bench_bfs_range_3_maze_17x14` | 90_627 | 90_627 | +0.0 % |
| `bench_bfs_range_3_maze_7x7` | 62_061 | 62_061 | +0.0 % |
| `bench_bfs_range_6_cave_17x14` | 145_825 | 145_825 | +0.0 % |
| `bench_bfs_range_6_cave_7x7` | 92_415 | 92_415 | +0.0 % |
| `bench_bfs_range_6_empty_17x14` | 159_255 | 159_255 | +0.0 % |
| `bench_bfs_range_6_empty_7x7` | 92_415 | 92_415 | +0.0 % |
| `bench_bfs_range_6_maze_17x14` | 149_575 | 149_575 | +0.0 % |
| `bench_bfs_range_6_maze_7x7` | 92_415 | 92_415 | +0.0 % |
| `bench_bfs_reachable_cave_17x14` | 557_039 | 538_169 | -3.4 % |
| `bench_bfs_reachable_cave_7x7` | 104_253 | 99_453 | -4.6 % |
| `bench_bfs_reachable_maze_17x14` | 1_154_583 | 1_115_413 | -3.4 % |
| `bench_bfs_reachable_maze_7x7` | 175_079 | 166_779 | -4.7 % |
| `bench_bfs_reachable_serpentine_17x14` | 1_908_405 | 1_843_335 | -3.4 % |
| `bench_bfs_reachable_serpentine_7x7` | 185_197 | 176_397 | -4.8 % |
| `bench_bfs_reachable_unreachable_17x14` | 276_581 | 266_811 | -3.5 % |
| `bench_bfs_reachable_unreachable_7x7` | 84_017 | 80_217 | -4.5 % |
| `bench_bfs_search_cave_far_17x14` | 706_135 | 706_135 | +0.0 % |
| `bench_bfs_search_cave_far_7x7` | 131_733 | 131_733 | +0.0 % |
| `bench_bfs_search_cave_near_17x14` | 112_141 | 112_141 | +0.0 % |
| `bench_bfs_search_cave_near_7x7` | 81_521 | 81_521 | +0.0 % |
| `bench_bfs_search_empty_far_17x14` | 570_033 | 570_033 | +0.0 % |
| `bench_bfs_search_empty_far_7x7` | 131_733 | 131_733 | +0.0 % |
| `bench_bfs_search_empty_near_17x14` | 107_285 | 107_285 | +0.0 % |
| `bench_bfs_search_empty_near_7x7` | 82_241 | 82_241 | +0.0 % |
| `bench_bfs_search_maze_far_17x14` | 1_519_526 | 1_519_526 | +0.0 % |
| `bench_bfs_search_maze_far_7x7` | 239_984 | 239_984 | +0.0 % |
| `bench_bfs_search_maze_near_17x14` | 102_815 | 102_815 | +0.0 % |
| `bench_bfs_search_maze_near_7x7` | 78_204 | 78_204 | +0.0 % |
| `bench_bfs_search_serpentine_far_17x14` | 2_532_090 | 2_532_090 | +0.0 % |
| `bench_bfs_search_serpentine_far_7x7` | 257_269 | 257_269 | +0.0 % |
| `bench_bfs_search_serpentine_near_17x14` | 102_295 | 102_295 | +0.0 % |
| `bench_bfs_search_serpentine_near_7x7` | 80_361 | 80_361 | +0.0 % |
| `bench_bfs_search_unreachable_far_17x14` | 263_320 | 263_320 | +0.0 % |
| `bench_bfs_search_unreachable_far_7x7` | 89_843 | 89_843 | +0.0 % |
| `bench_bfs_search_unreachable_near_17x14` | 266_118 | 266_118 | +0.0 % |
| `bench_bfs_search_unreachable_near_7x7` | 67_873 | 67_873 | +0.0 % |

#### L3 Dial

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_dial_cave_17x14` | 1_427_654 | 1_406_744 | -1.5 % |
| `bench_dial_cave_17x14_classes_0` | 938_551 | 918_341 | -2.2 % |
| `bench_dial_cave_17x14_classes_1` | 1_393_694 | 1_372_784 | -1.5 % |
| `bench_dial_cave_17x14_classes_3` | 1_464_174 | 1_443_264 | -1.4 % |
| `bench_dial_cave_17x14_near` | 289_645 | 283_435 | -2.1 % |
| `bench_dial_cave_7x7` | 298_947 | 290_637 | -2.8 % |
| `bench_dial_cave_7x7_classes_0` | 175_278 | 167_668 | -4.3 % |
| `bench_dial_empty_17x14` | 1_184_765 | 1_167_355 | -1.5 % |
| `bench_dial_empty_17x14_classes_0` | 763_597 | 746_887 | -2.2 % |
| `bench_dial_field_cave_17x14_budget_8` | 335_705 | 326_895 | -2.6 % |
| `bench_dial_field_empty_17x14_budget_2` | 126_717 | 122_107 | -3.6 % |
| `bench_dial_field_empty_17x14_budget_8` | 347_555 | 338_745 | -2.5 % |
| `bench_dial_field_empty_17x14_classes_0_budget_2` | 89_901 | 85_291 | -5.1 % |
| `bench_dial_field_empty_17x14_classes_0_budget_8` | 248_637 | 239_827 | -3.5 % |
| `bench_dial_field_empty_17x14_classes_1_budget_2` | 118_199 | 113_589 | -3.9 % |
| `bench_dial_field_empty_17x14_classes_1_budget_8` | 331_801 | 322_991 | -2.7 % |
| `bench_dial_field_empty_17x14_classes_3_budget_2` | 134_645 | 134_645 | +0.0 % |
| `bench_dial_field_empty_17x14_classes_3_budget_8` | 362_719 | 358_519 | -1.2 % |
| `bench_dial_field_empty_7x7_classes_0_budget_1` | 48_787 | 45_077 | -7.6 % |
| `bench_dial_field_empty_7x7_classes_0_budget_4` | 89_431 | 83_421 | -6.7 % |
| `bench_dial_field_empty_7x7_classes_2_budget_1` | 69_315 | 65_405 | -5.6 % |
| `bench_dial_field_empty_7x7_classes_2_budget_4` | 130_947 | 124_937 | -4.6 % |
| `bench_dial_maze_17x14` | 3_364_897 | 3_318_087 | -1.4 % |
| `bench_dial_maze_17x14_classes_0` | 2_005_148 | 1_964_638 | -2.0 % |
| `bench_dial_serpentine_17x14` | 5_094_739 | 5_027_629 | -1.3 % |
| `bench_dial_serpentine_17x14_classes_0` | 3_293_977 | 3_227_567 | -2.0 % |
| `bench_dial_unreachable_17x14` | 681_530 | 666_920 | -2.1 % |

#### L4 Caver

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_caver_fill_dense_17x14` | 31_973 | 31_973 | +0.0 % |
| `bench_caver_fill_half_17x14` | 28_097 | 28_097 | +0.0 % |
| `bench_caver_fill_sparse_17x14` | 31_973 | 31_973 | +0.0 % |
| `bench_caver_generate_17x14_order_0` | 27_157 | 27_157 | +0.0 % |
| `bench_caver_generate_17x14_order_1` | 75_727 | 72_717 | -4.0 % |
| `bench_caver_generate_17x14_order_3` | 146_747 | 143_737 | -2.1 % |
| `bench_caver_generate_17x14_order_5` | 218_567 | 215_557 | -1.4 % |
| `bench_caver_generate_19x13_order_3` | 147_247 | 144_237 | -2.0 % |
| `bench_caver_generate_7x7_order_0` | 27_157 | 27_157 | +0.0 % |
| `bench_caver_generate_7x7_order_1` | 53_967 | 50_957 | -5.6 % |
| `bench_caver_generate_7x7_order_3` | 86_027 | 83_017 | -3.5 % |
| `bench_caver_generate_connected_17x14` | 432_232 | 412_358 | -4.6 % |
| `bench_caver_keep_component_17x14` | 300_925 | 284_161 | -5.6 % |
| `bench_caver_keep_component_maze_17x14` | 1_245_367 | 1_113_013 | -10.6 % |
| `bench_caver_keep_component_runs_17x14` | 376_836 | 376_836 | +0.0 % |
| `bench_caver_keep_component_runs_first_17x14` | 380_626 | 380_626 | +0.0 % |
| `bench_caver_keep_component_runs_maze_17x14` | 1_445_492 | 1_445_492 | +0.0 % |
| `bench_caver_keep_component_runs_serpentine_17x14` | 1_504_878 | 1_504_878 | +0.0 % |
| `bench_caver_keep_component_serpentine_17x14` | 2_080_829 | 1_840_935 | -11.5 % |

#### L5 Mazer and Digger

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_digger_corridor_17x14` | 314_852 | 310_722 | -1.3 % |
| `bench_digger_maze_17x14` | 3_229_661 | 3_094_676 | -4.2 % |
| `bench_mazer_17x14_order_0` | 2_875_890 | 2_900_244 | +0.8 % |
| `bench_mazer_17x14_order_0_seeds` | 23_573_184 | 23_068_131 | -2.1 % |
| `bench_mazer_17x14_order_1` | 1_826_661 | 1_499_695 | -17.9 % |
| `bench_mazer_17x14_order_1_seeds` | 14_796_998 | 13_857_147 | -6.4 % |
| `bench_mazer_19x13_order_0` | 3_167_395 | 2_890_702 | -8.7 % |
| `bench_mazer_7x7_order_0` | 524_603 | 516_043 | -1.6 % |

#### L6 Walker

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_walker_17x14_0` | 36_481 | 34_901 | -4.3 % |
| `bench_walker_17x14_200` | 1_001_849 | 970_779 | -3.1 % |
| `bench_walker_17x14_50` | 301_845 | 294_005 | -2.6 % |
| `bench_walker_17x14_500` | 2_467_497 | 2_411_657 | -2.3 % |
| `bench_walker_17x14_504` | 2_462_993 | 2_406_413 | -2.3 % |
| `bench_walker_19x13_200` | 1_008_929 | 972_589 | -3.6 % |
| `bench_walker_3x3_50` | 305_375 | 297_365 | -2.6 % |
| `bench_walker_7x7_200` | 995_139 | 962_659 | -3.3 % |
| `bench_walker_7x7_50` | 302_475 | 294_305 | -2.7 % |

#### L7 Spreader (max / mean over 256 seeds)

| Test | Before | After | Delta |
|---|---:|---:|---:|
| `bench_spreader_generate_cave_17x14_1` | 204_839 / 153_540 | 186_639 / 138_480 | -8.9 % / -9.8 % |
| `bench_spreader_generate_cave_17x14_20` | 308_848 / 258_451 | 291_588 / 244_582 | -5.6 % / -5.4 % |
| `bench_spreader_generate_cave_17x14_5` | 340_087 / 273_493 | 320_687 / 259_514 | -5.7 % / -5.1 % |
| `bench_spreader_generate_cave_17x14_60` | 322_711 / 266_711 | 305_451 / 252_801 | -5.3 % / -5.2 % |
| `bench_spreader_generate_cave_7x7_1` | 176_831 / 142_231 | 161_121 / 128_772 | -8.9 % / -9.5 % |
| `bench_spreader_generate_cave_7x7_20` | 219_394 / 182_146 | 208_954 / 173_856 | -4.8 % / -4.6 % |
| `bench_spreader_generate_cave_7x7_5` | 234_194 / 180_396 | 221_614 / 172_091 | -5.4 % / -4.6 % |
| `bench_spreader_generate_d30_17x14_1` | 178_633 / 177_424 | 162_113 / 160_904 | -9.2 % / -9.3 % |
| `bench_spreader_generate_d30_17x14_20` | 297_136 / 240_294 | 282_016 / 228_242 | -5.1 % / -5.0 % |
| `bench_spreader_generate_d30_17x14_5` | 306_469 / 249_910 | 291_349 / 237_851 | -4.9 % / -4.8 % |
| `bench_spreader_generate_d30_17x14_60` | 314_275 / 242_623 | 297_015 / 230_403 | -5.5 % / -5.0 % |
| `bench_spreader_generate_empty_17x14_1` | 203_769 / 141_298 | 186_639 / 128_053 | -8.4 % / -9.4 % |
| `bench_spreader_generate_empty_17x14_20` | 349_586 / 275_706 | 330_186 / 260_745 | -5.5 % / -5.4 % |
| `bench_spreader_generate_empty_17x14_5` | 386_026 / 259_599 | 361_304 / 249_697 | -6.4 % / -3.8 % |
| `bench_spreader_generate_empty_17x14_60` | 342_340 / 274_510 | 322_940 / 259_733 | -5.7 % / -5.4 % |
| `bench_spreader_generate_empty_7x7_1` | 176_841 / 140_967 | 161_121 / 127_590 | -8.9 % / -9.5 % |
| `bench_spreader_generate_empty_7x7_20` | 234_544 / 184_367 | 221_964 / 175_765 | -5.4 % / -4.7 % |
| `bench_spreader_generate_empty_7x7_5` | 234_204 / 184_027 | 221_624 / 175_425 | -5.4 % / -4.7 % |
| `bench_spreader_generate_maze_17x14_1` | 204_839 / 162_112 | 186_639 / 146_514 | -8.9 % / -9.6 % |
| `bench_spreader_generate_maze_17x14_20` | 317_978 / 248_152 | 300_718 / 235_427 | -5.4 % / -5.1 % |
| `bench_spreader_generate_maze_17x14_5` | 309_009 / 258_496 | 291_749 / 245_474 | -5.6 % / -5.0 % |
| `bench_spreader_generate_maze_17x14_60` | 314_372 / 251_565 | 297_112 / 238_626 | -5.5 % / -5.1 % |
| `bench_spreader_generate_maze_7x7_1` | 176_201 / 150_137 | 161_121 / 136_727 | -8.6 % / -8.9 % |
| `bench_spreader_generate_maze_7x7_16` | 106_509 / 105_300 | 103_059 / 101_850 | -3.2 % / -3.3 % |
| `bench_spreader_generate_maze_7x7_5` | 213_251 / 168_943 | 202_811 / 161_877 | -4.9 % / -4.2 % |
| `bench_spreader_generate_sparse2_10x25_1` | 135_256 / 131_275 | 131_176 / 127_195 | -3.0 % / -3.1 % |
| `bench_spreader_generate_sparse5_17x14_1` | 149_625 / 139_223 | 145_545 / 135_143 | -2.7 % / -2.9 % |
| `bench_spreader_generate_sparse5_17x14_2` | 149_865 / 143_721 | 145_445 / 139_301 | -2.9 % / -3.1 % |

## F1 Release preparation

Measured with scarb 2.19.4, snforge 0.61.0 (sierra gas), `snforge test -p origami_hexmap`.

* **Facade.** `HexMap::ring` calls `Bits::and` and `Dilation::dilate` / `expand_small` directly;
  the three `BfsInternal` delegations are gone. `bench_map_ring` 99_903, `bench_map_ring_7x7`
  46_403, `bench_map_ring_open_edge` 167_673: unchanged (the delegations were
  `#[inline(always)]`). `keep_component` stays on `Bfs::reachable` for its edge semantics.
* **Budgets lowered** (more than 5 % under their L8 budget after P1, rule of this file):

| Test | Measured | Budget before | Budget |
|---|---:|---:|---:|
| `bench_map_compute_distribution` | 193_168 | 218_000 | 203_000 |
| `bench_map_direct_compute_distribution` | 193_168 | 218_000 | 203_000 |
| `bench_map_variant_keep_component_caver` | 533_849 | 610_000 | 561_000 |
| `bench_map_variant_keep_component_caver_7x7` | 95_333 | 177_000 | 101_000 |
| `bench_map_variant_keep_component_caver_maze` | 1_111_093 | 1_306_000 | 1_167_000 |

* **Audit A4: bound checks.** `neighbor` returns `None` and `is_walkable` `false` for a position
  at or above `W * H`, and `hex_distance` panics (`Asserter: position not inside`). Formulations of
  `position < W * H` for any `u8` dimensions (`HexMapTrait::new` is unchecked), same 100-call loops
  as L8, per call = `(test - 142_090) / 100`:

| Function | Formulation | Test | Measured | Budget | Per call |
|---|---|---|---:|---:|---:|
| `neighbor` | none (before) | `bench_map_direct_neighbor` | 781_230 | 821_000 | 6_391 |
| `neighbor` | **`bounded_int` product, difference and sign (library)** | `bench_map_neighbor` | 837_960 | 880_000 | 6_959 |
| `neighbor` | row test `y >= H` after the division of `LayoutTrait::neighbor` | `bench_map_variant_neighbor_row` | 847_560 | 890_000 | 7_055 |
| `neighbor` | `u16` product and comparison | `bench_map_variant_neighbor_u16` | 857_460 | 901_000 | 7_154 |
| `neighbor` | `u8` product (panics above 255 tiles) | `bench_map_variant_neighbor_u8` | 857_460 | 901_000 | 7_154 |
| `is_walkable` | none (before) | L8 `bench_map_is_walkable` | 797_080 | 837_000 | 6_550 |
| `is_walkable` | **`bounded_int` (library)** | `bench_map_is_walkable` | 849_410 | 892_000 | 7_073 |
| `is_walkable` | `u16` | `bench_map_variant_is_walkable_u16` | 863_410 | 907_000 | 7_213 |
| `is_walkable` | `u8` | `bench_map_variant_is_walkable_u8` | 863_410 | 907_000 | 7_213 |
| `hex_distance` | none (before) | `bench_map_direct_hex_distance` | 1_088_280 | 1_143_000 | 9_462 |
| `hex_distance` | **`bounded_int`, one test per position (library)** | `bench_map_hex_distance` | 1_181_340 | 1_241_000 | 10_393 |
| `hex_distance` | `u16`, one product for both | `bench_map_variant_hex_distance_u16` | 1_220_940 | 1_282_000 | 10_789 |
| `hex_distance` | `Asserter::assert_inside` of the larger position | `bench_map_variant_hex_distance_max` | 1_241_730 | 1_304_000 | 10_996 |
| `hex_distance` | `bounded_int`, one product for both | `bench_map_variant_hex_distance_bounded_once` | 1_280_340 | 1_345_000 | 11_383 |
| `hex_distance` | row tests `y < H` after the divisions of the distance | `bench_map_variant_hex_distance_rows` | 1_375_530 | 1_445_000 | 12_334 |

  The `bounded_int` form is 1.1 % to 2.3 % cheaper than the runners-up, under the 5 % rule, so the
  code size decides: in a contract with the three queries it is also the smallest, 903 Sierra /
  1_704 CASM felts against 918 / 1_772 for `u16` (861 / 1_614 unchecked). The non-inlined helper
  variants (`rows`, `bounded_once`) lose to the inlined forms.
* **Package.** `.scarbignore` keeps `tests/`, `src/tests/`, `src/helpers/printer.cairo` and this
  file out of the published package (943.98 KiB -> 400.42 KiB). The test-only modules are declared
  under `#[cfg(test)]`, set for this package's own tests only: `#[cfg(target: "test")]` is also set
  when a dependent runs its tests, which then looked for the missing files.
