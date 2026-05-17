# Part 1 — Foundation Orchestrator

> **Required reading first:**
> - `docs/p2p-plan/00-shared-context.md` — system overview and design decisions
> - `docs/p2p-plan/01-contracts.md` — interfaces, types, C++ FFI conventions
>
> Read both fully before starting. Don't skim. The system is novel and the
> design decisions encoded above are non-obvious.

## Your role

You are the foundation. You:

1. Bootstrap the new code directory inside the `core` sub-repo.
2. Commit the canonical Go types + interface files from `01-contracts.md`.
3. Implement the lifecycle Orchestrator (the state machine that drives jobs).
4. Implement three `ComputeProvider` implementations (honest mock, malicious
   mock, real BGE-M3 wrapper).
5. Establish the cgo scaffolding pattern that Part 3 will follow for its
   C++ hot path. Ship a tiny example C++ library so the pattern is real and
   compiling, not just documented.
6. Build the integration test harness that wires Parts 2/3/4 together.
7. Write the end-to-end integration test that exercises honest + dishonest
   paths once Parts 2/3/4 are available (stubs in the meantime).

You are the **only** orchestrator allowed to edit files in `core/p2p/types/`,
`core/p2p/iface/`, `core/p2p/orchestrator/`, `core/p2p/providers/`, and
`core/p2p/testharness/`. Parts 2/3/4 own their respective subdirectories.

## Worktree setup

```bash
cd /thearray/git/Adamaton
bin/adam doctor
bin/adam claim core/p2p-foundation
# you are now in: core/core-worktrees/<you>-p2p-foundation/
```

(Note: `core/<task>` because we're working inside the `core` submodule. The
new p2p code lives in `core/p2p/` inside the `core` repo.)

## Scope (in)

### 1.1 Bootstrap

- Create directory `core/p2p/` with subdirectories:
  - `types/` — shared types
  - `iface/` — engine interfaces
  - `orchestrator/` — lifecycle state machine
  - `providers/` — ComputeProvider implementations
  - `testharness/` — integration test scaffolding
- Add `core/p2p/README.md` summarizing v0 architecture (link to the plan
  files in the umbrella repo).
- Ensure `go build ./...` passes from the `core` repo root after your code
  is added (no breakage of existing core packages).

### 1.2 Commit canonical types + interfaces

Take the Go code in `01-contracts.md` verbatim, format with `gofmt`, and
commit:

- `core/p2p/types/types.go` — all the structs from `## Shared types`
- `core/p2p/iface/ledger.go` — `LedgerEngine` interface
- `core/p2p/iface/audit.go` — `AuditEngine` + `ReferenceComputer` interfaces
- `core/p2p/iface/federation.go` — `FederationEngine` interface + `PoolParams`
- `core/p2p/iface/provider.go` — `ComputeProvider` interface

These files contain ONLY type and interface declarations — no
implementations. They are the contract that Parts 2/3/4 will compile
against. Commit these FIRST so Parts 2/3/4 can branch from them.

### 1.3 cgo scaffolding pattern (the example library)

Set up the canonical cgo pattern by shipping a tiny example C++ library
that Part 1 itself uses. Suggestion: a `version` library that returns a
build-version string from C++ — small enough to be obviously trivial, big
enough to validate the build pipeline.

Layout:

```
core/p2p/cppexample/
  cppexample.go              # Go shell
  cppexample_cgo.go          # cgo wrapper
  cppexample_test.go         # Go test that exercises the C++
  cxx/
    include/p2p_cppexample_capi.h
    cppexample.cpp
    third_party/doctest.h
    tests/cppexample_test.cpp
    README.md
```

The C++ side exposes `extern "C" const char* p2p_cppexample_version()`.

Why ship this rather than just documenting the pattern? Because the actual
build pipeline (cgo + C++23 + cross-compilation to pi5 / blackwell) has
sharp edges, and shipping a working example surfaces them before Part 3
hits them at scale.

Verify the example builds on:

- Linux x86_64 (workstation, `go build ./...`)
- Cross-compile to ARM64 (run `GOOS=linux GOARCH=arm64 CGO_ENABLED=1
  CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ go build ./...` to
  match the pi5 target). If the toolchain isn't available locally, document
  the required tooling in `cxx/README.md`.

Single-header doctest: download from
`https://raw.githubusercontent.com/doctest/doctest/master/doctest/doctest.h`
and check in at `cxx/third_party/doctest.h`. This is a one-time setup.

### 1.4 ComputeProvider implementations

Implement three ComputeProviders in `core/p2p/providers/`:

- **`HonestMock`** — deterministic canned vectors (one fixed vector per
  Payload hash). Doesn't actually compute embeddings. Tests use this when
  they want predictable input/output for the audit engine.

- **`MaliciousMock`** — random vectors NOT derived from input. Configurable:
  always-malicious, malicious-with-probability-p, malicious-on-specific-input.
  Used by tests to exercise fraud detection.

- **`BGEHonest`** — calls into the existing `octen` package in the same
  `core` repo to run BGE-M3. Real worker. Serves at a configurable precision
  (fp32 / fp16 / int8) and returns the real embedding output. If `octen`'s
  current API needs adjustment to expose precision-controlled inference,
  surface it but don't change `octen` from within the foundation work —
  document the gap.

The `ReferenceComputer` used by AuditEngine is a separate instance of
`BGEHonest` (or a mock equivalent in tests).

### 1.5 Orchestrator

Implement `core/p2p/orchestrator/orchestrator.go` with the `Submit` method
described in `01-contracts.md § Job lifecycle`.

**Stake multiplier policy.** Configurable via `OrchestratorConfig`. Sensible
defaults:

