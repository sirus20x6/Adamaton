# /thearray/gogents/Makefile - GoGents build automation system

# Build configuration
BINARY_DIR := bin
WORKER_BINARY := $(BINARY_DIR)/worker
STARTER_BINARY := $(BINARY_DIR)/start_workflow

# VERSION is stamped into the built binaries via -ldflags. Each cmd/*/main.go
# package can declare `var version = "dev"` (a package-level var, not a const)
# and log it on startup; the linker overrides it at build time.
VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
LDFLAGS := -s -w -X main.version=$(VERSION)
GOFLAGS := -ldflags="$(LDFLAGS)"
GOOS := linux
GOARCH := amd64

# Default target
.PHONY: help
help: ## Show this help message
	@echo "🤖 GoGents - AI-Driven PR Review System"
	@echo "======================================="
	@echo ""
	@echo "📦 Build Commands:"
	@echo "  build                 Build all binaries"
	@echo "  build-worker          Build Temporal worker"
	@echo "  build-starter         Build workflow starter"
	@echo "  clean                 Clean build artifacts"
	@echo ""
	@echo "🧪 Testing:"
	@echo "  test                  Run unit tests"
	@echo "  health-check          System health check"
	@echo "  vllm-health           Check vLLM status"
	@echo ""
	@echo "🚀 Demo & Development:"
	@echo "  enhanced-demo         Run complete demo"
	@echo "  dev-full              Start development environment"
	@echo "  status-check          Check process status"
	@echo ""
	@echo "🌐 Production:"
	@echo "  production-deploy     Complete production setup"
	@echo "  systemd-status        Check systemd services"
	@echo ""
	@echo "📚 Documentation:"
	@echo "  agent-summary         Show all 12 AI agents"
	@echo "  worker-info           Worker configuration info"
	@echo "  version               Version information"

# Build targets
.PHONY: build build-worker build-starter clean deps

build: build-worker build-starter ## Build all main binaries
	@echo "✅ All binaries built successfully"

build-worker: ## Build Temporal worker
	@echo "DEPRECATED: ./workers/ target was for pre-fold layout; no replacement Temporal worker at this path. Use build-enhanced-worker, skills-worker, reindex-worker, or pi-dispatch-worker instead." && false

build-starter: ## Build workflow starter
	@mkdir -p $(BINARY_DIR)
	go build $(GOFLAGS) -o $(STARTER_BINARY) ./temporal/cmd/start-workflow/
	@echo "✅ Workflow starter built: $(STARTER_BINARY)"

# Pi (ARM64) cross-compile targets for the new Temporal workers introduced by
# the watchdogs-to-Temporal migration. Both binaries are intended to run on
# the Pi alongside the existing evo-worker; the local-arch versions exist
# mostly so CI / `go build` smoke tests can produce them.
.PHONY: r2g pi-r2g skills-worker reindex-worker pi-skills-worker pi-reindex-worker pi-workers skills-rae pi-skills-rae skills-rae-worker pi-skills-rae-worker
r2g: ## Build r2g (Go re-implementation of R2R /v3/* surface) for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/r2g && go build $(GOFLAGS) -o ../$(BINARY_DIR)/r2g ./cmd/r2g
	@echo "✅ r2g built: $(BINARY_DIR)/r2g"

pi-r2g: ## Cross-compile r2g for linux/arm64 (Pi 5) -- cgo for go-fitz (MuPDF)
	@mkdir -p $(BINARY_DIR)
	cd knowledge/r2g && GOOS=linux GOARCH=arm64 CGO_ENABLED=1 \
		CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/r2g.arm64 ./cmd/r2g
	@echo "✅ r2g (arm64, cgo) built: $(BINARY_DIR)/r2g.arm64"

skills-rae: ## Build skills-rae (SkillRAE retrieval + compilation service) for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-rae ./cmd/skills-rae
	@echo "✅ skills-rae built: $(BINARY_DIR)/skills-rae"

pi-skills-rae: ## Cross-compile skills-rae for linux/arm64 (Pi 5) -- pure Go, no cgo
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-rae.arm64 ./cmd/skills-rae
	@echo "✅ skills-rae (arm64) built: $(BINARY_DIR)/skills-rae.arm64"

skills-rae-worker: ## Build skills-rae-worker (Temporal indexer) for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-rae-worker ./cmd/skills-rae-worker
	@echo "✅ skills-rae-worker built: $(BINARY_DIR)/skills-rae-worker"

pi-skills-rae-worker: ## Cross-compile skills-rae-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-rae-worker.arm64 ./cmd/skills-rae-worker
	@echo "✅ skills-rae-worker (arm64) built: $(BINARY_DIR)/skills-rae-worker.arm64"

skillsbench: ## Build skillsbench (SkillRAE eval harness CLI) for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && go build $(GOFLAGS) -o ../$(BINARY_DIR)/skillsbench ./cmd/skillsbench
	@echo "✅ skillsbench built: $(BINARY_DIR)/skillsbench"

pi-skillsbench: ## Cross-compile skillsbench for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills-rae && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/skillsbench.arm64 ./cmd/skillsbench
	@echo "✅ skillsbench (arm64) built: $(BINARY_DIR)/skillsbench.arm64"

pi-nano-research: ## Cross-compile nano-research for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd deepresearch/nano-research && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/nano-research.arm64 ./cmd/nano-research
	@echo "✅ nano-research (arm64) built: $(BINARY_DIR)/nano-research.arm64"

pi-nano-research-worker: ## Cross-compile nano-research-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd deepresearch/nano-research && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/nano-research-worker.arm64 ./cmd/nano-research-worker
	@echo "✅ nano-research-worker (arm64) built: $(BINARY_DIR)/nano-research-worker.arm64"

skills-worker: ## Build skills-worker for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills && go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-worker ./cmd/skills-worker
	@echo "✅ skills-worker built: $(BINARY_DIR)/skills-worker"

