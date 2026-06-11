# Cross-module Go: replace directives, go.work, and worktree gotchas

Adamaton splits its Go code across 16+ modules in 7 sub-repos. This document
describes how local resolution works, where it breaks, and how to fix it.

## How local resolution works

The umbrella's `go.work` lists every module:

```
use (
    ./core
    ./deepresearch/nano-research
    ./delegator/delegator
    ./delegator/mcp
    ./evolve/dataset-manager
    ./evolve/evolve
    ./evolve/workflow-builder
    ./knowledge/r2g
    ./knowledge/reindex
    ./knowledge/skills
    ./knowledge/skills-rae
    ./platform/dashboard
    ./platform/dispatch
    ./platform/plugin-host
    ./platform/temporal
    ./platform/worker
)
```

When you run `go build ./...` from the umbrella root (or from any path where
`go` can find `go.work` by walking up), the workspace overrides module paths so
e.g. `github.com/sirus20x6/adamaton-core` resolves to `./core` on disk instead
of being fetched from the network.

## Sibling modules within a sub-repo

When one module in a sub-repo imports another module in the *same* sub-repo,
the workspace covers it **for umbrella-based builds**, but per-module CI builds
(from the sub-repo root without the umbrella's `go.work`) will try to fetch the
sibling from the network and fail.

Fix: add explicit `replace` + `require` in each importing module's `go.mod`:

```go
// in deepresearch/nano-research/go.mod
require github.com/sirus20x6/adamaton-deepresearch/searchcore v0.0.0-00010101000000-000000000000
replace github.com/sirus20x6/adamaton-deepresearch/searchcore => ../searchcore
```

Verify by building without the workspace:

```bash
GOWORK=off go build ./...   # from the sub-repo dir
```

If that passes, the sub-repo is self-contained and CI won't break.

## Cross-sub-repo replace (two levels up)

A module in one sub-repo that imports a module from another sub-repo uses a
`replace` that goes up two levels to the umbrella and then down:

```go
// in platform/dashboard/go.mod
replace github.com/sirus20x6/adamaton-core => ../../core
```

That `../../core` path is written for the canonical checkout depth
(`Adamaton/platform/dashboard/` -> `../../` = `Adamaton/`). It works fine from
the canonical checkout. It breaks inside a `bin/adam claim` worktree.

## Worktree breakage

When you run `bin/adam claim platform/dashboard-foo`, the worktree is created
at:

```
Adamaton/platform/platform-worktrees/sirus20x6-dashboard-foo/
```

That is one directory *deeper* than `Adamaton/platform/dashboard/`. The
`replace ../../core` in `go.mod` now resolves to:

```
platform/platform-worktrees/core   ← does not exist
```

`go mod tidy` and `go build` fail with:

```
replacement directory ../../core does not exist
```

**Fix:** create a symlink at the right depth so the relative path resolves:

```bash
ln -sf /thearray/git/Adamaton/core \
       /thearray/git/Adamaton/platform/platform-worktrees/core
```

Or drop a dev-only `go.work` at the worktree root that uses absolute paths. Do
**not** commit the symlink or `go.work` — stage files explicitly and never use
`git add .`.

For a cross-scope worktree (`bin/adam claim cross/<task>`), the worktree is at
`Adamaton/worktrees/sirus20x6-<task>/` and contains all submodules at their
pinned SHAs. Because the relative paths are the same depth as the canonical
checkout, `replace ../../core` continues to resolve correctly inside cross
worktrees.

## delegator-mcp build requires a cross worktree

`delegator/mcp/go.mod` imports modules from three different sub-repos:

```go
replace github.com/sirus20x6/adamaton-core           => ../../core
replace github.com/sirus20x6/adamaton-platform/temporal => ../../platform/temporal
replace github.com/sirus20x6/adamaton-delegator/delegator => ../delegator
```

If you build from a single-component worktree (`delegator/delegator-worktrees/`),
the `../../core` path goes up from `delegator/mcp/` to `delegator/` and then
one more level — reaching the sub-repo root, not the umbrella. `core` doesn't
exist there.

**Canonical rebuild recipe:**

```bash
# From a cross worktree or the canonical checkout
cd /thearray/git/Adamaton   # or your cross-worktree root
cd delegator/mcp
GOWORK=off go build -o /thearray/git/evo/bin/delegator-mcp ./cmd/delegator-mcp
```

`GOWORK=off` with the `replace` directives in `go.mod` means the build uses
only relative paths — it works from the umbrella root because `../../core`
resolves correctly at that depth.

After rebuilding, reconnect the MCP server in Claude Code (restart the session
or use `/mcp restart`) — a running session keeps the old binary in memory.

## ztok: symlink vs COPY in Docker

`knowledge/r2g` and (transitively) `platform/plugin-host` carry:

```go
replace github.com/sirus20x6/ztok-go => ../../ztok/bindings/go
```

`ztok` is **not** a git submodule — it lives at `/thearray/git/ztok` as a
standalone repo. The canonical Adamaton checkout has no `./ztok` directory.

Local builds need a temporary symlink:

```bash
cd /thearray/git/Adamaton
ln -s /thearray/git/ztok ztok   # do NOT commit
```

Docker `COPY` in the r2g and dashboard Dockerfiles does `COPY ztok ztok`. This
requires a **real directory**, not a symlink, in the build context. When
running `docker buildx build` from the umbrella root with a symlink:

- `docker buildx build --follow-symlinks` resolves the symlink if you pass the
  flag, but the default behavior varies by builder version
- The safest approach for CI: ensure `/thearray/git/ztok` is checked out at
  the umbrella root as a real directory when building images that include r2g
  or plugin-host

See `bin/adam ship r2g` for how the production build handles this (context=`.`
from umbrella root; the Zig `ztoklib` stage compiles from source).

## GOWORK=off: when and why

Use `GOWORK=off` to simulate per-module CI (the sub-repo builds that don't see
the umbrella workspace):

```bash
GOWORK=off go build ./...   # must pass for the sub-repo to be self-contained
GOWORK=off go test  ./...
```

Do **not** use `GOWORK=off` from the umbrella root for normal development — you
lose cross-module resolution and every `replace github.com/...adamaton-core`
must be present in each module's `go.mod`.

## Summary of rules

| Situation | Fix |
|-----------|-----|
| Add sibling-module import within a sub-repo | Add `require` + `replace ../sibling` in `go.mod`; verify with `GOWORK=off go build` |
| Build/test in a single-component claim worktree | Add a symlink so `../../<repo>` resolves |
| Build delegator-mcp | Use a cross worktree; run `GOWORK=off go build` from `delegator/mcp/` |
| Local ztok for r2g/plugin-host builds | `ln -s /thearray/git/ztok ztok` at umbrella root; export `PKG_CONFIG_PATH` + `LD_LIBRARY_PATH` |
| Docker COPY ztok | Real directory required in build context (symlinks may not follow) |
