### Environment Variables

The enhanced worker uses the following configuration variables:

#### Temporal Configuration
```bash
TEMPORAL_ADDRESS=localhost:7233          # Temporal server address
TEMPORAL_NAMESPACE=default               # Temporal namespace
TEMPORAL_TASK_QUEUE=pr-review           # Task queue name
WORKER_IDENTITY=pr-review-worker-1      # Worker identity
```

#### Worker Settings
```bash
MAX_CONCURRENT_ACTIVITIES=10            # Max parallel activities
MAX_CONCURRENT_WORKFLOWS=5              # Max parallel workflows
LOG_LEVEL=INFO                          # Logging level
ENABLE_METRICS_LOGGING=true            # Enable metrics logging
ENABLE_DECISION_AUDIT_LOG=true         # Enable decision audit logs
```

#### External Services
```bash
VLLM_ENDPOINT=http://vllm.local:8000/generate  # vLLM server endpoint
MCP_SERVER_URL=http://localhost:3000           # MCP server URL
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx          # GitHub access token
```

#### Week 2 Enhancements
```bash
ENABLE_ENHANCED_DIFF_ANALYSIS=true     # Enhanced diff analysis
ENABLE_LANGUAGE_DETECTION=true         # Multi-language detection
ENABLE_COMPLEXITY_SCORING=true         # Complexity scoring
ENABLE_CRITICAL_FILE_DETECTION=true    # Critical file detection
ENABLE_TEST_COVERAGE_CHECKS=true       # Test coverage enforcement
ENABLE_RICH_COMMENTS=true              # Rich markdown comments
```

#### Security Settings
```bash
AUTO_MERGE_RISK_THRESHOLD=MEDIUM        # Auto-merge risk threshold
REQUIRE_ALL_PASS_FOR_MEDIUM_RISK=true  # Require all agents to pass for medium risk
ENFORCE_TEST_COVERAGE=true             # Enforce test coverage
NEVER_AUTO_MERGE_SECURITY_FAILS=true   # Never auto-merge security failures
```

#### Performance Tuning
```bash
VLLM_REQUEST_TIMEOUT_SECONDS=120       # vLLM request timeout
MCP_REQUEST_TIMEOUT_SECONDS=30         # MCP request timeout
ACTIVITY_TIMEOUT_MINUTES=3             # Activity timeout
MAX_RETRY_ATTEMPTS=3                   # Maximum retry attempts
```

### Configuration Validation

Use the built-in validation to ensure your configuration is correct:

```bash
make worker-config-validate
```

This will check:
- ✅ Required environment variables are set
- ✅ Configuration file exists and is readable
- ✅ Values are within valid ranges
- ✅ External services are accessible
