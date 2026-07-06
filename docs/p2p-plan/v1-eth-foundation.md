# v1: ETH on Base — Foundation

> Status: design strawman (2026-05-17, fiat-free revision). Not yet
> implemented. Holds the architectural decisions that v0 deferred to "v1+"
> in `00-shared-context.md`.

## How v1 relates to v0

v0 shipped a single-process Go simulation: in-memory ledger, in-memory
federation, in-memory orchestrator, with a C++23 hot path for similarity
scoring. All four parts live behind interface contracts in `core/p2p/iface/`.

v1 replaces the in-memory ledger and federation engines with **on-chain
backings**: real smart contracts on a Base L2, real ETH at stake, all
accounting in native ETH units (gwei) — no fiat anywhere in the protocol.
The orchestrator and the audit engine stay primarily Go-side; only the
*state* moves on-chain. The interface contracts in `iface/` are preserved
— v1 implementations satisfy the same Go interfaces, so the orchestrator
doesn't notice the difference.

## v1 roadmap — three phases

| Phase | Scope | Adds |
|-------|-------|------|
| **v1.0** | ETH foundation: smart contracts on Base; Go adapter layer; gwei-denominated accounting; bootstrap mechanics (donation-mint, premined founder credit, per-client credit lines) | This document |
| **v1.1** | Stealth addresses (EIP-5564) on the payment path; ERC-4337 Account Abstraction with a paymaster for gas-payer privacy | Separate doc later |
| **v1.2** | ZK reputation via Semaphore-based group proofs; on-chain reputation commitments instead of plaintext scores | Separate doc later |

Each phase ships independently. v1.0 is the only one that must precede the
others — v1.1 and v1.2 layer on top of v1.0's contracts.

## v1.0 goals + non-goals

### Goals

- Replace in-memory LedgerEngine and FederationEngine with on-chain backings
- Settle compute jobs in native ETH on Base, denominated in gwei internally
- Working bootstrap mechanic: identity registration via donation, premined
  founder credit, per-client credit extension to new nodes
- Crypto-native accounting (gwei everywhere) — no fiat, no oracle dependency,
  no central pricing data feeding into the protocol
- Asset-agnostic `Settler` abstraction at the boundary so v2 can add Monero
  (federated multisig) or any other asset as a second adapter without
  touching protocol-internal code
- Local Anvil test environment for fast iteration; Base Sepolia for
  integration realism

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
- **Governance** — network-leader multisig (a Gnosis Safe) retains upgrade
  keys and ops keys; v1 doesn't address the token / DAO transition deferred
  in v0 context.
- **Any USD or fiat reference inside the protocol.** External display tools
  may convert to fiat at presentation time; the protocol itself doesn't
  know dollars exist.

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
   │  └─────────────────────────────────┘ │
   └───────────────────────────────────────┘
```

No oracle contract. No price feed. No fiat-reference component anywhere.

## Asset and accounting model

### Settlement asset: native ETH

v1.0 stakes, locks, and settles exclusively in native ETH. No wrapped ETH,
no ERC-20 stablecoin, no fiat reference. The "currency" of the network *is*
ETH, full stop.

### Internal unit: gwei

The Go `types.Money` value (today described as "micro-USDC") becomes:

```go
// types.Gwei is the protocol's native unit: 10^-9 ETH.
// 1 ETH = 1_000_000_000 gwei. int64 holds up to ~9.2 billion ETH, plenty.
type Gwei int64

