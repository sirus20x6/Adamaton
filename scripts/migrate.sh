#!/usr/bin/env bash
# scripts/migrate.sh — one-shot evo + deepresearch/platform -> Adamaton bootstrap.
#
# Run from the umbrella root: ./scripts/migrate.sh [component]
#   With no argument: runs for all components in DAG order.
#   With a component name: runs just that one (e.g. ./scripts/migrate.sh knowledge).
#
# What it does per component:
#   1. rsync the relevant evo paths into the sub-repo's working tree
#      (excludes .git, leaves the sub-repo's existing README intact).
#   2. Rewrite every .go file's imports:
#        github.com/thearray/evo/<X> -> github.com/sirus20x6/adamaton-<dest>/<X>
#      using one sed pass per (old-prefix, new-prefix) pair.
#   3. Rewrite each affected go.mod's module path + drop replace
#      directives that pointed at relative evo paths.
#   4. The umbrella's go.work `use` directives (added after this script)
#      resolve all cross-component imports at build time.
#
# After this script: the umbrella's go.work needs to be populated
# (see scripts/populate_go_work.sh, or do it by hand from the printed
# list), then `go build ./...` from the umbrella exercises the
# cross-component graph.
#
# Idempotent: rsync overlays, sed rewrites are idempotent.

set -euo pipefail

ADAM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVO="${EVO_ROOT:-/thearray/git/evo}"
DR_PLATFORM="${DR_PLATFORM:-/thearray/git/deepresearch/platform}"

# ---- import rewrite map -------------------------------------------------
# Each line: <old-prefix> <new-prefix>
# Applied via sed to every .go file in every sub-repo.

REWRITES=(
    "github.com/thearray/evo/core github.com/sirus20x6/adamaton-core"
    "github.com/thearray/evo/skills-rae github.com/sirus20x6/adamaton-knowledge/skills-rae"
    "github.com/thearray/evo/skills github.com/sirus20x6/adamaton-knowledge/skills"
    "github.com/thearray/evo/reindex github.com/sirus20x6/adamaton-knowledge/reindex"
    "github.com/thearray/evo/r2g github.com/sirus20x6/adamaton-knowledge/r2g"
    "github.com/thearray/evo/nano-research github.com/sirus20x6/adamaton-deepresearch/nano-research"
    "github.com/thearray/evo/dashboard github.com/sirus20x6/adamaton-platform/dashboard"
    "github.com/thearray/evo/plugin-host github.com/sirus20x6/adamaton-platform/plugin-host"
    "github.com/thearray/evo/dispatch github.com/sirus20x6/adamaton-platform/dispatch"
    "github.com/thearray/evo/temporal github.com/sirus20x6/adamaton-platform/temporal"
    "github.com/thearray/evo/delegator github.com/sirus20x6/adamaton-delegator/delegator"
    "github.com/thearray/evo/mcp github.com/sirus20x6/adamaton-delegator/mcp"
    "github.com/thearray/evo/workflow-builder github.com/sirus20x6/adamaton-evolve/workflow-builder"
    "github.com/thearray/evo/evolve github.com/sirus20x6/adamaton-evolve/evolve"
)

apply_rewrites_in() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    local pair old new
    for pair in "${REWRITES[@]}"; do
        old="${pair%% *}"
        new="${pair#* }"
        # Escape slashes for sed delimiters.
        find "$dir" -name '*.go' -exec sed -i "s|${old}|${new}|g" {} +
    done
}

