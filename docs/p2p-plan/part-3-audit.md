# Part 3 — Audit Engine (Go shell + C++ hot path)

> **Required reading first:**
> - `docs/p2p-plan/00-shared-context.md` — system overview and design decisions
> - `docs/p2p-plan/01-contracts.md` — interface contracts AND the
>   `## C++ FFI conventions` section (you live in both languages)
>
> Read both fully before starting.

## Your role

You implement the `AuditEngine` — the verification engine. You're the only
part that uses both languages. You own:

**Go shell (decision + control):**
- **Replay orchestration** — selecting verifiers, dispatching replays
- **Audit budget management** — adaptive rate, per-node and per-category
- **Verifier independence** — no two verifiers from the same pool
- **Fraud history tracking** — fueling the control law

**C++ hot path (math + future BLAS-backed replay):**
- **Cosine similarity** — for embedding outputs
- **Kendall's tau** — for rerank outputs
- **Stable C ABI** — Go calls into C++ via cgo

You are the **only** orchestrator allowed to edit files in `core/p2p/audit/`,
which includes the `cxx/` subdirectory.

## Worktree setup

```bash
cd /thearray/git/Adamaton
bin/adam doctor
bin/adam claim core/p2p-audit
```

## Dependency: Part 1's foundation

You depend on Part 1 having committed:

- `core/p2p/types/types.go`
- `core/p2p/iface/audit.go`
- The cgo scaffolding example at `core/p2p/cppexample/` — your `cxx/`
  follows this pattern exactly.

Sequence: same as Part 2. Wait for Part 1's commits, rebase against them.
If delayed, work against local copies of the types/iface and rebase later.

**Look at `core/p2p/cppexample/` carefully** — it's the canonical pattern.
Your job is to follow it for the similarity library, not invent your own.
If the example surfaces a build issue Part 1 missed, surface to user.

## Scope (in)

### 3.1 C++ hot path — `core/p2p/audit/cxx/`

Implement two functions:

```c
// p2p_audit_capi.h
double p2p_cosine_similarity(const float* a, const float* b, int len);
double p2p_kendall_tau(const int* rank_a, const int* rank_b, int len);
```

**`p2p_cosine_similarity`:**
- Standard cosine: `dot(a, b) / (norm(a) * norm(b))`
- Returns NaN on invalid input (null pointers, len <= 0, zero-norm vector)
- v0: scalar loop is fine. v1+: SIMD via `<immintrin.h>` for AVX2/AVX-512
  paths, or `std::experimental::simd` if your compiler supports it. Don't
  pre-optimize for v0 — make it correct first.

**`p2p_kendall_tau`:**
- Standard Kendall's tau-b: count concordant minus discordant pairs,
  normalize by `n*(n-1)/2`.
- `O(n^2)` is acceptable for v0 (rerank inputs are typically n=10..100).
  v1+ can move to `O(n log n)` via merge-sort-with-inversions.
- Returns NaN on invalid input.

**Style constraints (Zig-discipline C++):**

- `-std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic`
- No `<iostream>`
- No exceptions, no RTTI
- `[[nodiscard]]` on internal pure functions that return values
- `noexcept` on all public functions
- `constexpr` where it makes sense (e.g., for any compile-time constants)

Internal C++ implementation can use modern idioms freely (templates,
`std::span`, etc.) — the constraints are at the FFI boundary and in the
no-exceptions discipline.

**C++ tests (`cxx/tests/similarity_test.cpp`):**

doctest-based. Cases:

- Cosine of identical vectors → 1.0
- Cosine of orthogonal vectors → 0.0
- Cosine of antiparallel vectors → -1.0
- Cosine handles small vectors (len=1, len=2)
- Cosine returns NaN on null pointers or len <= 0
- Cosine of zero vector returns NaN (not NaN-then-divide-by-zero-silently)
- Kendall tau of identical rankings → 1.0
- Kendall tau of reverse rankings → -1.0
- Kendall tau of random rankings reproduces reference values from a known
  Python `scipy.stats.kendalltau` run (precompute a handful of expected
  values and assert)
