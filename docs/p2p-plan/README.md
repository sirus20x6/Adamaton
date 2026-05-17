# P2P Compute Network — v0 Plan

Four-part parallelizable plan to bootstrap a decentralized compute marketplace
on the Adamaton stack. Designed so 4 orchestrator agents can work in
independent worktrees with minimal coordination overhead.

## How to use these files

1. **Every orchestrator reads:** `00-shared-context.md` and `01-contracts.md`.
   These are the system overview and the frozen interface contracts.
2. **Each orchestrator reads one of:** `part-1-foundation.md`,
   `part-2-ledger.md`, `part-3-audit.md`, `part-4-federation.md`.
3. **Each orchestrator claims its own worktree** via the `bin/adam claim`
   command in its plan file.
4. **Orchestrators may spawn as many subagents as they like** internally;
   the part files include suggested splits.

## Partition summary

| Part | Scope | Language | Worktree claim |
|------|-------|----------|----------------|
| 1 | Foundation (types, interfaces, orchestrator, providers, cgo scaffolding, harness) | Go (+ tiny C++ example) | `bin/adam claim core/p2p-foundation` |
| 2 | LedgerEngine (stake, escrow, slashing, tax, reserve) | Go | `bin/adam claim core/p2p-ledger` |
| 3 | AuditEngine (decision shell + C++ hot path for similarity) | Go + C++23 | `bin/adam claim core/p2p-audit` |
| 4 | FederationEngine (pools, reputation, telemetry) | Go | `bin/adam claim core/p2p-federation` |

## Intersection map

```
              ┌──────────────┐
              │ Part 1       │
              │ Foundation   │
              │ types, iface,│
              │ orchestrator,│
              │ cgo example  │
              └──────┬───────┘
                     │  iface contracts
        ┌────────────┼────────────┐
        ▼            ▼            ▼
   ┌────────┐  ┌────────┐  ┌──────────────┐
   │ Part 2 │  │ Part 4 │  │ Part 3       │
   │ Ledger │  │ Federa │  │ Audit        │
   │ (Go)   │  │ tion   │  │ Go shell +   │
   │        │  │ (Go)   │  │ C++ hot path │
   └────────┘  └────────┘  └──────────────┘
```

The only intersections between Parts 2/3/4 are interface calls through Part
1's `iface/` package. There are no shared state, no shared private types,
and no cross-part writes.

Part 3's C++ work follows the cgo pattern Part 1 establishes in
`core/p2p/cppexample/` — read that example carefully before starting.

## Critical rules

- **No merges yet.** The user has said: "see how far we can get before the
  first code merge, then reassess." Each orchestrator publishes their work
  with `git push -u origin <branch>` and then `bin/adam release
  <scope>/<task> --keep-branch` (which removes the worktree but preserves
  the branch). No PRs without explicit go-ahead.

- **No interface changes without approval.** If your implementation reveals
  a needed interface change, STOP and surface to the user. Don't edit
  `iface/` files unilaterally.

- **Workflow rules apply** (from umbrella `CLAUDE.md`): no commits to main,
  no `Co-Authored-By:` trailers, no `--no-verify`, no `@`-mentions in
  commit bodies. Hooks enforce these.

## Updates applied since the plan was first published

Each entry below has already been folded into the canonical files listed
in parens — they are kept here as a rebase checklist for orchestrators
whose branches predate the change.

- **`AuditOutcome` gained a `Worker NodeID` field** (canonical: `01-contracts.md`
  `## Shared types`; Part 1 foundation branch already includes it). Surfaced
  by Parts 1, 3, and 4 independently — `Federation.OnAuditOutcome` cannot
  attribute the rep delta without it, and cross-engine reads from
  Federation to Audit/Ledger are forbidden by the contract. The
  AuditEngine populates `outcome.Worker` from `job.Worker` at audit time.
  - **Part 3 rebase action:** remove the internal `jobWorker` index in the
    audit engine; set `Worker: job.Worker` when constructing outcomes.
  - **Part 4 rebase action:** read `outcome.Worker` directly in
    `OnAuditOutcome`; remove the "`Verifiers[0]` is the worker by
    convention" v0 hack.
  - **All parts:** drop your local bootstrap copy of `p2p/types/types.go`
    and `p2p/iface/*.go` on rebase. Part 1's branch owns those files.

- **Part 2 ledger math correction in §2.7** (canonical: `part-2-ledger.md`).
  The original "Honest job flow" example asserted `Available = 90 + (10 *
  0.97) = 99.7 USDC`, conflating released stake with settled payment. The
  contract treats them as independent flows: Release returns the locked
  stake to Available, then Settle adds a separate `value - tax` payment.
  Correct value is `100 + 9.7 = 109.7 USDC` (matches Part 2's
  implementation, which the spec text now reflects).

