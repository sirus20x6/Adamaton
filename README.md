# Adamaton

Umbrella repo for the Adamaton system. Seven sub-repos embedded as git submodules; the umbrella holds compose/deploy configs, agent-coordination tooling, and shared docs.

## Layout

```
Adamaton/
├── core/           → adamaton-core         (Go: foundation — pgutil, llmclient, octen, workerregistry, executor/cli)
├── frontend/       → adamaton-frontend     (React/Vite SPA)
├── knowledge/      → adamaton-knowledge    (Go: skills, skills-rae, reindex, r2g — RAG + memory)
├── deepresearch/   → adamaton-deepresearch (Go: nano-research 9-stage pipeline + sidecars)
├── platform/       → adamaton-platform     (Go: dashboard, plugin-host, dispatch, temporal-worker)
├── delegator/      → adamaton-delegator    (Go: delegator + MCP servers)
├── evolve/         → adamaton-evolve       (Go: evolve, workflow-builder, KernelBench evaluator)
├── go.work         (aggregates every Go module across submodules for local dev)
├── bin/adam        (agent-coordination CLI: claim/release/status/deploy/bump)
├── hooks/          (canonical pre-commit/pre-push templates synced into each submodule)
├── deploy/         (per-host compose/Caddyfile/up.sh: pi5, pi5-speaker, blackwell, workstation)
├── docs/           (ARCHITECTURE, WORKTREE_WORKFLOW, DEPLOY, MIGRATION)
├── scripts/        (migrate.sh — one-shot evo → Adamaton bootstrap)
└── .locks/         (per-task lockfiles; tracked so concurrent agents see each other's claims)
```

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

## Docs

- [Architecture](docs/ARCHITECTURE.md) — component DAG, HTTP contracts, schema ownership.
- [Worktree workflow](docs/WORKTREE_WORKFLOW.md) — how to claim, work, release.
- [Deploy](docs/DEPLOY.md) — per-host bring-up, rollback, troubleshooting.
- [Migration](docs/MIGRATION.md) — log of the evo → Adamaton split for archaeology.

## Migration status

This repo was bootstrapped on 2026-05-16 by splitting the [evo](https://github.com/sirus20x6/evo-archive) monorepo. See `docs/MIGRATION.md` for the full log; pre-Adamaton history lives in the read-only `evo-archive` repo for `git blame` archaeology.
