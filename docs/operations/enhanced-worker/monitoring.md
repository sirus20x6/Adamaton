### Health Checking

The health check utility validates:
- ✅ Temporal server connectivity
- ✅ Namespace accessibility  
- ✅ Active worker presence
- ✅ GitHub token configuration
- ✅ vLLM endpoint accessibility
- ✅ MCP server accessibility

```bash
# Run comprehensive health check
make health-check-enhanced

# Check individual components
./bin/worker-health
```

### Performance Metrics

The monitoring system tracks:

#### Workflow Metrics
- **Processing Count**: Total workflows processed
- **Success Rate**: Percentage of successful workflows
- **Processing Time**: Average, min, max workflow execution time

#### Activity Metrics  
- **Execution Count**: Total activities executed
- **Success Rate**: Percentage of successful activities
- **Response Time**: Average activity execution time

#### Agent Performance
- **Decision Counts**: Total decisions per agent
- **Pass Rates**: Success rate for each AI agent
- **Response Times**: Average time per agent decision

#### Risk Assessment
- **Risk Distribution**: Count of LOW/MEDIUM/HIGH/CRITICAL risk assessments
- **Complexity Scores**: Distribution of complexity levels 1-4
- **Auto-merge Rate**: Percentage of PRs auto-merged vs manual review

#### Language Statistics
- **Detection Frequency**: How often each programming language is detected
- **File Type Distribution**: Production vs test vs config files

### Metrics Output Example

```json
{
  "start_time": "2025-06-09T06:47:18Z",
  "workflows_processed": 142,
  "workflows_successful": 138,
  "workflows_failed": 4,
  "agent_decisions": {
    "Security": {
      "total_checks": 142,
      "pass_count": 139,
      "fail_count": 3,
      "avg_time_seconds": 2.45
    },
    "Performance": {
      "total_checks": 142,
      "pass_count": 134,
      "fail_count": 8,
      "avg_time_seconds": 1.98
    }
  },
  "complexity_scores": {
    "level_1_count": 89,
    "level_2_count": 35,
    "level_3_count": 15,
    "level_4_count": 3,
    "avg_score": 1.7
  },
  "language_stats": {
    "Go": 78,
    "JavaScript": 32,
    "Python": 25,
    "TypeScript": 18
  }
}
```

### Automated Reporting

The enhanced worker includes automatic metrics reporting:

```bash
# Enable periodic metrics logging (every 5 minutes)
ENABLE_METRICS_LOGGING=true

# View real-time metrics
make worker-logs | grep "Metrics Summary"
```
