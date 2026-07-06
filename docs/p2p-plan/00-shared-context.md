# P2P Decentralized Compute Network — Shared Context

> This document is required reading for all 4 orchestrators working on the
> P2P network bootstrap. Read this in full before reading your part-specific
> plan file. The design here is the output of five turns of design iteration
> with the project owner and is the source of truth for the v0 work.

## Vision

A P2P decentralized network where people exchange compute for crypto. Users
install a base container, an identity is generated, they pick plugins (compute
services they want to run), set up their nodes, and their identity spans all
their compute. WireGuard provides intra-identity LAN (all of *one user's*
nodes mesh privately).

A reputation system + proof-of-work-style verification ensures advertised
compute is actually delivered. Users earn credits by selling compute, spend
credits to buy compute (often for bursty AI workloads where local compute is
too slow). The protocol skims a small network tax to fund verification
infrastructure and operations.

## v0 wedge: embedding + rerank, NOT inference

LLM inference is hard to verify because outputs are nondeterministic across
GPUs / inference engines / batch sizes / quantization, even at temp=0.
Embeddings and rerankers are much easier:

- Outputs are fixed-size vectors / score lists
- Comparable via cosine similarity (embeddings) or rank correlation (rerankers)
- Tolerant of 1e-4 FP drift across hardware
- Already in production in this repo (BGE-M3 via the `octen` package)

v0 implements an embedding + rerank marketplace only. Inference, training, and
other workloads are explicitly out of scope until the audit mechanism is
proven.

## Language strategy

The system splits across two languages by responsibility:

- **Go** for business logic — orchestrator state machine, ledger book-keeping,
  federation/pool registry, reputation tracking. This is where Adamaton
  already lives (`core/octen`, `core/llmclient`, `core/pgutil`,
  `core/workerregistry`, etc.) so integration is cheap. Performance is not
  the bottleneck for these layers.

- **C++23 in "Zig style"** for performance-critical hot paths — similarity
  scoring (cosine, Kendall tau), audit replay execution (eventually
  BLAS-backed), crypto primitives (later), libp2p-equivalent networking
  (later). Discipline: no exceptions, explicit error returns, allocator-aware,
  no streams, no RTTI unless necessary. Compile with `-std=c++23
  -fno-exceptions -fno-rtti -Wall -Wextra -Wpedantic`.

**FFI boundary:** Go calls C++ via `cgo`. The C ABI is the contract — only
POD types, pointers, and integers cross. Each C++ hot path exposes a small
`extern "C"` API. See `01-contracts.md § C++ FFI conventions` for the
canonical pattern.

**Where C++ lives:** inside the same Go packages, in `cxx/` subdirectories.
cgo compiles the C++ at `go build` time. No CMake for v0 — the build is `go
build ./...` and that's it. If we grow past what cgo's inline compilation
handles, we can move to a separate build system.

## Core primitives

### Identity

A node has a cryptographic identity (Ed25519 keypair, but v0 stores opaque
pubkey bytes; signature verification is a v1+ concern). A user can own many
nodes — all their nodes share an "owner" identifier that WireGuard binds
into a single LAN. For v0, identity is a flat `NodeID` (= public key hash).
Multi-node ownership and WireGuard mesh bring-up are v1+.

### Stake

Stake is **capital at risk per job**. The maximum lie value a worker can pull
off is bounded by the worker's liquid stake. To take on a job worth $V, the
worker locks $V × stake_multiplier of their stake.

- Stake is denominated in micro-USDC (`int64`) in v0. Future: USDC on Base.
- Stake multiplier is per-category: cheap categories (single embedding) ~10×
  face value; high-value categories use multiples of job value.
- Stake is locked on job acceptance, released on settlement, slashed on
  confirmed fraud.

### Reputation

Reputation is the worker's **qualification for high-value jobs**. Separate
from stake. Earned by passing audits over time.

- Reputation cap is bounded by `verified_donated_compute_value`. A node can't
  have reputation exceeding the market-rate value of compute they've donated.
- Individually-earned reputation is non-confiscable on pool exit.
- A pool may extend additional reputation as a member endorsement; the
  endorsement is revocable, but revocation does not retroactively confiscate
  work done while endorsed.

