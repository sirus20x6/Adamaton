# Part 2 — Ledger Engine

> **Required reading first:**
> - `docs/p2p-plan/00-shared-context.md` — system overview and design decisions
> - `docs/p2p-plan/01-contracts.md` — interface contracts (your interface is
>   defined verbatim there)
>
> Read both fully before starting.

## Your role

You implement the `LedgerEngine` — the economic engine. You own:

- **Stake** management (deposit / withdraw / lock per-job / release)
- **Slashing** mechanics (graduated slash fractions on confirmed fraud)
- **Tax accounting** (network tax + per-pool tax on settlement)
- **Insurance reserve** (deposits from taxes + slashes; payouts for
  restitution and auditor compensation)
- **Settlement** of paid work after clean release

You are the **only** orchestrator allowed to edit files in `core/p2p/ledger/`.

The Ledger is pure Go — no C++ hot path needed. Performance is not a v0
concern here; correctness and concurrency safety are.

## Worktree setup

```bash
cd /thearray/git/Adamaton
bin/adam doctor
bin/adam claim core/p2p-ledger
```

## Dependency: Part 1's foundation

You depend on Part 1 having committed `core/p2p/types/types.go` and
`core/p2p/iface/ledger.go`. Sequence:

1. Wait for Part 1's branch (`<them>/p2p-foundation`) to push commits with
   the types and iface files. This should happen within the first hour or
   two of Part 1's work — surface to the user if you're blocked waiting.
