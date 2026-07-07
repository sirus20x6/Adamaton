# Adamaton

Umbrella repo for the Adamaton system — an autonomous research, retrieval, and
self-improvement platform. Seven sub-repos embedded as git submodules; the
umbrella holds compose/deploy configs, agent-coordination tooling, and shared
docs.

## Layout

```
Adamaton/
├── core/           → adamaton-core         (Go: foundation — pgutil, llmclient, octen, tracectx, workerregistry, p2p/eth, executor/cli)
├── frontend/       → adamaton-frontend     (React/Vite SPA)
├── knowledge/      → adamaton-knowledge    (Go: skills, skills-rae, reindex, r2g — RAG + skill-memory)
├── deepresearch/   → adamaton-deepresearch (Go: nano-research 9-stage pipeline + sidecars)
├── platform/       → adamaton-platform     (Go: dashboard, plugin-host, dispatch, temporal-worker)
├── delegator/      → adamaton-delegator    (Go: delegator + MCP servers)
├── evolve/         → adamaton-evolve       (Go: evolve, workflow-builder, KernelBench evaluator)
├── go.work         (aggregates every Go module across submodules for local dev)
├── bin/adam        (agent-coordination CLI: claim/release/status/ci/bump/ship/deploy/fleet)
├── hooks/          (canonical pre-commit/pre-push templates synced into each submodule)
├── deploy/         (per-host compose/Caddyfile/up.sh: pi5, pi5-speaker, blackwell, workstation)
├── docs/           (ARCHITECTURE, WORKTREE_WORKFLOW, DEPLOY, MIGRATION)
├── scripts/        (migrate.sh — one-shot evo → Adamaton bootstrap)
└── .locks/         (per-task lockfiles; tracked so concurrent agents see each other's claims)
```

## Features

### Autonomous deep research — `deepresearch`
NanoResearch, a 9-stage research pipeline: multi-source retrieval → iterative
query refinement → evidence synthesis → cited long-form artifacts → distillation
candidates. Pluggable search strategies (dual-confidence, evidence-based,
iterative-refinement, IterDRAG, parallel-constrained). Sources: web (SearXNG),
arXiv full-text (PDF → LaTeX → text), DOI/URL ingest, and government-statistics
adapters. Streams progress over SSE; runs as a Temporal workflow. Implements the
NanoResearch pipeline; feeds a self-distillation loop that mines training
candidates from completed research.

### Retrieval & knowledge — `knowledge`
- **r2g** — hybrid RAG: lexical (BM25) + dense (BGE-M3 / Octen) retrieval fused
  with Reciprocal Rank Fusion, a cross-encoder reranking pass, optional
  graph-vote retrieval (TGS-RAG), and a native graph-relationships endpoint.
- **skills-rae** — the SkillRAE method: skill-based context compilation for
  retrieval-augmented execution. Two-stage retrieval (BM25 bottom-up + community
  top-down over BGE-M3 embeddings) compiled into a token-budgeted context block
  and served over MCP for agents.
- **H-Mem** — hierarchical memory over the corpus: episodic capture plus
  recursive rollup summary trees, so retrieval can draw on condensed higher-level
  abstractions instead of only leaf chunks.
- Zig-accelerated tokenization (`ztok`, byte-identical cl100k, ~5.7× faster),
  reindex pipeline, and figure rendering.

### Evolutionary self-improvement — `evolve`
A mutation → evaluate → select loop with a **KernelBench** CUDA-kernel evaluator
(runs on the GPU host), plus a visual workflow builder/runtime with built-in
plugin nodes. Long-running evolutions drive through Temporal.

### Multi-agent delegation — `delegator`
Budget-aware router that fans coding tasks across Codex / Gemini / OpenCode with
quota tracking and cost accounting, exposed as MCP servers for Claude Code —
including kanban-orchestration tools for agent-driven project execution.

### Platform & orchestration — `platform`
Dashboard API aggregator, a plugin-host loading 14 search-source plugins, and
the Temporal worker stack. Higher-level features: per-project **kanban boards**
(atomic card claim for agent orchestration), persistent **tmux terminals** over
websockets, **experiment** tracking + Temporal-dispatched launch, fleet-health
rollup, and observability (Temporal queue-depth gauge, low-cardinality
error-class tagging, W3C trace-context propagation across service boundaries).
Auth via an encrypted credential keyring; per-host deploy-agent tokens.

### Decentralized compute & privacy — `core` (`p2p/eth`)
An experimental Ethereum-native compute network (design + foundation): on-chain
ledger / federation / audit adapters, **zk-reputation** (Semaphore identities,
Poseidon hashing, Groth16 proofs of "≥N passing audits"), and **ERC-5564**
stealth-address settlement. See `docs/p2p-plan/` for the full design corpus.

