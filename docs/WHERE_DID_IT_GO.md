# Where did it go? — evo → Adamaton path map

Reference for archaeology: when an old memory, script, or comment references a path in the legacy `/thearray/git/evo/` monorepo or `/thearray/git/deepresearch/platform/`, this table shows the new home in Adamaton.

## Top-level component → sub-repo

| evo path | Adamaton path | Go module path |
|---|---|---|
| `evo/core/` | `Adamaton/core/` | `github.com/sirus20x6/adamaton-core` |
| `evo/skills/` | `Adamaton/knowledge/skills/` | `github.com/sirus20x6/adamaton-knowledge/skills` |
| `evo/skills-rae/` | `Adamaton/knowledge/skills-rae/` | `github.com/sirus20x6/adamaton-knowledge/skills-rae` |
| `evo/reindex/` | `Adamaton/knowledge/reindex/` | `github.com/sirus20x6/adamaton-knowledge/reindex` |
| `evo/r2g/` | `Adamaton/knowledge/r2g/` | `github.com/sirus20x6/adamaton-knowledge/r2g` |
| `evo/tools/arxiv-skip/` | `Adamaton/knowledge/tools/arxiv-skip/` | — (Zig) |
| `evo/tools/latex2text/` | `Adamaton/knowledge/tools/latex2text/` | — (Zig) |
| `evo/nano-research/` | `Adamaton/deepresearch/nano-research/` | `github.com/sirus20x6/adamaton-deepresearch/nano-research` |
| `evo/dashboard/` | `Adamaton/platform/dashboard/` | `github.com/sirus20x6/adamaton-platform/dashboard` |
| `evo/plugin-host/` | `Adamaton/platform/plugin-host/` | `github.com/sirus20x6/adamaton-platform/plugin-host` |
| `evo/dispatch/` | `Adamaton/platform/dispatch/` | `github.com/sirus20x6/adamaton-platform/dispatch` |
| `evo/temporal/` | `Adamaton/platform/temporal/` | `github.com/sirus20x6/adamaton-platform/temporal` |
| `evo/delegator/` | `Adamaton/delegator/delegator/` | `github.com/sirus20x6/adamaton-delegator/delegator` |
| `evo/mcp/` | `Adamaton/delegator/mcp/` | `github.com/sirus20x6/adamaton-delegator/mcp` |
| `evo/evolve/` | `Adamaton/evolve/evolve/` | `github.com/sirus20x6/adamaton-evolve/evolve` |
| `evo/workflow-builder/` | `Adamaton/evolve/workflow-builder/` | `github.com/sirus20x6/adamaton-evolve/workflow-builder` |

## Cross-component refactors (not just moves)

Two packages moved into `core/` during pre-split refactor (P0):

| Old path | New path |
|---|---|
| `evo/delegator/contextmode/OctenClient` | `Adamaton/core/octen/` (renamed `OctenClient`→`Client`, `NewOctenClient`→`NewClient`, `OctenEmbedDim`→`EmbedDim`) |
| `evo/workflow-builder/executor/CLIExecutor` + helpers | `Adamaton/core/executor/cli/` (workflow-builder retains a thin `CLIPlugin` adapter at `evolve/workflow-builder/executor/cli_adapter.go`) |

## deepresearch/platform → Adamaton

| deepresearch path | Adamaton path |
|---|---|
| `platform/frontend/` | `Adamaton/frontend/` |
| `platform/plugins/` | `Adamaton/platform/plugin-host-plugins/` |
| `platform/reranker/` | `Adamaton/knowledge/sidecars/reranker/` |
| `platform/bench/` | `Adamaton/knowledge/bench/` |
| `platform/docs/` | `Adamaton/deepresearch/docs/` |
| `platform/infra/{postgres,redis,searxng,cluster-sidecar,sidecar}` | `Adamaton/deploy/pi5/infra/` |
| `platform/docker-compose.yml` | `Adamaton/deploy/pi5/docker-compose.yml` (image refs swapped to `adamaton-<sub>:${IMAGE_TAG}`) |
| `platform/docker-compose.workstation.yml` | `Adamaton/deploy/workstation/docker-compose.yml` |
| `platform/infra/Caddyfile` | `Adamaton/deploy/pi5/Caddyfile` |

## Infrastructure assets

| evo path | Adamaton path |
|---|---|
| `evo/Makefile` (119 targets) | `Adamaton/Makefile` (paths rewritten: `cd skills-rae` → `cd knowledge/skills-rae` etc.) |
| `evo/configs/` (agents.yaml, models.yaml, production.yaml, dynamicconfig/, …) | `Adamaton/deploy/pi5/configs/` |
| `evo/docker/postgres/` | `Adamaton/deploy/pi5/infra/postgres-evo/` |
| `evo/systemd/` (service units) | `Adamaton/deploy/systemd/` (kept for bare-metal scenarios) |
| `evo/scripts/{crashloop-guard,register-gitea-agents,…}.sh` | `Adamaton/scripts/` |
| `evo/.golangci.yml` | `Adamaton/.golangci.yml` |
| `evo/.github/workflows/` | `Adamaton/.github/workflows/` (per-sub-repo workflows live under each sub-repo's `.github/`) |
| `evo/.env.example` | `Adamaton/.env.example` (per-host envs at `Adamaton/deploy/<host>/.env.example`) |
| `evo/.dockerignore` | `Adamaton/.dockerignore` |
| `evo/docs/` (operational: VLLM_INTEGRATION, GITEA_*, troubleshooting) | `Adamaton/docs/operations/` (separate from `Adamaton/docs/{ARCHITECTURE,WORKTREE_WORKFLOW,DEPLOY,MIGRATION,AGENT_ONBOARDING,CICD,WHERE_DID_IT_GO}.md`) |

## What was intentionally NOT migrated

These live in the read-only `sirus20x6/evo-archive` repo (P8 will push it). Reference there for archaeology:

- `evo/_legacy/`
- `evo/INTEGRATION_K.md` through `INTEGRATION_Q.md` (historical migration phase docs)
- `evo/DEVELOPMENT_GUIDE.md`, `PROJECT_STATUS.md`, `GITEA_AGENT_SETUP_COMPLETE.md`
- `evo/gogents-agents-config.json` (old gogents agent config)
- `evo/quick-start.sh` (superseded by `bin/adam` workflows)
- `evo/tests/integration/` (historical tests)
- `evo/examples/gitea-agent-comments.go` (one-off demo)
- `evo/deepresearch/` (submodule pointing at upstream LDR — reference only, not our code)
- `evo/docker-compose.postgres.yml` (superseded by `Adamaton/deploy/workstation/docker-compose.yml`)
- `evo/example_github_action.yml` (redundant with `Adamaton/.github/workflows/`)
- `platform/backend/` (Python R2R-era code; functionality long since reimplemented in r2g + plugin-host)

## How to use this map

When grep finds a path that doesn't exist anymore:

```bash
# Memory or comment says "see evo/delegator/contextmode/..."
# Look up in this doc → it moved (the contextmode stuff went to core/octen/)

# Old script references /thearray/git/evo/skills/
# Look up → /thearray/git/Adamaton/knowledge/skills/

# If you can't find it here:
cd ~/evo-archive && git log --all --source -- <path>      # pre-rename archaeology
```
