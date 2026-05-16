# /thearray/gogents/docs/development/production.md
## Production Deployment

### Production Readiness Checklist

#### Pre-Deployment Validation
```bash
# 1. Run complete test suite
make full-test-suite

# 2. Performance benchmarks
make performance-tests
make load-test-realistic

# 3. Security validation
make security-check
gosec ./...

# 4. Configuration validation
make worker-config-validate
make deploy-check

# 5. Build production binaries
make production-build
```

### Production Architecture

#### Recommended Production Setup
```
Load Balancer (nginx/Traefik)
    ↓
┌─────────────────────────────────────┐
│  GoGents API Server (Port 9123)    │
│  - Web Dashboard                   │
│  - REST API                        │
│  - Health Endpoints               │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│      Temporal Server               │
│  - PostgreSQL Backend             │
│  - High Availability Setup        │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│    Multiple GoGents Workers        │
│  - Horizontal Scaling              │
│  - Load Distribution               │
│  - Fault Tolerance                │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│       External Services            │
│  - vLLM Cluster (GPU-accelerated) │
│  - GitHub/Gitea API               │
│  - Monitoring Stack               │
└─────────────────────────────────────┘
```

### One-Command Deployment
```bash
# Complete production deployment
make production-deploy

# This performs:
# 1. Build optimized binaries
# 2. Create system user and directories
# 3. Install systemd service files
# 4. Configure security and permissions
# 5. Start all services
# 6. Verify deployment health
```

### Manual Production Setup

#### 1. System Preparation
```bash
# Create production user
sudo useradd -r -s /bin/false gogents
sudo mkdir -p /opt/gogents/{bin,logs,data,config}
sudo chown -R gogents:gogents /opt/gogents

# Create configuration directory
sudo mkdir -p /etc/gogents
sudo chown root:gogents /etc/gogents
sudo chmod 750 /etc/gogents
```

#### 2. Install Binaries
```bash
# Build and install production binaries
make production-build
sudo cp bin/api-server /opt/gogents/bin/
sudo cp bin/worker /opt/gogents/bin/
sudo cp bin/start_workflow /opt/gogents/bin/
sudo chown gogents:gogents /opt/gogents/bin/*
sudo chmod +x /opt/gogents/bin/*
```

#### 3. Production Configuration
```bash
# Create production configuration
sudo vim /etc/gogents/production.env

# Production settings
TEMPORAL_ADDRESS=localhost:7233
TEMPORAL_NAMESPACE=gogents-prod
TEMPORAL_TASK_QUEUE=pr-review-prod

# Security settings
GITHUB_TOKEN=ghp_prod_xxxxxxxxxxxxxxxxxxxx
API_CORS_ORIGINS=https://gogents.company.com
API_RATE_LIMIT_REQUESTS_PER_MINUTE=100

# Performance settings
MAX_CONCURRENT_ACTIVITIES=20
MAX_CONCURRENT_WORKFLOWS=10
WORKER_POOL_SIZE=4

# vLLM production endpoint
VLLM_ENDPOINT=http://vllm-cluster.internal:8000/generate
VLLM_REQUEST_TIMEOUT_SECONDS=120

# Monitoring
ENABLE_METRICS_LOGGING=true
METRICS_RETENTION_DAYS=90
LOG_LEVEL=INFO

# Security
AUTO_MERGE_RISK_THRESHOLD=HIGH
NEVER_AUTO_MERGE_SECURITY_FAILS=true
REQUIRE_ALL_PASS_FOR_CRITICAL_FILES=true
```

#### 4. Database Setup (PostgreSQL)
```bash
# Install PostgreSQL for production Temporal
sudo apt-get install postgresql postgresql-contrib

# Create Temporal database
sudo -u postgres createdb temporal_prod
sudo -u postgres createuser temporal_user

# Configure Temporal for PostgreSQL
sudo vim /etc/temporal/production.yaml

# PostgreSQL configuration
persistence:
  defaultStore: postgres
  datastores:
    postgres:
      sql:
        driverName: "postgres"
        databaseName: "temporal_prod"
        connectAddr: "localhost:5432"
        connectProtocol: "tcp"
        user: "temporal_user"
        password: "${POSTGRES_PASSWORD}"
```

### Service Configuration

#### Production Systemd Services
```ini
# /etc/systemd/system/gogents-api.service
[Unit]
Description=GoGents API Server
After=network.target temporal-server.service
Requires=temporal-server.service

[Service]
Type=simple
User=gogents
Group=gogents
ExecStart=/opt/gogents/bin/api-server
Restart=on-failure
RestartSec=10
EnvironmentFile=/etc/gogents/production.env

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/gogents/logs /opt/gogents/data

# Resource limits
MemoryHigh=1G
MemoryMax=2G
CPUQuota=100%
TasksMax=1000

[Install]
WantedBy=gogents.target
```

```ini
# /etc/systemd/system/gogents-worker@.service
[Unit]
Description=GoGents Worker %i
After=network.target gogents-api.service
PartOf=gogents.target

[Service]
Type=simple
User=gogents
Group=gogents
ExecStart=/opt/gogents/bin/worker
Restart=on-failure
RestartSec=10
EnvironmentFile=/etc/gogents/production.env
Environment=WORKER_ID=%i

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/gogents/logs /opt/gogents/data

# Resource limits
MemoryHigh=2G
MemoryMax=4G
CPUQuota=200%
TasksMax=2000

[Install]
WantedBy=gogents.target
```

