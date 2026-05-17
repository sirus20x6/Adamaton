# P2P Network — Interface Contracts (frozen for v0)

> Required reading: `00-shared-context.md`.
>
> This document is the canonical Go interface, type, and FFI contract for v0.
> All four parts implement against these signatures. Part 1's first commit is
> the verbatim Go files derived from this document; Parts 2/3/4 build their
> implementations against these signatures.
>
> **Interfaces are frozen.** If your implementation reveals a needed change,
> STOP and surface it. Don't modify the interfaces yourself.

## Module path

The `core` sub-repo's Go module is `github.com/sirus20x6/adamaton-core`. All
p2p code lives under `github.com/sirus20x6/adamaton-core/p2p/...`.

## Package layout

```
core/p2p/
  types/         - shared types. Part 1 owns.
  iface/         - the interface declarations below. Part 1 owns.
  ledger/        - LedgerEngine implementation. Part 2 owns.
  audit/         - AuditEngine implementation. Part 3 owns.
  audit/cxx/     - C++23 hot path. Part 3 owns.
  federation/    - FederationEngine implementation. Part 4 owns.
  orchestrator/  - lifecycle state machine. Part 1 owns.
  providers/     - ComputeProvider impls (mock + BGE-M3). Part 1 owns.
  testharness/   - integration test scaffolding. Part 1 owns.
```

## Shared types — `core/p2p/types/`

```go
package types

import "time"

// Money is the internal unit of account: micro-USDC (1e-6 USDC).
// 1 USDC == 1_000_000 Money. int64 holds up to ~9.2 trillion USDC.
type Money int64

const (
    MicroUSDC Money = 1
    MilliUSDC Money = 1_000
    USDC      Money = 1_000_000
)

type NodeID string
type PoolID string
type JobID string
type AuditID string

type JobCategory string

const (
    JobEmbedding JobCategory = "embedding"
    JobRerank    JobCategory = "rerank"
)

type Precision string

const (
    PrecisionFP32 Precision = "fp32"
    PrecisionFP16 Precision = "fp16"
    PrecisionINT8 Precision = "int8"
)

type Job struct {
    ID         JobID
    Category   JobCategory
    Model      string      // e.g. "BGE-M3"
    Precision  Precision   // declared by the worker upon acceptance
    Payload    []byte      // serialized input
    Value      Money       // gross price the publisher pays (pre-tax)
    OfferedAt  time.Time
    Publisher  NodeID
    Worker     NodeID      // set on acceptance
}

type JobReceipt struct {
    JobID   JobID
    Worker  NodeID
    Output  []byte    // serialized output (cosine vector or rerank scores)
    DoneAt  time.Time
}

type Stake struct {
    NodeID    NodeID
    Available Money            // free, withdrawable
    Locked    map[JobID]Money  // per-job locked amounts
}

type Identity struct {
    NodeID  NodeID
    PubKey  []byte    // Ed25519 in v0, opaque
    Pool    PoolID    // empty if solo
}

type Reputation struct {
    NodeID            NodeID
    EarnedScore       int64   // grown by passed audits
    DonatedVerified   Money   // total verified-donated compute value
    PoolEndorsement   int64   // additional rep from current pool (revocable)
}

type AuditOutcome struct {
    ID          AuditID
    JobID       JobID
    Verifiers   []NodeID
    Similarity  float64    // 0..1 (1.0 = bit-exact)
    Pass        bool
    Severity    float64    // 0=clean, 1=egregious; drives slash formula
    PerformedAt time.Time
}

type Pool struct {
    ID          PoolID
    Tier        int       // 1..5
    Tax         float64   // 0..0.1; additional rate above network tax
    Operator    NodeID
    Members     []NodeID
    KYCRequired bool
    TotalStake  Money
    Volume      Money     // 30-day rolling (v0: unbounded counter)
}

type TelemetryEvent struct {
    Kind    string         // "slash", "audit_fail", "pool_join", etc.
    Payload map[string]any
    At      time.Time
}
```

## Engine interfaces — `core/p2p/iface/`

### `LedgerEngine` — Part 2 owns

```go
package iface

import "github.com/sirus20x6/adamaton-core/p2p/types"

type LedgerEngine interface {
    // Stake management
    DepositStake(node types.NodeID, amount types.Money) error
    WithdrawStake(node types.NodeID, amount types.Money) error
    GetStake(node types.NodeID) (types.Stake, error)

    // Per-job escrow
    LockForJob(node types.NodeID, jobID types.JobID, amount types.Money) error
    // ReleaseFromJob returns (slashed, returnedToWorker, error).
    // slashFraction == 0 means clean release; == 1 means full slash.
    ReleaseFromJob(jobID types.JobID, slashFraction float64) (slashed, returned types.Money, err error)

    // Settlement of paid work after clean release
    SettleJob(jobID types.JobID, worker types.NodeID, value types.Money,
              networkTaxRate, poolTaxRate float64) (paid types.Money, err error)

    // Network tax accounting
    NetworkTaxRate() float64
    UpdateNetworkTaxRate(newRate float64) error

    // Insurance reserve
    InsuranceReserve() types.Money
    PayoutFromReserve(to types.NodeID, amount types.Money, reason string) error
}
```

