#!/usr/bin/env bash
# Workstation -> Pi sync for coding-agent memory files.
#
# The deepresearch frontend's Memory page is served by evo-api on the Pi;
# its filesystem scanner walks $HOME/.claude/projects, $HOME/.codex/memories,
# etc. inside the container. Those paths don't exist on the Pi by default,
# so the container sees them via bind mounts onto /home/sirus/agent-memory/
# (configured in ~/deepresearch/docker-compose.yml).
#
# This script syncs the workstation's source-of-truth memory files to that
# Pi staging dir. Designed to be re-runnable: --delete keeps the Pi side
# matching the workstation. Skips secrets + chat history + caches.
#
# Usage:
#   ./sync-agent-memory-to-pi.sh           # one-shot
#   ./sync-agent-memory-to-pi.sh --dry     # show what would change
#
# Cron suggestion (every 5 min):
#   */5 * * * * /thearray/git/evo/scripts/sync-agent-memory-to-pi.sh >/dev/null 2>&1

set -euo pipefail

PI_HOST="${PI_HOST:-pi5}"
PI_ROOT="${PI_AGENT_MEMORY:-/home/sirus/agent-memory}"

DRY=""
if [[ "${1:-}" == "--dry" || "${1:-}" == "-n" ]]; then
  DRY="-n"
fi

# Make sure the Pi-side tree exists. mkdir is cheap to re-run.
ssh "$PI_HOST" "mkdir -p '$PI_ROOT'/{claude/projects,codex/memories,gemini}"

# Claude Code: per-project memory dirs + global CLAUDE.md. Exclude the
# rest of ~/.claude (credentials, history, plugins, caches).
if [[ -d "$HOME/.claude/projects" ]]; then
  rsync -a --delete $DRY \
    "$HOME/.claude/projects/" "$PI_HOST:$PI_ROOT/claude/projects/"
fi
if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
  rsync -a $DRY \
    "$HOME/.claude/CLAUDE.md" "$PI_HOST:$PI_ROOT/claude/CLAUDE.md"
fi

# Codex: only ~/.codex/memories/ — everything else is auth / history / logs.
if [[ -d "$HOME/.codex/memories" ]]; then
  rsync -a --delete $DRY \
    "$HOME/.codex/memories/" "$PI_HOST:$PI_ROOT/codex/memories/"
fi

# Gemini: just the top-level GEMINI.md. Skip OAuth tokens + history.
if [[ -f "$HOME/.gemini/GEMINI.md" ]]; then
  rsync -a $DRY \
    "$HOME/.gemini/GEMINI.md" "$PI_HOST:$PI_ROOT/gemini/GEMINI.md"
fi

# OpenCode: ~/.config/opencode/memories/ if the user has any. The dir
# doesn't exist on this workstation today; the conditional means we
# don't error when it isn't there.
if [[ -d "$HOME/.config/opencode/memories" ]]; then
  rsync -a --delete $DRY \
    "$HOME/.config/opencode/memories/" \
    "$PI_HOST:$PI_ROOT/opencode/memories/"
fi

if [[ -z "$DRY" ]]; then
  echo "synced; counts on Pi:"
  ssh "$PI_HOST" "find $PI_ROOT -name '*.md' | wc -l"
fi
