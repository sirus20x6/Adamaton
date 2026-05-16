# /thearray/gogents/docs/main/temporal-setup.md
## NixOS Temporal Server Setup

### Package Installation
Add Temporal to your NixOS configuration:

```nix
# /etc/nixos/configuration.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    temporal
    temporal-cli
  ];
}
```

Apply the configuration:
```bash
sudo nixos-rebuild switch
```

### ScyllaDB Configuration
Create the Temporal configuration for ScyllaDB:

```yaml
# /etc/temporal/config.yaml
persistence:
  defaultStore: scylla-default
  visibilityStore: scylla-default
  numHistoryShards: 4
  datastores:
    scylla-default:
      cassandra:
        hosts: "127.0.0.1"
        port: 9042
        keyspace: "temporal"
        maxConns: 20
        disableInitialHostLookup: false
        connectTimeout: "30s"

services:
  frontend:
    rpc:
      grpcPort: 7233
      membershipPort: 6933
      bindOnLocalHost: true
  history:
    rpc:
      grpcPort: 7234
      membershipPort: 6934
      bindOnLocalHost: true
  matching:
    rpc:
      grpcPort: 7235
      membershipPort: 6935
      bindOnLocalHost: true
  worker:
    rpc:
      grpcPort: 7239
      membershipPort: 6939
      bindOnLocalHost: true
```

### Systemd Service
Add to your NixOS configuration:

```nix
# Temporal server service with ScyllaDB backend
systemd.services.temporal-server = {
  description = "Temporal Server (ScyllaDB Backend)";
  after = [ "network.target" "scylla-server.service" ];
  wants = [ "scylla-server.service" ];
  wantedBy = [ "multi-user.target" ];
  
  serviceConfig = {
    ExecStart = "${pkgs.temporal}/bin/temporal-server start --config /etc/temporal/config.yaml";
    Restart = "on-failure";
    User = "temporal";
    Group = "temporal";
    StateDirectory = "temporal";
    StandardOutput = "journal";
    StandardError = "journal";
    # Wait for ScyllaDB to be ready
    ExecStartPre = "/bin/bash -c 'timeout 60 bash -c \"until nc -z localhost 9042; do sleep 2; done\"'";
  };
};

# Create temporal user
users.users.temporal = {
  isSystemUser = true;
  group = "temporal";
  home = "/var/lib/temporal";
  createHome = true;
};

users.groups.temporal = {};

# Enable ScyllaDB service
services.scylla = {
  enable = true;
  package = pkgs.scylla;
};

# Create config file
environment.etc."temporal/config.yaml".text = ''
  # Use the ScyllaDB configuration shown above
'';
```

### Verification
```bash
# Check ScyllaDB status
sudo systemctl status scylla-server

# Check Temporal service status
sudo systemctl status temporal-server

# Test ScyllaDB connectivity
telnet localhost 9042

# Test Temporal connectivity
curl -s http://localhost:7233

# Verify with CLI
temporal namespace describe default

# Check keyspace
cqlsh -e "DESCRIBE KEYSPACES;"
```
