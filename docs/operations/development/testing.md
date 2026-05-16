# /thearray/gogents/docs/development/testing.md
## Testing

### Test Structure
```
/thearray/gogents/tests/
├── unit/                    # Unit tests
│   ├── activities/         # Activity tests
│   ├── workflows/          # Workflow tests
│   └── internal/           # Internal package tests
├── integration/            # Integration tests
│   ├── e2e/               # End-to-end tests
│   ├── api/               # API tests
│   └── vllm/              # vLLM integration tests
├── performance/           # Performance and benchmark tests
└── fixtures/              # Test data and fixtures
```

### Unit Testing

#### Running Unit Tests
```bash
# Run all unit tests
make test

# Run specific package tests
go test -v ./activities/...
go test -v ./workflows/...
go test -v ./internal/...

# Run with coverage
make test-coverage

# Run with race detection
go test -race ./...
```

#### Activity Testing Example
```go
// tests/unit/activities/security_test.go
func TestSecurityCheckActivity(t *testing.T) {
    tests := []struct {
        name           string
        diff           string
        expectedVerdict string
        expectedContains string
    }{
        {
            name: "SQL injection vulnerability",
            diff: `+    query := "SELECT * FROM users WHERE id = " + userID`,
            expectedVerdict: "FAIL",
            expectedContains: "SQL injection",
        },
        {
            name: "Safe parameterized query",
            diff: `+    query := "SELECT * FROM users WHERE id = ?"`,
            expectedVerdict: "PASS",
            expectedContains: "",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result, err := SecurityCheckActivity(context.Background(), tt.diff)
            assert.NoError(t, err)
            assert.Equal(t, tt.expectedVerdict, result.Verdict)
            if tt.expectedContains != "" {
                assert.Contains(t, result.Rationale, tt.expectedContains)
            }
        })
    }
}
```

#### Workflow Testing Example
```go
// tests/unit/workflows/pr_review_test.go
func TestPRReviewWorkflow(t *testing.T) {
    testSuite := &testsuite.WorkflowTestSuite{}
    env := testSuite.NewTestWorkflowEnvironment()

    // Mock activities
    env.OnActivity(activities.FetchDiffActivity, mock.Anything, mock.Anything).Return(sampleDiff, nil)
    env.OnActivity(activities.SecurityCheckActivity, mock.Anything, mock.Anything).Return(
        CheckResult{Agent: "Security", Verdict: "PASS", Rationale: "No security issues"}, nil)

    env.ExecuteWorkflow(PRReviewWorkflow, PRReviewArgs{
        PRNumber:  123,
        RepoOwner: "test",
        RepoName:  "repo",
    })

    assert.True(t, env.IsWorkflowCompleted())
    assert.NoError(t, env.GetWorkflowError())
}
```

### Integration Testing

#### Running Integration Tests
```bash
# Run integration tests (requires running services)
make integration-tests

# Run specific integration test suites
go test -v -tags=integration ./tests/integration/e2e/...
go test -v -tags=integration ./tests/integration/api/...
go test -v -tags=integration ./tests/integration/vllm/...
```

#### End-to-End Testing
```go
// tests/integration/e2e/pr_review_test.go
// +build integration

func TestFullPRReviewWorkflow(t *testing.T) {
    // Setup test environment
    client := setupTemporalClient(t)
    defer client.Close()

    // Start workflow
    we, err := client.ExecuteWorkflow(
        context.Background(),
        client.StartWorkflowOptions{
            ID:        "test-pr-review-" + uuid.New().String(),
            TaskQueue: "pr-review-test",
        },
        workflows.PRReviewWorkflow,
        workflows.PRReviewArgs{
            PRNumber:  1,
            RepoOwner: "octocat",
            RepoName:  "Hello-World",
        },
    )
    require.NoError(t, err)

    // Wait for completion
    err = we.Get(context.Background(), nil)
    require.NoError(t, err)

    // Verify results
    history := getWorkflowHistory(t, client, we.GetID())
    assertWorkflowCompleted(t, history)
    assertAllAgentsExecuted(t, history)
}
```

#### API Integration Testing
```go
// tests/integration/api/dashboard_test.go
func TestDashboardAPI(t *testing.T) {
    // Start test API server
    server := startTestAPIServer(t)
    defer server.Close()

    // Test dashboard stats endpoint
    resp, err := http.Get(server.URL + "/api/v1/dashboard/stats")
    require.NoError(t, err)
    defer resp.Body.Close()

    assert.Equal(t, http.StatusOK, resp.StatusCode)

    var stats DashboardStats
    err = json.NewDecoder(resp.Body).Decode(&stats)
    require.NoError(t, err)

    assert.GreaterOrEqual(t, stats.WorkflowsProcessed, 0)
    assert.GreaterOrEqual(t, stats.SuccessRate, 0.0)
}
```

### Performance Testing

#### Benchmark Tests
```bash
# Run performance benchmarks
make performance-tests

# Run specific benchmarks
go test -v -bench=. -benchtime=10s ./tests/performance/...

# Profile during benchmarks
go test -bench=. -cpuprofile=cpu.prof ./tests/performance/...
go tool pprof cpu.prof
```

#### Load Testing
```bash
# Realistic load test
make load-test-realistic

# Stress test with high concurrency
make stress-test

# Monitor during load tests
make status-check
make worker-logs
```

