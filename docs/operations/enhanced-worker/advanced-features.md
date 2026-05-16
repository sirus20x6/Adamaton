### Customization

The enhanced worker supports various customization options:

#### Risk Threshold Adjustment
```bash
# Set custom auto-merge risk threshold
AUTO_MERGE_RISK_THRESHOLD=HIGH  # LOW, MEDIUM, HIGH, CRITICAL
```

#### Timeout Configuration
```bash
# Adjust timeouts for different components
VLLM_REQUEST_TIMEOUT_SECONDS=180    # Longer for complex analysis
MCP_REQUEST_TIMEOUT_SECONDS=60      # Longer for large diffs
ACTIVITY_TIMEOUT_MINUTES=5          # Longer for heavy workloads
```

#### Enhancement Toggles
```bash
# Selectively enable/disable Week 2 features
ENABLE_ENHANCED_DIFF_ANALYSIS=false     # Disable enhanced analysis
ENABLE_COMPLEXITY_SCORING=false         # Disable complexity scoring
ENABLE_TEST_COVERAGE_CHECKS=false       # Disable test coverage enforcement
```

### Extension Points

The system is designed for easy extension:

#### Additional AI Agents
1. Create new agent function in `activities/pr_review_activities.go`
2. Add prompt builder function
3. Register activity in `workers/worker.go`
4. Update workflow in `workflows/pr_review_workflow.go`

Example agent addition:
```go
// StyleCheckActivity performs code style analysis
func StyleCheckActivity(ctx context.Context, diff string) (CheckResult, error) {
    metrics := AnalyzeDiffEnhanced(diff)
    prompt := buildStylePrompt(diff, metrics)
    result, err := callVLLMAgent(prompt, "Style")
    if err != nil {
        return result, err
    }
    result.Metrics = metrics
    return result, nil
}
```

#### Custom Language Support
Add language detection in `activities/diff_analysis.go`:
```go
// Add to GetLanguageFromExtension function
languageMap := map[string]string{
    // ... existing mappings
    "zig":    "Zig",
    "nim":    "Nim", 
    "crystal": "Crystal",
}
```

#### Custom Risk Assessment
Modify risk calculation in `workflows/pr_review_workflow.go`:
```go
func calculateRiskLevel(passCount, failCount int, criticalFailures []string, metrics *AnalysisMetrics) string {
    // Add custom risk factors
    if containsCustomRiskPattern(metrics) {
        return "HIGH"
    }
    // ... existing logic
}
```

### Horizontal Scaling

Deploy multiple workers for increased throughput:

```bash
# Scale to 3 workers
make systemd-scale WORKERS=3

# Monitor worker distribution
temporal task-queue describe pr-review

# Load balance across workers
WORKER_IDENTITY=worker-1 ./bin/enhanced-worker &
WORKER_IDENTITY=worker-2 ./bin/enhanced-worker &
WORKER_IDENTITY=worker-3 ./bin/enhanced-worker &
```

### Integration with CI/CD

#### GitHub Actions Integration
```yaml
name: Enhanced PR Review
on:
  pull_request:
    types: [opened, synchronize]
    
jobs:
  ai-review:
    runs-on: self-hosted
    steps:
      - name: Trigger Enhanced Review
        run: |
          ./bin/start_workflow \
            --pr ${{ github.event.pull_request.number }} \
            --owner ${{ github.repository_owner }} \
            --repo ${{ github.event.repository.name }}
```

#### GitLab CI Integration
```yaml
enhanced_review:
  stage: review
  script:
    - ./bin/start_workflow --pr $CI_MERGE_REQUEST_IID --owner $CI_PROJECT_NAMESPACE --repo $CI_PROJECT_NAME
  only:
    - merge_requests
```

### Monitoring Integration

#### Prometheus Metrics
Extend monitoring to export Prometheus metrics:
```go
// Add to internal/monitoring/metrics.go
func (m *Metrics) ExportPrometheus() string {
    return fmt.Sprintf(`
# HELP gogents_workflows_total Total workflows processed
# TYPE gogents_workflows_total counter
gogents_workflows_total %d

# HELP gogents_workflows_success_rate Workflow success rate
# TYPE gogents_workflows_success_rate gauge  
gogents_workflows_success_rate %.2f
`, m.WorkflowsProcessed, m.GetSuccessRate())
}
```

#### Grafana Dashboard
Create dashboards for:
- Workflow throughput and success rates
- Agent performance comparison
- Risk level distribution over time
- Language detection trends
- Response time percentiles

### Future Enhancements

The enhanced worker architecture supports future extensions:

1. **Machine Learning Integration**: Train models on historical review data
2. **Custom Agent Plugins**: Load external agent implementations
3. **Multi-Repository Analysis**: Cross-repository dependency checking
4. **Security Scanning Integration**: Integration with SAST/DAST tools
5. **Performance Profiling**: Automated performance regression detection
6. **Documentation Generation**: Automatic documentation updates
7. **Code Quality Scoring**: Comprehensive quality metrics
8. **Team-Specific Policies**: Per-team or per-repository configuration
