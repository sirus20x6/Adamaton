# Agent onboarding — first 5 minutes

You just cloned (or were assigned to) Adamaton. Here's the canonical start sequence.

## 0. One-time setup (already done if you cloned recursively)

```bash
git clone --recursive git@github.com:sirus20x6/Adamaton.git
cd Adamaton
```

If you cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

## 1. Environment sanity check

```bash
bin/adam doctor
```

This verifies: `git` user config, `gh` CLI authenticated, `go` ≥1.25 installed, 7 submodules initialized, hooks installed in every checkout, no stale state on `main`. Fix anything it flags **before** you start working — the hooks will reject commits otherwise.

## 2. Install hooks (only first time, or after umbrella pull that changed `hooks/`)

```bash
bin/adam sync-hooks
```

Installs `pre-commit`, `pre-push`, `commit-msg` into the umbrella's and every submodule's `.git/hooks/`. Idempotent.

## 3. Claim work — never edit `main` directly

```bash
# For a task that touches ONE sub-repo:
bin/adam claim platform/dashboard-pagination
# → creates platform/platform-worktrees/sirus-dashboard-pagination
# → branch: sirus/dashboard-pagination off origin/main
# → lockfile: .locks/platform-dashboard-pagination.json

# For a task that spans MULTIPLE sub-repos:
bin/adam claim cross/llmclient-streaming
# → creates worktrees/sirus-llmclient-streaming (umbrella worktree with all submodules)
```

Then `cd` into the path it prints. The pre-commit hook will reject any commit on `main` from the canonical checkout — **the worktree is where you work**.

## 4. While working

- `git status`, `git add`, `git commit` as usual inside the worktree
- Push your branch when you have something to share: `git push -u origin HEAD`
- Open a PR on the sub-repo for review

If you accidentally edited `main` in the canonical checkout (you'll see a red rejection from pre-commit):

```bash
bin/adam rescue
# prints the recovery steps; usually:
#   git stash push -m 'rescue from main'
#   bin/adam claim <scope>/<task>
#   cd <new-worktree>
#   git stash pop
```

## 5. When the PR merges

```bash
cd /thearray/git/Adamaton                              # back to umbrella canonical
bin/adam release <scope>/<task>                        # cleans up worktree + lockfile
bin/adam bump <sub-repo>                               # advances umbrella's pin to new origin/main HEAD
git push origin main                                   # pushes the pin advance (only umbrella-main commits allowed via bump)
```

`bin/adam bump` sets `ADAM_BUMP=1` so the pre-commit hook allows the pin commit.

## 6. Daily rhythm

```bash
bin/adam pull                          # sync umbrella + all submodules to remote
bin/adam status                        # what claims are active across the fleet
bin/adam status --conflicts            # any path overlaps with other agents' work
```

## 7. Testing

```bash
bin/adam test                          # all sub-repos, skipping DB-deps
bin/adam test --scope=knowledge        # one sub-repo
```

## 8. Deploys (operator role)

```bash
bin/adam doctor                        # always first
bin/adam build pi5                     # cross-compile + tag images for pi5
bin/adam deploy pi5                    # rsync configs + ssh + docker compose up -d
bin/adam fleet status                  # what version each host is on
bin/adam fleet promote sha-abc123      # bump all MANIFEST.yaml files
bin/adam fleet pull all                # roll out the promoted tag
```

## Cheat sheet: the only things you'll do daily

| Goal | Command |
|---|---|
| Start work | `bin/adam claim <scope>/<task>` |
| End work | `bin/adam release <scope>/<task>` |
| Check fleet | `bin/adam status` |
| Sync | `bin/adam pull` |
| Bump pin after PR | `bin/adam bump <sub>` |
| Recover from main-edit mistake | `bin/adam rescue` |

Everything else (`doctor`, `build`, `test`, `clean`, `deploy`, `fleet`) is occasional.

## What this enforces

- **No agent ever commits to umbrella `main` directly** except via `bin/adam bump`.
- **Every agent's work lives on a feature branch** in a worktree, isolated from concurrent agents.
- **Lockfiles in `.locks/`** show who's working on what — other agents see your claim and don't overlap.

## Where to learn more

- [Architecture](ARCHITECTURE.md) — the 7-component DAG and HTTP contracts.
- [Worktree workflow](WORKTREE_WORKFLOW.md) — the claim/release lifecycle in depth.
- [Deploy](DEPLOY.md) — per-host bring-up + rollback.
- [CI/CD](CICD.md) — how images get built and rolled out across the fleet.
- [Where did it go?](WHERE_DID_IT_GO.md) — old `evo` path → new Adamaton path map (for archaeology).