### Donation-to-start

To bootstrap reputation, a new node donates compute. The donation is verified
via the same audit mechanism as paid work — otherwise attackers donate fake
work to fake-stake real work.

- Donation value is denominated in USDC at the time of donation.
- Solo participants have a reputation cap = baseline donation amount. To
  exceed this cap, the node must join a pool.

### Audit

Audits replay a job on independent verifier nodes and compare the verifier's
output to the worker's claimed output. For embeddings: cosine similarity.
For rerankers: Kendall's tau.

**Precision-declared serving.** A worker advertises the precision they serve
(`BGE-M3 @ fp16`). Audits compare against the declared precision's reference
output. Cheating = claiming fp16 but secretly serving int8 (cosine sim drops
from ~0.9999 to ~0.99 — detectable).

**Verifier independence.** No two verifiers from the same pool.
Reputation-weighted selection so high-rep verifiers are picked more often.

**Replay cost.** Auditing is paid for from the network tax + insurance
reserve. Verifiers earn from each audit they perform.

### Federations (not "feudalism")

Pools are voluntary aggregations of nodes that:

- Set an additional tax on top of the network tax (capped)
- Run an internal trust system (KYC, attestations) layered on the protocol audit
- Provide internal enforcement for emerging fraud patterns ("pool police")
- Tier-scaled verification requirements: small pools may be privacy-respecting
  (anonymous members, light KYC); large pools (tier ≥ 3) required to publish
  operator identity + audited financials.

Pool tier is derived from `(total_stake, member_count, transaction_volume)`.

**Appeals.** Pool internal decisions can be appealed to the protocol-level
arbiter (network leaders + tribunal of high-rep cross-pool nodes). Without an
appeals path, "pool police" becomes a shakedown operation.

**Pool-level slashing.** A pool found running unfair internal enforcement
(false slashing, audit collusion) gets slashed at the pool level. The pool
operator's staked collateral is at risk.

### Solo participation

Solo nodes operate without joining a pool. They pay only the network tax
(no pool tax), are capped at the solo reputation ceiling (= baseline
donation tier), and receive the same audit treatment as pool members. Solo
is intentionally viable to prevent forced pool participation (the
cartelization failure mode).

### Network tax + insurance reserve

- The protocol takes 1% of every settled job (elastic; floor 0.5%, ceiling
  set by the control law).
- The tax replenishes an **insurance reserve** that funds:
  - Auditor payments
  - Restitution for confirmed-fraud victims
  - Network-leader operational costs
- A pool's additional tax stacks on top of the network tax.

### Settlement

- Internal accounting in **micro-USDC** (`int64`, 1e-6 USDC). Avoids float,
  matches stablecoin precision.
- v0 settles in-memory; no real chain.
- v1+: USDC on Base / Arbitrum L2 (cheap, fast, EVM tooling).
- v1+ for bursty workloads: payment channels or batched off-chain receipts
  settled periodically.

## Adaptive control law for audit + tax rates

Both the audit rate and the network tax are **elastic**: they scale up under
network stress (rising detected fraud, depleting insurance reserve).

### Three control signals, three time-scales

- **Slow:** insurance-reserve depletion rate (drives baseline tax)
- **Medium:** per-node failed-audit rate (drives per-node audit rate)
- **Fast:** per-category anomaly detection (drives per-category audit budget)

### Guardrails against runaway underseverity

- A **floor of unconditional random audits** (~0.5% of all jobs) regardless
  of detected fraud. The independent thermometer.
- Audit budget is **per-category**, not global — cheap-category fraud waves
  can't drain the budget that protects high-value categories.
- Slashing math: `audit_probability × slash_amount > cheat_payoff`. Slashing
  is multiples of job value, not 1×. High-value jobs are ~100% audited so
  slash factor can be smaller.

## Trust ↔ privacy ladder

