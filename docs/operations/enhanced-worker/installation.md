### Quick Start

1. **Build the Enhanced Worker**:
   ```bash
   make build-enhanced-worker
   make build-health-check
   ```

2. **Run Health Check**:
   ```bash
   make health-check-enhanced
   ```

3. **Start Enhanced Worker**:
   ```bash
   make run-enhanced-worker
   ```

### Production Deployment

1. **Automated Deployment**:
   ```bash
   make worker-deploy
   ```

2. **Manual Configuration**:
   ```bash
   sudo nano /etc/gogents/worker.env
   ```

3. **Service Management**:
   ```bash
   # Start service
   make worker-start
   
   # Check status
   make worker-status
   
   # View logs
   make worker-logs
   
   # Restart service
   make worker-restart
   ```

### Manual Installation Steps

1. **Create User and Directories**:
   ```bash
   sudo useradd -r -s /bin/false gogents
   sudo mkdir -p /opt/gogents/{bin,logs,data}
   sudo mkdir -p /etc/gogents
   ```

2. **Build and Install Binaries**:
   ```bash
   go build -o /opt/gogents/bin/enhanced-worker ./workers/worker.go
   go build -o /opt/gogents/bin/worker-health ./cmd/worker-health.go
   sudo chown gogents:gogents /opt/gogents/bin/*
   ```

3. **Install Configuration**:
   ```bash
   sudo cp configs/worker.env.example /etc/gogents/worker.env
   sudo chown root:gogents /etc/gogents/worker.env
   sudo chmod 640 /etc/gogents/worker.env
   ```

4. **Install and Enable Service**:
   ```bash
   sudo cp systemd/pr-review-worker.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable pr-review-worker
   sudo systemctl start pr-review-worker
   ```