2. Once available, rebase your branch onto Part 1's branch (`git fetch
   origin && git rebase origin/<them>/p2p-foundation`).
3. If Part 1 is delayed, you may bootstrap locally: copy the type and
   interface declarations from `01-contracts.md` verbatim into local files,
   work against them, and rebase later. Part 1's verbatim version is the
   source of truth — your local copy will be discarded.

## Scope (in)

### 2.1 In-memory state

Implement an in-memory state container:

- `stakes map[NodeID]*stakeRecord` — each node's Available + Locked
- `insuranceReserve types.Money` — accumulating pool
- `networkTaxRate float64` — mutable, set via `UpdateNetworkTaxRate`
- `journal []settlementEntry` — for debugging + telemetry pull

All operations protected by `sync.RWMutex`. Aim for fine-grained locking
where reasonable; but a single-mutex implementation is acceptable for v0
since contention isn't a v0 concern.

### 2.2 Stake operations

- `DepositStake(node, amount)` — increments Available. Errors on
  non-positive amount.
- `WithdrawStake(node, amount)` — decrements Available. Errors if
  Available < amount, or if any Locked entry exists for the node (can't
  withdraw while jobs in flight).
- `GetStake(node)` — returns the current state (deep copy, not the live
  pointer; callers should not be able to mutate engine state through the
  returned struct).

### 2.3 Per-job escrow

- `LockForJob(node, jobID, amount)` — moves `amount` from Available to
  `Locked[jobID]`. Errors if Available < amount or jobID already locked
  for any node.
- `ReleaseFromJob(jobID, slashFraction)` — finds the lock for jobID,
  splits the locked amount:
  - `slashed = locked * slashFraction` → insurance reserve
  - `returned = locked * (1 - slashFraction)` → node's Available
  - Returns `(slashed, returned, nil)` or error if jobID not found.
- `slashFraction` is `float64` in `[0, 1]`. Caller (orchestrator) computes
  from audit outcome severity.

**Rounding policy.** When splitting `locked * slashFraction`, use
`int64`-safe rounding (`int64(math.Round(...))`). The two split portions
must sum exactly to the locked amount (no lost dust). Achieve this by
computing one portion via rounding and deriving the other via subtraction:

```go
slashed := types.Money(math.Round(float64(locked) * slashFraction))
returned := locked - slashed
```

### 2.4 Settlement

`SettleJob(jobID, worker, value, networkTaxRate, poolTaxRate)`:

- Verifies the job is no longer locked (must come after ReleaseFromJob).
  If still locked, error.
- Computes:
  - `networkTax = Money(math.Round(float64(value) * networkTaxRate))`
  - `poolTax = Money(math.Round(float64(value) * poolTaxRate))`
  - `paid = value - networkTax - poolTax`
- If `paid <= 0`, error (`tax rates too high`).
- Credits `paid` to worker's Available balance.
- Credits `networkTax + poolTax` to insurance reserve (v0 collapses pool
  tax into the network reserve; v1+ will route pool tax to the pool
  operator).
- Records entry in journal: `{jobID, worker, value, networkTax, poolTax,
  paid, at: time.Now()}`.
- Returns `(paid, nil)`.

**Tax cap.** Enforce a constant `MaxCombinedTaxRate = 0.5`. If
`networkTaxRate + poolTaxRate > MaxCombinedTaxRate`, error. Defends against
caller mistakes.

### 2.5 Network tax rate management

Constants:

```go
const (
    NetworkTaxFloor   = 0.005  // 0.5%
    NetworkTaxCeiling = 0.05   // 5%
    DefaultNetworkTaxRate = 0.01  // 1% baseline
)
```

- `NetworkTaxRate()` — current value (initialized to default).
- `UpdateNetworkTaxRate(newRate)` — errors if outside
  `[NetworkTaxFloor, NetworkTaxCeiling]`.

You do **not** implement the control law (that's the orchestrator's job
or a separate controller). You only expose the setter and getter.

### 2.6 Insurance reserve

- `InsuranceReserve()` — current value.
- `PayoutFromReserve(to, amount, reason)` — decrement reserve, increment
  recipient's Available. Error if reserve < amount. Records to journal
  with reason.

## Tests

### 2.7 Unit tests — `core/p2p/ledger/ledger_test.go`

- **Honest job flow:** Deposit 100 USDC → LockForJob 10 USDC →
  ReleaseFromJob(0.0) → SettleJob with networkTax=0.01, poolTax=0.02 →
  assert: Available is `90 + (10 * 0.97) = 99.7 USDC`, reserve is
  `0.3 USDC`.
- **Full slash:** Deposit 100 → LockForJob 10 → ReleaseFromJob(1.0) →
  assert reserve = 10, Available = 90, no SettleJob possible.
- **Partial slash:** Deposit 100 → LockForJob 10 → ReleaseFromJob(0.5) →
  assert reserve = 5, Available returns 5 to the node, total Available now 95.
- **Tax accounting:** SettleJob with networkTax=0.01, poolTax=0.02 →
  reserve grew by exactly 3% of value, worker got 97%.
- **Tax cap guard:** SettleJob with rates summing > 0.5 errors.
- **Withdraw guards:** Can't withdraw if any Locked entry exists.
- **Lock guards:** Can't LockForJob with same JobID twice.
- **Capital efficiency:** Available 100, lock 10 jobs of 1 each → 10
  locked, 90 available. Try to lock an 11th of 95 → error.
- **Tax rate guards:** UpdateNetworkTaxRate(0) and (0.1) error;
  UpdateNetworkTaxRate(0.01) succeeds.
- **PayoutFromReserve:** Error if reserve < amount; success decrements
  reserve and credits recipient.
- **Dust-free rounding:** With locked = 7 and slashFraction = 0.3,
  slashed + returned == 7 exactly (no off-by-one).

### 2.8 Race tests — `core/p2p/ledger/ledger_concurrent_test.go`

- 1000 LockForJob calls from 100 goroutines on the same node with random
  unique JobIDs — assert final state is consistent (no double-lock, no
  lost locks; sum invariant holds). Use `go test -race`.
- 100 goroutines concurrently calling Deposit + Withdraw — assert final
  balance matches sum of operations.
- Concurrent Settle + Lock for different jobs — no deadlock, no
  inconsistent state.

### 2.9 Property tests — `core/p2p/ledger/ledger_property_test.go`

Use `testing/quick` or write a small fuzz loop:

For any random sequence of (Deposit, Lock, Release, Settle, Withdraw,
PayoutFromReserve) operations, the invariant holds:

```
sum(Available for all nodes) +
sum(Locked across all jobs and nodes) +
InsuranceReserve()
==
sum(all Deposits) - sum(all Withdraws)
```

(Insurance reserve grows from slashes and taxes, which are internal
redistributions; the total system value equals what came in minus what
went out.)

Run 1000+ random sequences.

## Non-goals (NOT in scope)

- **Do not implement the adaptive tax control law.** That belongs in
  the orchestrator (Part 1) or a separate controller package. Your
  engine exposes the setter and getter only.
- **Do not implement persistence.** All state in memory.
- **Do not implement on-chain settlement.** v0 is in-memory.
- **Do not implement payment channels or batched receipts.** v1+.
- **Do not edit Part 1, 3, or 4 directories.** Surface needed interface
  changes; do not commit them yourself.

## Coordination with other parts

- **Part 1 (Orchestrator)** calls your interface during the job lifecycle.
- **Part 4 (Federation)** does NOT call into Ledger. The orchestrator
  reads PoolTaxRate from Federation and passes it to SettleJob.
- **Part 3 (Audit)** does NOT call into Ledger directly.

## Deliverables (files you will create)

```
core/p2p/ledger/ledger.go                  (LedgerEngine implementation)
core/p2p/ledger/state.go                   (internal state types if needed)
core/p2p/ledger/journal.go                 (settlement journal helpers)
core/p2p/ledger/ledger_test.go             (unit tests)
core/p2p/ledger/ledger_concurrent_test.go  (race tests)
core/p2p/ledger/ledger_property_test.go    (property-based tests)
core/p2p/ledger/doc.go                     (package godoc summary)
```

## Definition of done

- `go test ./p2p/ledger/...` passes
- `go test -race ./p2p/ledger/...` passes
- All unit tests from § 2.7 pass
- Property invariant holds across 1000+ random sequences
- Package godoc explains the public types

## When you're done

```bash
bin/adam release core/p2p-ledger --keep-branch
```

Surface to the user: "Ledger done, branch `<you>/p2p-ledger` ready."

## Suggested subagent splits

- **Subagent A:** scaffold + state + basic ops (Deposit / Withdraw / Lock
  / Release / Settle / Reserve)
- **Subagent B:** unit tests (each scenario in § 2.7 as a separate test
  function)
- **Subagent C:** race tests + property tests
