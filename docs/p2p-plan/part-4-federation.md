# Part 4 — Federation Engine

> **Required reading first:**
> - `docs/p2p-plan/00-shared-context.md` — system overview and design decisions
> - `docs/p2p-plan/01-contracts.md` — interface contracts (your interface is
>   defined verbatim there)
>
> Read both fully before starting.

## Your role

You implement the `FederationEngine` — the trust/social engine. You own:

- **Pool registry** (create / join / leave / tier assignment)
- **Reputation** (earned score + donated credit + pool endorsement)
- **Solo participation** (reputation cap at the solo ceiling)
- **Pool tier classification** (auto-tier from stake + members + volume)
- **Network-leader telemetry** (event emission for offline analysis)

You are the **only** orchestrator allowed to edit files in
`core/p2p/federation/`. The Federation is pure Go — no C++ needed.

## Worktree setup

```bash
cd /thearray/git/Adamaton
bin/adam doctor
bin/adam claim core/p2p-federation
```

## Dependency: Part 1's foundation

Same as Parts 2 and 3 — wait for Part 1's types and iface commits, rebase
against them when available. Bootstrap locally if Part 1 is delayed; rebase
later.

## Scope (in)

### 4.1 Pool registry — `core/p2p/federation/pools.go`

In-memory state:

- `pools map[PoolID]*poolRecord` — `{operator, params, members, current
  tier, volume}`
- `nodeToPool map[NodeID]PoolID` — quick reverse lookup
- `endorsements map[NodeID]int64` — pool endorsement per node (separate
  from EarnedScore)

Operations:

- `RegisterPool(operator, params)` — generates new `PoolID` (e.g., `pool-<hash>`
  of operator + counter for v0 simplicity). Stores. Emits `pool_create` event.
- `JoinPool(node, pool, attestation)` — errors if node already in another
  pool. Verifies pool exists. The `attestation` blob is opaque in v0 (any
  non-nil bytes accepted). Updates member list + reverse map. Emits
  `pool_join` event.
- `LeavePool(node)` — removes from member list and reverse map. Clears
  endorsement (`endorsements[node] = 0`). Does NOT modify EarnedScore.
  Emits `pool_leave` event.
- `GetPool(pool)` — returns pool record (deep copy, with current tier
  recomputed). Errors if pool doesn't exist.
- `PoolOf(node)` — returns `(PoolID, true)` if pooled, `("", false)` if solo.
- `PoolTaxRate(pool)` — returns the pool's configured tax rate.

### 4.2 Tier classification — `core/p2p/federation/tiers.go`

Tiers (matching the trust-privacy ladder in shared context):

```
Tier 1 (solo):   1 member, $0 volume, $0 total stake
Tier 2 (small):  ≤ $10k stake AND ≤ 50 members AND ≤ $1k volume
Tier 3 (mid):    ≤ $100k stake AND ≤ 500 members AND ≤ $10k volume
Tier 4 (large):  ≤ $1M stake AND ≤ 5000 members AND ≤ $100k volume
Tier 5 (mega):   anything above
```

Tier is the *max* of where the pool would land by each axis. A pool with
$50k stake but 5 members is still Tier 3 (stake bumps it up).

Tier is recomputed lazily on `GetPool` and on `RecordSettlement`. If the
tier changes from a previous reading, emit `tier_change` event.

