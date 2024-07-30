# Scarb dependent crates.
scarb --manifest-path crates/algebra/Scarb.toml build
scarb --manifest-path crates/defi/Scarb.toml build
scarb --manifest-path crates/map/Scarb.toml build
scarb --manifest-path crates/random/Scarb.toml build
scarb --manifest-path crates/rating/Scarb.toml build
scarb --manifest-path crates/security/Scarb.toml build

# Sozo dependent crates.
sozo build --manifest-path crates/token/Scarb.toml
sozo build --manifest-path crates/governance/Scarb.toml
