#!/usr/bin/env bash
# deploy/pi5-speaker/up.sh — bring up the nano-research replica node.
#
# Mirrors /thearray/git/evo/nano-research/deploy/pi-replica/deploy.sh. The
# image build/push step is a placeholder (see deploy/pi5/up.sh for rationale);
# for now the operator builds the arm64 images on the workstation with
# `make pi-nano-research-worker pi-nano-research`, ships them to the replica
# out-of-band, and re-tags them as adamaton-nano-research:$IMAGE_TAG.

set -euo pipefail

HOST="${PI5_SPEAKER_SSH_ALIAS:-pi5-speaker}"
PI1_ALIAS="${PI1_SSH_ALIAS:-pi5}"
UMBRELLA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THIS_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$UMBRELLA_ROOT"
IMAGE_TAG="$(git rev-parse --short HEAD)"
echo "==> deploying pi5-speaker replica at image tag ${IMAGE_TAG}"

echo "==> [1/4] verify ${HOST} reachable + has docker"
REMOTE_HOME=$(ssh -o ConnectTimeout=8 "$HOST" 'echo $HOME' | tr -d '\r')
REMOTE_DIR="${REMOTE_DIR:-$REMOTE_HOME/Adamaton-deploy}"
ssh "$HOST" 'docker --version && docker compose version >/dev/null && uname -m' >/dev/null

echo "==> [2/4] rsync deploy/pi5-speaker/ -> ${HOST}:${REMOTE_DIR}/"
ssh "$HOST" "mkdir -p '${REMOTE_DIR}'"
rsync -avP --partial \
    --exclude=.env \
    --exclude=up.sh \
    "${THIS_DIR}/" "${HOST}:${REMOTE_DIR}/"

# Seed .env with Pi #1's eth0 IP the first time only.
if ! ssh "$HOST" "test -f '${REMOTE_DIR}/.env'"; then
    PI1_IP=$(ssh "$PI1_ALIAS" "ip -4 addr show eth0 | awk '/inet / {sub(/\/.*/,\"\",\$2); print \$2; exit}'" | tr -d '\r')
    echo "==> seeding ${HOST}:${REMOTE_DIR}/.env with PI1_HOST=${PI1_IP}"
    ssh "$HOST" "sed 's|^PI1_HOST=.*|PI1_HOST=${PI1_IP}|' '${REMOTE_DIR}/.env.example' > '${REMOTE_DIR}/.env'"
fi

echo "==> [3/4] (placeholder) image build/push"
echo "    skipped -- expect adamaton-nano-research:${IMAGE_TAG} +"
echo "             adamaton-nano-figure-renderer:${IMAGE_TAG} on ${HOST}"

echo "==> [4/4] docker compose up -d on ${HOST}"
ssh "$HOST" "cd '${REMOTE_DIR}' && IMAGE_TAG='${IMAGE_TAG}' docker compose up -d && IMAGE_TAG='${IMAGE_TAG}' docker compose ps"

# Verify both Temporal workers are polling the nano-research queue.
sleep 5
echo "==> verifying nano-research task queue has 2 pollers"
ssh "$PI1_ALIAS" \
    'docker exec adamaton-deploy-temporal-1 temporal --address temporal:7233 \
        task-queue describe --task-queue nano-research 2>&1 | tail -20' || \
    echo "    (couldn't query Temporal -- check container name; harmless if first deploy)"

echo
echo "Done. Replica running at ${IMAGE_TAG} on ${HOST}."
