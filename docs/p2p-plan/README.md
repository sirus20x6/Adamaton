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

## After all 4 parts ship

The user reassesses direction. Possible next moves:
- Wire stubs → real engines in Part 1's integration test, verify end-to-end
- Add real cryptographic identity (Ed25519 signatures on jobs)
- Add real networking (libp2p)
- Move to a real chain settlement layer
- Build a control law that adjusts network tax rate based on insurance
  reserve depletion

None of those are in v0 scope.