const (
    Gwei1   Gwei = 1
    MilliETH Gwei = 1_000_000        // 0.001 ETH = 10^6 gwei
    ETH     Gwei = 1_000_000_000     // 1 ETH    = 10^9 gwei
)
```

Rationale for gwei specifically:

- Gwei is the canonical mid-scale ETH unit (gas prices are quoted in it).
- An `int64` in gwei can hold up to ~9.2 × 10⁹ ETH — far more headroom than
  any v1 use case will need.
- Typical amounts are conveniently sized integers:
  - A small embedding compute job: a few thousand gwei to a few hundred thousand
  - A larger inference / multi-job batch: tens to hundreds of millions of gwei
  - A whole-ETH stake: 1,000,000,000 gwei (1 ETH)
- No conversion math for the orchestrator. The Go side accumulates and
  decides in gwei. The contracts hold wei (the chain's smallest unit)
  internally and convert at the FFI boundary with a `× 10⁹` multiplication.

### No oracle

Because the protocol does not denominate anything in dollars (or any other
external unit), there is no need to read off-chain price data. No Chainlink,
no Pyth, no medianizer. The protocol's accounting is closed: ETH in → gwei
in protocol → ETH out, exact.

If a UI wants to *display* a USD value to a user, that conversion happens
off-chain at presentation time, never touching the protocol layer.

### Why no fiat at all

The full chain of reasoning:

- **Decentralization.** The whole pitch of a decentralized compute network
  is that no single entity (or jurisdiction) can shut it down. Pricing in
  USD via Chainlink imports a regulatory and dependency surface that
  contradicts that pitch.
- **Volatility is the participant's problem, not the protocol's.** Workers
  who want USD-stable income can swap their earned ETH for a stablecoin at
  their wallet; that's a personal choice, not a protocol parameter.
- **No oracle compromise risk.** The protocol can't be "broken" by a feed
  manipulation attack because there's no feed.
- **No oracle staleness gas cost.** Every cross-asset price check on-chain
  would be a Chainlink call. Skipping that saves gas on every settle.
- **Future asset adapters** (Monero v2, Lightning, etc.) each settle in
  their own native unit. The internal `Gwei` is the ETH-side unit; a
  hypothetical `XMRAtomic` would be the Monero-side unit. The protocol's
  `Settler` interface keeps them parallel.

### Asset-neutral adapter interface (forward-looking)

```go
// iface/settler.go
type Settler interface {
    Asset() AssetType                                       // "ETH", "XMR-MULTISIG", ...
    Deposit(node NodeID, externalAmount *big.Int) error    // wei for ETH, etc.
    Withdraw(node NodeID, externalAmount *big.Int) ([]byte, error)
    Balance(node NodeID) (*big.Int, error)
    TotalLocked() *big.Int                                  // total backing held by protocol
}
```

The orchestrator stays asset-agnostic: it just knows about its `Gwei`
balance for ETH operations, or whatever native unit a future adapter
exposes. v1.0 ships only `EthereumSettler`. The interface exists from
day one so future settlers slot in cleanly.

## Smart contract architecture

All contracts deploy to Base (Sepolia testnet for v1.0). Solidity 0.8.24+.
Foundry as the build/test framework.

All contracts are **upgradable via proxy** with the upgrade authority held
by the Gnosis Safe (the network-leader multisig). This pattern means the
Safe's signature requirements apply equally to ops decisions and upgrade
decisions — the multisig is doing double duty as upgrade-governance.
Standard pattern: OpenZeppelin transparent or UUPS proxies; pick UUPS to
keep upgrade logic in the implementation contracts.

### Module: Registry.sol

Identity NFTs. Soulbound ERC-721 (non-transferable). Each NodeID is
backed by a token whose owner is the node's Ethereum address.

```solidity
contract Registry {
    function mintIdentity(address node, bytes32 donationProof) external returns (uint256 tokenId);
    function burnIdentity(uint256 tokenId) external;
    function nodeOf(uint256 tokenId) external view returns (address);
    function tokenOf(address node) external view returns (uint256);
    function isMinted(address node) external view returns (bool);

    // Reserved for v1.2 ZK reputation: commitment root attached to each identity.
    function commitmentRootOf(uint256 tokenId) external view returns (bytes32);
    function setCommitmentRoot(uint256 tokenId, bytes32 root) external; // empty in v1.0

    // Reserved for v1.1 stealth addresses: meta-address bound to identity.
    function stealthMetaAddressOf(uint256 tokenId) external view returns (bytes memory);
    function setStealthMetaAddress(uint256 tokenId, bytes calldata meta) external; // empty in v1.0

    // Soulbound: transferFrom always reverts.
    function transferFrom(address, address, uint256) external pure { revert("soulbound"); }
}
```

- `mintIdentity` is callable only by the Federation contract (after
  donation audit passes).
- `burnIdentity` is callable only by the Federation contract (on
  slashing past a default-count threshold).
- The `commitmentRoot` and `stealthMetaAddress` storage slots are reserved
  but unused in v1.0 — v1.1 and v1.2 fill them in without re-minting.

### Module: Ledger.sol

Economic engine. Holds wei deposited by nodes; tracks per-job locks; splits
between worker payment, network tax, and insurance reserve on settle;
routes slashed funds to reserve. All on-chain amounts are wei (uint256);
the Go side works in gwei (int64) and converts at the FFI.

```solidity
contract Ledger {
    struct StakeRec {
        uint256 availableWei;
        mapping(bytes32 => uint256) lockedWei; // jobId → wei
    }
    mapping(address => StakeRec) public stakes;
    uint256 public insuranceReserveWei;
    uint16 public networkTaxBps = 100; // 1.00% in basis points

    function depositStake() external payable;
    function withdrawStake(uint256 weiAmount) external;
    function getStake(address node) external view returns (uint256 available, uint256 locked);

    function lockForJob(address node, bytes32 jobId, uint256 weiAmount) external; // auth: Orchestrator Safe
    function releaseFromJob(bytes32 jobId, uint16 slashFractionBps) external returns (uint256 slashed, uint256 returned);
    function settleJob(bytes32 jobId, address worker, uint256 grossWei, uint16 poolTaxBps) external returns (uint256 paidWei);

    function payoutFromReserve(address to, uint256 weiAmount, bytes32 reasonHash) external;
    function updateNetworkTaxBps(uint16 newBps) external; // auth: governance Safe

    event StakeDeposited(address indexed node, uint256 weiAmount);
    event StakeLocked(address indexed node, bytes32 indexed jobId, uint256 weiAmount);
    event JobSlashed(bytes32 indexed jobId, uint256 slashedWei, uint16 slashFractionBps);
    event JobSettled(bytes32 indexed jobId, address indexed worker, uint256 paidWei, uint256 networkTaxWei, uint256 poolTaxWei);
}
```

Notable:

- **Floor 50 bps, ceiling 500 bps** for network tax (matching v0 constants
  `NetworkTaxFloor` / `NetworkTaxCeiling`).
- **`grossWei` parameter** in `settleJob` is the pre-tax wei amount the
  publisher is paying. Settlement deducts `(networkTaxBps + poolTaxBps) ×
  grossWei / 10000` and pays the rest to the worker. No USD conversion
  anywhere.
- **Auth model:** most state-changing functions are callable only by the
  designated Orchestrator multisig (set at deploy time, upgradable via
  the governance Safe).

### Module: Federation.sol

Pools, reputation (plaintext in v1.0), credit lines. All economic amounts
in gwei-equivalent (uint256 wei on-chain, mapped to int64 gwei in Go).

```solidity
contract Federation {
    struct PoolRec {
        address operator;
        uint16 taxBps;
        uint8 tier;
        bool kycRequired;
    }
    struct RepRec {
        int256 earnedScore;       // signed; can go negative on heavy slashing
        uint256 donatedVerified;  // wei
        int256 poolEndorsement;
        uint32 defaultCount;      // separate burn-threshold tracker
    }
    mapping(bytes32 => PoolRec) public pools;
    mapping(address => bytes32) public poolOf;
    mapping(address => RepRec) public reputations;

    // Per-client credit-extension knobs (all in wei)
    struct CreditPolicy {
        uint256 perNodeMaxWei;
        uint256 totalExposureWei;
    }
    mapping(address => CreditPolicy) public creditPolicies;
    mapping(address => uint256) public outstandingExposureWei; // per client

    // Outstanding debt per (creditor, debtor) pair
    mapping(address => mapping(address => uint256)) public debtWei;

    function registerPool(uint16 taxBps, bool kycRequired) external returns (bytes32 poolId);
    function joinPool(bytes32 poolId) external;
    function leavePool() external;
    function poolTaxBps(bytes32 poolId) external view returns (uint16);

    function addDonationCredit(address node, uint256 weiAmount) external; // auth: Audit
    function onAuditOutcome(bytes32 jobId, address worker, bool pass, int16 severityBps) external; // auth: Audit
    function effectiveReputationCap(address node) external view returns (int256);
    function defaultCount(address node) external view returns (uint32);

    function setPerClientCredit(uint256 perNodeMaxWei, uint256 totalExposureWei) external;
    function consumeCredit(address creditor, address debtor, uint256 weiAmount) external returns (bool);
    function repayCredit(address creditor, address debtor, uint256 weiAmount) external;

    event RepUpdated(address indexed node, int256 newScore, uint32 defaultCount);
    event CreditExtended(address indexed creditor, address indexed debtor, uint256 weiAmount);
    event CreditRepaid(address indexed creditor, address indexed debtor, uint256 weiAmount);
}
```

- **EarnedScore is signed** (`int256`). A worker who fails many audits
  accumulates negative score and becomes ineligible for new jobs until
  positive again. Separate `defaultCount` tracks identity-burn threshold
  (e.g., burn at defaultCount ≥ 10).
- **`effectiveReputationCap`** returns the wei-equivalent cap derived from
  EarnedScore + endorsements + DonatedVerified. v0 formula carries
  forward, just with all values being wei rather than USD.
- **Credit policy is per-client** (publisher), not per-job-overridable in
  v1.0. A per-job override field can be added later.

### Module: Audit.sol

Outcome posting + dispute window. Signature verification ensures only the
authorized verifier set can post.

```solidity
contract Audit {
    struct Outcome {
        bytes32 jobId;
        address worker;
        uint16 similarityBps;   // 0-10000
        bool pass;
        int16 severityBps;      // signed for asymmetric ramps
        uint64 postedAt;
        uint64 finalizesAt;     // postedAt + disputeWindowSeconds
    }
    mapping(bytes32 => Outcome) public outcomes;
    mapping(bytes32 => bool) public finalized;
    uint64 public constant disputeWindowSeconds = 24 hours;

    function postOutcome(
        bytes32 jobId, address worker,
        uint16 similarityBps, bool pass, int16 severityBps,
        address[] calldata verifiers, bytes[] calldata verifierSigs
    ) external;

    function challengeOutcome(bytes32 jobId, bytes calldata proof) external;
    function finalize(bytes32 jobId) external;

    event OutcomePosted(bytes32 indexed jobId, bool pass, uint16 similarityBps);
    event OutcomeChallenged(bytes32 indexed jobId, address challenger);
    event OutcomeFinalized(bytes32 indexed jobId);
}
```

- `postOutcome` requires M-of-N signatures over `(jobId, worker, severity, ...)`
  from registered verifiers. Reuses OpenZeppelin's `ECDSA.recover`.
- 24-hour dispute window; counter-proofs during the window revert the
  outcome and slash the original posters.
- On finalize, Audit calls `Federation.onAuditOutcome` and
  `Ledger.releaseFromJob` to apply rep deltas and slashing.

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
  events.go            — subscribes to chain events, updates local caches
  cache.go             — read-mostly state cached locally (stakes, reps)
  testharness/         — Anvil bring-up, contract deployment, fixtures
  doc.go
```

