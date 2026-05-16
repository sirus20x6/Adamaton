# /thearray/gogents/docs/development/debugging.md
## Debugging

### Debug Environment Setup
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
export ENABLE_ACTIVITY_DEBUGGING=true
export ENABLE_DECISION_AUDIT_LOG=true

# Start with debug configuration
make run-worker
make run-api
```

### Common Debugging Scenarios

#### 1. Worker Connection Issues
```bash
# Check Temporal connectivity
curl -s http://localhost:7233
temporal namespace describe default

# Debug worker registration
export LOG_LEVEL=DEBUG
./bin/worker

# Monitor worker logs
journalctl -u gogents-worker@1.service -f
```

#### 2. Agent Execution Problems
```bash
# Debug specific agent
export LOG_LEVEL=DEBUG
go test -v ./activities/ -run TestSecurityCheckActivity

# Monitor agent calls
tail -f /opt/gogents/logs/worker.log | grep "Security Agent"

# Check vLLM integration
make vllm-test
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "test"}]}'
```

#### 3. Workflow Execution Issues
```bash
# Check workflow status
temporal workflow list --namespace default

# Describe specific workflow
temporal workflow describe --workflow-id pr-review-owner-repo-123

# Check workflow history
temporal workflow show --workflow-id pr-review-owner-repo-123

# Monitor workflow execution
temporal workflow observe --workflow-id pr-review-owner-repo-123
```

### Debugging Tools

#### 1. Go Debugging with Delve
```bash
# Install delve
go install github.com/go-delve/delve/cmd/dlv@latest

# Debug worker
dlv debug ./workers/worker.go

# Debug with environment
dlv debug ./workers/worker.go -- --env development

# Attach to running process
dlv attach $(pgrep worker)
```

#### 2. VS Code Debugging
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
      "env": {
        "LOG_LEVEL": "DEBUG"
      },
      "showLog": true
    },
    {
      "name": "Debug Specific Test",
      "type": "go",
      "request": "launch",
      "mode": "test",
      "program": "${workspaceFolder}/activities",
      "args": ["-test.run", "TestSecurityCheckActivity"],
      "envFile": "${workspaceFolder}/.env.testing"
    }
  ]
}
```

#### 3. Performance Profiling
```bash
# CPU profiling
go tool pprof http://localhost:6060/debug/pprof/profile

# Memory profiling
go tool pprof http://localhost:6060/debug/pprof/heap

# Goroutine profiling
go tool pprof http://localhost:6060/debug/pprof/goroutine

# Block profiling
go tool pprof http://localhost:6060/debug/pprof/block
```

### Logging and Monitoring

#### 1. Structured Logging
```go
// Enable structured logging in development
logger := logrus.New()
logger.SetLevel(logrus.DebugLevel)
logger.SetFormatter(&logrus.JSONFormatter{})

// Use contextual logging
logger.WithFields(logrus.Fields{
    "workflow_id": workflowID,
    "agent": "Security",
    "pr_number": prNumber,
}).Debug("Starting security analysis")
```

#### 2. Temporal Web UI
```bash
# Access Temporal Web UI (if enabled)
open http://localhost:8088

# Monitor workflows in real-time
# View workflow history and execution details
# Debug failed activities and retries
```

#### 3. Custom Debug Endpoints
```go
// Add debug endpoints to API server
func setupDebugRoutes(router *mux.Router) {
    router.HandleFunc("/debug/health", debugHealthHandler)
    router.HandleFunc("/debug/config", debugConfigHandler)
    router.HandleFunc("/debug/agents", debugAgentsHandler)
    router.HandleFunc("/debug/vllm", debugVLLMHandler)
}

func debugHealthHandler(w http.ResponseWriter, r *http.Request) {
    health := map[string]interface{}{
        "temporal": checkTemporal(),
        "vllm": checkVLLM(),
        "mcp": checkMCP(),
        "workers": getWorkerStatus(),
    }
    json.NewEncoder(w).Encode(health)
}
```

### Debug Configuration

#### Development Debug Settings
```bash
# .env.debug
LOG_LEVEL=DEBUG
ENABLE_ACTIVITY_DEBUGGING=true
ENABLE_DECISION_AUDIT_LOG=true
ENABLE_METRICS_LOGGING=true

# Extended timeouts for debugging
ACTIVITY_TIMEOUT_MINUTES=30
VLLM_REQUEST_TIMEOUT_SECONDS=600
MCP_REQUEST_TIMEOUT_SECONDS=300

# Debug-specific settings
DEBUG_SAVE_PROMPTS=true
DEBUG_SAVE_RESPONSES=true
DEBUG_SLOW_MODE=true
```

#### Verbose Output
```bash
# Enable verbose output
export GOGENTS_DEBUG=1
export GOGENTS_VERBOSE=1

# Save debug artifacts
export DEBUG_OUTPUT_DIR=/tmp/gogents-debug
mkdir -p $DEBUG_OUTPUT_DIR
```

