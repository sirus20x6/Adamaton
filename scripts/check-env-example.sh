#!/usr/bin/env bash
# check-env-example.sh — fail when a REQUIRED env var referenced by the
# deploy compose files is not declared in .env.example.
#
# "Required" means referenced as ${VAR} or ${VAR:?err} (no default value);
# ${VAR:-default} references are optional by construction and skipped. On
# top of that, an explicit allow-list of secrets must stay declared even
# where compose gives them a harmless dev default — forgetting one fails
# silently at runtime (empty token, undecryptable credentials).
#
# Wired into `make ci`. Values in .env.example may be placeholders; only
# the declaration is checked.
set -euo pipefail
cd "$(dirname "$0")/.."

example=".env.example"
[[ -f "$example" ]] || { echo "missing $example" >&2; exit 1; }

declared="$(grep -hE '^[A-Za-z_][A-Za-z0-9_]*=' "$example" deploy/*/image-tags.env.example 2>/dev/null \
    | cut -d= -f1 | sort -u)"

required="$(grep -hoE '\$\{[A-Za-z_][A-Za-z0-9_]*(:\?[^}]*)?\}' deploy/*/docker-compose.yml \
    | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*).*/\1/' | sort -u)"

must_declare="API_TOKEN BUDGET_API_TOKEN CREDENTIAL_ENCRYPTION_KEY DEPLOY_AGENT_TOKEN GARAGE_RPC_SECRET GITHUB_TOKEN"

missing=0
for var in $(printf "%s\\n" $required $must_declare | sort -u); do
    if ! grep -qx "$var" <<<"$declared"; then
        echo "MISSING from .env.example: $var" >&2
        missing=1
    fi
done
if (( missing )); then
    echo "env drift: declare the variables above in .env.example (placeholder values are fine)" >&2
    exit 1
fi
echo "ok: every required compose env var is declared in .env.example"