- Both functions handle large vectors (len=10000) without overflow

Build the standalone test binary (fast iteration):

```bash
g++ -std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic \
    -I cxx/include -I cxx/third_party \
    cxx/similarity.cpp cxx/tests/similarity_test.cpp \
    -o /tmp/p2p_audit_similarity_test && /tmp/p2p_audit_similarity_test
```

### 3.2 Go wrapper — `core/p2p/audit/similarity_cgo.go`

Thin cgo wrapper around the C++. Follow the pattern from
`core/p2p/cppexample/cppexample_cgo.go`:

```go
package audit

/*
#cgo CXXFLAGS: -std=c++23 -fno-exceptions -fno-rtti -O3 -Wall -Wextra -Wpedantic
#cgo CPPFLAGS: -I${SRCDIR}/cxx/include
#include "p2p_audit_capi.h"
*/
import "C"
import "unsafe"

func cosineSimilarity(a, b []float32) float64 { ... }
func kendallTau(rankA, rankB []int32) float64 { ... }
```

Go-level tests in `similarity_test.go` exercise the FFI boundary (the C++
tests already cover the math; these tests verify the Go bindings behave).

### 3.3 Serialization helpers — `core/p2p/audit/serde.go`

The interface passes `Output []byte` in `JobReceipt`. Audit deserializes.

- `SerializeEmbedding([]float32) []byte` — little-endian f32 packed
- `DeserializeEmbedding([]byte) ([]float32, error)` — inverse
- `SerializeRerankScores([]int32) []byte`
- `DeserializeRerankScores([]byte) ([]int32, error)`

