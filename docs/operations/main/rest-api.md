# /thearray/gogents/docs/main/rest-api.md
## REST API

### Base URL
**Production**: http://localhost:9123/api/v1/  
**Development**: http://localhost:9123/api/v1/

### Authentication
Currently using internal authentication. Future versions will support:
- API key authentication
- JWT tokens
- OAuth 2.0 integration

### Core Endpoints

#### Dashboard API
```bash
# Get system statistics
GET /api/v1/dashboard/stats
Response: {
  "workflows_processed": 142,
  "success_rate": 0.97,
  "active_workers": 3,
  "agent_performance": {...}
}

# Get real-time metrics
GET /api/v1/dashboard/metrics
Response: {
  "timestamp": "2025-06-09T12:00:00Z",
  "cpu_usage": 45.2,
  "memory_usage": 62.1,
  "active_workflows": 8
}
```

#### Worker Management
```bash
# List workers
GET /api/v1/workers
Response: [
  {
    "id": "worker-1",
    "status": "running",
    "tasks_completed": 45,
    "uptime": "2h 30m"
  }
]

# Start worker
POST /api/v1/workers/start
Body: { "worker_count": 2 }

# Stop worker
POST /api/v1/workers/stop
Body: { "worker_id": "worker-1" }
```

#### Workflow Management
```bash
# Start workflow
POST /api/v1/workflows/start
Body: {
  "pr_number": 123,
  "repo_owner": "myorg",
  "repo_name": "myrepo"
}

# Get workflow status
GET /api/v1/workflows/{workflow_id}
Response: {
  "id": "pr-review-123",
  "status": "running",
  "progress": 0.75,
  "agents_completed": ["Security", "Performance"],
  "agents_pending": ["Architecture"]
}

# List workflows
GET /api/v1/workflows?status=running&limit=50
```

#### Health Checks
```bash
# System health
GET /api/v1/health
Response: {
  "status": "healthy",
  "services": {
    "temporal": "running",
    "vllm": "running",
    "mcp": "running"
  }
}

# Component-specific health
GET /api/v1/health/vllm
GET /api/v1/health/temporal
GET /api/v1/health/github
```

### WebSocket API
Real-time updates for dashboard:

```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:9123/api/v1/ws');

// Subscribe to events
ws.send(JSON.stringify({
  type: 'subscribe',
  events: ['workflow_started', 'agent_completed', 'metrics_updated']
}));

// Receive real-time updates
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Real-time update:', data);
};
```

### Rate Limiting
- **Default**: 100 requests per minute per IP
- **Authenticated**: 1000 requests per minute
- **WebSocket**: 10 connections per IP

### Error Handling
Standard HTTP status codes with detailed error messages:

```json
{
  "error": "workflow_not_found",
  "message": "Workflow with ID 'invalid-id' not found",
  "timestamp": "2025-06-09T12:00:00Z"
}
```