reindex-worker: ## Build reindex-worker for the local arch
	@mkdir -p $(BINARY_DIR)
	cd knowledge/reindex && go build $(GOFLAGS) -o ../$(BINARY_DIR)/reindex-worker ./cmd/reindex-worker
	@echo "✅ reindex-worker built: $(BINARY_DIR)/reindex-worker"

pi-skills-worker: ## Cross-compile skills-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd knowledge/skills && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build $(GOFLAGS) -o ../$(BINARY_DIR)/skills-worker.arm64 ./cmd/skills-worker
	@echo "✅ skills-worker (arm64) built: $(BINARY_DIR)/skills-worker.arm64"

pi-reindex-worker: ## Cross-compile reindex-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd knowledge/reindex && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build $(GOFLAGS) -o ../$(BINARY_DIR)/reindex-worker.arm64 ./cmd/reindex-worker
	@echo "✅ reindex-worker (arm64) built: $(BINARY_DIR)/reindex-worker.arm64"

pi-dispatch-worker: ## Cross-compile dispatch-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd platform/dispatch && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build $(GOFLAGS) -o ../$(BINARY_DIR)/dispatch-worker.arm64 ./cmd/dispatch-worker
	@echo "✅ dispatch-worker (arm64) built: $(BINARY_DIR)/dispatch-worker.arm64"

pi-adamaton-worker: ## Cross-compile evo-worker for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd evolve/evolve && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build $(GOFLAGS) -o ../$(BINARY_DIR)/evo-worker.arm64 ./cmd/evo-worker
	@echo "✅ evo-worker (arm64) built: $(BINARY_DIR)/evo-worker.arm64"

# pi-arxiv-skip cross-compiles the Zig sidecar (tools/arxiv-skip) for
# the Pi. The output lives at tools/arxiv-skip/zig-out/bin/arxiv-skip
# (statically linked aarch64 ELF), ready to be copied next to the
# Dockerfile in that directory for `docker build`. Static musl is on
# purpose so the alpine image has no glibc-vs-musl version-skew worry.
pi-arxiv-skip: ## Cross-compile arxiv-skip sidecar for linux/arm64 (Pi 5)
	cd knowledge/tools/arxiv-skip && zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSmall
	@echo "✅ arxiv-skip (arm64) built: tools/arxiv-skip/zig-out/bin/arxiv-skip"

.PHONY: pi-dispatch-worker pi-evo-worker pi-arxiv-skip latex2text pi-latex2text

# Zig CLI for arxiv LaTeX → JSON, replaces pandoc on the deepresearch fast path.
# Native build is used for development/benchmarking; pi target ships a static
# musl arm64 binary into the alpine sidecar image.
latex2text: ## Build latex2text for the host (development)
	cd knowledge/tools/latex2text && zig build -Doptimize=ReleaseSafe
	@mkdir -p $(BINARY_DIR)
	@cp tools/latex2text/zig-out/bin/latex2text $(BINARY_DIR)/latex2text
	@echo "✅ latex2text built: $(BINARY_DIR)/latex2text"

pi-latex2text: ## Cross-compile latex2text for linux/arm64-musl (Pi 5)
	cd knowledge/tools/latex2text && zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSmall
	@echo "✅ latex2text (arm64-musl static) built: tools/latex2text/zig-out/bin/latex2text"

pi-workers: pi-skills-worker pi-reindex-worker pi-dispatch-worker pi-evo-worker pi-arxiv-skip pi-latex2text ## Build all Pi workers + sidecars
	@echo "✅ Pi workers ready in $(BINARY_DIR)/"

# ---------------------------------------------------------------------------
# plugin-host: standalone Go service that supervises plugin subprocesses
# (gRPC over Unix sockets). See plugin-host/proto/ for the wire schema.
# ---------------------------------------------------------------------------

.PHONY: proto-gen plugin-host pi-plugin-host

proto-gen: ## Regenerate Go + Python stubs from plugin-host/proto/
	@echo "📜 Regenerating Go stubs..."
	@mkdir -p plugin-host/gen/go
	cd platform/plugin-host && PATH="$$HOME/go/bin:$$PATH" protoc \
		-I proto \
		--go_out=gen/go --go_opt=paths=source_relative \
		--go-grpc_out=gen/go --go-grpc_opt=paths=source_relative \
		proto/dr/plugin/v1/types.proto \
		proto/dr/plugin/v1/plugin.proto \
		proto/dr/plugin/v1/host.proto
	@echo "🐍 Regenerating Python stubs..."
	@mkdir -p plugin-host/gen/python
	cd platform/plugin-host && python3 -m grpc_tools.protoc \
		-I proto \
		--python_out=gen/python --grpc_python_out=gen/python \
		proto/dr/plugin/v1/types.proto \
		proto/dr/plugin/v1/plugin.proto \
		proto/dr/plugin/v1/host.proto
	@echo "✅ proto-gen done"

plugin-host: ## Build plugin-host for the local arch
	@mkdir -p $(BINARY_DIR)
	cd platform/plugin-host && go build $(GOFLAGS) -o ../$(BINARY_DIR)/plugin-host ./cmd/plugin-host
	@echo "✅ plugin-host built: $(BINARY_DIR)/plugin-host"

pi-plugin-host: ## Cross-compile plugin-host for linux/arm64 (Pi 5)
	@mkdir -p $(BINARY_DIR)
	cd platform/plugin-host && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
		go build $(GOFLAGS) -o ../$(BINARY_DIR)/plugin-host.arm64 ./cmd/plugin-host
	@echo "✅ plugin-host (arm64) built: $(BINARY_DIR)/plugin-host.arm64"

clean: ## Clean build artifacts
	@echo "🧹 Cleaning build artifacts..."
	rm -rf $(BINARY_DIR)
	go clean -cache
	@echo "✅ Clean complete"

deps: ## Download dependencies
	@echo "📦 Downloading dependencies..."
	go mod download
	go mod tidy

# Testing targets
.PHONY: test lint format test-coverage ci test-knowledge test-delegator test-platform test-deepresearch test-evolve

test: ## Run unit tests with race detector
	@echo "🧪 Running unit tests..."
	# -race catches concurrency bugs at test time; -count=1 disables the test
	# binary cache so each run actually re-executes the suite (the cache is
	# what lets a stale flaky test masquerade as "passing" across CI runs).
	go test -race -count=1 -v ./...

