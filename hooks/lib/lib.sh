#!/usr/bin/env bash
# Shared helpers for Adamaton hooks (pre-commit, pre-push, commit-msg).
# Sourced into each hook via: . "$(git rev-parse --show-toplevel)/../hooks/lib/lib.sh"
# (or, for submodules, walks up until it finds the umbrella).

# Walk up from $PWD until a directory contains both `.gitmodules` AND a
# `hooks/` subdir — that's the umbrella. Used by the hooks to find the
# canonical lockfile dir + hook templates regardless of which submodule
# checkout invoked them.
adam_find_umbrella() {
    local d="${1:-$PWD}"
    while [[ "$d" != "/" ]]; do
        if [[ -f "$d/.gitmodules" && -d "$d/hooks" && -d "$d/.locks" ]]; then
            echo "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done
    # Worktrees-of-submodules live under <umbrella>/<sub>/<sub>-worktrees/...
    # so a second pass looking for any ancestor with the umbrella markers.
    d="${1:-$PWD}"
    while [[ "$d" != "/" ]]; do
        for cand in "$d/.." "$d/../.." "$d/../../.." "$d/../../../.."; do
            if [[ -f "$cand/.gitmodules" && -d "$cand/hooks" && -d "$cand/.locks" ]]; then
                (cd "$cand" && pwd)
                return 0
            fi
        done
        d="$(dirname "$d")"
    done
    return 1
}

adam_current_agent() {
    if [[ -n "${ADAM_AGENT:-}" ]]; then
        echo "$ADAM_AGENT"
    else
        git config user.name 2>/dev/null || whoami
    fi
}

# Print the agent name owning a given branch (looked up across all
# lockfiles). Empty if unclaimed.
adam_lock_owner_for_branch() {
    local branch="$1" umbrella
    umbrella="$(adam_find_umbrella)" || return 0
    local f
    for f in "$umbrella"/.locks/*.json; do
        [[ -e "$f" ]] || continue
        local lock_branch lock_agent
        lock_branch="$(grep -E '"branch"' "$f" | sed -E 's/.*"branch" *: *"([^"]+)".*/\1/')"
        if [[ "$lock_branch" == "$branch" ]]; then
            lock_agent="$(grep -E '"agent"' "$f" | sed -E 's/.*"agent" *: *"([^"]+)".*/\1/')"
            echo "$lock_agent"
            return 0
        fi
    done
}

adam_red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
adam_yellow() { printf "\033[33m%s\033[0m\n" "$*" >&2; }
adam_green()  { printf "\033[32m%s\033[0m\n" "$*" >&2; }