### Adapter semantics

- **Reads** use `eth_call` (no gas, instant): `GetStake`, `GetReputation`,
  `EffectiveReputationCap`, etc.
- **Writes** submit signed transactions; await receipt; emit local events.
- **Unit conversion at the FFI boundary**: Go side speaks gwei (int64);
  contract side speaks wei (uint256). Conversions are unconditional
  multiplications/divisions by 10⁹ at each method's edge. No oracle math,
  no fiat lookups.
- **Caching**: each engine maintains a local cache of read-mostly fields.
  Cache invalidation on chain events (subscribed via `eth_subscribe`).
- **Nonce management**: per-signer queue with retry on revert
  (re-fetch nonce, re-sign, re-submit).
- **Idempotency**: methods are designed to be safely re-callable.

### Local vs on-chain state

| Concept | Source of truth | Cached in Go? |
|---------|----------------|---------------|
| Stake balances (wei) | Ledger.sol | Yes (invalidated on `StakeDeposited`, `StakeLocked`, etc.) |
| Job locks | Ledger.sol | Yes |
| Insurance reserve | Ledger.sol | Yes |
| Network tax rate | Ledger.sol | Yes |
| Reputation scores | Federation.sol | Yes (invalidated on `RepUpdated`) |
| Pool registry | Federation.sol | Yes |
| Credit policies | Federation.sol | Yes |
| Default counts | Federation.sol | Yes |
| Audit outcomes | Audit.sol | Streamed; archived in append-only log |
| Identity NFTs | Registry.sol | Yes |
| Audit replay history | (local only — never on-chain) | Yes |
| Job receipts | (local only — never on-chain) | Yes |

