# /thearray/gogents/docs/main/vllm-integration.md
## Enhanced vLLM Integration

### OpenAI-Compatible API
GoGents uses vLLM's OpenAI-compatible chat completions endpoint for enhanced performance:

```bash
# vLLM endpoint
POST /v1/chat/completions

# Health check
GET /health

# Available models
GET /v1/models
```

### Agent Enhancement
**6 agents now use vLLM** with specialized system prompts:

- 🔒 **Security Agent** - Advanced vulnerability detection
- ⚖️ **Compliance Agent** - Regulatory standards analysis
- ⚡ **Performance Agent** - Optimization analysis
- 🧪 **Testing Agent** - Coverage and quality review
- 🏗️ **Architecture Agent** - Design pattern analysis
- ♿ **Accessibility Agent** - WCAG compliance review

### Configuration
```bash
# vLLM server settings (vLLM native /generate endpoint)
VLLM_ENDPOINT=http://localhost:8000/generate
GOGENTS_VLLM_MAX_TOKENS=512
GOGENTS_VLLM_TEMPERATURE=0.1
GOGENTS_VLLM_TIMEOUT=2m

# Per-agent configuration
GOGENTS_AGENTS_SECURITY_MAX_TOKENS=768
GOGENTS_AGENTS_COMPLIANCE_TEMPERATURE=0.05
```

### Response Format
All vLLM agents use structured responses:
```
VERDICT: [PASS/FAIL/WARNING]
CONFIDENCE: [0.0-1.0]
SEVERITY: [LOW/MEDIUM/HIGH/CRITICAL]
RATIONALE: [One sentence summary]
DETAILS: [Specific issues, one per line]
```

### Management Commands
```bash
# Check vLLM health
make vllm-health

# Test integration
make vllm-test

# Benchmark performance
make vllm-benchmark

# Test all vLLM agents
make vllm-agents-test
```

### Fallback System
Automatic fallback to original implementation if vLLM fails:
- Graceful degradation
- No service interruption
- Comprehensive error logging
- Health monitoring integration
