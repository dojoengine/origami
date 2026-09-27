#!/usr/bin/env bash
set -euo pipefail

# Build every crate of the workspace.
scarb build --workspace
