### Unit Tests
```bash
# Run Week 2 enhancement tests
make week2-test

# Run specific test suites
go test -v ./activities/... -run TestEnhanced
go test -v ./workflows/... -run TestEnhanced
go test -v ./internal/... -run TestConfig
```

### Integration Tests
```bash
# Comprehensive health check
make health-check-enhanced

# Test external service connectivity
curl -s http://localhost:7233  # Temporal
curl -s $VLLM_ENDPOINT/health  # vLLM
curl -s $MCP_SERVER_URL        # MCP Server
```

### Demo Mode
```bash
# Run Week 2 enhanced demo
make enhanced-demo-week2

# Features demonstrated:
# ✅ Enhanced diff analysis with function extraction
# ✅ Multi-language detection and categorization  
# ✅ Critical file and test file identification
# ✅ Complexity scoring (1-4 scale)
# ✅ Risk assessment (LOW/MEDIUM/HIGH/CRITICAL)
# ✅ Context-aware AI prompts
# ✅ Rich markdown comments with detailed metrics
# ✅ Progressive security policies
# ✅ Test coverage enforcement
```

### Load Testing
```bash
# Realistic load test
make load-test-realistic

# Stress test with high concurrency
make stress-test

# Monitor performance during tests
make worker-status
make worker-logs
```

### Performance Benchmarks

Expected performance metrics:
- **Workflow Processing**: ~15-30 seconds per PR
- **Agent Response Time**: ~2-5 seconds per agent
- **Complexity Analysis**: ~100ms per diff
- **Language Detection**: ~50ms per diff
- **Memory Usage**: ~50-100MB per worker
- **CPU Usage**: ~10-20% per worker (excluding vLLM calls)

### Test Data Generation

```bash
# Generate test PRs with different complexity levels
./scripts/generate-test-data.sh

# Test specific scenarios
./bin/start_workflow --pr 1 --owner test --repo simple-go
./bin/start_workflow --pr 2 --owner test --repo complex-multifile
./bin/start_workflow --pr 3 --owner test --repo critical-config
```