### Common Issues and Solutions

#### 1. vLLM Connection Failures
```bash
# Symptoms: "vLLM request failed" errors
# Debug:
curl -s http://localhost:8000/health
nvidia-smi  # Check GPU availability
ps aux | grep vllm

# Solutions:
systemctl restart vllm-server
export VLLM_ENDPOINT="http://localhost:8000/generate"
make vllm-health
```

#### 2. Agent Response Parsing Errors
```bash
# Symptoms: "Failed to parse agent response" errors
# Debug:
export DEBUG_SAVE_RESPONSES=true
cat /tmp/gogents-debug/security-agent-response.txt

# Solutions:
# Check agent prompt formatting
# Verify vLLM model compatibility
# Update response parsing logic
```

#### 3. Memory Leaks
```bash
# Symptoms: Increasing memory usage over time
# Debug:
go tool pprof http://localhost:6060/debug/pprof/heap
top 10  # In pprof console

# Monitor goroutines
go tool pprof http://localhost:6060/debug/pprof/goroutine
```

#### 4. Performance Issues
```bash
# Symptoms: Slow response times
# Debug:
make vllm-benchmark
make load-test-realistic

# Monitor system resources
htop
iotop
nvidia-smi

# Check database performance
cqlsh -e "SELECT * FROM temporal.executions LIMIT 10;"
nodetool tablestats temporal
```

### Testing Debug Features

#### Debug Test Runner
```go
// tests/debug_test.go
func TestWithDebug(t *testing.T) {
    if !isDebugMode() {
        t.Skip("Skipping debug test - DEBUG mode not enabled")
    }

    // Enable debug logging for test
    oldLevel := logrus.GetLevel()
    logrus.SetLevel(logrus.DebugLevel)
    defer logrus.SetLevel(oldLevel)

    // Run test with debug output
    result, err := SecurityCheckActivity(context.Background(), sampleDiff)
    assert.NoError(t, err)
    
    // Debug assertions
    assert.NotEmpty(t, result.Rationale)
    t.Logf("Agent response: %+v", result)
}
```

#### Mock Services for Debugging
```go
// Create debug-friendly mocks
type DebugVLLMClient struct {
    responses []string
    callCount int
}

func (d *DebugVLLMClient) ExecuteAgentAnalysis(ctx context.Context, agentType types.AgentType, diff string, config types.AgentConfig) (types.CheckResult, error) {
    d.callCount++
    log.Printf("DEBUG: vLLM call #%d for agent %s", d.callCount, agentType)
    log.Printf("DEBUG: Prompt length: %d characters", len(diff))
    
    // Return predictable response for debugging
    return types.CheckResult{
        Agent: string(agentType),
        Verdict: "PASS",
        Confidence: 0.9,
        Rationale: fmt.Sprintf("Debug response #%d", d.callCount),
    }, nil
}
```

### Debug Workflows

#### Step-by-Step Debugging
```bash
# 1. Enable debug mode
export LOG_LEVEL=DEBUG

# 2. Start services one by one
make run-api
# Check: curl http://localhost:9123/health
<!-- Port 9123: API server moved off 8080 in audit pass 9; 8080 is banned per CLAUDE.md. -->

make run-worker  
# Check: temporal worker list

# 3. Test individual components
make vllm-test
make health-check

# 4. Run minimal test
./bin/start_workflow --pr 1 --owner test --repo debug

# 5. Monitor execution
journalctl -f | grep gogents
```

#### Debugging Checklist
- [ ] All environment variables set correctly
- [ ] All external services (Temporal, vLLM, MCP) accessible
- [ ] Worker registered and polling task queue
- [ ] Agent prompts generating valid responses
- [ ] Response parsing working correctly
- [ ] Decision logic producing expected results
- [ ] GitHub/Gitea API calls succeeding
- [ ] Web dashboard showing correct data

### Advanced Debugging

#### Distributed Tracing (Future Enhancement)
```go
// Add tracing context to activities
func SecurityCheckActivity(ctx context.Context, diff string) (CheckResult, error) {
    span := trace.SpanFromContext(ctx)
    span.SetAttributes(
        attribute.String("agent.type", "security"),
        attribute.Int("diff.length", len(diff)),
    )
    defer span.End()
    
    // Activity implementation...
}
```

#### Debug Metrics Collection
```go
// Collect debug metrics
type DebugMetrics struct {
    AgentCalls     map[string]int
    ResponseTimes  map[string]time.Duration
    ErrorCounts    map[string]int
    LastErrors     map[string]error
}

func (d *DebugMetrics) RecordAgentCall(agent string, duration time.Duration, err error) {
    d.AgentCalls[agent]++
    d.ResponseTimes[agent] = duration
    if err != nil {
        d.ErrorCounts[agent]++
        d.LastErrors[agent] = err
    }
}
```