### `AuditEngine` — Part 3 owns

```go
type AuditEngine interface {
    // Decides probabilistically whether to audit; if audited, performs replay
    // and returns the outcome. If not audited, returns (audited=false, nil, nil).
    SubmitJobForAudit(job types.Job, receipt types.JobReceipt) (audited bool, outcome *types.AuditOutcome, err error)

    // ForceAudit triggers an audit deterministically (high-value, suspicious).
    ForceAudit(job types.Job, receipt types.JobReceipt) (types.AuditOutcome, error)

    // CurrentAuditRate returns the rate for a given (category, node).
    CurrentAuditRate(category types.JobCategory, node types.NodeID) float64

    // ReportDetectedFraud feeds back into the control law.
    ReportDetectedFraud(outcome types.AuditOutcome)

    // RegisterVerifier adds a node to the auditor pool with stake-backed weight
    // and pool affiliation (used for verifier-independence selection).
    RegisterVerifier(node types.NodeID, weight int64, pool types.PoolID) error

    // SetReferenceComputer wires the model runner used by verifiers.
    // For v0, this is BGE-M3 via the octen package or a mock.
    SetReferenceComputer(rc ReferenceComputer)
}

// ReferenceComputer runs the same model the worker claimed to run.
// v0 ships a mock; v1+ wires the real BGE-M3 path.
type ReferenceComputer interface {
    Compute(job types.Job) ([]byte, error)
}
```

### `FederationEngine` — Part 4 owns

```go
type FederationEngine interface {
    // Pool management
    RegisterPool(operator types.NodeID, params PoolParams) (types.PoolID, error)
    JoinPool(node types.NodeID, pool types.PoolID, attestation []byte) error
    LeavePool(node types.NodeID) error
    GetPool(pool types.PoolID) (types.Pool, error)
    PoolOf(node types.NodeID) (types.PoolID, bool)
    PoolTaxRate(pool types.PoolID) float64

    // Reputation
    GetReputation(node types.NodeID) (types.Reputation, error)
    AddDonationCredit(node types.NodeID, verifiedValue types.Money) error
    OnAuditOutcome(outcome types.AuditOutcome) error

    // Effective rep cap = solo cap if solo, else solo cap + pool endorsement,
    // bounded above by DonatedVerified-in-score-units.
    EffectiveReputationCap(node types.NodeID) int64

    // Pool endorsement (revocable)
    SetPoolEndorsement(pool types.PoolID, node types.NodeID, amount int64) error
    RevokePoolEndorsement(node types.NodeID) error

    // Volume tracking (orchestrator calls this on each settle to feed tier calc)
    RecordSettlement(pool types.PoolID, value types.Money) error

    // Telemetry — network leader observability
    EmitEvent(event types.TelemetryEvent) error
    DrainEvents() []types.TelemetryEvent  // for testing / external collectors
}

type PoolParams struct {
    Operator    types.NodeID
    Tax         float64
    KYCRequired bool
}
```

### `ComputeProvider` — Part 1 owns (the worker side)

```go
type ComputeProvider interface {
    Quote(job types.Job) (price types.Money, accept bool)
    Run(job types.Job) (types.JobReceipt, error)
}
```

## Orchestrator entry — `core/p2p/orchestrator/`

```go
package orchestrator

import (
    "github.com/sirus20x6/adamaton-core/p2p/iface"
    "github.com/sirus20x6/adamaton-core/p2p/types"
)

// Orchestrator drives a job through its lifecycle, calling into the three
// engines at each phase.
type Orchestrator struct {
    Ledger     iface.LedgerEngine
    Audit      iface.AuditEngine
    Federation iface.FederationEngine
    Provider   iface.ComputeProvider

    Config OrchestratorConfig
}

type OrchestratorConfig struct {
    // Stake multiplier by category.
    StakeMultiplier map[types.JobCategory]float64
    // Job value above which we force-audit instead of probabilistic.
    HighValueAuditThreshold types.Money
}

// Submit drives a job from offer -> settle (or slash).
func (o *Orchestrator) Submit(job types.Job) (Outcome, error)

type Outcome struct {
    Job           types.Job
    Receipt       *types.JobReceipt
    Audit         *types.AuditOutcome
    SlashFraction float64
    PaidToWorker  types.Money
    Slashed       types.Money
    Error         error
}
```

