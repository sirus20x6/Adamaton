# /thearray/gogents/docs/development/workflow.md
## Development Workflow

### Setup and Initial Development
```bash
# 1. Clone and setup
cd /thearray
git clone https://github.com/yourusername/gogents
cd gogents
./scripts/setup-dev.sh

# 2. Configure development environment
cp .env.example .env.development
vim .env.development  # Add your tokens and URLs
source .env.development

# 3. Install Git hooks
make git-hooks

# 4. Verify setup
make health-check
```

### Daily Development Cycle

#### 1. Start Development Environment
```bash
# Start all services for development
make dev-full

# Or start components individually
make run-api      # API server only
make run-worker   # Worker only

# Monitor with dashboards
make web-dashboard      # http://localhost:9123/dashboard.html
make metrics-dashboard  # http://localhost:9123/performance.html
```

#### 2. Code Development
```bash
# Create feature branch
git checkout -b feature/new-agent-type

# Make changes and test frequently
make build        # Build all components
make test         # Run unit tests
make lint         # Code quality checks

# Test specific components
go test -v ./activities/...
go test -v ./workflows/...
go test -v ./internal/...
```

#### 3. Testing During Development
```bash
# Quick development testing
make enhanced-demo    # Full system demo
make vllm-test       # Test vLLM integration
make gitea-demo      # Test Gitea integration

# Integration testing
make integration-tests
make performance-tests
make load-test-realistic
```

#### 4. Pre-commit Workflow
```bash
# Run all quality checks
make pre-commit

# This runs:
# - gofmt formatting
# - golangci-lint static analysis
# - Unit tests
# - Documentation validation
# - Security checks

# Manual checks if needed
make quality           # All quality checks
make docs-validate     # Documentation validation
make worker-config-validate  # Configuration checks
```

#### 5. Commit and Push
```bash
# Commit with semantic messages
git add .
git commit -m "feat: add new documentation agent"
git commit -m "fix: resolve vLLM timeout issues"
git commit -m "docs: update development guide"

# Push to feature branch
git push origin feature/new-agent-type
```

### Development Patterns

#### Adding New AI Agents
```bash
# 1. Define agent type
vim internal/types/agents.go
# Add: const AgentDocumentation AgentType = "documentation"

# 2. Add system prompt
vim internal/llm/client.go
# Add case in buildAgentSystemPrompt()

# 3. Create activity function
vim activities/pr_review_activities.go
# Add: func DocumentationCheckActivity(...)

# 4. Register activity
vim workers/worker.go
# Add: w.RegisterActivity(activities.DocumentationCheckActivity)

# 5. Update workflow
vim workflows/pr_review_workflow.go
# Add agent to parallel execution

# 6. Test the new agent
make build
make enhanced-demo
```

#### Debugging Agent Issues
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG

# Run worker with debug output
make run-worker

# Monitor specific agent
journalctl -f | grep "Security Agent"
journalctl -f | grep "vLLM request"

# Test individual agent
go test -v ./activities/ -run TestSecurityCheckActivity
```

#### Testing Configuration Changes
```bash
# Test configuration validation
make worker-config-validate

# Test with different settings
export MAX_CONCURRENT_ACTIVITIES=20
make run-worker

# Monitor resource usage
htop
nvidia-smi  # For GPU monitoring
```

### Code Quality Standards

#### Go Code Standards
```bash
# Format code
gofmt -w .
goimports -w .

# Lint code
golangci-lint run ./...

# Check for race conditions
go test -race ./...

# Check for security issues
gosec ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

#### Documentation Standards
```bash
# Validate include-based documentation
make docs-validate

# Check for missing includes
make docs-create-missing

# Generate dependency graph
make docs-dependency-graph

# Full documentation health check
make docs-full-check
```

### Debugging and Troubleshooting

#### Common Development Issues
```bash
# Worker won't start
make health-check
systemctl status temporal-server

# vLLM integration issues
make vllm-health
curl -s http://localhost:8000/health

# Configuration problems
make worker-config-validate
env | grep GOGENTS

# Performance issues
make load-test-realistic
make vllm-benchmark
```

#### Debugging Tools
```bash
# Enable Go profiling
go tool pprof http://localhost:6060/debug/pprof/heap
go tool pprof http://localhost:6060/debug/pprof/cpu

# Monitor with delve debugger
dlv debug ./workers/worker.go

# Use VS Code debugging
# Set breakpoints and use F5 to start debugging
```

### Collaboration Workflow

#### Working with Team
```bash
# Keep fork updated
git remote add upstream https://github.com/original/gogents
git fetch upstream
git checkout main
git merge upstream/main

# Create feature branch from latest
git checkout -b feature/description

# Regular rebase to stay current
git fetch upstream
git rebase upstream/main
```

#### Code Review Process
1. **Create PR** from feature branch
2. **Automated checks** must pass (CI/CD)
3. **Manual review** by team members
4. **Documentation review** for user-facing changes
5. **Testing verification** for new features
6. **Merge** after approval

### Release Preparation
```bash
# Pre-release testing
make full-test-suite
make stress-test
make production-build

# Update documentation
make docs-full-check
vim PROJECT_STATUS.md  # Update metrics and status

# Version and release
git tag v1.x.x
git push origin v1.x.x
make release
```
