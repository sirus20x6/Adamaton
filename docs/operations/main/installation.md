# /thearray/gogents/docs/main/installation.md
## Quick Installation

### 1. Clone and Setup
```bash
cd /thearray
git clone https://github.com/yourusername/gogents
cd gogents
chmod +x scripts/setup-dev.sh init-git.sh
./scripts/setup-dev.sh
```

### 2. Configure Environment
```bash
# Copy example configuration
cp .env.example .env

# Edit with your settings
vim .env

# Required variables:
# GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
# VLLM_ENDPOINT=http://localhost:8000/generate
# MCP_SERVER_URL=http://localhost:3000

# Source configuration
source .env
```

### 3. Build and Verify
```bash
# Build all components
make build

# Run health check
make health-check

# Test vLLM integration
make vllm-health
```

### 4. Start Services
```bash
# Development mode
make dev-full

# Production deployment
make production-deploy
```

### 5. Verify Installation
- **Web Dashboard**: http://localhost:9123/dashboard.html
- **Performance Monitor**: http://localhost:9123/performance.html
- **REST API**: http://localhost:9123/api/v1/
- **Temporal UI**: http://localhost:8088 (if enabled)
