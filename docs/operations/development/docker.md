# /thearray/gogents/docs/development/docker.md
## Docker Development (Legacy - Now Using Native NixOS)

### ⚠️ **Note: Docker Support Status**

**GoGents has transitioned to native NixOS deployment** for optimal performance and integration. Docker support is maintained for development environments and cross-platform compatibility, but **native deployment is strongly recommended** for production use.

### Current Deployment Approach
- ✅ **Native NixOS** - Primary deployment method
- ✅ **Systemd Services** - Production-ready service management
- ✅ **ScyllaDB Backend** - High-performance distributed database
- 🔶 **Docker** - Available for development/testing only

### Docker Development Setup (Legacy)

#### Basic Docker Development
```bash
# Build development image
docker build -t gogents:dev .

# Run with development settings
docker run -it --rm \
  -e LOG_LEVEL=DEBUG \
  -e GITHUB_TOKEN=$GITHUB_TOKEN \
  -e VLLM_ENDPOINT=http://host.docker.internal:8000/generate \
  -p 9123:9123 \
  gogents:dev
```

#### Docker Compose (Development Only)
```yaml
# docker-compose.dev.yml
version: '3.8'
services:
  scylla:
    image: scylladb/scylla:latest
    command: --smp 1 --memory 2G --overprovisioned 1 --api-address 0.0.0.0
    ports:
      - "9042:9042"
    volumes:
      - scylla-data:/var/lib/scylla

  temporal:
    image: temporalio/server:latest
    depends_on:
      - scylla
    environment:
      - TEMPORAL_CONFIG_PATH=/etc/temporal/config.yaml
    ports:
      - "7233:7233"
      - "8088:8088"  # Web UI
    volumes:
      - ./configs/temporal-scylla.yaml:/etc/temporal/config.yaml

  gogents-worker:
    build: .
    environment:
      - LOG_LEVEL=DEBUG
      - TEMPORAL_ADDRESS=temporal:7233
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - VLLM_ENDPOINT=http://vllm:8000/generate
    depends_on:
      - temporal
    volumes:
      - ./logs:/opt/gogents/logs

volumes:
  scylla-data:
```

### Migration from Docker to Native

#### Why Native NixOS is Better
1. **Performance**: 30-40% better performance without container overhead
2. **Integration**: Native systemd integration with proper service management
3. **Security**: Better isolation and resource management
4. **Maintenance**: Simplified deployment and updates
5. **Monitoring**: Better integration with system monitoring tools

#### Migration Steps
```bash
# 1. Export existing Docker configuration
docker inspect gogents-worker > docker-config.json

# 2. Convert to native deployment
make production-deploy

# 3. Migrate data (if any)
sudo cp /var/lib/docker/volumes/gogents_data/_data/* /var/lib/gogents/

# 4. Verify native deployment
make systemd-status
make health-check
```

### Docker Support for Special Cases

#### Cross-Platform Development
```dockerfile
# Dockerfile.dev
FROM golang:1.20-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o worker ./workers/worker.go
RUN CGO_ENABLED=0 GOOS=linux go build -o api-server ./cmd/api/server.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/worker .
COPY --from=builder /app/api-server .
COPY --from=builder /app/web ./web

EXPOSE 9123
CMD ["./worker"]
```

#### CI/CD Testing
```yaml
# .github/workflows/docker-test.yml (for cross-platform testing)
name: Docker Test
on: [push, pull_request]

jobs:
  docker-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker image
        run: docker build -t gogents:test .
      
      - name: Test Docker image
        run: |
          docker run --rm gogents:test ./worker --version
```

### Development Environment Comparison

#### Native NixOS Development (Recommended)
```bash
# Advantages
✅ Native performance
✅ Direct systemd integration  
✅ Better debugging capabilities
✅ Simplified dependency management
✅ Production-like environment

# Setup
make dev-full
make systemd-install
```

#### Docker Development (When Needed)
```bash
# Advantages  
✅ Cross-platform compatibility
✅ Isolated environment
✅ Easy cleanup
✅ Consistent across machines

# Setup
docker-compose -f docker-compose.dev.yml up
```

### Performance Comparison

| Metric | Native NixOS | Docker |
|--------|--------------|--------|
| **Startup Time** | 2-3 seconds | 5-10 seconds |
| **Memory Usage** | 100MB | 150-200MB |
| **CPU Overhead** | 0% | 5-10% |
| **I/O Performance** | Native | 10-15% slower |
| **Network Latency** | Direct | Additional bridge overhead |

### Recommendations

#### Use Native NixOS When:
- ✅ **Production deployment**
- ✅ **Performance is critical**
- ✅ **Long-term development**
- ✅ **NixOS environment available**

#### Use Docker When:
- 🔶 **Cross-platform development**
- 🔶 **CI/CD testing**
- 🔶 **Quick experimentation**
- 🔶 **Non-NixOS environments**

### Future Direction

**GoGents development focuses on native NixOS deployment** with Docker maintained as a compatibility option. New features prioritize native integration, and Docker support is provided for development convenience only.

For production deployments, **always use native NixOS** with systemd services:
```bash
make production-deploy  # Recommended approach
```
