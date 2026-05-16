# /thearray/gogents/docs/main/development.md
## Development Guide

### Quick Development Setup
```bash
# Clone and setup
cd /thearray
git clone https://github.com/yourusername/gogents
cd gogents
./scripts/setup-dev.sh

# Configure environment
cp .env.example .env
vim .env  # Add your GitHub token and service URLs
source .env

# Start development environment
make dev-full
```

### Development Workflow
```bash
# Build and test cycle
make build          # Build all binaries
make test           # Run unit tests
make lint           # Code quality checks
make quality        # All quality checks

# Development services
make run-api        # API server only
make run-worker     # Worker only
make dev-full       # Complete environment

# Testing
make integration-tests    # Integration test suite
make performance-tests   # Performance benchmarks
make load-test-realistic # Realistic load testing
```

### Code Organization
```
/thearray/gogents/
├── activities/          # Temporal activities
│   ├── pr_review_activities.go
│   └── diff_analysis.go
├── workflows/           # Temporal workflows
│   └── pr_review_workflow.go
├── workers/            # Worker implementations
│   └── worker.go
├── cmd/                # CLI tools
│   ├── start_workflow.go
│   ├── api/
│   └── gitea_review.go
├── internal/           # Internal packages
│   ├── llm/           # LLM client abstractions
│   ├── types/         # Type definitions
│   ├── config/        # Configuration management
│   └── monitoring/    # Metrics and monitoring
├── web/               # Web dashboard files
├── tests/             # Test suites
└── docs/              # Documentation
```

### Adding New Agents
1. **Define Agent Type** in `internal/types/agents.go`
2. **Add System Prompt** in `internal/llm/client.go`
3. **Register Activity** in `workers/worker.go`
4. **Update Workflow** in `workflows/pr_review_workflow.go`

Example:
```go
// 1. Add to types
const AgentDocumentation AgentType = "documentation"

// 2. Add prompt
case types.AgentDocumentation:
    return basePrompt + `You are a DOCUMENTATION EXPERT...`

// 3. Register activity
w.RegisterActivity(activities.DocumentationCheckActivity)

// 4. Update workflow
docResult := workflow.ExecuteActivity(ctx, activities.DocumentationCheckActivity, diff)
```

### Testing Strategy
```bash
# Unit tests
go test -v ./activities/...
go test -v ./workflows/...
go test -v ./internal/...

# Integration tests
go test -v -tags=integration ./tests/integration/...

# Performance tests
go test -v -bench=. -benchtime=10s ./tests/...

# End-to-end tests
make enhanced-demo    # Full system demo
make gitea-demo      # Gitea integration demo
```

### Debugging
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG

# Run with race detection
go run -race ./workers/worker.go

# Profile performance
go tool pprof http://localhost:6060/debug/pprof/heap
go tool pprof http://localhost:6060/debug/pprof/cpu
```

### Git Workflow
```bash
# Install pre-commit hooks
make git-hooks

# Pre-commit checks
make pre-commit

# Commit workflow
git add .
git commit -m "feat: add new documentation agent"
# Pre-commit hook runs automatically
```

### Environment Variables
```bash
# Development
LOG_LEVEL=DEBUG
TEMPORAL_ADDRESS=localhost:7233
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
VLLM_ENDPOINT=http://localhost:8000/generate

# Testing
TEST_GITHUB_TOKEN=ghp_test_token
TEST_VLLM_ENDPOINT=http://test-vllm:8000/generate
TEST_TEMPORAL_ADDRESS=localhost:7234
```

### Documentation
Follow the include-based documentation system:
```bash
# Validate documentation
make docs-validate

# Create missing includes
make docs-create-missing

# Check documentation health
make docs-full-check
```

### Contributing Guidelines
1. **Follow Go conventions** (gofmt, golint, go vet)
2. **Write tests** for new functionality
3. **Update documentation** for user-facing changes
4. **Run quality checks** before committing
5. **Use semantic commits** (feat:, fix:, docs:, etc.)
