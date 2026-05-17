# v1: ETH on Base — Foundation

> Status: design strawman (2026-05-17). Not yet implemented. Holds the
> architectural decisions that v0 deferred to "v1+" in `00-shared-context.md`.

## How v1 relates to v0

v0 shipped a single-process Go simulation: in-memory ledger, in-memory
federation, in-memory orchestrator, with a C++23 hot path for similarity
scoring. All four parts live behind interface contracts in `core/p2p/iface/`.

v1 replaces the in-memory ledger and federation engines with **on-chain
backings**: real smart contracts on a Base L2, real ETH at stake, real
oracle-converted USD-equivalent accounting. The orchestrator and the
audit engine stay primarily Go-side; only the *state* moves on-chain.
The interface contracts in `iface/` are preserved — v1 implementations
satisfy the same Go interfaces, so the orchestrator doesn't notice the
difference.

## v1 roadmap — three phases

| Phase | Scope | Adds |
|-------|-------|------|
| **v1.0** | ETH foundation: smart contracts on Base; Go adapter layer; oracle-driven USD accounting; bootstrap mechanics (donation-mint, premined founder credit, per-client credit lines) | This document |
| **v1.1** | Stealth addresses (EIP-5564) on the payment path; ERC-4337 Account Abstraction with a paymaster for gas-payer privacy | Separate doc later |
| **v1.2** | ZK reputation via Semaphore-based group proofs; on-chain reputation commitments instead of plaintext scores | Separate doc later |

Each phase ships independently. v1.0 is the only one that must precede the
others — v1.1 and v1.2 layer on top of v1.0's contracts.

## v1.0 goals + non-goals

### Goals

- Replace in-memory LedgerEngine and FederationEngine with on-chain backings
- Settle compute jobs in ETH on Base, with USD-equivalent internal accounting
- Working bootstrap mechanic: identity registration via donation, premined
  founder credit, per-client credit extension to new nodes
- Asset-neutral internal accounting (`Money int64` = micro-USD via oracle).
  This is the abstraction that lets v2 add Monero (or any other asset) as
  a second `Settler` adapter without rewriting protocol-internal code.
- Local Anvil test environment for fast iteration; Base Sepolia for
  integration-realism

### Non-goals (deferred)

- **Stealth addresses** — v1.1.
- **ZK reputation** — v1.2.
- **On-chain privacy in any form** — v1.0 is fully transparent.
- **Multi-asset settlement** (XMR, BTC, etc.) — architecture supports it,
  no second adapter shipped.
- **Distributed verifiers** — audit replays remain in-process. The
  *outcomes* are posted on-chain; the *computation* is local.
- **Mainnet deployment** — testnet only for v1.0.
- **Production-grade audits of contracts** — v1.0 ships unaudited to
  testnet. Audit happens before any mainnet move.
- **Governance** — network-leader multisig retains upgrade keys; v1
  doesn't address the token / DAO transition deferred in v0 context.

## Architecture overview

```
┌─────────────────────────────────────────────────────┐
│ Go application (existing core/p2p/*)                │
│   orchestrator                                       │
│   providers (BGE-M3, mocks)                          │
│   audit engine (in-process replay + control law)     │
│   testharness                                        │
└──────────────────────┬──────────────────────────────┘
                       │ iface.LedgerEngine, iface.FederationEngine
                       │ (same interfaces as v0)
        ┌──────────────┴──────────────┐
        │ Go adapter layer  (NEW)     │
        │ core/p2p/eth/                │
        │   client                     │
        │   ledger_eth.go              │
        │   federation_eth.go          │
        │   audit_eth.go (outcome      │
        │                  posting)    │
        │   oracle.go                  │
        │   events.go                  │
        └──────────────┬──────────────┘
                       │ JSON-RPC + signed txs
              ┌────────┴────────┐
              │   Base L2       │
              │   (Sepolia      │
              │    testnet      │
              │    for v1.0)    │
              └────────┬────────┘
                       │
   ┌───────────────────┼───────────────────┐
   │  Solidity contracts (NEW)             │
   │  ┌─────────────────────────────────┐ │
   │  │ Registry.sol                    │ │
   │  │   identity NFTs (soulbound)     │ │
   │  │   mint via donation proof       │ │
   │  ├─────────────────────────────────┤ │
   │  │ Ledger.sol                      │ │
   │  │   stake / lock / slash / settle │ │
   │  │   network tax + insurance       │ │
   │  ├─────────────────────────────────┤ │
   │  │ Federation.sol                  │ │
   │  │   pools, reputation, credit     │ │
   │  ├─────────────────────────────────┤ │
   │  │ Audit.sol                       │ │
   │  │   outcome posting + dispute     │ │
   │  ├─────────────────────────────────┤ │
   │  │ OracleAdapter.sol               │ │
   │  │   Chainlink ETH/USD feed        │ │
   │  └─────────────────────────────────┘ │
   └───────────────────────────────────────┘
```

