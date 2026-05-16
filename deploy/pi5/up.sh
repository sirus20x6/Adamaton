#!/usr/bin/env bash
# deploy/pi5/up.sh — bring up the pi5 main stack.
#
# Phase 4 (deploy populate) will fill this in. For now it's a stub that
# documents the steps the script will perform.
#
# Steps the populated version runs:
#   1. Read umbrella submodule pins.
#   2. Cross-compile arm64 binaries for: knowledge.skills-rae-worker,
#      knowledge.reindex-worker, knowledge.r2g, deepresearch.nano-research,
#      deepresearch.nano-research-worker, platform.dashboard,
#      platform.plugin-host, platform.dispatch-worker, platform.temporal-worker.
#   3. Build OCI images tagged `adamomaton-<component>:<umbrella-sha-short>`.
#   4. rsync image tars to pi5 (wifi-safe).
#   5. rsync deploy/pi5/{docker-compose.yml,Caddyfile,.env} to pi5:~/Adamomaton-deploy/.
#   6. ssh pi5 'cd ~/Adamomaton-deploy && docker compose up -d && docker compose ps'.

set -euo pipefail
echo "deploy/pi5/up.sh: not implemented yet (Phase 4)" >&2
exit 1