### Failure modes

- **RPC unreachable**: retry with backoff; degrade to read-only mode if
  the failure persists. Don't lose enqueued txs (persist nonce queue).
- **Transaction reverts**: log, propagate to caller. For idempotent
  operations, retry; for non-idempotent (rare), surface the failure.
- **Reorg**: Base claims fast finality (~2 seconds), but for v1.0 we
  conservatively wait **10+ blocks** before considering any settlement
  final. This is per user direction; high enough to avoid all practical
  reorgs on Base.

## Bootstrap mechanics

### Phase 1: Founder genesis (one-time, at deploy)

```
1. Deploy contracts on Base Sepolia (via proxies).
2. Founder calls Federation.bootstrapGenesis(founderAddr, premineEarnedScore, premineDonatedWei)
   - Sets founder's EarnedScore = premineEarnedScore (raw int256)
   - Sets founder's DonatedVerified = premineDonatedWei (in wei)
   - Callable once, by the deployer key only.
3. Founder calls Registry.mintIdentity(founderAddr, bytes32(0)) — a special
   genesis path that bypasses the donation-audit requirement.
4. Founder calls Federation.setPerClientCredit(perNodeMaxWei, totalExposureWei)
   with their chosen credit-extension parameters.
5. Founder calls Ledger.depositStake() {value: someETH} to provide working
   capital for taking jobs themselves and acting as auditor.
6. Network is live; founder can act as worker and auditor.
```