| Tier | Stake | Members | Verification | Privacy |
|------|-------|---------|--------------|---------|
| 1 (solo) | n/a | 1 | protocol audit only | anonymous OK |
| 2 (small) | <$10k | <50 | pool op attests members exist | members anonymous |
| 3 (mid) | <$100k | <500 | pool op identity public, member KYC tier-1 | members pseudonymous |
| 4 (large) | <$1M | <5000 | pool op audited financials, member KYC tier-2 | pool ops transparent |
| 5 (mega) | $1M+ | 5000+ | regulated entity, external audits | full disclosure |

Tier transitions happen automatically as stake/members/volume cross
thresholds; pools that cross a threshold and refuse to meet new disclosure
requirements get downgraded (loss of high-value job access).

## Governance: deferred

Network leaders (project founders) take the 1% baseline tax for v0/v1.
Governance of those funds is **explicitly deferred** — known open question.
Reasonable transition paths (DAO, token-governance, foundation) are not
chosen yet. Revisit after v1.

## Non-goals for the v0 plan-files work

- **Real networking.** No libp2p, no gossip, no NAT traversal. All v0 code
  runs in a single Go process.
- **Real cryptography.** Stake transfers are in-memory state mutations.
  No signatures, no chain interaction.
- **Multi-model.** BGE-M3 only. No model registry.
- **Inference / training.** Embedding + rerank only.
- **Persistence.** No database. State lives in memory; reset on restart.
- **UI / dashboard.** No frontend work.
- **WireGuard setup.** Identity is just an ID, no LAN bring-up.
- **Token issuance.** USDC is the unit of account.
- **Governance mechanism.** Network leaders are a constant for v0.

## Glossary

- **NodeID** — public key hash; identifies a single node.
- **PoolID** — identifies a federation pool.
- **JobID** — identifies a single unit of compute work.
- **AuditID** — identifies a single audit event.
- **Money** — `int64` micro-USDC (1 USDC = 1_000_000 Money units).
- **Engine** — one of the three pluggable subsystems (Ledger, Audit, Federation).
- **Orchestrator** — Part 1's lifecycle state machine that calls into the engines.
- **Worker / Provider** — a node that does compute work for paying clients.
- **Verifier / Auditor** — a node that re-runs jobs for verification.
- **Publisher** — a node that pays for compute.

## How the 4 parts fit together

- **Part 1 (Foundation, Go):** bootstraps `core/p2p/`, defines canonical Go
  interfaces and types, implements the lifecycle orchestrator, owns the
  cgo scaffolding pattern, ships `ComputeProvider` implementations and
  the integration test harness.
- **Part 2 (Ledger, Go):** implements the LedgerEngine (stake, escrow,
  slashing, tax accounting, insurance reserve).
- **Part 3 (Audit, Go + C++):** implements the AuditEngine. Go shell owns
  decision logic / control law / verifier selection. C++23 hot path owns
  similarity scoring (cosine, Kendall tau). Connected via cgo using the
  pattern Part 1 establishes.
- **Part 4 (Federation, Go):** implements the FederationEngine (pool
  registry, reputation, tier verification, network-leader telemetry).

The parts touch each other only via the Go interfaces in `01-contracts.md`.
**Interfaces are frozen in the plan files.** If your implementation needs
an interface change, STOP and surface it — don't change interfaces yourself.

## Sequencing

Each orchestrator works in its own worktree of the `core` sub-repo. The
worktrees live on independent branches and don't merge to `main` yet — the
user has explicitly said: "see how far we can get before the first code
merge, then reassess." Treat your branch as in-flight; don't open PRs
without checking in.

## Workflow rules (umbrella CLAUDE.md)

- **Never commit to main directly.** Hook-enforced. Always `bin/adam claim`
  first. Your plan file tells you the exact claim command.
- **No `Co-Authored-By:` trailers.** Hook-enforced.
- **No `--no-verify` or hook-skipping.** Hook-enforced.
- **No `@`-mentions in commit message bodies.** Hook-enforced.
- **Publishing your work:** `git push -u origin <branch>` (the branch name
  is printed by `bin/adam claim`), then `bin/adam release <scope>/<task>
  --keep-branch`. The push makes your branch visible to the user and the
  other orchestrators; the release removes your worktree but keeps the
  branch on disk (with `--keep-branch`). We are NOT merging yet, so do
  not open a PR.
