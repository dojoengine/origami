# Changelog

All notable changes to the Origami crates. The six crates share one version.

## [1.8.0] - unreleased

First release published on the [scarbs.xyz](https://scarbs.xyz) registry: `origami_defi`,
`origami_hexmap`, `origami_map`, `origami_random`, `origami_rating`, `origami_security`.

### Toolchain

- Scarb and Cairo 2.19.4 (from 2.12.2); `origami_hexmap` is tested with Starknet Foundry 0.61.0.
- Registry metadata on every crate (description, license, repository, homepage, documentation,
  readme, keywords); versions and license inherited from the workspace and resolved in the
  packages.
- Test-only files (integration tests; `origami_hexmap` benchmarks, printer and `GAS.md`) are kept
  out of the packages with `.scarbignore`.
- Release workflow: on a `v*` tag, checks the tag against the crate versions, packages the six
  crates and creates the GitHub release; publishes to scarbs.xyz the versions not yet there once
  the `SCARB_REGISTRY_AUTH_TOKEN` secret is set.

### Removed

- `origami_algebra` (vectors and matrices) and its `cubit` dependency: use the
  [`nalgebra`](https://scarbs.xyz/packages/nalgebra) or [`glam`](https://scarbs.xyz/packages/glam)
  packages.

### Changed

- **`origami_defi`** runs on [`fixed`](https://scarbs.xyz/packages/fixed) 0.4.0 instead of
  `cubit`: values are signed Q32.32 `fixed::Fixed` numbers, range `[-2^31, 2^31)`, resolution
  `2^-32`. Only the inputs and the result have to fit: intermediate products are kept wide. The
  domain limits of each function are documented (`# Domain`). Dependents add `fixed@0.4.0` to
  build the values.

### Added

- **`origami_hexmap`**: hexagonal tile maps on a `felt252` bitmap (`W * H <= 251`), with the
  `HexMap` facade that mirrors `origami_map::Map`:
  - generators: `new_maze`, `new_cave`, `new_random_walk`, `new_hexagon`, `open_with_corridor`,
    `open_with_maze`, `compute_distribution` (uniform), `keep_component`;
  - finders: `search_path` (BFS), `distance_to`, `search_path_weighted` and
    `field_of_movement` (up to 3 cost classes), `reachable`, `range`, `ring`, `hex_distance`,
    `neighbor`, `is_walkable`;
  - `u252`, an unsigned integer held in one `felt252`.
  - Gas (snforge 0.61.0, sierra gas): the scenario cave + component + entrance + 10 objects +
    path costs 1.14M on 17x14 (145.8M on `origami_map` 18x14, cairo-test estimate).
  - Determinism: a seed gives the same map for a given version; the generators' streams are
    part of the API from 1.8.0 on.
- `origami_defi`: `FixedStorePacking` (a `Fixed` stored as one `i64`).

### Fixed

- `origami_defi`: the fields of `DiscreteGDA` and `ContinuousGDA` are public, as those of
  `LinearVRGDA` and `LogisticVRGDA`: the structs could not be built outside the crate.
- Every crate README example compiles against the current API (`tests/readme.cairo` in each
  crate).

## [1.7.0]

Last release on git tags only (Scarb 2.12.2).
