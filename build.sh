#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building env-test-ark for WASI P1..."
cargo build --target wasm32-wasip1 --release

# Copy to current dir for convenience
cp ./target/wasm32-wasip1/release/env-test-ark.wasm ./env-test-ark.wasm

echo "Done! Output: env-test-ark.wasm"
ls -lh env-test-ark.wasm
