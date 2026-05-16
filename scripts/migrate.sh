#!/usr/bin/env bash
# scripts/migrate.sh — one-shot evo → Adamomaton bootstrap.
#
# Phase 2 will populate this. The populated script:
#
#   1. For each of the 7 sub-repos, in DAG order (core → leaves → platform):
#      a. Copy the relevant paths from /thearray/git/evo/ into the sub-repo
#         working tree.
#      b. Rewrite import paths via `gofmt -r`:
#           github.com/thearray/evo/X -> github.com/sirus20x6/adamomaton-<dest>/X
#         per the mapping in docs/MIGRATION.md.
#      c. Rewrite each go.mod's module path.
#      d. Drop `replace github.com/thearray/evo/... => ../...` directives.
#      e. Add `require github.com/sirus20x6/adamomaton-core` pins where needed.
#      f. git add -A && git commit -m 'Initial commit: Adamomaton import from evo@<sha>'
#      g. git tag v0.1.0
#      h. git push --tags
#   2. From the umbrella, write go.work listing every Go module path.
#   3. `bin/adam bump` each sub-repo to its newly-pushed v0.1.0 tag.
#   4. `go build ./...` from the umbrella exercises every cross-component dep.
#
# Idempotent: re-running on top of an already-migrated tree skips files
# whose target already exists; --reset wipes sub-repos first.

set -euo pipefail
echo "scripts/migrate.sh: not implemented yet (Phase 2)" >&2
exit 1
