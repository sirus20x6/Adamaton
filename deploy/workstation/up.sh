#!/usr/bin/env bash
# deploy/workstation/up.sh — bring up local dev backing services.
#
# Runs `docker compose up -d` in this directory. No ssh / rsync -- the
# workstation IS the umbrella checkout, so we operate in place.

set -euo pipefail

UMBRELLA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THIS_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$UMBRELLA_ROOT"
IMAGE_TAG="$(git rev-parse --short HEAD)"

cd "$THIS_DIR"

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "==> seeded $(pwd)/.env from .env.example (edit before re-running if you want non-default creds)"
fi

echo "==> bringing up workstation dev services (postgres + temporal-dev)"
IMAGE_TAG="${IMAGE_TAG}" docker compose up -d
IMAGE_TAG="${IMAGE_TAG}" docker compose ps

cat <<EOF

Done. Workstation backing services are up.

  Postgres:    localhost:\${POSTGRES_HOST_PORT:-5433}   (user: postgres / db: postgres)
  Temporal:    localhost:7233 (gRPC)  /  http://localhost:8233 (Web UI)

Run individual Go workers in their own shells from each sub-repo, e.g.:

    cd platform && go run ./cmd/evo-api
    cd knowledge && go run ./cmd/skills-rae-worker
    cd evolve && go run ./cmd/evo-worker

EOF