#### Benchmark Example
```go
// tests/performance/agent_benchmark_test.go
func BenchmarkSecurityAgent(b *testing.B) {
    diff := loadSampleDiff("security_test.diff")
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _, err := SecurityCheckActivity(context.Background(), diff)
        if err != nil {
            b.Fatal(err)
        }
    }
}

func BenchmarkParallelAgents(b *testing.B) {
    diff := loadSampleDiff("complex_change.diff")
    
    b.ResetTimer()
    b.RunParallel(func(pb *testing.PB) {
        for pb.Next() {
            // Simulate parallel agent execution
            var wg sync.WaitGroup
            agents := []string{"Security", "Performance", "Architecture"}
            
            for _, agent := range agents {
                wg.Add(1)
                go func(agentName string) {
                    defer wg.Done()
                    runAgent(agentName, diff)
                }(agent)
            }
            wg.Wait()
        }
    })
}
```

### Mock Services for Testing

### Quick Test Options

#### Option 1: Enhanced Demo (Recommended)
```bash
cd /thearray/gogents
chmod +x test-setup.sh
./test-setup.sh
make enhanced-demo
```

This will:
- ✅ Build all components
- ✅ Start API server and worker
- ✅ Open web dashboard at http://localhost:9123/dashboard.html
<!-- Port 9123: API server moved off 8080 in audit pass 9; 8080 is banned per CLAUDE.md. -->
- ✅ Run sample PR review with all 12 agents

#### Option 2: Create Test Project
```bash
# LEGACY — pre-fold test-project scaffolder, retired to _legacy/.
cd /thearray/git/evo
chmod +x _legacy/create-test-project.sh
./_legacy/create-test-project.sh
```

This creates a comprehensive test project at `/tmp/gogents-test-project` with:
- **Security vulnerabilities** (SQL injection, command injection)
- **Performance issues** (O(n²) algorithms, memory leaks)
- **Architecture problems** (monolithic functions)

#### vLLM Mock Server
```go
// tests/mocks/vllm_mock.go
type MockVLLMServer struct {
    server *httptest.Server
    responses map[string]string
}

func NewMockVLLMServer() *MockVLLMServer {
    mock := &MockVLLMServer{
        responses: make(map[string]string),
    }
    
    mock.server = httptest.NewServer(http.HandlerFunc(mock.handleRequest))
    return mock
}

func (m *MockVLLMServer) handleRequest(w http.ResponseWriter, r *http.Request) {
    if r.URL.Path == "/health" {
        w.WriteHeader(http.StatusOK)
        return
    }
    
    if r.URL.Path == "/v1/chat/completions" {
        response := VLLMResponse{
            Choices: []struct {
                Message struct {
                    Content string `json:"content"`
                } `json:"message"`
            }{
                {Message: struct {
                    Content string `json:"content"`
                }{Content: "VERDICT: PASS\nCONFIDENCE: 0.9\nSEVERITY: LOW\nRATIONALE: No issues found"}},
            },
        }
        json.NewEncoder(w).Encode(response)
    }
}
```

#### GitHub MCP Mock
```go
// tests/mocks/mcp_mock.go
type MockMCPServer struct {
    server *httptest.Server
    diffs  map[string]string
}

func (m *MockMCPServer) SetDiff(prNumber int, diff string) {
    key := fmt.Sprintf("pr-%d", prNumber)
    m.diffs[key] = diff
}

func (m *MockMCPServer) handleRequest(w http.ResponseWriter, r *http.Request) {
    var req MCPRequest
    json.NewDecoder(r.Body).Decode(&req)
    
    if req.Method == "getPullRequestDiff" {
        prNumber := req.Params["prNumber"].(float64)
        key := fmt.Sprintf("pr-%.0f", prNumber)
        
        response := MCPResponse{
            Result: map[string]interface{}{
                "diff": m.diffs[key],
            },
        }
        json.NewEncoder(w).Encode(response)
    }
}
```

### Test Data Management

#### Test Fixtures
```go
// tests/fixtures/diffs.go
var TestDiffs = map[string]string{
    "security_vulnerability": `
+func authenticate(user, password string) bool {
+    query := "SELECT * FROM users WHERE username = '" + user + "' AND password = '" + password + "'"
+    // SQL injection vulnerability
+}`,
    
    "performance_issue": `
+func processItems(items []Item) {
+    for i := 0; i < len(items); i++ {
+        for j := 0; j < len(items); j++ {
+            // O(n²) complexity issue
+        }
+    }
+}`,
    
    "safe_change": `
+func addNumbers(a, b int) int {
+    return a + b
+}`,
}
```

### Continuous Integration

#### Test Commands in Makefile
```makefile
test: ## Run unit tests
	go test -v ./...

test-coverage: ## Run tests with coverage
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html

integration-tests: ## Run integration tests
	go test -v -tags=integration ./tests/integration/...

performance-tests: ## Run performance tests
	go test -v -bench=. -benchtime=10s ./tests/performance/...

full-test-suite: test integration-tests performance-tests ## Run all tests
	@echo "✅ All tests completed"
```

#### CI/CD Pipeline
```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.20'
      
      - name: Unit Tests
        run: make test
      
      - name: Integration Tests
        run: make integration-tests
        env:
          GITHUB_TOKEN: ${{ secrets.TEST_GITHUB_TOKEN }}
      
      - name: Performance Tests  
        run: make performance-tests
```