## Job lifecycle (the contract between engines)

The orchestrator's `Submit` method is the canonical lifecycle. Engines are
called in this order:

1. **Offer.** Publisher creates a `Job`. Orchestrator validates basics.
2. **Quote/Accept.** A `ComputeProvider` accepts the job. Orchestrator
   records `job.Worker`.
3. **Check rep / stake.** Orchestrator calls
   `federation.GetReputation(worker)` and `federation.EffectiveReputationCap`
   and checks the worker's cap permits this job's value (job rejected if not).
4. **Lock stake.** Orchestrator calls
   `ledger.LockForJob(worker, jobID, job.Value * stakeMultiplier(category))`.
5. **Execute.** Orchestrator calls `provider.Run(job)` → `JobReceipt`.
6. **Audit (probabilistic or forced).**
   - If `job.Value >= Config.HighValueAuditThreshold`: call
     `audit.ForceAudit(job, receipt)`.
   - Else: call `audit.SubmitJobForAudit(job, receipt)`.
7. **Compute slashFraction.** From `outcome.Severity`:
   - `severity == 0` → slashFraction = 0
   - `severity > 0 && severity < 0.3` → slashFraction = severity (mild)
   - `severity >= 0.3 && severity < 0.7` → slashFraction = 0.5 + severity/2
   - `severity >= 0.7` → slashFraction = 1.0 (full slash, egregious)
   - Unaudited job → slashFraction = 0
8. **Settle.** Orchestrator calls
   `ledger.ReleaseFromJob(jobID, slashFraction)` then
   `ledger.SettleJob(...)` if `slashFraction < 1.0`. Slashed funds go to
   the insurance reserve.
9. **Record settlement volume.** Orchestrator calls
   `federation.RecordSettlement(workerPool, job.Value)` if worker is pooled.
10. **Update rep.** Orchestrator calls
    `federation.OnAuditOutcome(*outcome)` (if audited) so rep is adjusted.
11. **Report fraud to audit controller.** Orchestrator calls
    `audit.ReportDetectedFraud(*outcome)` (if audited and not passing).
12. **Telemetry.** Orchestrator calls `federation.EmitEvent` for slash,
    audit fail, audit pass, settle, etc.

## Where each part hooks into the lifecycle

```
        Offer
          │
          ▼
       [Quote] ─────── (Part 1: orchestrator + ComputeProvider)
          │
          ▼
   [Check rep cap] ─── (Part 4: FederationEngine)
          │
          ▼
   [Lock stake] ───── (Part 2: LedgerEngine)
          │
          ▼
       [Execute] ───── (Part 1: ComputeProvider impl)
          │
          ▼
        [Audit] ─────── (Part 3: AuditEngine — Go shell + C++ hot path)
          │
          ▼
   [Release + Settle] (Part 2: LedgerEngine)
          │
          ▼
   [Record volume] ─── (Part 4: FederationEngine)
          │
          ▼
   [Update rep] ────── (Part 4: FederationEngine)
          │
          ▼
   [Report fraud] ──── (Part 3: AuditEngine)
          │
          ▼
   [Emit telemetry] ── (Part 4: FederationEngine)
```

## Cross-part read interactions (the "barely intersecting" boundary)

Read-only interface calls between engines. MUST go through interfaces, not
shared state.

- **Audit → Federation:** verifier independence uses `PoolID` carried in
  `RegisterVerifier(node, weight, pool)`. No live call into Federation
  during audit; the affiliation is captured at registration time.

- **Federation → Ledger:** none. The orchestrator passes pool-tax through
  to the ledger; the ledger doesn't read pool state directly.

- **Ledger → Federation:** none directly. `SettleJob` takes `poolTaxRate`
  as a parameter, which the orchestrator pre-reads from
  `federation.PoolTaxRate`.

There are NO cross-part *write* interactions. Each engine is the sole writer
of its own state.

## C++ FFI conventions

When a Go package uses a C++ hot path, the canonical pattern is:

### Directory layout

```
core/p2p/<pkg>/
  <pkg>.go                  # Go business logic
  <pkg>_cgo.go              # cgo wrapper file
  cxx/
    include/<pkg>_capi.h    # C ABI header (#include'd from cgo)
    <pkg>.cpp               # C++ implementation
    third_party/doctest.h   # single-header test framework
    tests/<pkg>_test.cpp    # standalone C++ tests
    README.md               # build notes
```

### C ABI header (`<pkg>_capi.h`)

