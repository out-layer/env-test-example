#!/bin/bash
#
# Run env-test-example locally.
#
# The module reports which environment variables it can see, which is how you check
# that OutLayer's secrets pipeline actually delivered anything: a secret that failed
# to arrive comes back as null rather than failing loudly somewhere downstream.
# Locally, --env stands in for an injected secret.
#
# Usage:
#   ./run.sh                                   # demo: one variable set, one missing
#   ./run.sh --env API_KEY=abc --env DB=xyz    # ask for exactly these, with values
#   ./run.sh --input '{"env_vars":["HOME"]}'   # custom input JSON
#   ./run.sh --runner                          # execute via the OutLayer test runner
#   ./run.sh --test                            # cargo unit tests only
#   ./run.sh --rebuild                         # force a rebuild first
#
set -euo pipefail
cd "$(dirname "$0")"

WASM="env-test-example.wasm"
RUNNER="../wasi-test-runner/target/release/wasi-test"

ENV_ARGS=()
ENV_NAMES=()
INPUT=""
MODE="wasmtime"
REBUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)     ENV_ARGS+=(--env "$2"); ENV_NAMES+=("${2%%=*}"); shift 2 ;;
        --input)   INPUT="$2"; shift 2 ;;
        --runner)  MODE="runner"; shift ;;
        --test)    MODE="test"; shift ;;
        --rebuild) REBUILD=true; shift ;;
        -h|--help)
            cat <<'USAGE'
Run env-test-example locally.

The module reports which environment variables it can see, which is how you check
that OutLayer's secrets pipeline actually delivered anything: a secret that failed to
arrive comes back as null rather than failing loudly somewhere downstream. Locally,
--env stands in for an injected secret.

  ./run.sh                                   demo: one variable set, one missing
  ./run.sh --env API_KEY=abc --env DB=xyz    ask for exactly these, with values
  ./run.sh --input '{"env_vars":["HOME"]}'   custom input JSON
  ./run.sh --runner                          execute via the OutLayer test runner
  ./run.sh --test                            cargo unit tests only
  ./run.sh --rebuild                         force a rebuild first
USAGE
            exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
done

if [[ "$MODE" == "test" ]]; then
    exec cargo test
fi

# Default demo: one variable that is set, one that deliberately is not, so the
# difference between "delivered" and "missing" is visible in a single run.
if [[ ${#ENV_ARGS[@]} -eq 0 ]]; then
    ENV_ARGS=(--env API_KEY=secret-123)
    ENV_NAMES=(API_KEY MISSING_VAR)
fi

# Ask for exactly the variables named on the command line unless told otherwise.
if [[ -z "$INPUT" ]]; then
    INPUT=$(printf '%s\n' "${ENV_NAMES[@]}" | jq -R . | jq -sc '{env_vars: .}')
fi

if [[ "$REBUILD" == true || ! -f "$WASM" ]]; then
    echo "Building..." >&2
    ./build.sh >/dev/null
fi

echo "Input: $INPUT" >&2

if [[ "$MODE" == "runner" ]]; then
    if [[ ! -x "$RUNNER" ]]; then
        echo "Building the test runner (one-off, ~1-2 min)..." >&2
        (cd ../wasi-test-runner && cargo build --release >/dev/null)
    fi
    # Enforces fuel and memory limits and validates the output the way the worker does.
    exec "$RUNNER" --wasm "$WASM" --input "$INPUT" "${ENV_ARGS[@]}"
fi

command -v wasmtime >/dev/null || {
    echo "wasmtime not found — install it from https://wasmtime.dev or use --runner" >&2
    exit 1
}

echo "$INPUT" | wasmtime "${ENV_ARGS[@]}" "$WASM"
echo