`KYCRequired` is `true` if tier ≥ 3 (regardless of the pool's `params`
setting — that's a minimum, but tier 3+ forces it on).

For v0, total stake is computed from `operator + member` Available
balances. (You can't compute that without calling into Ledger — but the
interface forbids cross-engine calls. So for v0, total stake is tracked
as a counter that the orchestrator updates via... hmm.)

**Pragmatic v0 simplification:** instead of computing total stake from
Ledger state, the orchestrator passes total stake as an input. Add a
helper `UpdatePoolStake(pool PoolID, totalStake Money)` that the
orchestrator (or a test harness) calls periodically. Surface this as a
needed interface addition to the user. If approved, implement; if not,
just track member count + volume and document the gap.

(Alternative: just track member count + volume in v0 — tier classification
will be looser but doesn't need cross-engine calls. Take this approach as
the default.)

### 4.3 Reputation — `core/p2p/federation/reputation.go`

State:

- `reputations map[NodeID]*reputationRecord` — `{EarnedScore int64,
  DonatedVerified Money, ...}`

Operations:

- `GetReputation(node)` — returns record (copy). Initializes a zero record
  if the node hasn't been seen.
- `AddDonationCredit(node, verifiedValue)` — increments DonatedVerified.
  Errors on non-positive value.
- `OnAuditOutcome(outcome)`:
  - If `outcome.Pass`: increment EarnedScore by `+1` (v0 keeps it simple;
    v1+ weights by job value)
  - If `!outcome.Pass`: decrement EarnedScore by `+10` (asymmetric: cheating
    costs more than honesty earns). Floor at 0.

### 4.4 Pool endorsement (revocable)

- `SetPoolEndorsement(pool, node, amount)` — pool operator endorses a
  member. Stores in `endorsements` map. Errors if node not a member of pool.
  Emits `endorsement_set` event.
- `RevokePoolEndorsement(node)` — clears endorsement. Emits
  `endorsement_revoke` event.

The orchestrator decides who's allowed to call SetPoolEndorsement; you
just store. (v1+ adds operator-authorization checks.)

### 4.5 Effective reputation cap

`EffectiveReputationCap(node)`:

```go
const SoloCap int64 = 100  // configurable later

rep, _ := f.GetReputation(node)
_, pooled := f.PoolOf(node)

donatedCap := int64(rep.DonatedVerified / types.USDC)  // 1 USDC = 1 rep unit

var rawCap int64
if pooled {
    rawCap = rep.EarnedScore + f.endorsements[node]
} else {
    rawCap = min(rep.EarnedScore, SoloCap)
}

// Bound by donation ceiling (the market-rate-of-donated-compute rule)
return min(rawCap, donatedCap)
```

The rules:

1. Solo nodes can't exceed `SoloCap` regardless of their EarnedScore.
2. Pooled nodes can exceed `SoloCap` via EarnedScore + pool endorsement.
3. Both are bounded above by their `DonatedVerified` in score units —
   the "reputation never exceeds market rate of donated compute" rule.

### 4.6 Volume tracking — `RecordSettlement(pool, value)`

- Add to the pool's `Volume` counter.
- Recompute tier; if it changed, emit `tier_change` event.

### 4.7 Telemetry — `core/p2p/federation/telemetry.go`

In-memory event sink:

- `events []TelemetryEvent` — append-only ring buffer (max size 10000 for v0)

Operations:

- `EmitEvent(event)` — appends, evicts oldest if at capacity.
- `DrainEvents()` — returns + clears buffer (atomic swap).

Events emitted *by* Federation:

- `pool_create`, `pool_join`, `pool_leave`
- `tier_change`
- `endorsement_set`, `endorsement_revoke`
- `donation_credit_added`
- `audit_outcome_processed` (on `OnAuditOutcome`)

The orchestrator also emits events through Federation (`EmitEvent`):

- `slash`, `audit_fail`, `audit_pass`, `settle` (orchestrator calls
  `federation.EmitEvent` so Federation is the single telemetry sink for
  the network-leader observability layer)

### 4.8 Tests

#### Unit tests — `core/p2p/federation/federation_test.go`

- **Pool create + join + leave:** Two nodes register a pool, join it,
  leave it. Membership tracked. Events emitted.
- **Solo cap:** Node with EarnedScore 200 but solo →
  `EffectiveReputationCap` is `SoloCap` (100), bounded down by
  `min(200, 100) = 100`.
- **Pool extends cap:** Solo node has EarnedScore 100. Joins pool. Pool
  endorses with +200. `EffectiveReputationCap` is 300 (or capped at
  DonatedVerified, whichever lower).
- **Donation cap binding:** Node has EarnedScore 500, in a pool with
  endorsement 200, but DonatedVerified only `100 * USDC` →
  `EffectiveReputationCap` is 100 (donation ceiling wins).
- **Pool exit preserves earned rep:** Node earns 100, joins pool, gets
  endorsed +200 → cap = 300. Leaves pool → cap drops back. EarnedScore
  is still 100. Only the endorsement was revoked.
- **Tier transitions:** Register pool with low parameters. Add members
  + volume to push tier up. Each crossing emits `tier_change`.
- **KYC auto-on at tier 3:** Pool starts KYCRequired=false. Grow to
  tier 3. `GetPool` returns KYCRequired=true regardless of original setting.
- **OnAuditOutcome rep changes:** Pass=true increments EarnedScore by 1;
  Pass=false decrements by 10, floored at 0.
- **Telemetry drain:** Multiple operations emit events; DrainEvents
  returns them in order, then buffer is empty.
- **Concurrent ops:** 100 goroutines calling RegisterPool / JoinPool /
  OnAuditOutcome / GetReputation — no race conditions (use `-race`).

## Non-goals (NOT in scope)

- **Do not implement persistence.**
- **Do not implement KYC verification.** Attestation blob is opaque in v0;
  any non-nil bytes pass.
- **Do not implement appeals / dispute resolution.** v1+.
- **Do not implement operator-authorization for SetPoolEndorsement.** Trust
  the orchestrator's caller in v0.
- **Do not implement governance of the 1% tax.** Deferred per shared context.
- **Do not call into Ledger or Audit.** All cross-engine reads go through
  the orchestrator.
- **Do not edit other parts' directories.**

## Coordination with other parts

- **Part 1 (Orchestrator)** calls your interface during the lifecycle:
  `GetReputation`, `EffectiveReputationCap`, `OnAuditOutcome`,
  `RecordSettlement`, `EmitEvent`.
- **Part 3 (Audit)** captures pool affiliation at verifier-registration
  time (no live call into Federation during audit). The PoolID flows through
  `RegisterVerifier`.
- **Part 2 (Ledger)** doesn't talk to you directly. The orchestrator reads
  `PoolTaxRate` from you and passes the float to `Ledger.SettleJob`.

## Deliverables (files you will create)

```
core/p2p/federation/federation.go        (FederationEngine wire-up)
core/p2p/federation/pools.go             (pool registry)
core/p2p/federation/tiers.go             (tier classification)
core/p2p/federation/reputation.go        (rep state + cap calculation)
core/p2p/federation/telemetry.go         (event sink + drain)
core/p2p/federation/state.go             (internal state types)
core/p2p/federation/federation_test.go   (integration unit tests)
core/p2p/federation/pools_test.go        (registry tests)
core/p2p/federation/tiers_test.go        (tier transition tests)
core/p2p/federation/reputation_test.go   (cap calc tests)
core/p2p/federation/telemetry_test.go    (event sink tests)
core/p2p/federation/doc.go               (package godoc summary)
```

## Definition of done

- `go test ./p2p/federation/...` passes
- `go test -race ./p2p/federation/...` passes
- All 10 unit test scenarios from § 4.8 pass
- `go vet ./p2p/federation/...` clean
- Package godoc explains public types

## When you're done

```bash
git push -u origin <your-branch>           # branch shown by 'bin/adam claim'
bin/adam release core/p2p-federation --keep-branch
```

(We're NOT merging yet — no PR. `git push` publishes your branch; release
with `--keep-branch` removes the worktree but preserves the branch.)

Surface to the user: "Federation done, branch pushed."

## Suggested subagent splits

- **Subagent A:** pools.go + tiers.go + their tests (registry + tier classifier)
- **Subagent B:** reputation.go + reputation_test.go (rep state + cap calc)
- **Subagent C:** telemetry.go + telemetry_test.go (event sink)
- **Subagent D:** federation.go (wire-up) + federation_test.go (integration scenarios)
