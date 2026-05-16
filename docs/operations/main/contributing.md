# /thearray/gogents/docs/main/contributing.md
## Contributing

### Getting Started
```bash
# Fork and clone
git fork https://github.com/yourusername/gogents
git clone https://github.com/your-username/gogents
cd gogents

# Setup development environment
./scripts/setup-dev.sh
make git-hooks  # Install pre-commit hooks
```

### Development Workflow
1. **Create feature branch**
   ```bash
   git checkout -b feature/add-new-agent
   ```

2. **Make changes and test**
   ```bash
   make build test lint
   make pre-commit
   ```

3. **Update documentation**
   ```bash
   make docs-validate
   # Update relevant docs/main/*.md files
   ```

4. **Commit with semantic messages**
   ```bash
   git commit -m "feat: add documentation analysis agent"
   git commit -m "fix: resolve vLLM timeout issues"
   git commit -m "docs: update installation guide"
   ```

5. **Submit pull request**

### Code Standards
- **Go Style**: Follow effective Go guidelines
- **Formatting**: Use `gofmt` and `golangci-lint`
- **Testing**: Maintain >80% test coverage
- **Documentation**: Update docs for user-facing changes
- **Performance**: Benchmark performance-critical changes

### Testing Requirements
```bash
# Unit tests
go test -v ./...

# Integration tests
make integration-tests

# Performance tests
make performance-tests

# Full test suite
make full-test-suite
```

### Adding New Features

#### New AI Agents
1. **Define agent type** in `internal/types/agents.go`
2. **Add system prompt** in `internal/llm/client.go`
3. **Create activity function** in `activities/pr_review_activities.go`
4. **Register in worker** in `workers/worker.go`
5. **Update workflow** in `workflows/pr_review_workflow.go`
6. **Add tests** in `tests/`
7. **Update documentation**

#### API Endpoints
1. **Define handler** in `cmd/api/handlers/`
2. **Add route** in `cmd/api/server.go`
3. **Write tests** in `tests/api/`
4. **Update OpenAPI spec**
5. **Document in** `docs/main/rest-api.md`

#### Configuration Options
1. **Add to environment parsing** in `internal/config/`
2. **Update validation** in configuration validators
3. **Document in** `docs/main/configuration.md`
4. **Add example to** `configs/*.env.example`

### Documentation Guidelines
Follow the include-based documentation system:

1. **Main documents** use includes: `{!docs/component/file.md!}`
2. **Create includes** in appropriate `docs/*/` directories
3. **Validate** with `make docs-validate`
4. **Check completeness** with `make docs-full-check`

### Code Review Process
1. **Automated checks** must pass (CI/CD)
2. **Manual review** by maintainers
3. **Documentation review** for user-facing changes
4. **Performance review** for critical paths
5. **Security review** for security-related changes

### Bug Reports
Include:
- **System information** (NixOS version, Go version)
- **Configuration** (sanitized environment variables)
- **Steps to reproduce**
- **Expected vs actual behavior**
- **Logs** (from `journalctl` or application logs)
- **Health check output** from `make health-check`

### Feature Requests
Include:
- **Use case** and motivation
- **Proposed solution** or API design
- **Alternatives considered**
- **Implementation complexity** estimate
- **Breaking changes** assessment

### Security Issues
- **Do not** file public issues for security vulnerabilities
- **Email** security@yourorganization.com
- **Include** detailed reproduction steps
- **Wait** for response before public disclosure

### Community Guidelines
- **Be respectful** and inclusive
- **Help others** with questions and issues
- **Share knowledge** and best practices
- **Collaborate** on improvements
- **Follow** the code of conduct

### Recognition
Contributors are recognized in:
- **CONTRIBUTORS.md** file
- **Release notes** for significant contributions
- **GitHub releases** with contributor highlights
- **Documentation** credits for major documentation work
