#!/bin/bash
# /thearray/gogents/scripts/setup-dev.sh - Development environment setup script

set -e

echo "Setting up development environment for AI-driven PR review..."

# Check required environment variables
echo "Checking environment variables..."
if [ -z "$GITHUB_TOKEN" ]; then
    echo "⚠️  GITHUB_TOKEN not set. You'll need this for GitHub API access."
fi

if [ -z "$VLLM_ENDPOINT" ]; then
    echo "ℹ️  VLLM_ENDPOINT not set. Using default: http://vllm.local:8000/generate"
    export VLLM_ENDPOINT="http://vllm.local:8000/generate"
fi

if [ -z "$MCP_SERVER_URL" ]; then
    echo "ℹ️  MCP_SERVER_URL not set. Using default: http://localhost:3000"
    export MCP_SERVER_URL="http://localhost:3000"
fi

# Check if Temporal server is running
echo "Checking Temporal server..."
if ! nc -z localhost 7233 2>/dev/null; then
    echo "⚠️  Temporal server not running on localhost:7233"
    echo "   Start it with: temporal-server start --config /etc/temporal/config.yaml"
else
    echo "✅ Temporal server is running"
fi

# Check if vLLM is reachable
echo "Checking vLLM endpoint..."
if ! curl -sf "$VLLM_ENDPOINT" >/dev/null 2>&1; then
    echo "⚠️  vLLM endpoint not reachable at $VLLM_ENDPOINT"
else
    echo "✅ vLLM endpoint is reachable"
fi

# Check if MCP server is reachable
echo "Checking MCP server..."
if ! curl -sf "$MCP_SERVER_URL" >/dev/null 2>&1; then
    echo "⚠️  MCP server not reachable at $MCP_SERVER_URL"
else
    echo "✅ MCP server is reachable"
fi

echo ""
echo "Development environment setup complete!"
echo ""
echo "Next steps (post-fold, per-module workspace):"
echo "1. Build a worker:  cd skills && go build ./cmd/skills-worker"
echo "   (or 'make pi-skills-worker' for arm64 cross-compile)"
echo "2. Run locally:     ./skills/skills-worker"
echo "3. See Makefile 'pi-*' targets for all per-module workers."
echo ""
echo "Environment:"
echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:+***set***}"
echo "  VLLM_ENDPOINT: $VLLM_ENDPOINT"
echo "  MCP_SERVER_URL: $MCP_SERVER_URL"