Only POD types, pointers, and integers cross the boundary.

```c
#ifndef P2P_<PKG>_CAPI_H
#define P2P_<PKG>_CAPI_H

#ifdef __cplusplus
extern "C" {
#endif

// Example: cosine similarity of two equal-length f32 vectors.
// Returns NaN on input error (len <= 0 or null pointers).
double p2p_cosine_similarity(const float* a, const float* b, int len);

// Example: Kendall's tau-b rank correlation of two equal-length int rankings.
double p2p_kendall_tau(const int* rank_a, const int* rank_b, int len);

#ifdef __cplusplus
}
#endif

#endif // P2P_<PKG>_CAPI_H
```

### C++ implementation (`<pkg>.cpp`)

`-std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic`.

Style rules (Zig-style discipline):

- **No exceptions.** `-fno-exceptions`. Errors via sentinel returns (NaN for
  doubles, -1 for ints, nullptr for pointers) or out-parameter `int* err`.
- **No RTTI.** `-fno-rtti`. No `dynamic_cast`, no `typeid`.
- **No `<iostream>`.** Use `printf`/`fprintf` for v0 logging.
- **No hidden allocations in hot paths.** Stack-allocate or take explicit
  buffer arguments. If allocation is unavoidable, use the C++23
  `std::pmr` allocators with caller-provided memory resources.
- **`constexpr`/`consteval` where reasonable.** Catches errors at compile time.
- **`[[nodiscard]]` on public return values.** No silently dropped results.
- **`noexcept` everywhere.** With `-fno-exceptions` this is implicit; mark
  it anyway for readers.
- **Stable C ABI for public symbols.** Internal C++ types are free; just
  don't expose them across the FFI boundary.
- **One translation unit per public surface.** Don't split a coherent
  feature across many .cpp files unless there's a compile-time reason.

Internally you may use modern C++ idioms freely — RAII, templates,
ranges, concepts, `std::span`, `std::expected` (C++23 for in-process
error returns; doesn't cross FFI), etc. The constraints are *at the FFI
boundary* and *in the discipline that prevents footguns*.

### Go wrapper (`<pkg>_cgo.go`)

```go
package <pkg>

/*
#cgo CXXFLAGS: -std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic
#cgo CPPFLAGS: -I${SRCDIR}/cxx/include
#include "<pkg>_capi.h"
*/
import "C"
import "unsafe"

func cosineSimilarity(a, b []float32) float64 {
    if len(a) == 0 || len(a) != len(b) {
        return 0
    }
    return float64(C.p2p_cosine_similarity(
        (*C.float)(unsafe.Pointer(&a[0])),
        (*C.float)(unsafe.Pointer(&b[0])),
        C.int(len(a)),
    ))
}
```

### C++ tests

doctest is a single-header test framework. Drop `doctest.h` into
`cxx/third_party/`. Tests at `cxx/tests/<pkg>_test.cpp`:

```cpp
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "../third_party/doctest.h"
#include "../include/<pkg>_capi.h"

TEST_CASE("cosine_similarity: identical vectors -> 1.0") {
    float a[] = {1, 0, 0};
    float b[] = {1, 0, 0};
    CHECK(p2p_cosine_similarity(a, b, 3) == doctest::Approx(1.0));
}
```

Build standalone test binary (for fast iteration without `go test`):

```bash
g++ -std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic \
    -I cxx/include -I cxx/third_party \
    cxx/<pkg>.cpp cxx/tests/<pkg>_test.cpp \
    -o /tmp/<pkg>_test && /tmp/<pkg>_test
```

Also run via `go test` (which builds + links the C++ as part of cgo):

```bash
go test ./p2p/<pkg>/...
```

### Memory and lifetime rules

- **Go owns Go memory.** Don't store Go pointers in C++ structs across
  function-call boundaries (cgo will warn).
- **C++ owns C++ memory.** If C++ needs to return a buffer, take the
  buffer + capacity as input from Go (`out_buf`, `out_cap`) and return
  the bytes written. No malloc-and-return-pointer pattern in v0.
- **Strings.** Use `const char*` + `int len` for input; for output, take
  `char* out`, `int cap` and return written length.
- **Floats.** `float` (f32) and `double` (f64) only. No `long double`
  (platform-dependent).

## Interface change protocol

If your implementation reveals a needed interface change:

1. STOP implementing.
2. Write a short note: which interface, what change, why your impl needs it.
3. Surface to the project owner. Do not edit interface files yourself.
4. Continue with the rest of your scope that doesn't depend on the change.

Interfaces are frozen until the user explicitly approves a change. An
unauthorized interface change breaks the other 3 parts in flight.