### Monitoring and Observability

#### Health Monitoring
```bash
# Built-in health checks
curl http://localhost:9123/api/v1/health

# Service monitoring
systemctl status gogents.target
journalctl -u gogents.target -f

# Performance monitoring
curl http://localhost:9123/api/v1/dashboard/stats
curl http://localhost:9123/api/v1/dashboard/metrics
```

#### Prometheus Integration
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'gogents'
    static_configs:
      - targets: ['localhost:9123']
    metrics_path: '/api/v1/metrics'
    scrape_interval: 30s
```

#### Grafana Dashboard
```json
{
  "dashboard": {
    "title": "GoGents Production Metrics",
    "panels": [
      {
        "title": "Workflow Processing Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(gogents_workflows_total[5m])",
            "legend": "Workflows/sec"
          }
        ]
      },
      {
        "title": "Agent Success Rate",
        "type": "singlestat",
        "targets": [
          {
            "expr": "gogents_agent_success_rate",
            "legend": "Success Rate"
          }
        ]
      }
    ]
  }
}
```

### Security Hardening

#### Network Security
```bash
# Configure firewall
sudo ufw allow 9123/tcp  # API server
sudo ufw allow from 10.0.0.0/8 to any port 7233  # Temporal (internal only)
sudo ufw enable

# Reverse proxy configuration (nginx)
server {
    listen 443 ssl;
    server_name gogents.company.com;
    
    ssl_certificate /etc/ssl/certs/gogents.crt;
    ssl_certificate_key /etc/ssl/private/gogents.key;
    
    location / {
        proxy_pass http://localhost:9123;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://localhost:9123;
    }
}
```

#### Secret Management
```bash
# Use systemd credentials for secrets
sudo systemctl edit gogents-api.service

# Add credentials
[Service]
LoadCredential=github-token:/etc/secrets/github-token
LoadCredential=vllm-key:/etc/secrets/vllm-key

# Access in application
export GITHUB_TOKEN=$(cat ${CREDENTIALS_DIRECTORY}/github-token)
```

### Backup and Recovery

#### Automated Backups
```bash
#!/bin/bash
# /opt/gogents/scripts/backup.sh

BACKUP_DIR="/backup/gogents/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup configuration
tar -czf "$BACKUP_DIR/config.tar.gz" /etc/gogents/

# Backup Temporal database
pg_dump temporal_prod > "$BACKUP_DIR/temporal.sql"

# Backup logs and data
tar -czf "$BACKUP_DIR/data.tar.gz" /opt/gogents/logs /opt/gogents/data

# Cleanup old backups (keep 30 days)
find /backup/gogents/ -type d -mtime +30 -exec rm -rf {} +
```

#### Recovery Procedures
```bash
# Stop services
sudo systemctl stop gogents.target

# Restore configuration
sudo tar -xzf /backup/gogents/20250609_120000/config.tar.gz -C /

# Restore database
sudo -u postgres psql temporal_prod < /backup/gogents/20250609_120000/temporal.sql

# Restore data
sudo tar -xzf /backup/gogents/20250609_120000/data.tar.gz -C /

# Start services
sudo systemctl start gogents.target
```

### Performance Optimization

#### Production Tuning
```bash
# Temporal performance tuning
# Increase history shards for higher throughput
numHistoryShards: 8

# Worker optimization
MAX_CONCURRENT_ACTIVITIES=30
MAX_CONCURRENT_WORKFLOWS=15

# Database optimization
# PostgreSQL configuration
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.7
wal_buffers = 16MB
default_statistics_target = 100
```

#### Scaling Guidelines
```bash
# Scale workers based on load
make systemd-scale WORKERS=8

# Monitor queue depth
temporal task-queue describe pr-review-prod

# Auto-scaling (future enhancement)
# Scale workers based on queue depth metrics
```

### Maintenance Procedures

#### Regular Maintenance
```bash
# Weekly maintenance script
#!/bin/bash
# /opt/gogents/scripts/maintenance.sh

# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Rotate logs
sudo logrotate /etc/logrotate.d/gogents

# Cleanup old data
find /opt/gogents/data/temp -type f -mtime +7 -delete

# Database maintenance
sudo -u postgres vacuumdb --analyze temporal_prod

# Service health check
make health-check
```

#### Rolling Updates
```bash
# Zero-downtime update procedure
# 1. Build new binaries
make production-build

# 2. Stop workers gradually
for i in {4..1}; do
    sudo systemctl stop gogents-worker@$i.service
    sleep 30
done

# 3. Update binaries
sudo cp bin/* /opt/gogents/bin/

# 4. Update API server
sudo systemctl restart gogents-api.service

# 5. Start workers
for i in {1..4}; do
    sudo systemctl start gogents-worker@$i.service
    sleep 10
done

# 6. Verify deployment
make health-check
```

### Disaster Recovery

#### High Availability Setup
```bash
# Multi-region deployment
# Primary region: us-east-1
# Secondary region: us-west-2

# Database replication
# PostgreSQL streaming replication
# Temporal cluster setup with multiple nodes

# Load balancer failover
# Route traffic to healthy regions
# Automatic failover with health checks
```

#### Recovery Testing
```bash
# Monthly disaster recovery test
# 1. Simulate primary region failure
# 2. Verify automatic failover
# 3. Test data integrity
# 4. Measure recovery time
# 5. Document lessons learned
```