Suggested initial bootstrap parameters (configurable at deploy):

| Parameter | Suggested value | Notes |
|-----------|----------------|-------|
| Founder premine EarnedScore | `100` | Lets founder take small jobs from start |
| Founder premine DonatedVerified | `1 ETH` (= 10⁹ gwei) | Donation ceiling |
| Founder working stake | `1-10 ETH` | Operating capital |
| Per-client credit per node | `0.005 ETH` (= 5,000,000 gwei) | Sybil floor binds here |
| Per-client total exposure | `1 ETH` (= 10⁹ gwei) | Cap on concurrent debt |
| `MinIdentityCreationDonation` | `2 × perNodeMaxWei` = `0.01 ETH` | Sybil-deterrence rule |

The founder picks actual numbers at deploy. The rule `MinIdentityCreationDonation ≥ 2 × perNodeMaxWei` is enforced
on-chain so the Sybil math holds even if the founder mis-configures one of them.

### Phase 2: Soft launch (a few weeks)

```
1. Trusted friends generate keypairs, deposit small amounts of ETH for stake.
2. Each submits an "identity registration" job via the Orchestrator:
     job.Category = JobIdentityRegistration
     job.Value    = donation amount in gwei (≥ MinIdentityCreationDonation in wei)
     job.Payload  = registration payload (TBD)
3. Founder (and other minted identities) replay the donation work, post
   audit outcomes to Audit.sol.
4. On audit pass, Audit.sol calls:
     Federation.addDonationCredit(node, donationWei)
     Federation.onAuditOutcome(jobId, node, true, severity=0)
     Registry.mintIdentity(node, donationProof)
5. Newly minted node now has positive EarnedScore (from the passed donation
   audit), DonatedVerified = donationWei, and can take jobs up to their
   effective cap. Their per-publisher credit lines come on top.
6. New nodes build organic reputation by taking small jobs; founder's
   credit extension covers gaps for those whose rep is still climbing.
```

