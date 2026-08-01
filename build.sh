#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building env-test-example for WASI P1..."
cargo build --target wasm32-wasip1 --release

# Copy to current dir for convenience
cp ./target/wasm32-wasip1/release/env-test-example.wasm ./env-test-example.wasm

echo "Done! Output: env-test-example.wasm"
ls -lh env-test-example.wasm