ci: format-check vet lint test vuln build ## Aggregate target run by CI
	@echo "✅ CI checks passed"

# format-check fails when the tree has unformatted Go files. Used in CI in
# preference to `go fmt` because fmt mutates files; check just reports.
.PHONY: format-check vet
format-check: ## Verify all Go files are gofmt-clean
	@echo "🎨 Checking formatting..."
	@unformatted=$$(gofmt -l .); \
	if [ -n "$$unformatted" ]; then \
		echo "❌ The following files are not gofmt-clean:"; \
		echo "$$unformatted"; \
		exit 1; \
	fi
	@echo "✅ All files gofmt-clean"

vet: ## Run go vet
	@echo "🔬 Running go vet..."
	go vet ./...

.PHONY: lint vuln
lint: ## Run golangci-lint (installs it if missing)
	@command -v golangci-lint >/dev/null 2>&1 || { \
		echo "Installing golangci-lint..."; \
		go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest; \
	}
	golangci-lint run ./...

vuln: ## Run govulncheck (installs it if missing)
	@command -v govulncheck >/dev/null 2>&1 || \
		go install golang.org/x/vuln/cmd/govulncheck@latest
	govulncheck ./...

format: ## Format code
	@echo "🎨 Formatting code..."
	go fmt ./...

test-coverage: ## Run tests with coverage
	@echo "📊 Running tests with coverage..."
	go test -cover ./...

dev-setup: deps ## Setup development environment
	@echo "🔧 Setting up development environment..."
	@mkdir -p $(BINARY_DIR)
	@echo "✅ Development environment ready"

# Demo targets
.PHONY: run-worker demo example

run-worker: build-worker ## Run the worker
	@echo "🚀 Starting worker..."
	./$(WORKER_BINARY)

demo: enhanced-demo ## Alias for enhanced-demo

example: build ## Run example PR review with 12 AI agents
	@echo "Running example PR review with 12 AI agents..."
	./$(STARTER_BINARY) --pr 1 --owner octocat --repo Hello-World

# Performance testing
perf-test: ## Run performance tests with all 12 agents
	@echo "Running performance tests..."
	go test -v -bench=. -benchtime=10s ./...

load-test: ## Simulate high load with multiple workers
	@echo "Starting load test with 3 workers..."
	@bash -c 'for i in 1 2 3; do \
		echo "Starting worker $$i..."; \
		WORKER_ID=$$i ./$(WORKER_BINARY) & \
	done'
	@echo "Load test started. Monitor with 'ps aux | grep worker'"
	@echo "Stop with 'pkill -f worker'"

# Quality checks
quality: lint test test-coverage ## Run all quality checks

pre-commit: format lint test ## Run pre-commit checks
	@echo "✅ Pre-commit checks passed"

# Documentation helpers
docs-serve: ## Serve documentation locally
	@echo "Documentation available at:"
	@echo "- README.md: Main documentation"
	@echo "- docs/DEPLOYMENT.md: Production deployment"
	@echo "- docs/TROUBLESHOOTING.md: Common issues"
	@echo "- PROJECT_STATUS.md: Current status"
	@echo "- DEVELOPMENT_GUIDE.md: Development workflow"

agent-summary: ## Show summary of all 12 AI agents
	@echo "🤖 GoGents AI Agent Arsenal (12 Specialized Reviewers)"
	@echo "=================================================="
	@echo ""
	@echo "CRITICAL AGENTS (Weight: 2.0, Required: ✅):"
	@echo "  🔒 Security Agent      - Vulnerability detection"
	@echo "  ⚖️  Compliance Agent   - Regulatory standards"
	@echo "  🎯 Business Logic Agent - Requirements adherence"
	@echo ""
	@echo "IMPORTANT AGENTS (Weight: 1.5, Required: ❌):"
	@echo "  ⚡ Performance Agent   - Optimization analysis"
	@echo "  🧪 Testing Agent       - Test coverage quality"
	@echo "  🏗️  Architecture Agent  - Design patterns"
	@echo "  📦 Dependencies Agent  - Supply chain security"
	@echo "  🔧 Maintainability Agent - Long-term code health"
	@echo ""
	@echo "STANDARD AGENTS (Weight: 1.0, Required: ❌):"
	@echo "  📚 Documentation Agent - Code clarity"
	@echo "  ♿ Accessibility Agent  - WCAG compliance"
	@echo "  🔍 Const Agent         - C++ const correctness"
	@echo ""
	@echo "STYLE AGENT (Weight: 0.5, Required: ❌):"
	@echo "  🎨 Style Agent         - Formatting consistency"
	@echo ""
	@echo "Total: 12 AI agents providing comprehensive code review"

# Deployment helpers
deploy-check: ## Check deployment readiness
	@echo "🚀 Deployment Readiness Check"
	@echo "============================="
	@echo -n "✓ Go modules: " && go mod verify && echo "OK" || echo "FAIL"
	@echo -n "✓ Tests: " && go test ./... >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "✓ Lint: " && golangci-lint run ./... >/dev/null 2>&1 && echo "OK" || echo "WARN"
	@echo -n "✓ Build: " && go build ./... >/dev/null 2>&1 && echo "OK" || echo "FAIL"
	@echo -n "✓ Config: " && test -f .env && echo "OK" || echo "WARN - No .env file (copy .env.example)"
	@echo -n "✓ Binaries: " && test -f $(WORKER_BINARY) && test -f $(STARTER_BINARY) && echo "OK" || echo "FAIL"

production-build: clean ## Build optimized production binaries
	@echo "DEPRECATED: ./workers/ target was for pre-fold layout; production cross-builds for the legacy combined worker no longer exist. Use pi-workers (skills/reindex/dispatch/evo) and build-starter instead." && false
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GOFLAGS) -o $(BINARY_DIR)/start_workflow-linux-amd64 ./temporal/cmd/start-workflow/
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) -o $(BINARY_DIR)/start_workflow-darwin-amd64 ./temporal/cmd/start-workflow/
	@echo "✅ Production binaries built in $(BINARY_DIR)/"

