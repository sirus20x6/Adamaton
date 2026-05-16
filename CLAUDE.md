# Agent instructions — Adamaton umbrella

> ## 🚫 BLOCKING — never commit to `main` directly.
>
> All agent work goes on a feature branch via `bin/adam claim <scope>/<task>`.
> The pre-commit hook **hard-rejects** commits to `main`/`master` from the
> canonical checkout. If you accidentally edited `main`, run `bin/adam rescue`
> to recover (it stashes your changes so you can pop them into a fresh claim).
>
> First 3 commands for any new agent:
> ```bash
> bin/adam doctor                       # verify env (gh, go, hooks, submodules)
> bin/adam sync-hooks                   # install hooks if doctor flagged them
> bin/adam claim <scope>/<task>         # creates worktree + feature branch; cd into it
> ```
>
> The ONLY supported way to land a commit on the umbrella's `main` is
> `bin/adam bump <sub-repo>` (advances submodule pins; sets `ADAM_BUMP=1`
> internally to skip the hook). Everything else needs a PR.

You are working in the Adamaton umbrella repo. The 7 sub-repos (core, frontend, knowledge, deepresearch, platform, delegator, evolve) are submodules pinned by SHA.

## The two worktree modes

**Single-component work** (most tasks): create a worktree of the sub-repo, not the umbrella.

```bash
bin/adam claim platform/my-task
# → creates platform/platform-worktrees/<you>-my-task with branch <you>/my-task
```

**Cross-component work** (touches multiple sub-repos): create a worktree of the umbrella.

```bash
bin/adam claim cross/my-task
# → creates worktrees/<you>-my-task with all submodules initialized
```

When done:

```bash
bin/adam release platform/my-task        # pushes branch, removes worktree, deletes lockfile
```

## Coordination rules

- **Always `bin/adam claim` before editing.** This writes `.locks/<scope>-<task>.json` so other agents see what you're working on.
- **Check `bin/adam status --conflicts` before starting** if you're touching shared paths (`core/llmclient/`, `core/octen/`, `platform/dashboard/apiserver/`).
- **Never push to main/master directly.** Push to your `<you>/<task>` branch and open a PR on the sub-repo.
- **Never bypass hooks** (`--no-verify`, `--no-gpg-sign`, force-push to main). These exist for the cross-agent contract.
- **Bump the umbrella pin after merging a sub-repo PR.** `bin/adam bump <sub-repo>` updates the umbrella's submodule SHA and commits.

## Hooks

`bin/adam sync-hooks` installs canonical `pre-commit`, `pre-push`, `commit-msg` into every submodule. The hooks:
- Reject `Co-Authored-By:` trailers (commit content stays attributable to one author).
- Reject `@`-mentions in commit message bodies.
- Refuse `--force` to main/master and `--no-verify`.
- Warn when pushing a branch claimed by a different agent.

## Per-component CLAUDE.md

Each sub-repo has its own `CLAUDE.md` with build/test commands, dev DSN, and component-specific gotchas. Read the one for the sub-repo you're working in before making changes.

## Memory

Memory dir at `~/.claude/projects/-thearray-git-Adamaton/memory/`. Pre-Adamaton memories were copied over from `~/.claude/projects/-thearray-git-evo/memory/` during the cutover. Reference relevant ones via `[[name]]` links in new memories.

## Pre-existing constraints (carried from evo)

- **gogents commit style**: `user.name=sirus20x6`, `user.email=sirus20x6@users.noreply.github.com`, **no `Co-Authored-By:` trailers** (hook-enforced).
- **Port 8080 is banned** — pick 9123, 7376, 7378, etc. instead.
- **Pi Caddy bind-mount inode trap**: `mv newfile oldfile` on the host requires `docker compose restart frontend`, not just `caddy reload`.

## Deploy

`bin/adam deploy <host>` is the canonical bring-up:

- `pi5` — main stack (postgres, temporal, knowledge backends, deepresearch, platform, frontend, caddy)
- `pi5-speaker` — replica (nano-research-worker, figure-renderer)
- `blackwell` — GPU node (vLLM, evo-worker, distill trainer)
- `workstation` — local dev (postgres + temporal-dev only)

See `docs/DEPLOY.md` for rollback and per-host troubleshooting.
