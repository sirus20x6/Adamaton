#!/usr/bin/env bash
# Removes the sqlite files the pre-Pass-15 gogents stores wrote to
# disk. Safe to re-run — every step is conditional. Does NOT touch
# ccsaver's database (that store still uses sqlite as of Pass 15 and
# gogents reads it via internal/quota/ccsaver.go).
#
# What gets removed:
#   ~/.local/share/gogents/delegator/tasks.db{,-wal,-shm}
#   ~/.local/share/gogents/delegator/budget.db{,-wal,-shm}
#   ~/.local/share/gogents/delegator/contextmode.db{,-wal,-shm}
#   ${XDG_DATA_HOME}/gogents/delegator/* (above three, XDG variant)
#   /thearray/gogents/data/budget.db{,-wal,-shm}
#   /thearray/gogents/data/workflows.db{,-wal,-shm}
#
# Anything else under the data dirs (including ccsaver databases or
# operator-placed files) is left alone.
set -euo pipefail

removed=0

remove_triplet() {
    local base="$1"
    for suffix in "" "-wal" "-shm"; do
        local path="${base}${suffix}"
        if [[ -f "$path" ]]; then
            rm -f -- "$path"
            echo "  removed $path"
            removed=$((removed + 1))
        fi
    done
}

candidate_roots=()
if [[ -n "${XDG_DATA_HOME-}" ]]; then
    candidate_roots+=("${XDG_DATA_HOME}/gogents/delegator")
fi
if [[ -n "${HOME-}" ]]; then
    candidate_roots+=("${HOME}/.local/share/gogents/delegator")
fi
candidate_roots+=("/thearray/gogents/data")

for root in "${candidate_roots[@]}"; do
    [[ -d "$root" ]] || continue
    echo "scanning $root"
    for name in tasks.db budget.db contextmode.db workflows.db; do
        remove_triplet "${root}/${name}"
    done
done

echo "done. removed $removed file(s)."
