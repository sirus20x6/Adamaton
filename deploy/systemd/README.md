# /thearray/git/evo/systemd/README.md
# GoGents Systemd Services

This directory contains systemd service files for deploying GoGents natively on NixOS or any Linux system with systemd.

## Service Files

- **`evo.target`** - Main target that starts all GoGents services
- **`evo-api.service`** - Web dashboard and REST API server
- **`evo-worker@.service`** - Template for worker instances (supports multiple workers)

## Installation

1. **Create GoGents user and directories:**
```bash
sudo useradd -r -s /bin/false evo
sudo mkdir -p /opt/evo/{bin,logs,data}
sudo chown -R evo:evo /opt/evo
```

2. **Copy service files:**
```bash
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/evo.target /etc/systemd/system/
```

3. **Install binaries:**
```bash
# Build binaries
make production-build

# Copy to system location
sudo cp bin/api-server /opt/evo/bin/
sudo cp bin/worker /opt/evo/bin/
sudo cp bin/start_workflow /opt/evo/bin/
sudo chown evo:evo /opt/evo/bin/*
sudo chmod +x /opt/evo/bin/*
```

4. **Enable and start services:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable evo.target
sudo systemctl start evo.target
```

## Managing Services

### Start/Stop All Services
```bash
sudo systemctl start evo.target
sudo systemctl stop evo.target
```

### Individual Services
```bash
# API Server
sudo systemctl start evo-api.service
sudo systemctl status evo-api.service

# Workers (supports multiple instances)
sudo systemctl start evo-worker@1.service
sudo systemctl start evo-worker@2.service
sudo systemctl start evo-worker@3.service
```

### Scaling Workers
```bash
# Add more workers
sudo systemctl enable evo-worker@3.service
sudo systemctl start evo-worker@3.service

# Stop specific worker
sudo systemctl stop evo-worker@2.service
```

### View Logs
```bash
# All GoGents services
journalctl -u evo.target -f

# API Server only
journalctl -u evo-api.service -f

# Specific worker
journalctl -u evo-worker@1.service -f

# All workers
journalctl -u 'evo-worker@*' -f
```

## Configuration

### Environment Variables
Edit the service files to customize environment variables:
- `VLLM_ENDPOINT` - vLLM server endpoint
- `MCP_SERVER_URL` - GitHub MCP server URL
- `LOG_LEVEL` - Logging level (debug, info, warn, error)
- `GOGENTS_WORKFLOW_PASS_THRESHOLD` - Agent pass threshold

### Resource Limits
Adjust resource limits in service files:
- `MemoryMax` - Maximum memory usage
- `CPUQuota` - CPU usage percentage
- `TasksMax` - Maximum number of tasks

### Security
Services run with restricted permissions:
- Dedicated `evo` user
- Read-only system access
- Network restrictions
- No new privileges

## Monitoring

### Service Status
```bash
systemctl status evo.target
systemctl list-units 'evo*'
```

### Resource Usage
```bash
systemctl show evo-api.service --property=MemoryCurrent
systemctl show evo-worker@1.service --property=CPUUsageNSec
```

### Web Dashboard
Access the web dashboard at: http://localhost:9123/dashboard.html

### Metrics API
Access metrics via REST API: http://localhost:9123/api/v1/dashboard/stats

## Troubleshooting

### Service Won't Start
1. Check service status: `systemctl status service-name`
2. View logs: `journalctl -u service-name`
3. Verify binary permissions: `ls -la /opt/evo/bin/`
4. Check dependencies: `systemctl list-dependencies evo.target`

### High Resource Usage
1. Monitor resource usage: `systemctl status evo-worker@1`
2. Adjust limits in service files
3. Scale down workers if needed
4. Check vLLM server performance

### Network Issues
1. Verify Temporal server: `curl http://localhost:7233`
2. Check vLLM endpoint: `curl http://localhost:8000`
3. Test MCP server: `curl http://localhost:3000`
4. Review network restrictions in service files

## NixOS Integration

For NixOS, add to your `configuration.nix`:

```nix
{
  # Create evo* user
  users.users.evo = {
    isSystemUser = true;
    group = "evo";
    home = "/opt/evo";
    createHome = true;
  };
  users.groups.evo = {};

  # Install systemd services
  systemd.services = {
    evo-api = {
      description = "GoGents API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "temporal.service" ];
      serviceConfig = {
        Type = "exec";
        User = "evo";
        Group = "evo";
        ExecStart = "/opt/evo/bin/api-server";
        Restart = "always";
        # ... other config from service file
      };
    };
    # Add worker services similarly
  };
}
```

## Production Recommendations

1. **Use multiple workers** for high-throughput repositories
2. **Monitor resource usage** and adjust limits accordingly
3. **Set up log rotation** for long-running deployments
4. **Configure firewall** to restrict access to necessary ports
5. **Use systemd timers** for maintenance tasks
6. **Set up monitoring** with Prometheus/Grafana integration
7. **Regular backups** of ScyllaDB keyspace
8. **Security updates** for all dependencies
