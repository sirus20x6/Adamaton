# /thearray/gogents/docs/main/configuration.md
## Configuration

### Environment Variables

#### Core Configuration
```bash
# Temporal settings
TEMPORAL_ADDRESS=localhost:7233
TEMPORAL_NAMESPACE=default
TEMPORAL_TASK_QUEUE=pr-review

# GitHub integration
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# vLLM backend (vLLM native API path)
VLLM_ENDPOINT=http://localhost:8000/generate
VLLM_USE_CHAT_API=true

# MCP server
MCP_SERVER_URL=http://localhost:3000
```

#### Agent Configuration
```bash
# Global agent settings
GOGENTS_VLLM_MAX_TOKENS=512
GOGENTS_VLLM_TEMPERATURE=0.1
GOGENTS_VLLM_TIMEOUT=2m

# Per-agent overrides
GOGENTS_AGENTS_SECURITY_MAX_TOKENS=768
GOGENTS_AGENTS_SECURITY_TEMPERATURE=0.05
GOGENTS_AGENTS_PERFORMANCE_MAX_TOKENS=512
GOGENTS_AGENTS_ARCHITECTURE_MAX_TOKENS=768
```

#### Worker Settings
```bash
# Worker configuration
MAX_CONCURRENT_ACTIVITIES=10
MAX_CONCURRENT_WORKFLOWS=5
WORKER_IDENTITY=gogents-worker-1
LOG_LEVEL=INFO

# Performance tuning
ENABLE_METRICS_LOGGING=true
ENABLE_DECISION_AUDIT_LOG=true
ACTIVITY_TIMEOUT_MINUTES=3
MAX_RETRY_ATTEMPTS=3
```

#### Risk Assessment
```bash
# Auto-merge policies
AUTO_MERGE_RISK_THRESHOLD=MEDIUM
REQUIRE_ALL_PASS_FOR_MEDIUM_RISK=true
NEVER_AUTO_MERGE_SECURITY_FAILS=true

# Coverage enforcement
ENFORCE_TEST_COVERAGE=true
TEST_COVERAGE_THRESHOLD=80
```

### Configuration Files

#### Worker Configuration
```bash
# /etc/gogents/worker.env
TEMPORAL_ADDRESS=localhost:7233
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
VLLM_ENDPOINT=http://localhost:8000/generate
MCP_SERVER_URL=http://localhost:3000
LOG_LEVEL=INFO
MAX_CONCURRENT_ACTIVITIES=10
```

#### API Server Configuration
```bash
# /etc/gogents/api.env
PORT=9123
CORS_ORIGINS=*
RATE_LIMIT_REQUESTS_PER_MINUTE=100
METRICS_RETENTION_DAYS=30
DASHBOARD_ENABLED=true
```

### Validation
```bash
# Validate configuration
make worker-config-validate

# Test connectivity
make health-check

# View current settings
make worker-info
```
