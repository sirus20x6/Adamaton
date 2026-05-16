#!/usr/bin/env bash
# deploy/pi5/up.sh — bring up the pi5 main Adamaton stack.
#
# Mirrors the rsync-based deploy pattern from
# /thearray/git/evo/nano-research/deploy/pi-replica/deploy.sh — wifi-safe
# (rsync resumes partial transfers), idempotent (re-run to ship newer SHAs).
#
# Image build/push is intentionally OUT OF SCOPE for this iteration: a future
# pass moves the `make pi-<component>` cross-compile + `docker save | rsync`
# pipeline from /thearray/git/evo/Makefile into the umbrella as
# `bin/adam build pi5`. For now this script just ships the compose/Caddyfile/
# .env and assumes the images named `adamaton-<component>:$IMAGE_TAG`
# already exist on the Pi (loaded manually via the legacy evo Makefile
# targets — e.g. `make pi-skills-rae` then `docker save | ssh pi5 docker load`,
# then `docker tag evo-skills-rae:dev adamaton-skills-rae:$IMAGE_TAG`).

set -euo pipefail

HOST="${PI5_SSH_ALIAS:-pi5}"
UMBRELLA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THIS_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$UMBRELLA_ROOT"
IMAGE_TAG="$(git rev-parse --short HEAD)"
echo "==> deploying pi5 stack at image tag ${IMAGE_TAG}"

echo "==> [1/4] verify ${HOST} reachable + has docker"
REMOTE_HOME=$(ssh -o ConnectTimeout=8 "$HOST" 'echo $HOME' | tr -d '\r')
REMOTE_DIR="${REMOTE_DIR:-$REMOTE_HOME/Adamaton-deploy}"
ssh "$HOST" 'docker --version && docker compose version >/dev/null && uname -m' >/dev/null

echo "==> [2/4] rsync deploy/pi5/ -> ${HOST}:${REMOTE_DIR}/"
ssh "$HOST" "mkdir -p '${REMOTE_DIR}'"
# Note: --exclude=.env so the Pi keeps its own secrets across deploys;
# operator copies .env.example -> .env once during first bring-up.
rsync -avP --partial \
    --exclude=.env \
    --exclude=up.sh \
    "${THIS_DIR}/" "${HOST}:${REMOTE_DIR}/"

# Refuse to start without an .env on the remote -- easier to spot than a
# silent fallback to defaults in mid-flight.
if ! ssh "$HOST" "test -f '${REMOTE_DIR}/.env'"; then
    cat >&2 <<EOF
==> ERROR: ${HOST}:${REMOTE_DIR}/.env is missing.
    First-time setup: ssh ${HOST}; cp Adamaton-deploy/.env.example Adamaton-deploy/.env
    then edit secrets (EVO_API_TOKEN, API keys) and re-run this script.
EOF
    exit 1
fi

echo "==> [3/4] (placeholder) image build/push"
# Future iteration: invoke `bin/adam build pi5` here, which will run the
# cross-compile + docker save | rsync ... | docker load round-trip for each
# adamaton-<component>:${IMAGE_TAG} image. Today the operator builds via
# the legacy /thearray/git/evo/Makefile `pi-*` targets and re-tags on the Pi.
echo "    skipped -- images must already exist on ${HOST} as adamaton-<component>:${IMAGE_TAG}"

echo "==> [4/4] docker compose up -d on ${HOST}"
ssh "$HOST" "cd '${REMOTE_DIR}' && IMAGE_TAG='${IMAGE_TAG}' docker compose up -d && IMAGE_TAG='${IMAGE_TAG}' docker compose ps"

echo
echo "Done. Stack now running at ${IMAGE_TAG} on ${HOST}."