### Phase 3: Open launch (manual flag in v1.0)

When the soft-launch group has ≥N organic identities and the audit failure
rate is below threshold, the network opens up:

- v1.0 ships this as a **manual flag** set by the network-leader Safe.
- v2.x can automate based on on-chain telemetry signals.

After open launch, anyone can submit identity-registration jobs and any
sufficiently-reputed worker can verify them.

### Sybil math (gwei-native)

Recall the Sybil deterrence rule:

```
MinIdentityCreationDonationWei ≥ 2 × perNodeMaxCreditWei
```

With the suggested defaults above:

- `perNodeMaxCreditWei` = 5 × 10⁶ gwei (0.005 ETH)
- `MinIdentityCreationDonationWei` = 10⁷ gwei (0.01 ETH)
- Attacker mints identity at cost 0.01 ETH, can extract at most 0.005 ETH from a single client before the identity burns.
- Net per Sybil identity: −0.005 ETH minimum.

If the founder later raises per-node credit (e.g., to 0.02 ETH), the
contract auto-enforces `MinDonation` ≥ 0.04 ETH. No fiat anywhere in the
math.

## Settlement flow (end-to-end)

For a paid embedding job from publisher P to worker W, gross price V (in gwei):

```
Step 1: Off-chain matching
  - Orchestrator matches W to job; W signs a Quote denominated in gwei.
  - Quote validity: 10 minutes.

Step 2: Lock stake (on-chain)
  - Orchestrator calls Ledger.lockForJob(W, jobId, V × stakeMultiplier in wei)
  - Wei amount = (V × stakeMultiplier) × 10⁹

Step 3: Execute (off-chain)
  - W runs the compute, returns JobReceipt.

Step 4: Audit (off-chain compute, on-chain outcome)
  - Audit engine replays the job locally.
  - Computes similarity, severity.
  - Submits to Audit.sol with M-of-N verifier signatures.

Step 5: Wait for dispute window
  - 24 hours, configurable. (10+ blocks of confirmation depth is separate
    and applies to the underlying L2 finality, not this window.)

Step 6: Finalize (on-chain)
  - Anyone calls Audit.finalize(jobId).
  - Audit.sol calls Ledger.releaseFromJob with computed slashFractionBps.
  - If not fully slashed: Audit.sol calls Ledger.settleJob to pay W
    (paid = grossWei × (10000 − networkTaxBps − poolTaxBps) / 10000).
  - Audit.sol calls Federation.onAuditOutcome for rep update.
  - Audit.sol calls Federation.repayCredit if W was operating on credit
    (debt is paid from W's gross settlement before W's net payout).

Step 7: Events propagate
  - Go-side caches invalidate.
  - Orchestrator emits telemetry locally.
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

Weekly or per-PR integration runs deploy contracts to Base Sepolia and run a
smaller scenario. Slower (minutes per scenario, due to block times + ≥10
confirmation depth), but catches realistic things:

- L2-specific gas pricing
- Cross-contract interaction at real network latencies
- Real proxy upgrade flow exercise

Funding via Base Sepolia faucet (~1 ETH per agent per week, manual ask or
automated drip).

### What's NOT tested in v1.0

- Mainnet behavior (no mainnet deploy)
- Adversarial scenarios at scale (10k+ jobs, large pools)
- Long-running audit-rate adaptation (control law tuning is v2+)
- Realistic network latency between distributed verifiers (still in-process)
- Upgrade-flow security (the proxy admin process needs separate hardening
  before mainnet)

## Migration path from v0

- v0 in-memory engines (`testharness.StubLedger`, `testharness.StubFederation`)
  remain as test-only implementations.
- New `eth.LedgerEngine` and `eth.FederationEngine` implement the same
  `iface.*Engine` interfaces.
- The orchestrator picks one at construction (config flag).
- Audit engine: keeps the in-memory implementation from v0 for the
  replay/control-law logic; adds an on-chain outcome-posting layer via
  the Audit.sol adapter.
- v0's `Money int64` ("micro-USDC" label) gets relabeled to `Gwei int64`
  in a small follow-up commit on the foundation branch. The math is
  identical; only the comment changes.

```go
// New orchestrator construction shape (v1.0)
cfg := orchestrator.OrchestratorConfig{ ... }

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
- Workers register a stealth meta-address in `Registry.sol` (field already
  reserved in v1.0; v1.1 populates it).
