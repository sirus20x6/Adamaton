# /thearray/gogents/docs/main/systemd-deployment.md
## Native Systemd Deployment

### One-Command Production Deployment
```bash
# Complete production setup
make production-deploy
```

This command:
1. Builds optimized production binaries
2. Creates `gogents` system user
3. Installs systemd service files
4. Configures directories and permissions
5. Starts all services

### Service Architecture
```
gogents.target
├── gogents-api.service      # Web dashboard and REST API
├── gogents-worker@1.service # Primary worker
├── gogents-worker@2.service # Secondary worker (optional)
└── gogents-worker@N.service # Additional workers for scaling
```

### Service Management
```bash
# Start all services
sudo systemctl start gogents.target

# Stop all services  
sudo systemctl stop gogents.target

# Check status
make systemd-status

# View logs
make systemd-logs

# Scale workers
make systemd-scale WORKERS=4

# Restart services
sudo systemctl restart gogents.target
```

### Service Files
Located in `/etc/systemd/system/`:

#### gogents.target
```ini
[Unit]
Description=GoGents AI Code Review System
Requires=gogents-api.service
Wants=gogents-worker@1.service
After=network.target

[Install]
WantedBy=multi-user.target
```

#### gogents-api.service
```ini
[Unit]
Description=GoGents API Server
After=network.target

[Service]
Type=simple
User=gogents
Group=gogents
ExecStart=/opt/gogents/bin/api-server
Restart=on-failure
RestartSec=10
EnvironmentFile=/etc/gogents/api.env

[Install]
WantedBy=gogents.target
```

#### gogents-worker@.service
```ini
[Unit]
Description=GoGents Worker %i
After=network.target gogents-api.service

[Service]
Type=simple
User=gogents
Group=gogents
ExecStart=/opt/gogents/bin/worker
Restart=on-failure
RestartSec=10
EnvironmentFile=/etc/gogents/worker.env
Environment=WORKER_ID=%i

[Install]
WantedBy=gogents.target
```

### Directory Structure
```
/opt/gogents/
├── bin/               # Binaries
│   ├── api-server
│   ├── worker
│   └── start_workflow
├── logs/              # Log files
└── data/              # Runtime data

/etc/gogents/          # Configuration
├── worker.env
└── api.env

/var/lib/gogents/      # State data
└── temporal.db
```

### Security Configuration
- **User Isolation**: Runs as dedicated `gogents` user
- **File Permissions**: Restricted access to configuration and data
- **Resource Limits**: Memory and CPU limits via systemd
- **Network Security**: Configurable firewall rules

### Monitoring Integration
```bash
# Export metrics for monitoring
make metrics-export

# Health checks
make health-check

# Performance monitoring
journalctl -u gogents.target --since "1 hour ago"
```

### Backup and Recovery
```bash
# Backup configuration
sudo tar -czf gogents-config-backup.tar.gz /etc/gogents/

# Backup data
sudo tar -czf gogents-data-backup.tar.gz /var/lib/gogents/

# Restore from backup
sudo systemctl stop gogents.target
sudo tar -xzf gogents-config-backup.tar.gz -C /
sudo systemctl start gogents.target
```
