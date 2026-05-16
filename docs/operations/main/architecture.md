<!-- Port 9123: the API server moved off 8080 in audit pass 9. Port 8080 is banned in this project per CLAUDE.md (collides with too many local services). -->

┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                           │
│ (triggers workflow on PR events)                           │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│            Temporal Server (ScyllaDB Backend)              │
│            (orchestration, state, retries)                 │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                Go Worker + Web Dashboard                   │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   PR Workflow   │    │       Web Interface            │ │
│  │                 │    │  • Interactive Dashboard       │ │
│  │ 1. Fetch Diff   │    │  • Performance Monitoring      │ │
│  │ 2. 12 AI Agents │◄───┤  • REST API (port 9123)       │ │
│  │ 3. Score & Vote │    │  • Real-time Metrics          │ │
│  │ 4. Merge/Comment│    │                                │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────┐              ┌─────────────────┐
│   vLLM Server   │              │  GitHub MCP     │
│ (AI Processing) │              │ (API Gateway)   │
│ :8000/generate  │              │ :3000           │
└─────────────────┘              └─────────────────┘

**Flow**: GitHub PR → Temporal Workflow → 12 Parallel AI Agents → Weighted Scoring → Merge/Review Decision
