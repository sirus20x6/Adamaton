# /thearray/gogents/docs/VLLM_INTEGRATION.md
# vLLM Backend Integration

GoGents now supports **native vLLM integration** using the OpenAI-compatible API endpoints for enhanced performance and reliability.

## 🚀 **vLLM Integration Features**

### **OpenAI-Compatible API**
- **Chat Completions**: `/v1/chat/completions` endpoint for modern conversation format
- **System Prompts**: Enhanced agent prompts with role-based context
- **Structured Responses**: Consistent agent response parsing
- **Automatic Fallback**: Falls back to original implementation if vLLM fails

### **Enhanced Agent Performance**
- **Optimized Prompts**: Role-specific system prompts for each agent type
- **Better Context**: Chat-based conversation format improves understanding
- **Parallel Processing**: Multiple agents can utilize vLLM concurrency
- **Token Efficiency**: Optimized token usage per agent

## 📋 **Supported Endpoints**

Based on your vLLM server logs, the following endpoints are available:

### **Core API Endpoints**
```bash
# Health check
GET /health

# Models information  
GET /v1/models

# Chat completions (used by GoGents)
POST /v1/chat/completions

# Standard completions
POST /v1/completions

# Documentation
GET /docs
GET /openapi.json
```

### **Additional Endpoints**
```bash
# Utility endpoints
POST /tokenize
POST /detokenize
GET /load
POST /ping

# Specialized endpoints
POST /v1/embeddings
POST /pooling
POST /classify
POST /score
POST /rerank
```

## ⚙️ **Configuration**

### **Environment Variables**
```bash
# vLLM server endpoint (native /generate path)
VLLM_ENDPOINT=http://localhost:8000/generate

# Global vLLM settings
GOGENTS_VLLM_MAX_TOKENS=512
GOGENTS_VLLM_TEMPERATURE=0.1
GOGENTS_VLLM_TIMEOUT=2m

# Per-agent settings (example for security agent)
GOGENTS_AGENTS_SECURITY_MAX_TOKENS=512
GOGENTS_AGENTS_SECURITY_TEMPERATURE=0.1
```

### **Agent-Specific Configuration**
Each agent can have individual vLLM settings:
- **Max Tokens**: Customizable per agent (256-768 tokens)
- **Temperature**: Agent-specific creativity (0.1-0.3)
- **System Prompts**: Specialized prompts per agent type

## 🤖 **Enhanced Agents**

### **vLLM-Powered Agents**
These agents use the new vLLM chat completions API:

1. **🔒 VLLMSecurityCheckActivity** - Advanced security vulnerability detection
2. **⚡ VLLMPerformanceCheckActivity** - Performance optimization analysis  
3. **🏗️ VLLMArchitectureCheckActivity** - Software architecture review
4. **🧪 VLLMTestingCheckActivity** - Test coverage and quality analysis
5. **⚖️ VLLMComplianceCheckActivity** - Regulatory compliance checking
6. **♿ VLLMAccessibilityCheckActivity** - WCAG and accessibility review

### **Fallback Agents**
These agents use the original implementation:
- **Const Correctness** - C++ const correctness checking
- **Documentation** - Code documentation analysis
- **Dependencies** - Dependency vulnerability scanning
- **Style** - Code formatting and style checking
- **Maintainability** - Long-term code health analysis
- **Business Logic** - Requirements adherence checking

## 🛠️ **Management Commands**

### **Health & Status**
```bash
# Check vLLM server health
make vllm-health

# Get detailed vLLM information
make vllm-info

# Test basic vLLM functionality  
make vllm-test
```

### **Performance Testing**
```bash
# Benchmark vLLM performance
make vllm-benchmark

# Test all agents with vLLM
make vllm-agents-test

# Complete system demo with vLLM
make enhanced-demo
```

## 📊 **Performance Benefits**

### **Improved Agent Quality**
- **Better Context Understanding**: Chat format provides clearer context
- **Role-Specific Analysis**: System prompts optimized per agent
- **Consistent Formatting**: Structured response parsing
- **Enhanced Accuracy**: Better model utilization

### **System Performance**
- **Parallel Processing**: Multiple agents can run concurrently
- **Efficient Batching**: vLLM's automatic request batching
- **GPU Utilization**: Optimal use of your GPU resources
- **Faster Responses**: Direct API calls without overhead

## 🔧 **Technical Implementation**

### **vLLM Client Structure**
```go
// Enhanced activities with vLLM support
enhancedActivities := activities.NewEnhancedActivities(cfg, logger)

// vLLM-powered agents (preferred)
w.RegisterActivity(enhancedActivities.VLLMSecurityCheckActivity)
w.RegisterActivity(enhancedActivities.VLLMPerformanceCheckActivity)
// ... other enhanced agents

// Fallback to original implementation if needed
w.RegisterActivity(enhancedActivities.ConstCheckActivity)
// ... other fallback agents
```

### **Request Format**
```json
{
  "model": "auto",
  "messages": [
    {
      "role": "system", 
      "content": "You are a SECURITY EXPERT. Focus on: SQL injection, XSS..."
    },
    {
      "role": "user",
      "content": "Analyze this code diff:\n\n```diff\n...\n```"
    }
  ],
  "max_tokens": 512,
  "temperature": 0.1,
  "top_p": 0.95,
  "stream": false
}
```

### **Response Parsing**
```
VERDICT: [PASS/FAIL/WARNING]
CONFIDENCE: [0.0-1.0]
SEVERITY: [LOW/MEDIUM/HIGH/CRITICAL]
RATIONALE: [One sentence summary]
DETAILS: [Specific issues found, one per line]
```

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Connection Errors**
```bash
# Check if vLLM is running
make vllm-health

# Verify endpoint configuration
echo $VLLM_ENDPOINT

# Test manual connection
curl http://localhost:8000/health
```

#### **Model Loading Issues**
```bash
# Check available models
curl http://localhost:8000/v1/models

# Verify model loading in vLLM logs
journalctl -u vllm-server -f
```

#### **Performance Issues**
```bash
# Monitor vLLM performance
make vllm-benchmark

# Check GPU usage
nvidia-smi

# Monitor system resources
htop
```

### **Fallback Behavior**
If vLLM fails, GoGents automatically falls back to the original implementation:
```
2025-06-08 06:52:26 [ERROR] vLLM request failed: connection refused
2025-06-08 06:52:26 [INFO] Falling back to original implementation
2025-06-08 06:52:27 [INFO] Security check completed using fallback
```

## 🎯 **Next Steps**

1. **Verify vLLM Status**: `make vllm-health`
2. **Test Integration**: `make vllm-test`  
3. **Run Full Demo**: `make enhanced-demo`
4. **Monitor Performance**: `make vllm-benchmark`
5. **Deploy Production**: `make production-deploy`

## 📈 **Performance Metrics**

With your current vLLM setup:
- **Model Loading**: ~471 seconds (one-time)
- **Memory Usage**: ~18 GiB VRAM
- **KV Cache**: 159,440 tokens
- **Concurrency**: 1.22x for 131,072 tokens per request

**Expected GoGents Performance**:
- **Agent Response Time**: 2-5 seconds per agent
- **Parallel Processing**: Up to 12 agents simultaneously
- **Total Review Time**: 30-60 seconds per PR
- **Throughput**: 50-100 PRs/hour with single worker

---

**🎉 Your vLLM integration is ready! Enhanced AI agents will provide better code review quality with improved performance.**