# Canonical replace block appended to every depth-2 go.mod so cross-
# component imports resolve via relative paths inside the umbrella
# checkout. Go silently ignores replaces whose target isn't required,
# so listing every adamaton-* module in every depth-2 go.mod is safe.
# The umbrella's go.work is consulted first; this replace block is the
# fallback for sub-repo standalone builds (broken until sibling sub-repos
# are checked out at expected paths).
REPLACE_BLOCK='
replace (
	github.com/sirus20x6/adamaton-core => ../../core
	github.com/sirus20x6/adamaton-knowledge/skills => ../../knowledge/skills
	github.com/sirus20x6/adamaton-knowledge/skills-rae => ../../knowledge/skills-rae
	github.com/sirus20x6/adamaton-knowledge/reindex => ../../knowledge/reindex
	github.com/sirus20x6/adamaton-knowledge/r2g => ../../knowledge/r2g
	github.com/sirus20x6/adamaton-deepresearch/nano-research => ../../deepresearch/nano-research
	github.com/sirus20x6/adamaton-delegator/delegator => ../../delegator/delegator
	github.com/sirus20x6/adamaton-delegator/mcp => ../../delegator/mcp
	github.com/sirus20x6/adamaton-evolve/evolve => ../../evolve/evolve
	github.com/sirus20x6/adamaton-evolve/workflow-builder => ../../evolve/workflow-builder
	github.com/sirus20x6/adamaton-platform/dashboard => ../../platform/dashboard
	github.com/sirus20x6/adamaton-platform/plugin-host => ../../platform/plugin-host
	github.com/sirus20x6/adamaton-platform/dispatch => ../../platform/dispatch
	github.com/sirus20x6/adamaton-platform/temporal => ../../platform/temporal
)'

# Rewrite a single go.mod: module path, drop relative-path replaces.
rewrite_gomod() {
    local gomod="$1" new_module="$2"
    [[ -f "$gomod" ]] || return 0
    # 1. Module path.
    sed -i "1s|^module .*|module ${new_module}|" "$gomod"
    # 2. Apply same import rewrites to the require lines.
    local pair old new
    for pair in "${REWRITES[@]}"; do
        old="${pair%% *}"
        new="${pair#* }"
        sed -i "s|${old}|${new}|g" "$gomod"
    done
    # 3. Drop `replace github.com/sirus20x6/adamaton-* => ../...` lines,
    # both single-line and inside `replace ( ... )` blocks.
    # The umbrella's go.work resolves these via the workspace; standalone
    # checkouts get added back via per-sub-repo CI overrides (Phase 5).
    sed -i '/^replace github\.com\/sirus20x6\/adamaton-/d' "$gomod"
    sed -i '/^replace ($/,/^)$/{/sirus20x6\/adamaton-/d}' "$gomod"
    # 4. Drop empty replace blocks (e.g. "replace (" immediately followed by ")").
    sed -i '/^replace ($/{N;/^replace (\n)$/d}' "$gomod"
    # 5. Depth-2 go.mods (under a sub-repo's nested module dir) get the
    # canonical replace block for cross-component resolution. Skip for
    # core/go.mod (depth 1; it has no internal adamaton-* deps).
    local depth
    depth=$(echo "$gomod" | tr '/' '\n' | wc -l)
    if [[ "$depth" -ge 4 ]]; then  # /thearray/git/Adamaton/X/Y/go.mod -> 6 components; we want >=4 from sub-repo root
        echo "$REPLACE_BLOCK" >> "$gomod"
    fi
}

evo_sha() { git -C "$EVO" rev-parse HEAD; }

# ---- per-component migrations -------------------------------------------

migrate_core() {
    echo "==> core"
    rsync -a --delete --exclude=.git --exclude=README.md \
        "$EVO/core/" "$ADAM_ROOT/core/"
    apply_rewrites_in "$ADAM_ROOT/core"
    rewrite_gomod "$ADAM_ROOT/core/go.mod" "github.com/sirus20x6/adamaton-core"
}

migrate_evolve() {
    echo "==> evolve"
    rsync -a --delete --exclude=.git --exclude=README.md \
        "$EVO/evolve/" "$ADAM_ROOT/evolve/evolve/"
    rsync -a --delete --exclude=.git \
        "$EVO/workflow-builder/" "$ADAM_ROOT/evolve/workflow-builder/"
    apply_rewrites_in "$ADAM_ROOT/evolve"
    rewrite_gomod "$ADAM_ROOT/evolve/evolve/go.mod" \
        "github.com/sirus20x6/adamaton-evolve/evolve"
    rewrite_gomod "$ADAM_ROOT/evolve/workflow-builder/go.mod" \
        "github.com/sirus20x6/adamaton-evolve/workflow-builder"
}