- **C++ `noexcept` + `-Wpedantic` interaction** (documented in Part 1's
  `cppexample/cxx/README.md`). With `-fno-exceptions`, declaring
  `noexcept` on the `extern "C"` definition triggers `-Wpedantic` if the
  C header lacks it. Fix: declare `noexcept` in the C ABI header inside
  an `#ifdef __cplusplus` guard so C sees the plain decl and C++ sees the
  `noexcept` one. Part 1's `cppexample` follows this pattern; Part 3's
  audit C ABI does not (dropped `noexcept` from definitions instead — also
  valid, but inconsistent). If Part 3 wants the `noexcept` annotation
  back on the symbols, copy Part 1's guard pattern.

- **`GOWORK=off` from inside worktrees.** The umbrella's `go.work` only
  lists `./core` proper, not `./core/core-worktrees/*`. All `go build` /
  `go test` invocations from inside a core worktree need `GOWORK=off`
  (including ARM64 cross-compile). Documented in Part 1's `p2p/README.md`
  and `p2p/cppexample/cxx/README.md`.

- **cgo's `.cpp` auto-discovery rule.** cgo only picks up `.cpp` files in
  the package directory itself, not in subdirectories. The canonical
  Layout A pattern (real source in `cxx/`, plus a one-line shim
  `<pkg>_cgo.cpp` in the package dir that `#include`s the real file) is
  used by both `p2p/cppexample/` (Part 1) and `p2p/audit/` (Part 3). See
  `p2p/cppexample/cxx/README.md` for the build pattern.

## After all 4 parts ship

v0 is done. The next phase is v1, which moves from in-memory simulation
to real on-chain backings.

## v1: ETH on Base

See [`v1-eth-foundation.md`](v1-eth-foundation.md) for the v1 design
strawman (locked decisions; gwei-native accounting; no oracle, no fiat).
It replaces the in-memory `LedgerEngine` and `FederationEngine` with
smart contracts on Base (L2), introduces the bootstrap mechanics
(donation-mint, premined founder credit, per-client credit lines), and
sketches v1.1 (stealth addresses + AA paymaster), v1.2 (ZK reputation),
and v1.3 (DVS-based non-transferable bindings) as follow-on phases.

The asset-neutral `Settler` abstraction introduced in v1.0 leaves the
door open for v2.x to add Monero (or any other asset) as a second
settlement adapter without touching protocol-internal code.

### v1.0 implementation — four-part partition

Mirroring the v0 structure: four orchestrators in parallel, each owning
one well-bounded slice. The per-orchestrator briefs:

| Part | Plan file | Worktree command | Approx. lines |
|------|-----------|------------------|---------------|
| **A** Solidity contracts | [`v1.0-part-A-contracts.md`](v1.0-part-A-contracts.md) | `bin/adam claim core/v1-eth-A` | ~1500 |
| **B** Go adapter layer | [`v1.0-part-B-go-adapter.md`](v1.0-part-B-go-adapter.md) | `bin/adam claim core/v1-eth-B` | ~2000 |
| **C** Bootstrap + identity registration | [`v1.0-part-C-bootstrap.md`](v1.0-part-C-bootstrap.md) | `bin/adam claim core/v1-eth-C` | ~800 |
| **D** Test infrastructure | [`v1.0-part-D-test-infra.md`](v1.0-part-D-test-infra.md) | `bin/adam claim core/v1-eth-D` | ~1000 |

Each orchestrator reads `00-shared-context.md` + `v1-eth-foundation.md`
+ their specific part file.

### Ownership boundaries (so the 4 parts don't stomp on each other)

- **Part A** owns `core/contracts/` (Solidity + Foundry).
- **Part B** owns `core/p2p/eth/` (Go adapter) + small extensions to
  `iface/federation.go`, `iface/audit.go`, and the `Money → Gwei` relabel
  in `types/types.go`.
- **Part C** owns `core/p2p/orchestrator/` (for v1.0 lifecycle changes)
  and `core/cmd/p2p-bootstrap/`.
- **Part D** owns `core/p2p/eth/testharness/` and `core/deploy/v1/`.

### Inter-part dependencies

```
   A (contracts) ─────────┬─────────► commits ABIs to core/contracts/abi/
                          │
   B (Go adapter) ────────┴────────── consumes ABIs via abigen
            │
            ├──► commits iface extensions early (Part C consumes)
            │
   C (bootstrap) ──────────────────── consumes B's iface + C's CLI is used by D's tests
            │
   D (test infra) ─────────────────── consumes A's deploy scripts, B's adapter, C's bootstrap CLI
```

Each orchestrator's plan file lists the specific deliverables, acceptance
criteria, and `bin/adam release` command. Branches are pushed for review;
no merges to main without explicit go-ahead.
