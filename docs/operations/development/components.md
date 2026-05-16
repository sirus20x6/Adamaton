# /thearray/gogents/docs/development/components.md
## Key Components

### 1. Activities (`/activities/`)
Core Temporal activities that perform the actual work:

#### `pr_review_activities.go`
- **`FetchDiffActivity`**: Retrieves PR diff from GitHub/Gitea
- **`SecurityCheckActivity`**: AI-powered security analysis (vLLM)
- **`PerformanceCheckActivity`**: Performance optimization analysis (vLLM)
- **`ArchitectureCheckActivity`**: Design pattern analysis (vLLM)
- **`TestingCheckActivity`**: Test coverage analysis (vLLM)
- **`ComplianceCheckActivity`**: Regulatory compliance (vLLM)
- **`AccessibilityCheckActivity`**: WCAG compliance (vLLM)
- **`ConstCheckActivity`**: C++ const correctness
- **`MergeActivity`**: Auto-merge approved PRs
- **`CommentForHumanReviewActivity`**: Add review comments

#### `diff_analysis.go`
- **`AnalyzeDiffEnhanced()`**: Advanced diff parsing and metrics
- **`CategorizeFilesByLanguage()`**: Multi-language detection
- **`IsTestFile()`** / **`IsCriticalFile()`**: File classification

### 2. Workflows (`/workflows/`)
Temporal workflow orchestration:

#### `pr_review_workflow.go`
- **`PRReviewWorkflow`**: Main workflow orchestrating all agents
- **Risk assessment logic**: CRITICAL/HIGH/MEDIUM/LOW
- **Decision logic**: Auto-merge vs. manual review
- **Parallel agent execution** with weighted scoring

### 3. Workers (`/workers/`)
Temporal worker implementations:

#### `worker.go`
- **Worker registration**: Connects to Temporal server
- **Activity registration**: Registers all 12 agent activities
- **Health monitoring**: System health checks
- **Configuration management**: Environment-based config

### 4. Internal Packages (`/internal/`)

#### `llm/` - LLM Client Abstractions
- **`client.go`**: vLLM OpenAI-compatible client
- **`vllm_client.go`**: Enhanced vLLM integration
- **Agent-specific prompts**: Specialized system prompts
- **Fallback system**: Graceful degradation

#### `types/` - Type Definitions
- **Agent types**: All 12 agent type definitions
- **Result structures**: CheckResult, AnalysisMetrics
- **Configuration types**: AgentConfig, WorkerConfig

#### `config/` - Configuration Management
- **Environment parsing**: Centralized config loading
- **Validation**: Configuration validation
- **Defaults**: Sensible default values

#### `monitoring/` - Metrics and Monitoring
- **Performance tracking**: Agent response times
- **Success rate monitoring**: Pass/fail ratios
- **Resource monitoring**: CPU, memory, GPU usage

### 5. Command-Line Tools (`/cmd/`)

#### `start_workflow.go`
- **Workflow initiation**: Start PR review workflows
- **Parameter handling**: PR number, owner, repo
- **Error handling**: Comprehensive error reporting

#### `api/server.go`
- **REST API server**: Web dashboard backend
- **Real-time metrics**: Live system statistics
- **Worker management**: Start/stop worker control

#### `gitea_review.go`
- **Gitea integration**: Self-hosted secure review
- **Manual review CLI**: Direct PR analysis
- **Configuration**: Gitea-specific settings

#### `local_review.go`
- **Local file analysis**: Review files without GitHub/Gitea
- **Directory scanning**: Bulk file analysis
- **Git integration**: Analyze git changes locally

### 6. Web Interface (`/web/`)

#### `dashboard.html`
- **Interactive dashboard**: Real-time system monitoring
- **Agent status**: Live agent performance tracking
- **Workflow history**: Historical review data
- **Configuration UI**: Live settings management

#### `performance.html`
- **Performance monitoring**: Charts and graphs
- **Resource utilization**: CPU, memory, GPU metrics
- **Throughput analysis**: PR processing rates
- **Historical trends**: Long-term performance data

### 7. Configuration (`/configs/`)
- **Environment templates**: `.env.example` files
- **Systemd service files**: Production deployment
- **Worker configuration**: Production-ready settings

### 8. Testing (`/tests/`)
- **Unit tests**: Component-level testing
- **Integration tests**: End-to-end workflow testing
- **Performance tests**: Benchmarking and load testing
- **Mock services**: Testing infrastructure

### Component Interaction Flow
```
CLI/Webhook → Temporal → Worker → Activities → vLLM/MCP → Results → Decision → GitHub/Gitea
     ↓              ↓         ↓         ↓          ↓        ↓         ↓           ↓
  Parameters   Orchestration Tasks   Analysis   AI/API   Scoring  Merge/Comment Response
```