### Fleet & agent tooling — `bin/adam` + `deploy/`
Worktree-based agent coordination (`claim`/`release`/`status`), a local CI gate
(`adam ci` — no hosted runners), submodule pin management (`bump`), and
push-deploy across pi5 / pi5-speaker / blackwell / workstation with fleet-verify
and self-hosted alerting.

## Quickstart

```bash
git clone --recursive git@github.com:sirus20x6/Adamaton.git
cd Adamaton
bin/adam sync-hooks                       # install pre-commit/pre-push into each submodule
bin/adam status                           # list any active agent claims
bin/adam claim platform/my-feature        # create a worktree to work in
```

## Component dependency DAG

```
core ◄── knowledge
core ◄── deepresearch ◄── knowledge (HTTP only; no Go module dep)
core ◄── evolve
core ◄── delegator
core ◄── platform ◄── knowledge, delegator, evolve  (dashboard aggregation)
```

No cycles. See `docs/ARCHITECTURE.md` for component details.

## References

Prior art the features are built on. Several are cited directly in the codebase
(SkillRAE, NanoResearch, TGS-RAG, H-Mem, the self-distillation loop); the rest
are the established techniques and standards the implementations follow.

**Deep research & distillation**
- NanoResearch — the multi-stage autonomous research pipeline.
  [arXiv:2605.10813](https://arxiv.org/abs/2605.10813) (with OpenRaiser/NanoResearch).
- Self-distillation — mining training candidates from completed research runs.
  [arXiv:2603.12273](https://arxiv.org/abs/2603.12273)

**Skills & memory**
- SkillRAE — Meng, Wang & Fang, *SkillRAE: Agent Skill-Based Context Compilation
  for Retrieval-Augmented Execution*, 2026.
  [arXiv:2605.10114](https://arxiv.org/abs/2605.10114) (drives `skills-rae` + the
  SkillRAE MCP).
- H-Mem — hierarchical memory (episodic capture + recursive rollup summary
  trees), referenced in `knowledge/r2g` as the memory-subsystem design.

**Retrieval & RAG**
- BGE-M3 embeddings — Chen et al., *BGE M3-Embedding: Multi-Lingual,
  Multi-Functionality, Multi-Granularity Text Embeddings Through
  Self-Knowledge Distillation*, 2024. [arXiv:2402.03216](https://arxiv.org/abs/2402.03216)
- Reciprocal Rank Fusion — Cormack, Clarke & Büttcher, *Reciprocal Rank Fusion
  Outperforms Condorcet and Individual Rank Learning Methods*, SIGIR 2009.
- Okapi BM25 — Robertson & Zaragoza, *The Probabilistic Relevance Framework:
  BM25 and Beyond*, 2009.
- Cross-encoder passage reranking — Nogueira & Cho, *Passage Re-ranking with
  BERT*, 2019 ([arXiv:1901.04085](https://arxiv.org/abs/1901.04085)); models
  `cross-encoder/ms-marco-MiniLM-L-6-v2` and Qwen3-Rerank.
- IterDRAG / inference-time scaling for long-context RAG — Yue et al.,
  *Inference Scaling for Long-Context Retrieval Augmented Generation*, 2024.
  [arXiv:2410.04343](https://arxiv.org/abs/2410.04343)
- TGS-RAG (graph-vote retrieval) — [arXiv:2605.05643](https://arxiv.org/abs/2605.05643)

**Evolutionary optimization**
- KernelBench — Ouyang et al., *KernelBench: Can LLMs Write Efficient GPU
  Kernels?*, 2025. [arXiv:2502.10517](https://arxiv.org/abs/2502.10517)

**Zero-knowledge & privacy (p2p/eth)**
- Poseidon hash — Grassi, Khovratovich, Rechberger, Roy & Schofnegger,
  *Poseidon: A New Hash Function for Zero-Knowledge Proof Systems*,
  USENIX Security 2021.
- Groth16 — Groth, *On the Size of Pairing-Based Non-Interactive Arguments*,
  EUROCRYPT 2016.
- Semaphore — zero-knowledge membership/signaling protocol.
- ERC-5564 — Ethereum stealth-address standard.

**Infrastructure**
- W3C Trace Context — <https://www.w3.org/TR/trace-context/>

## Docs

- [Architecture](docs/ARCHITECTURE.md) — component DAG, HTTP contracts, schema ownership.
- [Worktree workflow](docs/WORKTREE_WORKFLOW.md) — how to claim, work, release.
- [Deploy](docs/DEPLOY.md) — per-host bring-up, rollback, troubleshooting.
- [Migration](docs/MIGRATION.md) — log of the evo → Adamaton split for archaeology.

## Migration status

This repo was bootstrapped on 2026-05-16 by splitting the [evo](https://github.com/sirus20x6/evo-archive) monorepo. See `docs/MIGRATION.md` for the full log; pre-Adamaton history lives in the read-only `evo-archive` repo for `git blame` archaeology.
