# Migration log: evo → Adamomaton

Bootstrapped on 2026-05-16. Old evo repo archived to read-only at `sirus20x6/evo-archive` for `git blame` archaeology; active code now lives across the 7 sub-repos under this umbrella.

## Phases (per the approved plan)

| Phase | Status | Notes |
|---|---|---|
| **P0** | done (2026-05-16) | Pre-split refactor inside evo. Two cross-component imports eliminated: `core/octen` carved out of `delegator/contextmode`, `core/executor/cli` carved out of `workflow-builder/executor`. Branch `adamomaton-p0` merged to evo main (commits `b7817e6`, `36094ea`). |
| **P1** | in progress (2026-05-16) | Bootstrap umbrella + 7 sub-repos. 8 GitHub repos created; submodules wired; bin/adam, hooks, docs, deploy skeletons in place. |
| **P2** | pending | scripts/migrate.sh + per-component code copy + import path rewrite. |
| **P3** | pending | Umbrella go.work + cross-repo build verification. |
| **P4** | pending | Frontend + plugin payloads + deploy/ configs populated. |
| **P5** | pending | bin/adam CLI hardening (status --conflicts, bats tests). |
| **P6** | pending | Hooks v1.1 (more robust lockfile parsing, dry-run mode). |
| **P7** | pending | Cutover to Pi #1, Pi #2, Blackwell. |
| **P8** | pending | Archive old evo (push to evo-archive, mark read-only). |
| **P9** | pending | Per-component CLAUDE.md + READMEs. |

## P0 — pre-split refactor (done)

Goal: eliminate two cross-component Go imports that would have become inter-repo coupling once sub-repos shipped.

- **`core/octen`**: moved `OctenClient` + `NewOctenClient` (~150 LOC) from `delegator/contextmode/` to `core/`. Renamed per Go convention: `OctenClient → Client`, `NewOctenClient → NewClient`, `OctenEmbedDim → EmbedDim`. Updated 5 importers (intra-contextmode + evolve × 2 + mcp). After this, **evolve no longer imports `delegator/contextmode`**.
- **`core/executor/cli`**: moved `CLIExecutor` + `CLIInput`/`CLIOutput`/`AgentSpec` + opencode_serve + local_models + opencode_config (~600 LOC, 6 files) from `workflow-builder/executor/` to `core/executor/cli/`. Left behind a `workflow-builder/executor/cli_adapter.go` (~75 LOC) defining `CLIPlugin` (a `*cli.CLIExecutor` wrapper) with the workflow-builder-specific `Execute(*PluginNode, input-map)` method. Updated 4 importers (delegator × 3 tests + mcp). After this, **delegator no longer imports `workflow-builder/executor`**.

Verification: all 12 Go modules build; `go vet` clean on the 5 touched modules; non-DB tests pass for core/{octen,executor/cli}, workflow-builder/executor, and delegator/{orchestrator,budget,contextmode,llm,quota,skillsclient}.

## P1 — bootstrap (in progress)

GitHub repos created (2026-05-16, all private under sirus20x6):
- adamomaton-core
- adamomaton-frontend
- adamomaton-knowledge
- adamomaton-deepresearch
- adamomaton-platform
- adamomaton-delegator
- adamomaton-evolve
- Adamomaton (umbrella)

Umbrella initialized at `/thearray/git/Adamomaton/` with:
- `.gitmodules` pinning all 7 sub-repos
- `bin/adam` CLI (claim/release/status/sync-hooks/deploy/bump/pin/pull)
- `hooks/{pre-commit,pre-push,commit-msg,lib/lib.sh}`
- `deploy/{pi5,pi5-speaker,blackwell,workstation}/` placeholders
- `docs/{ARCHITECTURE,WORKTREE_WORKFLOW,DEPLOY,MIGRATION}.md`
- `scripts/migrate.sh` placeholder
- `.locks/.gitkeep`
- `go.work` (empty; populated by `scripts/migrate.sh` in P2)
- `CLAUDE.md` (agent-facing instructions)
- `README.md`

Sub-repos remain empty (just their stub README) until P2 runs the migration script.

## Provenance

Pre-Adamomaton history is preserved in:

- **evo-archive** (created during P8) — full git history of the evo monorepo up to the P0 commits.
- **deepresearch/platform repo** — frontend + platform code that pre-dated the consolidation; the relevant slices are imported into adamomaton-frontend and adamomaton-platform.

For pre-Adamomaton blame:

```bash
cd ~/evo-archive
git log -- <path-as-it-was-in-evo>
```

`git blame` after the cutover starts from "Initial commit: Adamomaton import from evo@<sha>" in each sub-repo. The commit's body lists the source evo SHA so you can chase further.
