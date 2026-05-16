# Worktree workflow

## Two modes

### Single-component (default)

Most tasks touch one sub-repo. The worktree is a worktree of that sub-repo, sibling to the canonical checkout.

```bash
bin/adam claim platform/dashboard-pagination
# creates: platform/platform-worktrees/sirus-dashboard-pagination
# branch:  sirus/dashboard-pagination off origin/main
# lockfile: .locks/platform-dashboard-pagination.json

cd platform/platform-worktrees/sirus-dashboard-pagination
# ... edit, commit, push your branch ...

bin/adam release platform/dashboard-pagination
# removes the worktree, drops the lockfile
# (--keep-branch leaves the branch unpushed; default deletes if merged)
```

### Cross-component (umbrella worktree)

When a change spans multiple sub-repos (e.g., add a field to core, propagate to knowledge + platform), work on a worktree of the umbrella itself. Submodules initialize inside the worktree at the umbrella's pinned SHAs.

```bash
bin/adam claim cross/llmclient-streaming
# creates: worktrees/sirus-llmclient-streaming
# branch:  sirus/llmclient-streaming
# all submodules: cloned + checked out at pinned SHAs

cd worktrees/sirus-llmclient-streaming
# edit across core/, knowledge/, platform/
# inside each submodule: git checkout -b sirus/llmclient-streaming
# commit + push from each submodule
# from umbrella: git add core knowledge platform && git commit -m "bump for streaming"

bin/adam release cross/llmclient-streaming
```

## Lockfiles

`.locks/<scope>-<task>.json` describes one active claim:

```json
{
  "agent":     "sirus",
  "scope":     "platform",
  "task":      "dashboard-pagination",
  "branch":    "sirus/dashboard-pagination",
  "worktree":  "/thearray/git/Adamomaton/platform/platform-worktrees/sirus-dashboard-pagination",
  "paths":     ["platform/dashboard/apiserver/**"],
  "started_at":"2026-05-16T13:42:00Z"
}
```

Lockfiles are tracked in git so concurrent agents see each other's claims. Conflicts are soft:

- **`bin/adam status`** lists every active claim.
- **`bin/adam claim` aborts** if a lockfile for `<scope>/<task>` already exists. Pick a different task name or release the existing claim.
- **`pre-push` hook warns** when pushing a branch claimed by a different agent. Sleeps 5s; Ctrl-C to abort.
- **Path overlap detection** (`adam status --conflicts`) is a Phase 5 follow-up; currently TODO.

## Rules of engagement

- **Always claim before editing.** The lockfile is the only way other agents know what you're working on.
- **One scope/task pair per claim.** If a task grows into needing a second sub-repo's edits, release and re-claim as `cross/`.
- **Push frequently.** Other agents see your work via the sub-repo's `origin/<your-branch>`; pushing keeps that current.
- **Release when done.** Stale lockfiles confuse later agents into thinking work is still in progress.

## Going around the rules

Trust-based. If the lockfile is wrong (agent died, manual cleanup needed):

```bash
rm .locks/<scope>-<task>.json
git commit -am "manual: clear stale lock for <scope>/<task>"
```

The hooks let you bypass with `--force` flags; use sparingly.

## After your PR merges

```bash
bin/adam bump platform
# advances the umbrella's platform pin to origin/main HEAD
# creates one commit on the umbrella

git push           # update the pin remotely
```

Other agents `bin/adam pull` to see the new pin.
