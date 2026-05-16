# /thearray/gogents/docs/development/architecture.md
## Architecture Overview

### System Components
```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub/Gitea                           │
│                 (PR Events & API)                          │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Temporal Server                           │
│        (Workflow Orchestration + ScyllaDB)                │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              GoGents Worker + API Server                   │
│  ┌───────────────────┐    ┌─────────────────────────────── │
│  │  PR Workflow      │    │    Web Dashboard              │ │
│  │ ┌───────────────┐ │    │  • REST API (:9123)          │ │
│  │ │ 12 AI Agents  │ │◄───┤  • Real-time Monitoring      │ │
│  │ │ (Parallel)    │ │    │  • Performance Metrics       │ │
│  │ └───────────────┘ │    │  • Configuration UI           │ │
│  │  Risk Assessment │    │                               │ │
│  │  Merge Decision   │    │                               │ │
│  └───────────────────┘    └─────────────────────────────── │
└─────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────┐              ┌─────────────────┐
│   vLLM Server   │              │   GitHub MCP    │
│ (AI Processing) │              │ (API Gateway)   │
│   6 Enhanced    │              │  PR Management  │
│     Agents      │              │                 │
└─────────────────┘              └─────────────────┘
```

### Data Flow
1. **PR Event** → Webhook → Start Workflow
2. **Fetch Diff** → GitHub/Gitea API → Parse Changes
3. **Analyze Code** → 12 Agents (Parallel) → Generate Results
4. **Risk Assessment** → Complexity + Agent Results → Decision
5. **Action** → Auto-merge OR Comment for Review

### Agent Architecture
- **6 vLLM-Enhanced Agents**: Security, Compliance, Performance, Testing, Architecture, Accessibility
- **6 Traditional Agents**: Dependencies, Maintainability, Documentation, Business Logic, Const, Style
- **Parallel Execution**: All agents run simultaneously
- **Weighted Scoring**: Critical agents have higher influence
- **Fallback System**: Graceful degradation if services fail