migrate_knowledge() {
    echo "==> knowledge"
    for sub in skills skills-rae reindex r2g; do
        rsync -a --delete --exclude=.git \
            "$EVO/$sub/" "$ADAM_ROOT/knowledge/$sub/"
    done
    # Zig sidecars used by reindex (arxiv-skip) and r2g (latex2text).
    mkdir -p "$ADAM_ROOT/knowledge/tools"
    for tool in arxiv-skip latex2text; do
        rsync -a --delete --exclude=.git --exclude=.zig-cache --exclude=zig-out \
            "$EVO/tools/$tool/" "$ADAM_ROOT/knowledge/tools/$tool/"
    done
    apply_rewrites_in "$ADAM_ROOT/knowledge"
    rewrite_gomod "$ADAM_ROOT/knowledge/skills/go.mod" \
        "github.com/sirus20x6/adamaton-knowledge/skills"
    rewrite_gomod "$ADAM_ROOT/knowledge/skills-rae/go.mod" \
        "github.com/sirus20x6/adamaton-knowledge/skills-rae"
    rewrite_gomod "$ADAM_ROOT/knowledge/reindex/go.mod" \
        "github.com/sirus20x6/adamaton-knowledge/reindex"
    rewrite_gomod "$ADAM_ROOT/knowledge/r2g/go.mod" \
        "github.com/sirus20x6/adamaton-knowledge/r2g"
}

migrate_deepresearch() {
    echo "==> deepresearch"
    rsync -a --delete --exclude=.git --exclude=README.md \
        "$EVO/nano-research/" "$ADAM_ROOT/deepresearch/nano-research/"
    apply_rewrites_in "$ADAM_ROOT/deepresearch"
    rewrite_gomod "$ADAM_ROOT/deepresearch/nano-research/go.mod" \
        "github.com/sirus20x6/adamaton-deepresearch/nano-research"
}

migrate_delegator() {
    echo "==> delegator"
    for sub in delegator mcp; do
        rsync -a --delete --exclude=.git \
            "$EVO/$sub/" "$ADAM_ROOT/delegator/$sub/"
    done
    apply_rewrites_in "$ADAM_ROOT/delegator"
    rewrite_gomod "$ADAM_ROOT/delegator/delegator/go.mod" \
        "github.com/sirus20x6/adamaton-delegator/delegator"
    rewrite_gomod "$ADAM_ROOT/delegator/mcp/go.mod" \
        "github.com/sirus20x6/adamaton-delegator/mcp"
}

migrate_platform() {
    echo "==> platform"
    for sub in dashboard plugin-host dispatch temporal; do
        rsync -a --delete --exclude=.git \
            "$EVO/$sub/" "$ADAM_ROOT/platform/$sub/"
    done
    # Python plugin payloads from the deepresearch SPA repo.
    if [[ -d "$DR_PLATFORM/plugins" ]]; then
        rsync -a --delete --exclude=.git --exclude=__pycache__ --exclude='*.pyc' \
            "$DR_PLATFORM/plugins/" "$ADAM_ROOT/platform/plugin-host-plugins/"
    fi
    apply_rewrites_in "$ADAM_ROOT/platform"
    rewrite_gomod "$ADAM_ROOT/platform/dashboard/go.mod" \
        "github.com/sirus20x6/adamaton-platform/dashboard"
    rewrite_gomod "$ADAM_ROOT/platform/plugin-host/go.mod" \
        "github.com/sirus20x6/adamaton-platform/plugin-host"
    rewrite_gomod "$ADAM_ROOT/platform/dispatch/go.mod" \
        "github.com/sirus20x6/adamaton-platform/dispatch"
    rewrite_gomod "$ADAM_ROOT/platform/temporal/go.mod" \
        "github.com/sirus20x6/adamaton-platform/temporal"
}

migrate_frontend() {
    echo "==> frontend"
    # No go.mod here — pnpm workspace at the root of the sub-repo.
    rsync -a --delete --exclude=.git --exclude=node_modules --exclude=dist \
        --exclude=README.md \
        "$DR_PLATFORM/frontend/" "$ADAM_ROOT/frontend/"
}

# ---- dispatch -----------------------------------------------------------

ORDER=(core evolve knowledge delegator deepresearch platform frontend)

if [[ $# -eq 0 ]]; then
    for c in "${ORDER[@]}"; do
        "migrate_$c"
    done
else
    for c in "$@"; do
        "migrate_$c"
    done
fi

echo
echo "evo HEAD at migration time: $(evo_sha)"
echo "Don't forget: populate $ADAM_ROOT/go.work with `use` directives for every Go module."