# Release helpers
version: ## Show version information
	@echo "🔍 Version Information"
	@echo "===================="
	@echo "Go version: $(shell go version)"
	@echo "Build target: $(GOOS)/$(GOARCH)"
	@echo "Git commit: $(shell git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
	@echo "Git branch: $(shell git branch --show-current 2>/dev/null || echo 'unknown')"
	@echo "Build time: $(shell date -u +%Y-%m-%dT%H:%M:%SZ)"
	@echo "Total agents: 12"
	@echo "Total files: $(shell find . -name '*.go' | wc -l)"
	@echo "Total lines: $(shell find . -name '*.go' -exec wc -l {} + | tail -1 | awk '{print $$1}')"

release: clean production-build test ## Build release binaries
	@echo "🚀 Building release for $(GOOS)/$(GOARCH)..."
	@mkdir -p release
	@cp $(BINARY_DIR)/* release/ 2>/dev/null || true
	@echo "✅ Release binaries created in release/ directory"
	@echo ""
	@echo "📦 Release Contents:"
	@ls -la release/

# Monitoring helpers
# vLLM Backend Support
vllm-health: ## Check vLLM server health and status
	@echo "🤖 Checking vLLM server health..."
	@echo "Endpoint: ${VLLM_ENDPOINT:-http://localhost:8000}"
	@curl -s "${VLLM_ENDPOINT:-http://localhost:8000}/health" && echo "✅ vLLM server is healthy" || echo "❌ vLLM server is down"
	@echo ""
	@echo "Available models:"
	@curl -s "${VLLM_ENDPOINT:-http://localhost:8000}/v1/models" | jq '.data[].id' 2>/dev/null || echo "No model info available"

vllm-info: ## Show vLLM server information and capabilities
	@echo "🤖 vLLM Server Information"
	@echo "========================"
	@echo "Endpoint: ${VLLM_ENDPOINT:-http://localhost:8000}"
	@echo "Health: $(curl -s ${VLLM_ENDPOINT:-http://localhost:8000}/health | jq -r '.status' 2>/dev/null || echo 'Unknown')"
	@echo ""
	@echo "Available endpoints:"
	@curl -s "${VLLM_ENDPOINT:-http://localhost:8000}/docs" >/dev/null 2>&1 && echo "  📋 OpenAPI docs: ${VLLM_ENDPOINT:-http://localhost:8000}/docs" || echo "  No docs available"
	@echo "  🔗 Chat completions: ${VLLM_ENDPOINT:-http://localhost:8000}/v1/chat/completions"
	@echo "  🔗 Completions: ${VLLM_ENDPOINT:-http://localhost:8000}/v1/completions"
	@echo "  🔗 Models: ${VLLM_ENDPOINT:-http://localhost:8000}/v1/models"
	@echo ""
	@echo "Configuration:"
	@echo "  Max Tokens: ${GOGENTS_VLLM_MAX_TOKENS:-512}"
	@echo "  Temperature: ${GOGENTS_VLLM_TEMPERATURE:-0.1}"
	@echo "  Timeout: ${GOGENTS_VLLM_TIMEOUT:-2m}"

vllm-test: ## Test vLLM integration with a sample prompt
	@echo "🧪 Testing vLLM integration..."
	@curl -s -X POST "${VLLM_ENDPOINT:-http://localhost:8000}/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d '{
			"model": "auto",
			"messages": [
				{"role": "user", "content": "Hello, are you working? Please respond with TEST SUCCESSFUL."}
			],
			"max_tokens": 50,
			"temperature": 0.1
		}' | jq '.choices[0].message.content' && echo "✅ vLLM test successful" || echo "❌ vLLM test failed"

# vllm-benchmark uses bash brace expansion ({1..10}) and a JSON heredoc, so force bash for this recipe.
SHELL_VLLM_BENCH := /bin/bash
vllm-benchmark: SHELL := $(SHELL_VLLM_BENCH)
vllm-benchmark: ## Benchmark vLLM performance with multiple requests
	@echo "⚡ Benchmarking vLLM performance..."
	@echo "Running 10 parallel requests..."
	@time for i in {1..10}; do \
		(curl -s -X POST "$${VLLM_ENDPOINT:-http://localhost:8000}/v1/chat/completions" \
			-H "Content-Type: application/json" \
			-d '{ \
				"model": "auto", \
				"messages": [{"role": "user", "content": "Analyze: function test() { return true; }"}], \
				"max_tokens": 100, \
				"temperature": 0.1 \
			}' >/dev/null &); \
	done; wait
	@echo "✅ Benchmark complete"

vllm-agents-test: ## Test all vLLM-powered agents
	@echo "🤖 Testing vLLM-powered agents..."
	@echo "This will test the 6 enhanced vLLM agents:"
	@echo "  🔒 Security Agent (vLLM-powered)"
	@echo "  ⚖️ Compliance Agent (vLLM-powered)"
	@echo "  ⚡ Performance Agent (vLLM-powered)"
	@echo "  🧪 Testing Agent (vLLM-powered)"
	@echo "  🏗️ Architecture Agent (vLLM-powered)"
	@echo "  ♿ Accessibility Agent (vLLM-powered)"
	@make build-worker
	@echo "✅ Worker built with vLLM support"
	@echo "Run 'make enhanced-demo' to see vLLM agents in action!"



health-check: ## Perform comprehensive health check
	@echo "🏥 GoGents Health Check"
	@echo "======================="
	@echo ""
	@echo "🔧 Services:"
	@echo -n "  Temporal: " && curl -s http://localhost:7233 >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"
	@echo -n "  vLLM: " && curl -s $$VLLM_ENDPOINT >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"
	@echo -n "  MCP: " && curl -s $$MCP_SERVER_URL >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"
	@echo ""
	@echo "📊 System:"
	@echo "  Memory: $$(free -h | grep '^Mem:' | awk '{print $$3"/"$$2}' 2>/dev/null || echo 'N/A')"
	@echo "  Disk: $$(df -h . | tail -1 | awk '{print $$3"/"$$2" ("$$5")"}' 2>/dev/null || echo 'N/A')"
	@echo "  Load: $$(uptime | sed 's/.*load average: //' 2>/dev/null || echo 'N/A')"

# Git helpers
git-hooks: ## Install git hooks for development
	@echo "Installing git hooks..."
	@echo '#!/bin/bash\nmake pre-commit' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "✅ Git hooks installed"

# Enhanced Features
api-server: ## Build and run API server for web dashboard
	go build -o $(BINARY_DIR)/api-server ./dashboard/cmd/api/
	@echo "Starting API server on port 9123..."
	./$(BINARY_DIR)/api-server

run-api: build-api ## Run the API server
	@echo "🚀 Starting GoGents API server..."
	PORT=9123 ./$(BINARY_DIR)/api-server

build-api: ## Build API server binary
	go build -o $(BINARY_DIR)/api-server ./dashboard/cmd/api/

# Gitea Integration Support
build-gitea-review: ## Build Gitea review CLI tool
	go build -o $(BINARY_DIR)/gitea-review ./temporal/cmd/gitea-review/

build-gitea-webhook: ## Build Gitea webhook server
	go build -o $(BINARY_DIR)/gitea-webhook ./temporal/cmd/gitea-webhook/

build-gitea: build-gitea-review build-gitea-webhook ## Build all Gitea tools
	@echo "✅ Gitea integration tools built"

run-gitea-webhook: build-gitea-webhook ## Run Gitea webhook server
	@echo "🚀 Starting Gitea webhook server..."
	WEBHOOK_PORT=8090 ./$(BINARY_DIR)/gitea-webhook

gitea-review: build-gitea-review ## Run Gitea PR review (usage: make gitea-review PR=123 OWNER=myorg REPO=myrepo)
	@if [ -z "$(PR)" ] || [ -z "$(OWNER)" ] || [ -z "$(REPO)" ]; then \
		echo "Usage: make gitea-review PR=123 OWNER=myorg REPO=myrepo"; \
		exit 1; \
	fi
	@echo "🚀 Starting Gitea review for $(OWNER)/$(REPO)#$(PR)..."
	./$(BINARY_DIR)/gitea-review --pr $(PR) --owner $(OWNER) --repo $(REPO)

gitea-health: ## Check Gitea server connectivity
	@echo "🏍️ Checking Gitea server health..."
	@echo "Gitea URL: ${GITEA_BASE_URL:-http://localhost:3000}"
	@curl -s "${GITEA_BASE_URL:-http://localhost:3000}/api/v1/version" && echo "✅ Gitea server is healthy" || echo "❌ Gitea server is down"

gitea-demo: build-gitea ## Demo Gitea integration
	@echo "🎭 GoGents Gitea Integration Demo"
	@echo "===================================="
	@echo "Features:"
	@echo "  • Self-hosted secure code review"
	@echo "  • 12 AI agents with vLLM integration"
	@echo "  • GitHub-like PR experience"
	@echo "  • Webhook automation"
	@echo "  • Complete data sovereignty"
	@echo ""
	@echo "Usage Examples:"
	@echo "  Manual review: make gitea-review PR=123 OWNER=myorg REPO=myrepo"
	@echo "  Webhook server: make run-gitea-webhook"
	@echo "  Health check: make gitea-health"
	@echo ""
	@echo "Configuration required:"
	@echo "  GITEA_BASE_URL=https://git.company.local"
	@echo "  GITEA_TOKEN=your_gitea_token"


integration-tests: ## Run comprehensive integration tests
	@echo "🧪 Running integration tests..."
	# Note: requires a running Temporal server (see tests/integration/api_test.go).
	# The -tags=integration flag was removed because the test files do not currently
	# have a //go:build integration build constraint; re-add both together if gating is needed.
	go test -v ./tests/integration/...

performance-tests: ## Run performance and benchmark tests
	@echo "⚡ Running performance tests..."
	go test -v -bench=. -benchtime=10s ./tests/...

full-test-suite: test integration-tests performance-tests ## Run complete test suite
	@echo "✅ All tests completed"

test-knowledge: ## Run go test ./... in the knowledge sub-repo
	@echo "🧪 Testing knowledge..."
	cd knowledge && go test ./...

test-delegator: ## Run go test ./... in the delegator sub-repo
	@echo "🧪 Testing delegator..."
	cd delegator && go test ./...

test-platform: ## Run go test ./... in the platform sub-repo
	@echo "🧪 Testing platform..."
	cd platform && go test ./...

test-deepresearch: ## Run go test ./... in the deepresearch sub-repo
	@echo "🧪 Testing deepresearch..."
	cd deepresearch && go test ./...

test-evolve: ## Run go test ./... in the evolve sub-repo
	@echo "🧪 Testing evolve..."
	cd evolve && go test ./...

metrics-dashboard: ## Open metrics and performance dashboard
	@echo "📊 Opening performance dashboard..."
	@which open >/dev/null && open http://localhost:9123/performance.html || echo "Open http://localhost:9123/performance.html in your browser"

web-dashboard: ## Open main web dashboard
	@echo "🖥️ Opening web dashboard..."
	@which open >/dev/null && open http://localhost:9123/dashboard.html || echo "Open http://localhost:9123/dashboard.html in your browser"

dev-full: ## Complete development environment with API server and worker
	@echo "🚀 Starting full development environment..."
	@make build-api build-worker
	@echo "Starting API server in background..."
	@./$(BINARY_DIR)/api-server &
	@sleep 2
	@echo "Starting worker..."
	@./$(BINARY_DIR)/worker

kill-dev: ## Kill all development processes
	@echo "🛑 Stopping development processes..."
	@pkill -f "api-server" || true
	@pkill -f "worker" || true
	@echo "All processes stopped"

enhanced-demo: ## Run enhanced demo with all 12 agents (native deployment)
	@echo "🎭 Starting enhanced GoGents demo..."
	@echo "Features: 12 AI agents, Web dashboard, Real-time metrics (Native NixOS deployment)"
	@make build-api build-worker build-starter
	@echo "Starting API server..."
	@./$(BINARY_DIR)/api-server &
	@sleep 3
	@echo "Starting worker..."
	@./$(BINARY_DIR)/worker &
	@sleep 2
	@echo "Opening dashboards..."
	@make web-dashboard
	@make metrics-dashboard
	@echo "Running example PR review..."
	@./$(BINARY_DIR)/start_workflow --pr 1 --owner demo --repo enhanced-gogents

status-check: ## Check status of all GoGents processes
	@echo "📋 GoGents Process Status"
	@echo "========================"
	@echo -n "API Server: "; pgrep -f "api-server" >/dev/null && echo "✅ Running (PID: $$(pgrep -f api-server))" || echo "❌ Stopped"
	@echo -n "Worker: "; pgrep -f "worker" >/dev/null && echo "✅ Running (PID: $$(pgrep -f worker))" || echo "❌ Stopped"
	@echo -n "Temporal: "; curl -s http://localhost:7233 >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"
	@echo -n "vLLM: "; curl -s http://localhost:8000 >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"
	@echo -n "MCP: "; curl -s http://localhost:3000 >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down"

metrics-export: ## Export current metrics to JSON file
	@echo "📊 Exporting metrics..."
	@curl -s http://localhost:9123/api/v1/dashboard/stats > metrics_$(shell date +%Y%m%d_%H%M%S).json
	@echo "Metrics exported to metrics_$(shell date +%Y%m%d_%H%M%S).json"

# Native systemd deployment
systemd-install: production-build ## Install GoGents as systemd services
	@echo "🚀 Installing GoGents systemd services..."
	@echo "Creating gogents user and directories..."
	sudo useradd -r -s /bin/false gogents 2>/dev/null || true
	sudo mkdir -p /opt/gogents/{bin,logs,data}
	sudo chown -R gogents:gogents /opt/gogents
	@echo "Installing service files..."
	sudo cp systemd/*.service /etc/systemd/system/
	sudo cp systemd/gogents.target /etc/systemd/system/
	@echo "Installing binaries..."
	sudo cp $(BINARY_DIR)/api-server /opt/gogents/bin/
	sudo cp $(BINARY_DIR)/worker /opt/gogents/bin/
	sudo cp $(BINARY_DIR)/start_workflow /opt/gogents/bin/
	sudo chown gogents:gogents /opt/gogents/bin/*
	sudo chmod +x /opt/gogents/bin/*
	@echo "Enabling services..."
	sudo systemctl daemon-reload
	sudo systemctl enable gogents.target
	@echo "✅ GoGents installed! Start with: sudo systemctl start gogents.target"

systemd-start: ## Start all GoGents systemd services
	@echo "🚀 Starting GoGents services..."
	sudo systemctl start gogents.target
	@sleep 3
	sudo systemctl status gogents.target --no-pager

systemd-stop: ## Stop all GoGents systemd services
	@echo "🛑 Stopping GoGents services..."
	sudo systemctl stop gogents.target

systemd-status: ## Show status of all GoGents services
	@echo "📋 GoGents Service Status"
	@echo "========================"
	sudo systemctl status gogents.target --no-pager
	@echo ""
	@echo "Individual Services:"
	sudo systemctl list-units 'gogents*' --no-pager

systemd-logs: ## View logs from all GoGents services
	@echo "📜 GoGents Service Logs"
	@echo "======================="
	sudo journalctl -u gogents.target -f

systemd-scale: ## Scale workers (usage: make systemd-scale WORKERS=3)
	@WORKERS=$${WORKERS:-2}; \
	echo "⚡ Scaling to $$WORKERS workers..."; \
	for i in $$(seq 1 $$WORKERS); do \
		sudo systemctl enable gogents-worker@$$i.service; \
		sudo systemctl start gogents-worker@$$i.service; \
	done; \
	echo "✅ Scaled to $$WORKERS workers"

systemd-uninstall: ## Uninstall GoGents systemd services
	@echo "🗏 Uninstalling GoGents services..."
	sudo systemctl stop gogents.target 2>/dev/null || true
	sudo systemctl disable gogents.target 2>/dev/null || true
	sudo rm -f /etc/systemd/system/gogents*.service
	sudo rm -f /etc/systemd/system/gogents.target
	sudo systemctl daemon-reload
	@echo "Remove user and data with: sudo userdel gogents && sudo rm -rf /opt/gogents"

production-deploy: systemd-install systemd-start ## Complete production deployment
	@echo "🎆 GoGents production deployment complete!"
	@echo "====================================="
	@echo "Services: ✅ Running"
	@echo "Dashboard: http://localhost:9123/dashboard.html"
	@echo "Monitoring: http://localhost:9123/performance.html"
	@echo "API: http://localhost:9123/api/v1/"
	@echo ""
	@echo "Management commands:"
	@echo "  Status: make systemd-status"
	@echo "  Logs: make systemd-logs"
	@echo "  Scale: make systemd-scale WORKERS=4"
	@echo "  Stop: make systemd-stop"

# Enhanced Worker Support (Week 2)
build-enhanced-worker: ## Build enhanced worker with Week 2 capabilities
	@echo "DEPRECATED: ./workers/ target was for pre-fold layout; use skills-worker / reindex-worker / pi-dispatch-worker / pi-evo-worker instead." && false

build-health-check: ## Build worker health check utility
	go build $(GOFLAGS) -o $(BINARY_DIR)/worker-health ./temporal/cmd/worker-health/
	@echo "✅ Health check utility built"

build-budget-router: ## Build budget router service
	@mkdir -p $(BINARY_DIR)
	go build $(GOFLAGS) -o $(BINARY_DIR)/budget-router ./delegator/cmd/budget-router/
	@echo "✅ Budget router built: $(BINARY_DIR)/budget-router"

run-budget-router: build-budget-router ## Run budget router service
	@echo "🚀 Starting budget router on :8070..."
	./$(BINARY_DIR)/budget-router

budget-status: ## Check budget router status
	@curl -s http://localhost:8070/api/v1/budget/status | jq . 2>/dev/null || echo "Budget router not running"

build-delegator-mcp: ## Build the Go MCP server that absorbs the delegator
	@mkdir -p $(BINARY_DIR)
	go build $(GOFLAGS) -o $(BINARY_DIR)/delegator-mcp ./mcp/cmd/delegator-mcp/
	@echo "✅ Delegator MCP built: $(BINARY_DIR)/delegator-mcp"

run-enhanced-worker: build-enhanced-worker ## Run enhanced worker with Week 2 features
	@echo "🚀 Starting enhanced PR review worker..."
	@echo "Features: Multi-language analysis, complexity scoring, risk assessment"
	./$(BINARY_DIR)/enhanced-worker

health-check-enhanced: build-health-check ## Run comprehensive health check
	@echo "🏥 Running enhanced worker health check..."
	./$(BINARY_DIR)/worker-health

worker-info: ## Display enhanced worker configuration info
	@echo "🤖 Enhanced PR Review Worker Information"
	@echo "========================================"
	@echo "Week 2 Enhancements:"
	@echo "  ✅ Enhanced diff analysis with function extraction"
	@echo "  ✅ Multi-language detection (Go, C/C++, JS/TS, Python, Java, Rust, etc.)"
	@echo "  ✅ Critical file and test file identification"
	@echo "  ✅ Complexity scoring and risk assessment"
	@echo "  ✅ Context-aware AI prompts"
	@echo "  ✅ Rich markdown comments with metrics"
	@echo "  ✅ Intelligent merge decision logic"
	@echo ""
	@echo "Configuration:"
	@echo "  Temporal Address: ${TEMPORAL_ADDRESS:-localhost:7233}"
	@echo "  Task Queue: ${TEMPORAL_TASK_QUEUE:-pr-review}"
	@echo "  Max Concurrent Activities: ${MAX_CONCURRENT_ACTIVITIES:-10}"
	@echo "  Max Concurrent Workflows: ${MAX_CONCURRENT_WORKFLOWS:-5}"
	@echo "  vLLM Endpoint: ${VLLM_ENDPOINT:-http://vllm.local:8000/generate}"
	@echo "  MCP Server: ${MCP_SERVER_URL:-http://localhost:3000}"
	@echo "  GitHub Token: ${GITHUB_TOKEN:+[SET]}${GITHUB_TOKEN:-[NOT SET]}"

worker-deploy worker-status worker-logs worker-restart worker-stop worker-start worker-config-edit worker-config-validate:
	@echo "DEPRECATED: pre-fold native-systemd worker targets retired post-monorepo fold."
	@echo "Production workers run as docker-compose services on the Pi:"
	@echo "  cd ~/deepresearch && docker compose ps | grep worker"
	@echo "  cd ~/deepresearch && docker compose logs -f <worker>"
	@echo "Rebuild + ship from this repo via 'make pi-workers' (see pi-* targets above)."
	@false

enhanced-demo-week2: build-enhanced-worker build-health-check build-starter ## Run Week 2 enhanced demo
	@echo "🎆 GoGents Week 2 Enhanced Demo"
	@echo "==============================="
	@echo "Features:"
	@echo "  ✅ Enhanced diff analysis with function extraction"
	@echo "  ✅ Multi-language detection and categorization"
	@echo "  ✅ Critical file and test file identification"
	@echo "  ✅ Complexity scoring (1-4 scale)"
	@echo "  ✅ Risk assessment (LOW/MEDIUM/HIGH/CRITICAL)"
	@echo "  ✅ Context-aware AI prompts"
	@echo "  ✅ Rich markdown comments with detailed metrics"
	@echo "  ✅ Progressive security policies"
	@echo "  ✅ Test coverage enforcement"
	@echo ""
	@echo "Starting health check..."
	@./$(BINARY_DIR)/worker-health || echo "Health check completed with warnings"
	@echo ""
	@echo "Starting enhanced worker..."
	@./$(BINARY_DIR)/enhanced-worker &
	@sleep 3
	@echo "Running enhanced PR review..."
	@./$(BINARY_DIR)/start_workflow --pr 42 --owner demo --repo week2-features
	@echo "🎉 Week 2 demo completed!"

week2-test: build-enhanced-worker build-health-check ## Test Week 2 enhancements
	@echo "🧪 Testing Week 2 enhancements..."
	@echo "Running unit tests for enhanced activities..."
	go test -v ./activities/... -run TestEnhanced
	@echo "Running workflow tests..."
	go test -v ./workflows/... -run TestEnhanced
	@echo "Running integration tests..."
	@make health-check-enhanced
	@echo "✅ Week 2 tests completed"



load-test-realistic: ## Run realistic load test simulation
	@echo "⚡ Running realistic load test..."
	@bash -c 'for i in {1..20}; do \
		(./$(BINARY_DIR)/start_workflow --pr $$i --owner loadtest --repo batch-$$i &); \
		sleep 0.5; \
	done'
	@echo "Load test started - monitor with 'make status-check'"

stress-test: ## Run stress test with high concurrency
	@echo "💥 Running stress test..."
	@echo "Starting 5 workers..."
	@bash -c 'for i in {1..5}; do \
		WORKER_ID=stress-$$i ./$(BINARY_DIR)/worker & \
	done'
	@echo "Generating 100 concurrent requests..."
	@bash -c 'for i in {1..100}; do \
		(./$(BINARY_DIR)/start_workflow --pr $$i --owner stress --repo test-$$i &); \
	done'
	@echo "Stress test running - monitor system resources"

# Enhanced documentation management (include-based system)
docs-validate: ## Validate include-based documentation
	@echo "📚 Validating include-based documentation..."
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh validate

docs-stats: ## Show documentation statistics
	@echo "📊 Documentation Statistics"
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh stats

docs-create-missing: ## Create missing include files
	@echo "🏗️ Creating missing include files..."
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh create-missing

docs-dependency-graph: ## Generate documentation dependency graph
	@echo "🕸️ Generating dependency graph..."
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh dependency-graph

docs-check-orphans: ## Check for orphaned include files
	@echo "🔍 Checking for orphaned files..."
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh check-orphans

docs-full-check: ## Run comprehensive documentation check
	@echo "🔍 Running full documentation check..."
	@chmod +x scripts/manage-docs.sh
	./scripts/manage-docs.sh full-check

docs-help: ## Show documentation management help
	@echo "📚 Include-Based Documentation Management"
	@echo "======================================="
	@echo "The GoGents project uses modular, include-based markdown documentation."
	@echo ""
	@echo "Available Commands:"
	@echo "  docs-validate        - Validate all include statements"
	@echo "  docs-stats          - Show documentation statistics"
	@echo "  docs-create-missing - Create missing include files"
	@echo "  docs-dependency-graph - Generate dependency graph"
	@echo "  docs-check-orphans  - Check for orphaned files"
	@echo "  docs-full-check     - Run comprehensive check"
	@echo "  docs-help           - Show this help"
	@echo ""
	@echo "Documentation Structure:"
	@echo "  📄 Main files: README.md, DEVELOPMENT_GUIDE.md, PROJECT_STATUS.md"
	@echo "  📁 Components: docs/main/, docs/enhanced-worker/, docs/development/"
	@echo "  🔗 Syntax: {!docs/component/file.md!}"
	@echo ""
	@echo "For more information, see: docs/INCLUDE_SYSTEM.md"


docs-serve-enhanced: ## Serve enhanced documentation with examples
	@echo "📚 Enhanced Documentation Available:"
	@echo "====================================="
	@echo "📋 README.md: Complete project overview"
	@echo "🚀 DEVELOPMENT_GUIDE.md: Development workflow"
	@echo "🔧 docs/DEPLOYMENT.md: Production deployment"
	@echo "🐛 docs/TROUBLESHOOTING.md: Issue resolution"
	@echo "📊 PROJECT_STATUS.md: Current capabilities"
	@echo "🌐 web/dashboard.html: Interactive dashboard"
	@echo "⚡ web/performance.html: Performance monitoring"
	@echo "🧪 tests/integration/: Integration tests"
	@echo "🚀 systemd/README.md: Native deployment guide"
	@echo "🔧 systemd/*.service: Systemd service files"
	@echo ""
	@echo "💡 Quick Start: make dev-full"
	@echo "🎭 Demo Mode: make enhanced-demo"
	@echo "🚀 Production: make production-deploy"

feature-showcase: ## Showcase all enhanced features
	@echo "🌟 GoGents Enhanced Features Showcase"
	@echo "===================================="
	@echo ""
	@echo "🤖 12 AI Agents:"
	@make agent-summary
	@echo ""
	@echo "🖥️ Web Interfaces:"
	@echo "  • Interactive Dashboard (dashboard.html)"
	@echo "  • Real-time Performance Monitor (performance.html)"
	@echo "  • REST API Server (:9123/api/v1/)"
	@echo ""
	@echo "📊 Metrics & Monitoring:"
	@echo "  • Real-time performance tracking"
	@echo "  • Agent success rate monitoring"
	@echo "  • System health dashboards"
	@echo "  • Comprehensive alerting"
	@echo "  • Native NixOS systemd integration"
	@echo ""
	@echo "🧪 Testing & Quality:"
	@echo "  • Integration test suite"
	@echo "  • Performance benchmarks"
	@echo "  • Load testing capabilities"
	@echo "  • Stress testing tools"
	@echo ""
	@echo "🚀 Native Deployment:"
	@echo "  • NixOS systemd services"
	@echo "  • Temporal ScyllaDB backend"
	@echo "  • Horizontal worker scaling"
	@echo "  • Production-ready configuration"
	@echo "  • One-command deployment: make production-deploy"
	@echo "  • Service management: systemctl"
	@echo "  • Resource isolation and limits"
	@echo ""
	@echo "🚀 Ready to deploy in production!"

# =============================================================================
# Postgres (paradedb image, pg_search + pgvector pre-installed)
# =============================================================================
# Phase 0 of the sqlite→postgres migration. The compose overlay lives at
# docker-compose.postgres.yml; the gogents-network it joins is created by
# the base docker-compose.yml — bring that up at least once first.
.PHONY: pg-up pg-down pg-nuke pg-shell pg-logs pg-status test-pg
PG_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.postgres.yml

pg-up: ## Bring up the dev postgres container (paradedb image)
	@docker network inspect gogents-network >/dev/null 2>&1 || docker network create gogents-network
	$(PG_COMPOSE) up -d postgres
	@echo "Waiting for postgres to accept connections..."
	@$(PG_COMPOSE) exec -T postgres pg_isready -U $${POSTGRES_USER:-gogents} -d $${POSTGRES_DB:-gogents} -t 30 || \
		(echo "postgres failed to come up; see: make pg-logs"; exit 1)
	@echo "OK — postgres reachable at localhost:$${POSTGRES_HOST_PORT:-5433}"

pg-down: ## Stop postgres (keeps the volume)
	$(PG_COMPOSE) stop postgres

pg-nuke: ## Stop postgres AND remove the data volume (destroys all data)
	$(PG_COMPOSE) down -v postgres

pg-shell: ## Open a psql shell in the postgres container
	$(PG_COMPOSE) exec postgres psql -U $${POSTGRES_USER:-gogents} -d $${POSTGRES_DB:-gogents}

pg-logs: ## Tail postgres container logs
	$(PG_COMPOSE) logs -f --tail=200 postgres

pg-status: ## Show postgres container state + installed extensions
	@$(PG_COMPOSE) ps postgres
	@$(PG_COMPOSE) exec -T postgres psql -U $${POSTGRES_USER:-gogents} -d $${POSTGRES_DB:-gogents} \
		-c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

test-pg: ## Run tests that exercise testcontainers-backed postgres
	go test -race -count=1 ./internal/pgutil/...

# Convenience targets
dev: dev-setup build run-worker ## Complete development setup and start worker

all: clean deps build test lint ## Build everything and run all checks

super-clean: clean kill-dev ## Deep clean including Go caches and processes
	go clean -cache
	go clean -modcache
