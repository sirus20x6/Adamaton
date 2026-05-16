#!/usr/bin/env bash
# deploy/blackwell/up.sh — bring up the GPU node (vLLM + evo-kernel worker).
#
# Same rsync + ssh pattern as deploy/pi5/up.sh. Image build/push is a
# placeholder for now; the adamomaton-evo-worker:$IMAGE_TAG amd64 image is
# expected to already exist on blackwell (built locally with `go build` and
# wrapped in an OCI image, or pulled from a registry once the build pipeline
# moves into the umbrella).

set -euo pipefail

HOST="${BLACKWELL_SSH_ALIAS:-blackwell}"
UMBRELLA_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
THIS_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$UMBRELLA_ROOT"
IMAGE_TAG="$(git rev-parse --short HEAD)"
echo "==> deploying blackwell stack at image tag ${IMAGE_TAG}"

echo "==> [1/4] verify ${HOST} reachable + has docker + nvidia runtime"
REMOTE_HOME=$(ssh -o ConnectTimeout=8 "$HOST" 'echo $HOME' | tr -d '\r')
REMOTE_DIR="${REMOTE_DIR:-$REMOTE_HOME/Adamomaton-deploy}"
ssh "$HOST" 'docker --version && docker compose version >/dev/null && docker info 2>/dev/null | grep -q "Runtimes:.*nvidia"' \
    || { echo "ERROR: ${HOST} missing docker / nvidia-container-toolkit" >&2; exit 1; }

echo "==> [2/4] rsync deploy/blackwell/ -> ${HOST}:${REMOTE_DIR}/"
ssh "$HOST" "mkdir -p '${REMOTE_DIR}'"
rsync -avP --partial \
    --exclude=.env \
    --exclude=up.sh \
    "${THIS_DIR}/" "${HOST}:${REMOTE_DIR}/"

if ! ssh "$HOST" "test -f '${REMOTE_DIR}/.env'"; then
    cat >&2 <<EOF
==> ERROR: ${HOST}:${REMOTE_DIR}/.env is missing.
    First-time setup: ssh ${HOST}; cp Adamomaton-deploy/.env.example Adamomaton-deploy/.env
    then edit PI1_HOST + vLLM model pins and re-run this script.
EOF
    exit 1
fi

echo "==> [3/4] (placeholder) image build/push"
echo "    skipped -- expect adamomaton-evo-worker:${IMAGE_TAG} (amd64) on ${HOST}"

echo "==> [4/4] docker compose up -d on ${HOST}"
ssh "$HOST" "cd '${REMOTE_DIR}' && IMAGE_TAG='${IMAGE_TAG}' docker compose up -d && IMAGE_TAG='${IMAGE_TAG}' docker compose ps"

echo
echo "Done. GPU node running at ${IMAGE_TAG} on ${HOST}."
echo "vLLM model warm-up takes a few minutes on first boot; tail with:"
echo "    ssh ${HOST} 'cd ${REMOTE_DIR} && docker compose logs -f vllm'"
