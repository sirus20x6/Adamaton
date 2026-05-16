#!/usr/bin/env bash
# Pings the Semantic Scholar API once with our key so the key doesn't get
# revoked for ~60 days of inactivity. Reads SEMANTIC_SCHOLAR_API_KEY from the
# repo's .env. Logs to syslog/stderr; exit code 0 on 200, non-zero otherwise.
#
# Suggested host cron line (every Wednesday at 14:37 local):
#   37 14 * * 3 /thearray/git/deepresearch/platform/infra/s2_keepalive.sh

set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"
KEY=$(grep '^SEMANTIC_SCHOLAR_API_KEY=' "$ENV_FILE" | cut -d= -f2-)

if [ -z "$KEY" ]; then
  echo "s2_keepalive: SEMANTIC_SCHOLAR_API_KEY not set in $ENV_FILE" >&2
  exit 2
fi

URL='https://api.semanticscholar.org/graph/v1/paper/arXiv:1706.03762?fields=paperId,title'
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "x-api-key: $KEY" "$URL" || echo "curl_fail")

case "$CODE" in
  200) echo "s2_keepalive: OK ($(date -Iseconds))"; exit 0 ;;
  401|403) echo "s2_keepalive: key REVOKED (HTTP $CODE) — regenerate at semanticscholar.org" >&2; exit 3 ;;
  429) echo "s2_keepalive: rate-limited (HTTP 429), key still valid" >&2; exit 0 ;;
  *) echo "s2_keepalive: unexpected response ($CODE)" >&2; exit 4 ;;
esac