- Publishers compute stealth addresses for each payment; settle to the
  fresh address rather than the worker's primary address.
- The Go scanner watches Announcer events and surfaces incoming payments
  to the worker's wallet.
- **AA paymaster** (ERC-4337) lets new nodes have their gas paid by a
  network-funded paymaster (drawn from insurance reserve) — eliminates
  the "gas payer is your main wallet" privacy leak.

v1.0 prep so v1.1 is additive, not a rewrite:
- `Registry.sol` reserves `stealthMetaAddressOf` / `setStealthMetaAddress`
  storage and methods (no-op in v1.0).
- Settlement APIs in `Ledger.sol` will accept an optional `recipient`
  parameter in v1.1 — defaults to the worker's primary address but can
  be overridden to a stealth address. This is a v1.1 change, not v1.0.

## v1.2 preview: ZK reputation

- **Semaphore-based group membership proofs**: workers prove "I belong
  to the set of nodes with rep ≥ threshold" without revealing which node
  they are.
- `Federation.sol` reputation stops being a plaintext mapping and becomes
  a Merkle commitment over `(node, score)` leaves.
- Old `getReputation(node)` returns the commitment hash; a separate
  `proveQualified(threshold, proof)` becomes the gating function.
- Proof verification adds ~200-500k gas per job on top of existing flows.

v1.0 prep:
- `Registry.sol` reserves a `commitmentRootOf` field per identity, empty
  in v1.0; v1.2 attaches each node's reputation commitment to its identity NFT.
- Plaintext reputation in `Federation.sol` is structured so it can be
  superseded by a commitment-tree version without breaking the surface
  API.

## Open questions for v1.0 design review

(Of the original seven, all have been answered. Listing the locked-in
decisions here so the doc captures them in one place.)

1. **Multisig for Audit outcome posting:** Gnosis Safe (2-of-3 founders
   minimum). Same Safe also holds proxy-upgrade authority.

2. **Upgradability:** UUPS proxies for all contracts. Upgrade authority is
   the Gnosis Safe. Known cost: the Safe is the most attack-valuable target
   in the system. Mitigation: keep Safe signers cold-stored; documented
   incident-response playbook for compromised signer.

3. **Reputation on slash:** EarnedScore is signed and can go negative.
   Burn-identity threshold is tracked via a separate `defaultCount` field
   (burns at defaultCount ≥ 10, configurable). Negative score blocks
   new job acceptance until positive again.

4. **MinIdentityCreationDonation:** scales as `2 × perNodeMaxCreditWei`,
   enforced on-chain. No fixed dollar floor (no fiat in the protocol).

5. **Reorg confirmation depth on Base:** 10+ blocks (~20-30 sec settlement
   latency). Conservative; can relax post-mainnet once L2 finality is more
   measured.

6. **Identity NFT metadata:** Reserved fields for stealth meta-address
   (v1.1) and commitment root (v1.2). Empty in v1.0 storage but the slots
   exist.

## Implementation partition (preview — separate plan files later)

Once this doc is approved, the work breaks into 4 parts roughly matching
the v0 structure but for v1.0:

| Part | Scope | Approx. lines |
|------|-------|---------------|
| **v1.0-A: Contracts** | All Solidity (Registry, Ledger, Federation, Audit, proxies, deployment scripts) + Foundry tests | ~1500 |
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

Conservative estimate: **2-3 weeks** for v1.0 with 4 orchestrators in parallel.
