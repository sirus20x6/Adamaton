# /thearray/gogents/docs/main/performance.md
## Performance & Scaling

### Current Performance Metrics
- **Review Time**: 30-60 seconds per PR
- **Throughput**: 50-100 PRs/hour with single worker
- **Agent Response**: 2-5 seconds per agent
- **Memory Usage**: ~100MB per worker
- **CPU Usage**: ~10-20% per worker (excluding vLLM)

### Horizontal Scaling
```bash
# Scale workers
make systemd-scale WORKERS=4

# Load balancing
WORKER_IDENTITY=worker-1 ./bin/worker &
WORKER_IDENTITY=worker-2 ./bin/worker &
WORKER_IDENTITY=worker-3 ./bin/worker &

# Monitor distribution
temporal task-queue describe pr-review
```

### vLLM Optimization
```bash
# Optimize for your GPU
vllm serve model_name \
  --tensor-parallel-size 2 \
  --max-num-batched-tokens 8192 \
  --max-num-seqs 64 \
  --gpu-memory-utilization 0.95

# Monitor GPU usage
nvidia-smi -l 1
```

### Performance Tuning

#### Temporal Configuration
```yaml
# Increase history shards for throughput
services:
  history:
    numHistoryShards: 4  # Scale with load
  
  frontend:
    rpc:
      grpcPort: 7233
      maxMessageSize: 64MB  # For large diffs
```

#### Worker Configuration
```bash
# Concurrent processing
MAX_CONCURRENT_ACTIVITIES=20    # Increase for more parallel agents
MAX_CONCURRENT_WORKFLOWS=10     # Increase for more parallel PRs

# Timeouts
ACTIVITY_TIMEOUT_MINUTES=5      # Longer for complex analysis
VLLM_REQUEST_TIMEOUT_SECONDS=180 # Adjust for model speed
```

#### Resource Limits
```ini
# Systemd service limits
[Service]
MemoryHigh=2G
MemoryMax=4G
CPUQuota=200%  # 2 CPU cores max
TasksMax=1000
```

### Performance Monitoring
```bash
# Real-time metrics
make status-check

# Performance dashboard
make metrics-dashboard

# Export metrics
make metrics-export

# Benchmark testing
make vllm-benchmark
make load-test-realistic
```

### Optimization Strategies

#### 1. Agent Optimization
- **Fast Models**: Use GPT-4o-mini for simple checks
- **Parallel Execution**: All agents run simultaneously
- **Smart Timeouts**: Shorter timeouts for quick agents
- **Result Caching**: Cache results for identical diffs

#### 2. Infrastructure Optimization
- **GPU Allocation**: Dedicated GPU for vLLM
- **SSD Storage**: Fast storage for Temporal database
- **Network**: Low-latency connection to vLLM
- **Memory**: Sufficient RAM for concurrent workflows

#### Database Optimization
```bash
# ScyllaDB optimization
# Increase connection pools
max_connections: 50

# Tune consistency levels
consistency: LOCAL_QUORUM
serial_consistency: LOCAL_SERIAL

# Optimize compaction
compaction_throughput_mb_per_sec: 256

# Monitor ScyllaDB performance
cqlsh -e "SELECT * FROM system.compaction_history LIMIT 10;"
nodetool status
nodetool tablestats temporal
```

### Scaling Architecture
```
Load Balancer
    ↓
┌─────────────────────────────────────┐
│  Multiple GoGents API Instances    │
│  (Stateless, can scale infinitely) │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│      Temporal Cluster              │
│  (Handles workflow orchestration)  │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│    Multiple Worker Instances       │
│ (Auto-scale based on queue depth)  │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│       vLLM Cluster                 │
│  (GPU-accelerated LLM processing)  │
└─────────────────────────────────────┘
```

### Performance Testing
```bash
# Baseline performance
make performance-tests

# Load testing
make load-test-realistic

# Stress testing
make stress-test

# vLLM benchmarking
make vllm-benchmark
```

### Monitoring and Alerting
- **CPU/Memory**: System resource monitoring
- **Queue Depth**: Temporal task queue monitoring
- **Response Times**: Agent performance tracking
- **Error Rates**: Failure rate monitoring
- **GPU Utilization**: vLLM performance monitoring

### Troubleshooting Performance
1. **High Memory Usage**: Check for goroutine leaks
2. **Slow Responses**: Monitor vLLM latency
3. **Queue Buildup**: Scale workers or optimize agents
4. **Database Locks**: Optimize ScyllaDB configuration
5. **Network Latency**: Optimize service communication
6. **ScyllaDB Issues**: Monitor compaction and repair operations