```go
StakeMultiplier: map[types.JobCategory]float64{
    types.JobEmbedding: 10.0,
    types.JobRerank:    10.0,
},
```

**High-value threshold.** Configurable; default `100 * USDC`.

**Severity → slashFraction mapping.** Implement the curve from
`01-contracts.md § Job lifecycle step 7`.

### 1.6 Test harness

Build `core/p2p/testharness/` with helpers that:

- Spin up a complete system with stub or real engine implementations.
- Pre-fund N nodes with stake.
- Create N test pools (when Federation is real).
- Submit a configurable number of jobs from various publishers, mix of
  honest and malicious workers.
- Assert on outcomes: honest workers paid, malicious workers slashed, rep
  updated, insurance reserve grew, etc.

**Stub engine implementations** for the period when Parts 2/3/4 aren't
ready yet. Stubs live in `core/p2p/testharness/stubs.go`:

- `StubLedger` — implements `iface.LedgerEngine` with in-memory maps; just
  enough to make orchestrator tests compile and pass. Will be replaced by
  Part 2's real impl.
- `StubAudit` — implements `iface.AuditEngine`; configurable to return
  (audited=true, pass=true), (audited=true, pass=false, severity=X), or
  (audited=false). Will be replaced by Part 3's real impl.
- `StubFederation` — implements `iface.FederationEngine`; minimal pool +
  rep tracking. Will be replaced by Part 4's real impl.

### 1.7 Integration test

`core/p2p/orchestrator/integration_test.go`:

- Wire stubs initially, with build tags or env-var toggles to swap in real
  Parts 2/3/4 once those are available.
- Run a sequence of 100 jobs: 90 honest, 10 malicious.
- Assert:
  - All 90 honest jobs settle. Workers receive `(value - tax)`. Tax
    accounting balances.
  - All 10 malicious jobs are caught (force-audit) and slashed.
  - Insurance reserve increased by approximately
    `network_tax × 90 + slash_amounts`.
  - Reputation incremented for honest workers, decremented for malicious.
  - Telemetry events for slash and audit-fail were emitted.

Skip the integration test by default with a build tag (`//go:build integration`)
so unit tests run fast. Document how to enable in the package README.

## Non-goals (NOT in scope)

- **Do not implement the engines themselves** — Parts 2/3/4 do that. You
  ship stubs in `testharness/stubs.go`.
- **Do not implement networking.** No HTTP servers, no libp2p, no gossip.
- **Do not implement persistence.** All state in memory.
- **Do not edit Parts 2/3/4 directories** (`ledger/`, `audit/`,
  `federation/`). Even if you find a bug; surface it.

## Coordination with other parts

- **Interfaces are your contract.** You commit them; Parts 2/3/4 build
  against them. If you discover during orchestrator implementation that
  an interface needs to change, STOP and surface to the user.
- **Stubs unblock the others.** When you commit the iface/ files first
  (within the first hour or two), Parts 2/3/4 can rebase against your
  branch and start work in parallel.

## Deliverables (files you will create)

```
core/p2p/README.md
core/p2p/types/types.go
core/p2p/iface/ledger.go
core/p2p/iface/audit.go
core/p2p/iface/federation.go
core/p2p/iface/provider.go
core/p2p/orchestrator/orchestrator.go
core/p2p/orchestrator/orchestrator_test.go
core/p2p/orchestrator/integration_test.go
core/p2p/providers/honest_mock.go
core/p2p/providers/honest_mock_test.go
core/p2p/providers/malicious_mock.go
core/p2p/providers/malicious_mock_test.go
core/p2p/providers/bge_honest.go
core/p2p/providers/bge_honest_test.go
core/p2p/testharness/harness.go
core/p2p/testharness/stubs.go
core/p2p/testharness/scenarios.go
core/p2p/cppexample/cppexample.go
core/p2p/cppexample/cppexample_cgo.go
core/p2p/cppexample/cppexample_test.go
core/p2p/cppexample/cxx/include/p2p_cppexample_capi.h
core/p2p/cppexample/cxx/cppexample.cpp
core/p2p/cppexample/cxx/third_party/doctest.h
core/p2p/cppexample/cxx/tests/cppexample_test.cpp
core/p2p/cppexample/cxx/README.md
```

## Definition of done

- `go build ./...` from `core/` root passes (cgo compiles cppexample)
- `go test ./p2p/...` passes (with stub engines)
- `go test -race ./p2p/...` passes
- Orchestrator unit tests cover the happy path and the slash path
- Integration test (build-tag gated) wires the lifecycle end-to-end with stubs
- The cppexample C++ standalone test (`/tmp/cppexample_test`) passes
- `README.md` explains how to plug Parts 2/3/4's real engines into the harness
- ARM64 cross-compile of cppexample is documented in `cxx/README.md` (or
  verified working if toolchain available)

## When you're done

```bash
bin/adam release core/p2p-foundation --keep-branch
```

(`--keep-branch` keeps the branch pushed without removing the worktree —
we're not merging yet.)

Surface to the user: "Foundation done, branch `<you>/p2p-foundation` ready
for review. Stubs and iface/ are committed early on the branch; Parts 2/3/4
can rebase against them."

## Suggested subagent splits

You can spawn as many subagents as you like. Productive split:

- **Subagent A:** types/ and iface/ files (mechanical from spec) + commit early
- **Subagent B:** cppexample cgo scaffolding (C++ + cgo wrapper + tests)
- **Subagent C:** orchestrator state machine + unit tests
- **Subagent D:** the three ComputeProvider impls (BGEHonest needs to read
  the existing `octen` package to understand the API)
- **Subagent E:** test harness + stubs + integration test scaffold

Synchronize at the end on the integration test running cleanly with stubs.
