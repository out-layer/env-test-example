# env-test-example

A diagnostic WASI module that reports which environment variables it can see.

Its purpose is to answer one question: **did OutLayer actually deliver the secrets to
the module?** Secrets stored on-chain are decrypted inside the TEE and injected into
the WASM sandbox as environment variables. This module reads the variables you ask
for and echoes back what it found, so a failure in the secrets pipeline shows up as a
`null` instead of a value rather than as a silent misbehaviour somewhere downstream.

It has no dependencies beyond `serde`, does no I/O other than stdin/stdout, and is
WASI Preview 1.

## Interface

Input (stdin), a JSON object listing the variable names to read:

```json
{"env_vars": ["API_KEY", "MISSING_VAR"]}
```

Output (stdout), each name mapped to its value or `null` when unset:

```json
{"values": {"API_KEY": "secret-123", "MISSING_VAR": null}}
```

## Build

```bash
./build.sh
```

Adds the `wasm32-wasip1` target if missing, builds in release mode and copies the
result to `./env-test-example.wasm` (~100 KB).

## Running it locally

`./run.sh` wraps all of it. With no arguments it asks for one variable that is set
and one that deliberately is not, so the difference between "delivered" and "missing"
is visible in a single run:

```bash
./run.sh
```

```
Input: {"env_vars":["API_KEY","MISSING_VAR"]}
{"values":{"API_KEY":"secret-123","MISSING_VAR":null}}
```

```bash
./run.sh --env API_KEY=abc --env DB_URL=postgres://x   # ask for exactly these
./run.sh --input '{"env_vars":["HOME"]}' --env HOME=/tmp
./run.sh --runner                                      # via the OutLayer test runner
./run.sh --test                                        # cargo unit tests only
./run.sh --rebuild                                     # force a rebuild first
```

The underlying three ways, in increasing order of how closely they mirror OutLayer.

### 1. Unit tests

Covers input parsing and output serialisation only — no WASM involved.

```bash
cargo test
```

### 2. wasmtime directly

The quickest end-to-end check. `--env` is what stands in for an injected secret:

```bash
echo '{"env_vars":["API_KEY","MISSING_VAR","HOME"]}' \
  | wasmtime --env API_KEY=secret-123 --env HOME=/tmp env-test-example.wasm
```

```json
{"values":{"API_KEY":"secret-123","HOME":"/tmp","MISSING_VAR":null}}
```

Omit `--env` and every value comes back `null` — which is exactly the signature of a
secrets pipeline that failed to deliver anything.

### 3. The OutLayer test runner

Closest to how the worker executes it: enforces fuel and memory limits, detects the
WASI preview version and validates the output.

```bash
cd ../wasi-test-runner && cargo build --release && cd -

../wasi-test-runner/target/release/wasi-test \
  --wasm env-test-example.wasm \
  --input '{"env_vars":["API_KEY","MISSING_VAR"]}' \
  --env API_KEY=secret-123
```

```
Detected: WASI Preview 1 Module
Execution successful!
  - Fuel consumed: 13949 instructions
  - Output size: 54 bytes
Output: {"values":{"API_KEY":"secret-123","MISSING_VAR":null}}
All checks passed! Module is compatible with NEAR OutLayer.
```

## Running it on OutLayer

Store the secrets first, then request an execution that references them. Note that
`accessor` carries the repository binding and that `vault_id` must be present even
when null — near-sdk rejects JSON that omits a required `Option` field.

```bash
near call outlayer.testnet store_secrets '{
  "accessor": { "Repo": { "repo": "github.com/out-layer/env-test-example", "branch": "main" } },
  "profile": "default",
  "encrypted_secrets_base64": "<ECIES-encrypted JSON>",
  "access": "AllowAll",
  "vault_id": null
}' --accountId you.testnet --deposit 0.1
```

Encrypt with the CLI (`outlayer secrets set`) or the dashboard rather than by hand:
the keystore expects ECIES v1 — ephemeral X25519 ECDH, HKDF-SHA256 with info
`outlayer-keystore-v1`, then ChaCha20-Poly1305 — and only the TEE holds the key that
can decrypt it.

```bash
near call outlayer.testnet request_execution '{
  "source": { "GitHub": {
    "repo": "github.com/out-layer/env-test-example",
    "commit": "main",
    "build_target": "wasm32-wasip1"
  }},
  "resource_limits": { "max_instructions": 1000000000, "max_memory_mb": 128, "max_execution_seconds": 60 },
  "input_data": "{\"env_vars\":[\"API_KEY\"]}",
  "secrets_ref": { "profile": "default", "account_id": "you.testnet" },
  "response_format": null,
  "payer_account_id": null,
  "params": null
}' --accountId you.testnet --deposit 0.1 --gas 300000000000000
```

`resource_limits` is not optional in practice: omitting it puts the request into
compile-only mode, and a compile-only request that also carries `input_data` is
rejected.

The contract yields on the request and resumes when the worker reports back, so the
execution output arrives in the transaction result rather than needing to be polled.

## License

MIT OR Apache-2.0, at your option — see `LICENSE-MIT` and `LICENSE-APACHE`.