## Asset and accounting model

### Settlement asset: ETH

v1.0 stakes and settles in native ETH. No wrapped ETH, no ERC-20 stablecoin.
Everything that's locked or paid is wei on the Ledger contract's balance.

### Internal accounting unit: micro-USD via oracle

The `types.Money int64` from v0 stays as the internal unit. Its meaning
changes from "micro-USDC" to "micro-USD-equivalent" — an abstract dollar
unit, not tied to any specific token. Document this with a one-line
relabel in `types.go` (already noted as a candidate change in v0).

At every boundary where wei meets USD, the OracleAdapter converts using
the Chainlink ETH/USD price feed:

- **Deposit:** `n wei` arrives; Ledger stores it as wei but credits the
  depositor's "stake in USD" as `n × ethUsdPrice / 1e18`.
- **Lock:** orchestrator wants to lock $V; Ledger locks
  `V × 1e18 / ethUsdPrice` wei from the stake's wei balance.
- **Settle:** worker is owed $V net; Ledger pays
  `V × 1e18 / ethUsdPrice` wei.

Because the price moves between deposit and settle, **each individual
lock pins its USD equivalent at lock time** — the stake amount in wei is
fixed at lock, and the USD value at release/slash time is computed from
the same wei amount and the current price. Workers earn or lose
ETH-volatility exposure during the lock period; quote validity is short
(orchestrator can refuse to lock if the price has moved >X% since the
publisher's offer).

### Why not a stablecoin?

The user has expressed dissatisfaction with stablecoins (centralization /
censorship risk on USDC; collateral exposure on DAI). Settling in raw ETH
preserves decentralization at the cost of accepting volatility.
Mitigation: short quote windows (~10 min) and stake multiplier > 1 so
both sides absorb modest price moves without breaking trades.

### Asset-neutral abstraction (forward-looking)

The Go-side `Settler` interface (introduced in v1.0, even though only one
implementation ships) is shaped to support multiple assets:

```go
// iface/settler.go
type Settler interface {
    Asset() AssetType            // "ETH", "XMR-MULTISIG", etc.
    Deposit(node NodeID, externalAmount *big.Int) (credited Money, err error)
    Withdraw(node NodeID, credits Money) (txProof []byte, err error)
    Backing() *big.Int           // total external-asset units backing the protocol
    PriceFeed() (microUSDPerUnit *big.Int, err error)
}
```

v1.0 ships only `EthereumSettler`. v2.x can add `MoneroSettler` (federated
multisig) or `LightningSettler` without changing the orchestrator. See
v0 conversation logs for the full discussion of why this matters.

## Smart contract architecture

All contracts deploy to Base (Sepolia testnet for v1.0). Solidity 0.8.24+.
Foundry as the build/test framework.

### Module: Registry.sol

Identity NFTs. Soulbound ERC-721 (non-transferable). Each NodeID is
backed by a token whose owner is the node's Ethereum address.

```solidity
contract Registry {
    function mintIdentity(address node, bytes32 donationProof) external returns (uint256 tokenId);
    function burnIdentity(uint256 tokenId) external; // on slashing past threshold
    function nodeOf(uint256 tokenId) external view returns (address);
    function tokenOf(address node) external view returns (uint256);
    function isMinted(address node) external view returns (bool);

    // Soulbound: transferFrom always reverts
    function transferFrom(address, address, uint256) external pure { revert("soulbound"); }
}
```

- `mintIdentity` is callable only by the Federation contract (after
  donation audit passes)
- `burnIdentity` is callable only by the Federation contract (on
  slashing-past-threshold)
- Tokens carry no metadata in v1.0; v1.2 will attach a reputation
  commitment

### Module: Ledger.sol

Economic engine. Holds wei deposited by nodes; tracks per-job locks;
splits between worker payment, network tax, and insurance reserve on
settle; routes slashed funds to reserve.

```solidity
contract Ledger {
    struct StakeRec {
        uint256 availableWei;
        mapping(bytes32 => uint256) lockedWei; // jobId → wei
    }
    mapping(address => StakeRec) public stakes;
    uint256 public insuranceReserveWei;
    uint16 public networkTaxBps = 100; // 1.00% = 100 basis points

    function depositStake() external payable;
    function withdrawStake(uint256 weiAmount) external;
    function getStake(address node) external view returns (uint256 available, uint256 locked);

    function lockForJob(address node, bytes32 jobId, uint256 weiAmount) external; // auth: Orchestrator multisig
    function releaseFromJob(bytes32 jobId, uint16 slashFractionBps) external returns (uint256 slashed, uint256 returned);
    function settleJob(bytes32 jobId, address worker, uint256 valueUSD, uint16 poolTaxBps) external returns (uint256 paidWei);

    function payoutFromReserve(address to, uint256 weiAmount, bytes32 reasonHash) external;
    function updateNetworkTaxBps(uint16 newBps) external; // auth: governance multisig

    event StakeDeposited(address indexed node, uint256 weiAmount);
    event StakeLocked(address indexed node, bytes32 indexed jobId, uint256 weiAmount);
    event JobSlashed(bytes32 indexed jobId, uint256 slashedWei, uint16 slashFractionBps);
    event JobSettled(bytes32 indexed jobId, address indexed worker, uint256 paidWei, uint256 networkTaxWei, uint256 poolTaxWei);
}
```

- Floor: 0.5% (50 bps), ceiling: 5% (500 bps) for network tax (matching v0
  constants `NetworkTaxFloor` / `NetworkTaxCeiling`)
- `slashFractionBps`: 0-10000 (0% to 100% of locked amount, in basis points)
- Auth model: most state-changing functions are callable only by the
  designated Orchestrator multisig (set at deploy time, upgradable via
  governance multisig)

### Module: Federation.sol

Pools, reputation (plaintext in v1.0), credit lines.

```solidity
contract Federation {
    struct PoolRec {
        address operator;
        uint16 taxBps;
        uint8 tier;
        bool kycRequired;
        // members tracked via separate mapping; volume via aggregate counters
    }
    struct RepRec {
        int256 earnedScore;        // can go negative on burn
        uint256 donatedVerifiedUSD;
        int256 poolEndorsement;
    }
    mapping(bytes32 => PoolRec) public pools;
    mapping(address => bytes32) public poolOf;
    mapping(address => RepRec) public reputations;

    // Per-client credit-extension knobs
    struct CreditPolicy {
        uint256 perNodeUSD;
        uint256 totalExposureUSD;
    }
    mapping(address => CreditPolicy) public creditPolicies;
    mapping(address => uint256) public outstandingExposure; // per client

    // Outstanding debt per (creditor, debtor) pair
    mapping(address => mapping(address => uint256)) public debtUSD;

    function registerPool(uint16 taxBps, bool kycRequired) external returns (bytes32 poolId);
    function joinPool(bytes32 poolId) external;
    function leavePool() external;
    function poolTaxBps(bytes32 poolId) external view returns (uint16);

    function addDonationCredit(address node, uint256 valueUSD) external; // auth: Audit
    function onAuditOutcome(bytes32 jobId, address worker, bool pass, int256 severityBps) external; // auth: Audit
    function effectiveReputationCap(address node) external view returns (int256);

    function setPerClientCredit(uint256 perNodeUSD, uint256 totalExposureUSD) external;
    function consumeCredit(address creditor, address debtor, uint256 valueUSD) external returns (bool);
    function repayCredit(address creditor, address debtor, uint256 valueUSD) external;

    event RepUpdated(address indexed node, int256 newScore);
    event CreditExtended(address indexed creditor, address indexed debtor, uint256 valueUSD);
    event CreditRepaid(address indexed creditor, address indexed debtor, uint256 valueUSD);
}
```

- `effectiveReputationCap` implements the v0 formula:
  `min(min(EarnedScore, SoloCap), DonatedVerified)` for solo nodes;
  `min(EarnedScore + endorsement, DonatedVerified)` for pool members.
- Credit policy is one knob per client (publisher), not per-job-overridable
  in v1.0. A per-job override field can be added later if needed.
- Debt accounting in v1.0 only tracks outstanding USD; v1.0 doesn't
  enforce repayment ordering on the chain (orchestrator handles that
  off-chain).

### Module: Audit.sol

Outcome posting + dispute window.

```solidity
contract Audit {
    struct Outcome {
        bytes32 jobId;
        address worker;
        uint16 similarityBps;   // 0-10000
        bool pass;
        int16 severityBps;      // 0-10000, signed only for negative-severity shaped ramps
        uint64 postedAt;
        uint64 finalizesAt;     // postedAt + disputeWindowSeconds
    }
    mapping(bytes32 => Outcome) public outcomes;
    mapping(bytes32 => bool) public finalized;
    uint64 public constant disputeWindowSeconds = 24 hours; // configurable

    function postOutcome(
        bytes32 jobId, address worker,
        uint16 similarityBps, bool pass, int16 severityBps,
        address[] calldata verifiers, bytes[] calldata verifierSigs
    ) external; // auth: any caller with M-of-N verifier multisig

    function challengeOutcome(bytes32 jobId, bytes calldata proof) external;
    function finalize(bytes32 jobId) external; // anyone can call after window

    event OutcomePosted(bytes32 indexed jobId, bool pass, uint16 similarityBps);
    event OutcomeChallenged(bytes32 indexed jobId, address challenger);
    event OutcomeFinalized(bytes32 indexed jobId);
}
```

- `postOutcome` requires M-of-N signatures over `(jobId, worker, severity, ...)`
  from registered verifiers. Reuses OpenZeppelin's `ECDSA.recover`.
- Dispute window: 24 hours configurable. Anyone can submit a counter-proof
  during the window; if accepted, the outcome is reverted and the original
  posters are slashed (cross-engine call to Ledger).
- On finalize, Audit calls `Federation.onAuditOutcome` and
  `Ledger.releaseFromJob` to apply rep deltas and slashing.

### Module: OracleAdapter.sol

Chainlink ETH/USD price feed wrapper.

```solidity
contract OracleAdapter {
    AggregatorV3Interface immutable ethUsdFeed;

    function ethUsdPrice() external view returns (uint256 priceMicroUSDPerWei);
    function weiToMicroUSD(uint256 weiAmount) external view returns (uint256);
    function microUSDToWei(uint256 microUSD) external view returns (uint256);
}
```

- Chainlink ETH/USD feed on Base mainnet: `0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70`
- Chainlink ETH/USD feed on Base Sepolia: `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1`
- Staleness check: revert if last update > 1 hour ago
- Future: medianize across multiple feeds to avoid single-feed risk

### Module: NetworkLeader.sol (multisig)

Gnosis Safe with 2-of-3 (founders) or higher. Owns upgrade keys, network
tax adjustment, dispute-resolution decisions. Configured at deploy time.

## Go adapter layer (core/p2p/eth/)

The adapter implements the same `iface.*Engine` interfaces v0 used, just
backed by chain state instead of in-memory maps.

### Package layout

```
core/p2p/eth/
  client.go            — go-ethereum bindings, RPC connection, chain ID checks
  signer.go            — private key loading, nonce management
  abigen/              — auto-generated bindings from Solidity contracts
                          (one .go file per contract, generated via abigen)
  ledger_eth.go        — implements iface.LedgerEngine via Ledger.sol calls
  federation_eth.go    — implements iface.FederationEngine via Federation.sol
  audit_eth.go         — partial iface.AuditEngine — posts outcomes on-chain,
                          replay/control law still local
  oracle.go            — Chainlink reader, conversion helpers
  events.go            — subscribes to chain events, updates local caches
  cache.go             — read-mostly state cached locally (stakes, reps)
  testharness/         — Anvil bring-up, contract deployment, fixtures
  doc.go
```

### Adapter semantics

- **Reads** use `eth_call` (no gas, instant): `GetStake`, `GetReputation`,
  `EffectiveReputationCap`, etc.
- **Writes** submit signed transactions; await receipt; emit local events.
- **Caching**: each engine maintains a local cache of read-mostly fields.
  Cache invalidation on chain events (subscribed via `eth_subscribe`).
- **Nonce management**: per-signer queue with retry on revert
  (re-fetch nonce, re-sign, re-submit).
- **Idempotency**: methods are designed to be safely re-callable. If a tx
  is broadcast and the client crashes, the next attempt will see the
  effect (e.g., via tx hash lookup) and skip the work.

### Concurrency model

Each engine owns its own signer (or shares the orchestrator's). Multiple
in-flight transactions are serialized through a per-signer nonce queue.
Reads are concurrent-safe via go-ethereum's connection pool.

### Local vs on-chain state

| Concept | Source of truth | Cached in Go? |
|---------|----------------|---------------|
| Stake balances | Ledger.sol | Yes (invalidated on `StakeDeposited`, `StakeLocked`, etc.) |
| Job locks | Ledger.sol | Yes |
| Insurance reserve | Ledger.sol | Yes |
| Network tax rate | Ledger.sol | Yes |
| Reputation scores | Federation.sol | Yes (invalidated on `RepUpdated`) |
| Pool registry | Federation.sol | Yes |
| Credit policies | Federation.sol | Yes |
| Audit outcomes | Audit.sol | Streamed; archived in append-only log |
| ETH/USD price | OracleAdapter.sol | Yes, ~5s freshness |
| Identity NFTs | Registry.sol | Yes |
| Audit replay history | (local only — never on-chain) | Yes |
| Job receipts | (local only — never on-chain) | Yes |

### Failure modes

- **RPC unreachable**: retry with backoff; degrade to read-only mode if
  the failure persists. Don't lose enqueued txs (persist nonce queue).
- **Transaction reverts**: log, propagate to caller. For idempotent
  operations, retry; for non-idempotent (rare), surface the failure.
- **Reorg**: in v1.0, treat reorgs as best-effort. Base's finality is
  fast (block reordering rare past 1-2 blocks). For high-value flows,
  wait N=5 confirmations before considering settled.
- **Price feed stale**: contract reverts; Go side surfaces; orchestrator
  can pause or fall back to a cached recent price (with a max-staleness
  threshold).

## Bootstrap mechanics

### Phase 1: Founder genesis (one-time, at deploy)

```
1. Deploy contracts on Base Sepolia.
2. Founder calls Federation.bootstrapGenesis(founderAddr, premineUSD)
   - Sets founder's EarnedScore = premineUSD
   - Sets founder's DonatedVerified = premineUSD
   - This call requires the deployer key; can only be called once
3. Founder calls Registry.mintIdentity(founderAddr, bytes32(0)) — special
   genesis path that doesn't require a donation proof
4. Founder calls Federation.setPerClientCredit(perNodeUSD, totalExposureUSD)
   with their chosen credit-extension parameters
5. Founder calls Ledger.depositStake() {value: someETH} to provide working
   capital for taking jobs themselves
6. Network is live; founder can act as worker and auditor
```

Initial premine recommendation: **$100-1000** of EarnedScore and
DonatedVerified. The founder also extends a **$10000 total exposure**
credit line with **$10-50 per new node** (configurable).

### Phase 2: Soft launch (a few weeks)

```
1. Trusted friends generate keypairs, deposit small amounts of ETH for stake
2. Each submits an "identity registration" job via the Orchestrator:
     job.Category = JobIdentityRegistration
     job.Value = X USD (donation amount, ≥ MinIdentityCreationDonation)
     job.Payload = registration payload (TBD)
3. Founder (and other minted identities) replay the donation work, post
   audit outcomes to Audit.sol
4. On audit pass, Audit.sol calls:
     Federation.addDonationCredit(node, donationValueUSD)
     Federation.onAuditOutcome(jobId, node, true, severity=0)
     Registry.mintIdentity(node, donationProof)
5. Newly minted node now has EarnedScore = donations count, DonatedVerified
   = donationValueUSD, and can take jobs up to their effective cap
6. New nodes build organic reputation by taking small jobs; founder's
   credit extension covers gaps
```

### Phase 3: Open launch (signal-based or flag)

When the soft-launch group has ≥N organic identities and audit failure rate
is below threshold, the network opens up:

- v1.0 ships this as a **manual flag** set by the network-leader multisig
  (founder gates it explicitly)
- v2.x can automate based on on-chain telemetry

After open launch, anyone can submit identity-registration jobs and any
sufficiently-reputed worker can verify them.

### MinIdentityCreationDonation

Critical economic parameter. To make Sybil unprofitable:

```
min_donation_USD >= max(credit_extension_per_node) × P(default) × expected_milkings
```

For founder default `$50 per new node` and `P(default) ≈ 1` worst case
(an attacker defaults immediately on the first job), `min_donation ≥ $50`.

v1.0 default: **`$50 USD of donated compute work`** per identity creation.
Configurable by the network-leader multisig.

## Settlement flow (end-to-end)

For a paid embedding job from publisher P to worker W, value $V USD:

```
Step 1: Off-chain matching
  - Orchestrator matches W to job; W signs Quote
  - Quote validity: 10 minutes (price-pinned)

Step 2: Lock stake (on-chain)
  - Orchestrator calls Ledger.lockForJob(W, jobId, V × stakeMultiplier in wei,
    computed at current ETH/USD oracle price)
  - Wei amount is pinned at lock time

Step 3: Execute (off-chain)
  - W runs the compute, returns JobReceipt

Step 4: Audit (off-chain compute, on-chain outcome)
  - Audit engine replays the job locally
  - Computes similarity, severity
  - Submits to Audit.sol with M-of-N verifier signatures

Step 5: Wait for dispute window
  - 24 hours, configurable
  - In v1.0 this is intentionally long for safety; v2 may use optimistic
    settlement (instant payout, slash if disputed)

Step 6: Finalize (on-chain)
  - Anyone calls Audit.finalize(jobId)
  - Audit.sol calls Ledger.releaseFromJob with computed slashFractionBps
  - If not fully slashed: Audit.sol calls Ledger.settleJob to pay W
  - Audit.sol calls Federation.onAuditOutcome for rep update
  - Audit.sol calls Federation.repayCredit if W was operating on credit

Step 7: Events propagate
  - Go-side caches invalidate
  - Orchestrator emits telemetry locally
```

## Testing strategy

### Local Anvil (primary dev loop)

Foundry's Anvil runs a local Ethereum L2-shaped chain in-memory. Tests
deploy fresh contracts on each run, run a full scenario, tear down.

```
go test -tags integration ./core/p2p/eth/... runs:
  - spawns anvil --port 8545
  - deploys contracts via the Go adapter's bootstrap helper
  - runs a real-engine integration test (analogous to v0's TestRealEngineIntegration)
  - asserts on-chain state matches expectations
  - tears down anvil
```

Speed: ~5-10 seconds per scenario. Suitable for CI.

### Base Sepolia (integration realism)

Weekly or per-PR integration runs deploy contracts to Base Sepolia and
run a smaller scenario. Slower (minutes per scenario, due to block times
+ confirmations), but catches realistic things:

- Real Chainlink feed behavior (versus a mocked feed in Anvil)
- L2-specific gas pricing
- Cross-contract interaction at real network latencies

Funding via Base Sepolia faucet (~1 ETH per agent per week, manual ask
or automated drip).

### What's NOT tested in v1.0

- Mainnet behavior (no mainnet deploy)
- Adversarial scenarios at scale (10k+ jobs, large pools)
- Long-running audit-rate adaptation (control law tuning is v2+)
- Realistic network latency between distributed verifiers (still
  in-process)

## Migration path from v0

- v0 in-memory engines (`testharness.StubLedger`, `testharness.StubFederation`)
  remain as test-only implementations.
- New `eth.LedgerEngine` and `eth.FederationEngine` implement the same
  `iface.*Engine` interfaces.
- The orchestrator picks one at construction (config flag).
- Audit engine: keeps the in-memory implementation from v0 for the
  replay/control-law logic; adds an on-chain outcome-posting layer via
  the Audit.sol adapter.

```go
// New orchestrator construction shape
cfg := orchestrator.OrchestratorConfig{ ... }

// v0 style (still works for tests):
o := &orchestrator.Orchestrator{
    Ledger:     testharness.NewStubLedger(),
    Audit:      audit.NewEngine(),
    Federation: testharness.NewStubFederation(),
    Provider:   providers.NewHonestMock(types.PrecisionFP16),
    Config:     cfg,
}

// v1.0 style:
ethClient, _ := eth.NewClient(rpcURL, signerKey, contractAddrs)
ledgerEth := eth.NewLedger(ethClient)
fedEth := eth.NewFederation(ethClient)
auditEng := audit.NewEngine()
auditEng.SetOnchainPoster(eth.NewAuditPoster(ethClient))
o := &orchestrator.Orchestrator{
    Ledger:     ledgerEth,
    Audit:      auditEng,
    Federation: fedEth,
    Provider:   providers.NewBGEHonest(...),
    Config:     cfg,
}
```

## v1.1 preview: stealth addresses + AA paymaster

(Detailed doc later; this is the architecture preview so v1.0 leaves room.)

- **Announcer.sol** contract for EIP-5564 ephemeral-pubkey announcements
- Workers register a stealth meta-address in `Registry.sol` (new field)
- Publishers compute stealth addresses for each payment; settle to the
  fresh address rather than the worker's primary address
- The Go scanner watches Announcer events and surfaces incoming payments
  to the worker's wallet
- **AA paymaster** (ERC-4337) lets new nodes have their gas paid by a
  network-funded paymaster (drawn from insurance reserve) — eliminates
  the "gas payer is your main wallet" privacy leak

Changes in v1.0 to leave room:
- `Registry.sol` should reserve a `stealthMetaAddress` field even if
  unused in v1.0
- Settlement APIs in Ledger.sol should accept an optional `recipient`
  parameter that defaults to the worker's primary address but can be
  overridden to a stealth address
- Orchestrator should plumb a `Recipient` through the lifecycle

## v1.2 preview: ZK reputation

- **Semaphore-based group membership proofs**: workers prove "I belong
  to the set of nodes with rep ≥ threshold" without revealing which node
  they are
- `Federation.sol` reputation stops being a plaintext mapping and becomes
  a Merkle commitment over `(node, score)` leaves
- Old `getReputation(node)` returns the commitment hash, not the score
- `proveQualified(threshold, proof)` becomes the new gating function
  for the orchestrator
- Proof verification adds ~200-500k gas per job (~$0.10 on Base L2)

Changes in v1.0 to leave room:
- `Federation.sol` reputation storage should be structured so it can be
  migrated to a commitment tree without rewriting the surface API
- Reputation reads should be wrapped in an internal getter so the
  v1.2 ZK version can replace the implementation without breaking
  callers

## Open questions for v1.0 design review

1. **Multisig for Audit outcome posting**: Gnosis Safe vs. custom
   M-of-N? Gnosis Safe is battle-tested but heavy; custom is lighter
   but unaudited. Recommendation: **Gnosis Safe** (audited).

2. **Oracle resilience**: single Chainlink feed vs. medianizer over 2-3
   sources? v1.0 ships single-feed for simplicity; medianizer is v2.

3. **Upgrade pattern**: OpenZeppelin's transparent proxies vs. immutable
   redeploys? Recommendation: **immutable contracts for v1.0** (no proxy
   complexity, no upgrade-key risk). Migration to new versions via
   versioned deployments and an off-chain governance signal.

4. **Identity NFT metadata**: leave empty in v1.0, or attach a
   commitment-root URI for v1.2 compatibility? Recommendation: **empty
   in v1.0**, with the storage slot reserved.

5. **MinIdentityCreationDonation calibration**: $50 default seems
   reasonable but is calibrated against the founder's $50/node credit
   extension. If the founder runs cheaper, donation floor drops too.
   Probably should be **2× the per-node credit cap** for safety.

6. **Reorg handling on Base**: how many confirmations before treating a
   settle as final? Base claims fast finality (~2 seconds), but for
   high-value flows we may want 5-10 blocks. v1.0 uses **3 blocks** as
   the default `safe-finality` threshold.

7. **What happens to a node whose EarnedScore goes negative on a
   slashing event?** v0 floors at 0; v1.0 *could* allow negative (signal
   for burn). Recommendation: **floor at 0 for v1.0; track separate
   `defaultCount` for burn thresholds.**

## Implementation partition (preview — separate plan files later)

Once this doc is approved, the work breaks into 4 parts roughly
matching the v0 structure but for v1.0:

| Part | Scope | Approx. lines |
|------|-------|---------------|
| **v1.0-A: Contracts** | All Solidity (Registry, Ledger, Federation, Audit, OracleAdapter, deployment scripts) + Foundry tests | ~1500 |
| **v1.0-B: Go adapter layer** | `core/p2p/eth/` package implementing `iface.*Engine` against the contracts | ~2000 |
| **v1.0-C: Bootstrap + identity registration** | `JobIdentityRegistration` category, identity-mint flow, premined-founder bootstrap, per-client credit accounting | ~800 |
| **v1.0-D: Test infrastructure** | Anvil setup helpers, Sepolia deploy scripts, real-engine integration test against on-chain backings (analogous to v0's `TestRealEngineIntegration`) | ~1000 |

Each part gets its own claim'd worktree (`bin/adam claim core/v1-eth-X`)
and its own orchestrator. Inter-part contracts: the Solidity ABIs from
Part A get auto-generated into Go bindings via `abigen`, which is the
boundary between A and B.

## Approximate timeline

With 4 orchestrators in parallel:

- **Day 1**: this doc approved; Part A spawns first (contracts + ABI),
  generates bindings as it goes; Parts B, C, D can mock against the
  ABI signatures.
- **Day 3-5**: Part A finishes; Parts B/C/D rebase onto real bindings.
- **Day 5-10**: Parts B, C, D land; integration test passes on Anvil.
- **Day 10-12**: Deploy to Base Sepolia; integration test passes on testnet.
- **Day 12-14**: v1.0 done; v1.1 (stealth) design doc starts.

Conservative estimate: **2-3 weeks** for v1.0 with 4 orchestrators.
Faster if fewer rebases; slower if Solidity audits surface issues.
