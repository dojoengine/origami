# Scarb dependent crates.
scarb --manifest-path crates/algebra/Scarb.toml build
scarb --manifest-path crates/defi/Scarb.toml build
scarb --manifest-path crates/map/Scarb.toml build
scarb --manifest-path crates/random/Scarb.toml build
scarb --manifest-path crates/rating/Scarb.toml build
scarb --manifest-path crates/security/Scarb.toml build
scarb --manifest-path crates/tba/Scarb.toml build

# Sozo dependent crates.
sozo build --package "origami_token"
sozo build --package "origami_governance"