Document the wire format in `core/p2p/audit/README.md`. The honest mock
provider (Part 1's responsibility) must produce outputs in the same format.

### 3.4 Audit Engine Go shell — `core/p2p/audit/audit.go`

In-memory state:

- `verifiers map[NodeID]*verifierRecord` — `{weight int64, pool PoolID}`
- `auditHistory []types.AuditOutcome` — last N=10000 audits, ring buffer
- `nodeFailRate map[NodeID]*emaCounter` — per-node EMA of failed audits
- `categoryFraudRate map[JobCategory]*emaCounter` — per-category EMA
- `referenceComputer iface.ReferenceComputer` — set via `SetReferenceComputer`

Concurrency-safe with `sync.RWMutex`.

`SubmitJobForAudit(job, receipt)`:

1. Compute current audit rate via `CurrentAuditRate(category, node)`.
2. Roll random number; if rate > random, proceed; else return
   `(audited=false, nil, nil)`.
3. Select N verifiers (3 for embedding, 5 for rerank, configurable):
   - Filter by pool independence: candidates whose pool != worker's pool
     AND candidates with pairwise-distinct pools among themselves.
   - Reputation-weighted random sample from the filtered candidates.
   - If fewer than N qualified candidates exist, use what's available
     (log a warning); audit still runs.
4. For v0, "calling N verifiers" is simulated: run
   `referenceComputer.Compute(job)` once and use that as the canonical
   reference. (Real distinct verifiers happen in v1+; for v0, the
   correctness check is "does the worker's output match the reference?")
5. Deserialize worker's output (`receipt.Output`) and the reference.
6. Compute similarity via the C++ hot path: `cosineSimilarity` for
   embeddings, `kendallTau` for rerank.
7. Compare against threshold for the worker's declared precision:

   ```go
   var EmbeddingThresholdByPrecision = map[Precision]float64{
       PrecisionFP32: 0.9999,
       PrecisionFP16: 0.999,
       PrecisionINT8: 0.99,
   }
   const RerankThreshold = 0.95
   ```

8. Compute severity:

   ```go
   severity := math.Max(0, (threshold - similarity) / threshold)
   ```

   - similarity at threshold → severity ≈ 0
   - similarity at 0.5 of threshold → severity ≈ 0.5
   - similarity at 0 (or worse) → severity ≈ 1

9. Build `AuditOutcome`, record in `auditHistory`, return.

`ForceAudit(job, receipt)`: same as steps 3-9 above, no rate roll.

`CurrentAuditRate(category, node)`: see § 3.5.

`ReportDetectedFraud(outcome)`: update `nodeFailRate` and
`categoryFraudRate` EMAs. These feed the next `CurrentAuditRate` call.

`RegisterVerifier(node, weight, pool)`: stores in `verifiers` map.

`SetReferenceComputer(rc)`: stores; required to be called before any audit.

### 3.5 Adaptive rate control law — `core/p2p/audit/control.go`

```go
const (
    FloorAuditRate     = 0.005   // 0.5% unconditional
    BaselineAuditRate  = 0.05    // 5% when healthy
    HighValueThreshold = 100 * types.USDC  // force-audit gates above
)

// CurrentAuditRate returns the rate for (category, node).
// Bounded in [FloorAuditRate, 1.0].
func (a *Engine) CurrentAuditRate(category types.JobCategory, node types.NodeID) float64 {
    // If we have job value context, force-audit high-value jobs.
    // (The orchestrator handles this gate via ForceAudit; here we just
    // report the rate that would apply.)

    baseline := BaselineAuditRate

    perNode := a.perNodeBump(node)
    perCategory := a.perCategoryBump(category)

    rate := baseline + perNode + perCategory
    if rate < FloorAuditRate {
        rate = FloorAuditRate
    }
    if rate > 1.0 {
        rate = 1.0
    }
    return rate
}
```

**`perNodeBump(node)`:**

- 0 if last 100 audits had zero failures
- Linearly up to 0.95 as failure rate over last 100 audits approaches 100%
- Hard 1.0 if any of last 10 audits had severity > 0.5

**`perCategoryBump(category)`:**

- EMA over last 1000 jobs in the category
- Linearly: 0 at fraud rate 0%, 0.5 at fraud rate 10%, 1.0 at fraud rate 50%+

Document the curves in code comments — they'll be tuned later.

### 3.6 Tests

#### Unit tests — `core/p2p/audit/audit_test.go`

- **Honest passes:** Mock ReferenceComputer returns fixed vector V. Worker
  receipt has output V serialized. ForceAudit → Pass=true, Similarity ≈ 1.0.
- **Dishonest fails:** Mock ReferenceComputer returns V. Worker output is
  random vector W. ForceAudit → Pass=false, Severity > 0.5.
- **Precision threshold (FP16):** Worker declares fp16; output's cosine to
  fp16 reference is 0.995. Audit fails (threshold 0.999).
- **Precision mismatch:** Worker declares fp16; output matches int8
  reference (cosine 0.99) better than fp16 reference. Audit fails because
  similarity to *declared* precision is below threshold.
- **Adaptive rate — healthy:** Submit 100 jobs from an honest node →
  `CurrentAuditRate(JobEmbedding, node)` stays at baseline (~0.05).
- **Adaptive rate — fraud spike:** Submit 10 failed audits from one node
  → that node's rate jumps to ~1.0 within the next call.
- **Floor maintained:** Even with zero detected fraud over 1000 audits,
  `CurrentAuditRate` is ≥ 0.005.
- **Reranker rank correlation:** Worker returns ranks [3,1,2] vs.
  reference [1,2,3]. Kendall tau is low. Audit fails.
- **Verifier independence:** Register 4 verifiers, 2 from pool A, 2 from
  pool B. For a job from pool C, the audit picks 3 verifiers spread
  across pools.
- **Insufficient verifiers:** Register only 2 verifiers (target is 3).
  Audit still runs with what's available; logs a warning.

#### Go-level FFI tests — `core/p2p/audit/similarity_test.go`

- Identical vectors → 1.0
- Orthogonal → 0.0
- Antiparallel → -1.0
- Both wrappers handle empty / mismatched-length inputs gracefully
- Race test: 100 goroutines calling cosineSimilarity concurrently

#### C++ tests — `core/p2p/audit/cxx/tests/similarity_test.cpp`

See § 3.1.

## Non-goals (NOT in scope)

- **Do not implement networking for verifiers.** v0 simulates verifiers
  by calling ReferenceComputer in-process. Real distributed verifiers are
  v1+.
- **Do not implement auditor payment.** The orchestrator handles auditor
  payments via `Ledger.PayoutFromReserve` after the audit completes; you
  don't directly call into Ledger.
- **Do not implement BGE-M3 itself.** Use the ReferenceComputer interface;
  Part 1's `BGEHonest` is the canonical reference. For unit tests, a small
  in-package mock returns canned vectors.
- **Do not implement SIMD optimization.** v0 = scalar correctness.
  Document where SIMD would slot in.
- **Do not edit other parts' directories.**

## Coordination with other parts

- **Part 1 (Orchestrator)** calls your interface during the lifecycle and
  injects a `ReferenceComputer`. Part 1 ships the cgo scaffolding example
  you mimic — read it carefully.
- **Part 4 (Federation)** provides pool affiliation for verifiers. You
  capture it at `RegisterVerifier(node, weight, pool)` time — no live calls
  into Federation during audit.
- **No direct calls to/from Part 2 (Ledger).**

## Deliverables (files you will create)

```
core/p2p/audit/audit.go                       (AuditEngine Go shell)
core/p2p/audit/control.go                     (adaptive rate logic)
core/p2p/audit/control_test.go                (control law tests)
core/p2p/audit/serde.go                       (embed/rerank serialization)
core/p2p/audit/serde_test.go
core/p2p/audit/similarity_cgo.go              (cgo wrapper for C++ hot path)
core/p2p/audit/similarity_test.go             (Go-level FFI tests)
core/p2p/audit/audit_test.go                  (engine unit tests)
core/p2p/audit/mock_ref_computer.go           (test helper)
core/p2p/audit/cxx/include/p2p_audit_capi.h
core/p2p/audit/cxx/similarity.cpp
core/p2p/audit/cxx/third_party/doctest.h      (copy from Part 1's example)
core/p2p/audit/cxx/tests/similarity_test.cpp
core/p2p/audit/cxx/README.md
core/p2p/audit/doc.go                         (package godoc summary)
```

## Definition of done

- C++ standalone test (`/tmp/p2p_audit_similarity_test`) passes all cases
- `go test ./p2p/audit/...` passes (cgo builds C++ inline)
- `go test -race ./p2p/audit/...` passes
- All 10 unit test scenarios from § 3.6 pass
- `go vet ./p2p/audit/...` clean
- ARM64 cross-compile works (or documented blocker)
- Package godoc explains public types

## When you're done

```bash
bin/adam release core/p2p-audit --keep-branch
```

Surface to the user: "Audit done, branch `<you>/p2p-audit` ready. C++ hot
path lives at `core/p2p/audit/cxx/`; cgo builds it inline via `go build`."

## Suggested subagent splits

You can spawn as many subagents as you like. Productive split:

- **Subagent A:** C++ similarity.cpp + doctest tests (pure math, isolated)
- **Subagent B:** cgo wrapper + Go-level FFI tests
- **Subagent C:** serde (embedding + rerank wire format)
- **Subagent D:** control.go adaptive rate + control_test.go
- **Subagent E:** audit.go engine wire-up + audit_test.go integration scenarios

C++ work (A) and Go work (B-E) can proceed almost entirely in parallel —
they only meet at the FFI boundary, which is the C ABI header from § 3.1.
Commit that header early so both sides can compile against it.
