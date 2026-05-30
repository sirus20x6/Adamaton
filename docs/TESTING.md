# Testing guide

## Unit tests

All sub-repos use standard `go test ./...`. Run from a sub-repo directory or
from the umbrella root:

```bash
# From umbrella — covers every module in go.work
go test ./...

# Per sub-repo
cd knowledge/r2g && go test ./...
cd delegator/delegator && go test ./...
```

The umbrella's `bin/adam test` runner iterates all sub-repos and sets
`GOGENTS_SKIP_DOCKER_TESTS=1` automatically, skipping tests that spin up
containers:

```bash
bin/adam test                    # all sub-repos, no docker deps
bin/adam test --scope=knowledge  # one sub-repo
```

## Skipping docker-backed tests

Tests that start a Postgres container via `testcontainers-go` check this
environment variable:

```go
if os.Getenv("GOGENTS_SKIP_DOCKER_TESTS") != "" {
    t.Skip("GOGENTS_SKIP_DOCKER_TESTS set")
}
```

Set it to any non-empty value to skip those tests:

```bash
GOGENTS_SKIP_DOCKER_TESTS=1 go test ./...
```

This is the convention used across: `delegator/delegator` (postgres_store,
contextmode, budget), and similar testcontainer tests in `core/pgutil`.
Docker must be running and the current user must be in the `docker` group for
tests that are **not** skipped.

## Integration tests (umbrella-level)

The umbrella `Makefile` has an `integration-tests` target (see the Makefile for
exact invocation):

```bash
make integration-tests
```

This runs `go test -v ./tests/integration/...`. The integration tests require:

| Dependency | Address | Purpose |
|------------|---------|---------|
| Postgres (gogents) | `localhost:5433` | task store, budget, contextmode |
| Postgres (evo schema) | `localhost:5432` | evo tables |
| Temporal | `localhost:7233` | workflow engine |
| skills-rae | `localhost:7376` | skill retrieval |

Bring up the workstation compose first:

```bash
docker compose -f deploy/workstation/docker-compose.yml up -d
```

Then (optionally) start skills-rae:

```bash
cd knowledge/skills-rae && go run ./cmd/skills-rae &
```

## Per-sub-repo test targets

Individual sub-repos expose their own test targets via the umbrella Makefile:

```bash
make test-knowledge    # cd knowledge && go test ./...
make test-delegator    # cd delegator && go test ./...  (note: has docker-backed tests)
make test-platform     # cd platform  && go test ./...
make test-deepresearch # cd deepresearch && go test ./...
make test-evolve       # cd evolve && go test ./...
```

These do **not** set `GOGENTS_SKIP_DOCKER_TESTS`; if Docker is unavailable the
testcontainer tests will fail or time out. Use `bin/adam test` when you want
guaranteed-safe docker-free runs.

## core/pgutil tests

`core/pgutil/pgutil_test.go` boots a real Postgres via `testcontainers-go`.
Docker must be running for these to pass:

```bash
cd core && go test ./pgutil/...
```

Skip via `GOGENTS_SKIP_DOCKER_TESTS=1`.

## ztok / r2g tests

`knowledge/r2g` tokenizes via the ztok cgo binding. Before running tests:

```bash
export PKG_CONFIG_PATH="/thearray/git/ztok/zig-out/lib/pkgconfig"
export LD_LIBRARY_PATH="/thearray/git/ztok/zig-out/lib"
# and ensure the symlink at umbrella root exists:
cd /thearray/git/Adamaton && ln -sf /thearray/git/ztok ztok
```

See [docs/LOCAL_DEV.md](LOCAL_DEV.md) for the one-time ztok build step.

## core integration tests (Ethereum/anvil)

`core` has an `integration` Makefile target for on-chain tests that require
`anvil` (Foundry):

```bash
cd core && make integration   # go test -tags integration ./core/p2p/eth/...
```

These are separate from the normal `go test ./...` run; the build tag guards
them.

## Zig sidecar tests

```bash
cd knowledge/tools/latex2text && zig build test
cd knowledge/tools/arxiv-skip  && zig build test
```

## Python sidecar tests

```bash
# figure-renderer
cd deepresearch/nano-research/sidecars/figure-renderer
pip install -r requirements.txt
python -m pytest test_render.py
```

## CI summary

The umbrella CI runs: `format-check`, `vet`, `lint`, `test`, `vuln`, `build`
(see `Makefile` `ci` target). Integration tests run separately — see
[CICD.md](CICD.md).
