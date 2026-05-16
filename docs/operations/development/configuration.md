# /thearray/gogents/docs/development/configuration.md
## Configuration

### Environment Variables

#### Core Development Settings
```bash
# Development environment
export LOG_LEVEL=DEBUG
export TEMPORAL_ADDRESS=localhost:7233
export TEMPORAL_NAMESPACE=default
export TEMPORAL_TASK_QUEUE=pr-review-dev

# GitHub integration
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# vLLM backend (local development) — match the Go default which appends /generate
export VLLM_ENDPOINT=http://localhost:8000/generate
export VLLM_USE_CHAT_API=true

# MCP server (local development)
export MCP_SERVER_URL=http://localhost:3000
```

#### Development-Specific Settings
```bash
# Development worker settings
export MAX_CONCURRENT_ACTIVITIES=5      # Lower for development
export MAX_CONCURRENT_WORKFLOWS=2       # Lower for development
export WORKER_IDENTITY=dev-worker-1

# Development timeouts (longer for debugging)
export ACTIVITY_TIMEOUT_MINUTES=10
export VLLM_REQUEST_TIMEOUT_SECONDS=300
export MCP_REQUEST_TIMEOUT_SECONDS=120

# Debug features
export ENABLE_METRICS_LOGGING=true
export ENABLE_DECISION_AUDIT_LOG=true
export ENABLE_ACTIVITY_DEBUGGING=true
```

#### Agent Configuration for Development
```bash
# vLLM agent settings (relaxed for development)
export GOGENTS_VLLM_MAX_TOKENS=768
export GOGENTS_VLLM_TEMPERATURE=0.2    # Slightly higher for testing
export GOGENTS_VLLM_TIMEOUT=5m

# Per-agent development overrides
export GOGENTS_AGENTS_SECURITY_MAX_TOKENS=1024
export GOGENTS_AGENTS_SECURITY_TEMPERATURE=0.1
export GOGENTS_AGENTS_PERFORMANCE_MAX_TOKENS=512
```

### Configuration Files

#### Development Environment File
```bash
# .env.development
LOG_LEVEL=DEBUG
TEMPORAL_ADDRESS=localhost:7233
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
VLLM_ENDPOINT=http://localhost:8000/generate
MCP_SERVER_URL=http://localhost:3000

# Development-specific settings
MAX_CONCURRENT_ACTIVITIES=5
ACTIVITY_TIMEOUT_MINUTES=10
ENABLE_METRICS_LOGGING=true
ENABLE_DECISION_AUDIT_LOG=true

# API server settings (port 8080 is banned per CLAUDE.md — use 9123)
API_PORT=9123
API_CORS_ORIGINS=http://localhost:3000,http://localhost:9123
API_RATE_LIMIT_REQUESTS_PER_MINUTE=1000
```

#### Testing Configuration
```bash
# .env.testing
LOG_LEVEL=WARN
TEMPORAL_ADDRESS=localhost:7234        # Separate test instance
GITHUB_TOKEN=ghp_test_xxxxxxxxxxxx     # Test token
VLLM_ENDPOINT=http://localhost:8001/generate    # Test vLLM instance
MCP_SERVER_URL=http://localhost:3001   # Test MCP instance

# Test-specific settings
MAX_CONCURRENT_ACTIVITIES=2
ACTIVITY_TIMEOUT_MINUTES=2
TEST_MODE=true
MOCK_EXTERNAL_SERVICES=true
```

### Configuration Validation

#### Built-in Validation
```bash
# Validate development configuration
make worker-config-validate

# Test configuration with health checks
make health-check

# Verify all services are accessible
make dev-full-check
```

#### Manual Validation
```bash
# Check required environment variables
echo "Temporal: ${TEMPORAL_ADDRESS:-NOT SET}"
echo "GitHub Token: ${GITHUB_TOKEN:+SET}${GITHUB_TOKEN:-NOT SET}"
echo "vLLM: ${VLLM_ENDPOINT:-NOT SET}"
echo "MCP: ${MCP_SERVER_URL:-NOT SET}"

# Test service connectivity
curl -s http://localhost:7233 && echo "Temporal OK" || echo "Temporal FAIL"
curl -s http://localhost:8000/health && echo "vLLM OK" || echo "vLLM FAIL"
curl -s http://localhost:3000 && echo "MCP OK" || echo "MCP FAIL"
```

### IDE Configuration

#### VS Code Settings
```json
// .vscode/settings.json
{
  "go.testEnvFile": "${workspaceFolder}/.env.testing",
  "go.buildTags": "development",
  "go.lintOnSave": "package",
  "go.formatTool": "gofmt",
  "go.useLanguageServer": true,
  "go.toolsEnvVars": {
    "LOG_LEVEL": "DEBUG"
  }
}
```

#### VS Code Launch Configuration
```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Worker",
      "type": "go",
      "request": "launch",
      "mode": "auto",
      "program": "${workspaceFolder}/workers/worker.go",
      "envFile": "${workspaceFolder}/.env.development",
      "args": []
    },
    {
      "name": "Debug API Server", 
      "type": "go",
      "request": "launch",
      "mode": "auto",
      "program": "${workspaceFolder}/cmd/api/server.go",
      "envFile": "${workspaceFolder}/.env.development"
    }
  ]
}
```

### Configuration Management

#### Loading Order
1. **Default values** in code
2. **Environment variables**
3. **Configuration files** (.env files)
4. **Command-line flags** (highest priority)

#### Configuration Loading Example
```go
// internal/config/config.go
func LoadConfig() (*Config, error) {
    config := &Config{
        // Default values
        TemporalAddress: "localhost:7233",
        LogLevel: "INFO",
        MaxConcurrentActivities: 10,
    }
    
    // Load from environment
    if addr := os.Getenv("TEMPORAL_ADDRESS"); addr != "" {
        config.TemporalAddress = addr
    }
    
    // Load from .env file
    if err := godotenv.Load(); err == nil {
        // Re-read environment after loading .env
    }
    
    return config, config.Validate()
}
```
