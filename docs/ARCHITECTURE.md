# Architecture

## Component DAG

```
                              ┌────────────────────┐
                              │ adamomaton-core    │  ← bottom of stack
                              │  pgutil, llmclient │
                              │  octen, executor,  │
                              │  workerregistry,   │
                              │  subprocess, types │
                              └────────┬───────────┘
                                       │
        ┌─────────┬────────────┬───────┼─────────────┬──────────────┐
        ▼         ▼            ▼       ▼             ▼              ▼
  ┌──────────┐ ┌─────────┐ ┌──────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐
  │knowledge │ │ evolve  │ │deleg.│ │ platform │ │deepresearch  │ │ frontend │
  │          │ │         │ │      │ │ (dash,   │ │              │ │ (SPA)    │
  │skills,   │ │evolve,  │ │+ mcp │ │ plugin,  │ │nano-research │ │          │
  │skills-rae│ │workflow │ │      │ │ dispatch,│ │              │ │          │
  │reindex,  │ │-builder │ │      │ │ temporal)│ │              │ │          │
  │r2g       │ │evaluator│ │      │ │          │ │              │ │          │
  └────┬─────┘ └─────────┘ └──────┘ └────┬─────┘ └──────┬───────┘ └──────────┘
       │                                  │              │
       │  (HTTP at /v1/rae/*)             │              │
       └──────────────────────────────────┼──────────────┘
                                          │
            platform.dashboard imports {knowledge.skills, delegator,
                                        evolve.workflow-builder}
            by design — it's the API aggregator. No cycles.
```

## Repo boundaries

| Sub-repo | Owns | Schemas | Ports |
|---|---|---|---|
| **core** | pgutil, llmclient, octen, workerregistry, subprocess, executor/cli, types, config, envutil, metrics, credentialstore | — | — |
| **frontend** | React/Vite SPA, all pages | — | — (served by caddy) |
| **knowledge** | skills, skills-rae, reindex, r2g, sidecars/reranker | evo.skills, evo.skill_communities, evo.insights, corpora, documents, chunks, figures | 7376 (skills-rae) |
| **deepresearch** | nano-research (9-stage pipeline), figure-renderer sidecar | evo.research_runs, research_artifacts, llm_sessions, llm_traces, nano_events, distill_candidates | 7378 (nano-research), 8090 (figure-renderer) |
| **platform** | dashboard, plugin-host (14 plugins), dispatch, temporal worker | plugin_config | 9123 (dashboard), 7375 (plugin-host), 7233 (temporal) |
| **delegator** | delegator orchestrator, MCP servers (delegator-mcp, skillrae-mcp) | — | — (stdio MCP) |
| **evolve** | evolve, workflow-builder, KernelBench Python evaluator | evo.programs, evo.runs | — |

## Cross-component HTTP contracts

| Caller → Callee | Path | Purpose |
|---|---|---|
| deepresearch → knowledge | `POST /v1/rae/compile`, `/v1/rae/search` | Skill context for stage prompts |
| platform.dashboard → knowledge | `GET /v1/rae/communities`, `/v1/rae/skills/...` | Skills page backend |
| platform.dashboard → deepresearch | `GET /v1/nano/runs/*`, SSE events | /nano page backend |
| platform.dashboard → platform.plugin-host | `GET /platform/search/query?source=...` | Citation checker, search UI |
| platform.dashboard → delegator | (in-process Go import) | /delegator page backend (orchestrator state) |
| frontend → caddy → platform.dashboard | `/api/v1/*` | All user-facing API |
| evolve → deepresearch (rare) | (Postgres SQL) | Shared evo.insights table for memory writes |

## Feature → repo mapping (cross-cutting features)

| Feature | Schema | HTTP | UI | Worker/Activity |
|---|---|---|---|---|
| **Memory** (evo.insights) | knowledge | platform.dashboard | frontend | evolve, deepresearch |
| **Nodes** (worker registry) | core (registry types) | platform.dashboard | frontend | every worker self-registers |
| **Library** (corpora/docs) | knowledge.r2g | platform.dashboard | frontend | platform.plugin-host (importers) |
| **Evolution** (programs) | evolve | platform.dashboard | frontend | evolve.evo-worker |
| **NanoResearch** (research runs) | deepresearch | deepresearch | frontend | deepresearch.nano-research-worker |
| **Skills** (skill bank) | knowledge | platform.dashboard | frontend | knowledge.skills-rae-worker |

## Go module dependencies

Every component's `go.mod` has `require github.com/sirus20x6/adamomaton-core` (and additional pins for the higher-level deps).

**No `replace` directives in sub-repo `go.mod`** — local dev resolves via the umbrella's `go.work`. CI inside a single sub-repo (without the umbrella) uses the pinned tagged versions.

## Submodule pinning

The umbrella's `.gitmodules` lists the seven sub-repos. The pinned SHA is stored as the umbrella tree entry for each path. `bin/adam bump <sub>` advances the pin to the sub-repo's `origin/main` HEAD and creates a single umbrella commit; CI on the umbrella runs `go build ./...` against the pinned tree.
