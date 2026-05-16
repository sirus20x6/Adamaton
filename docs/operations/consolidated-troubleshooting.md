# Consolidated Troubleshooting Guide

## Common Issues and Solutions

### ScyllaDB Issues
- **ScyllaDB not accessible**:
  ```bash
  sudo systemctl status scylla-server
  nc -z localhost 9042
  ```
- **Schema initialization**:
  ```bash
  ./setup-scylla-schema.sh
  ```

### Temporal Issues
- **Temporal server not starting**:
  ```bash
  tail -f ~/.local/temporal/temporal-dev.log
  ./_legacy/setup-temporal.sh  # LEGACY — Scylla-era setup, retired
  ```

### Configuration Issues
- **Validate configuration**:
  ```bash
  make worker-config-validate
  ```
- **Update configuration**:
  ```bash
  sudo nano /etc/gogents/worker.env
  sudo systemctl restart gogents-worker@.service
  ```

### vLLM Integration
- **Endpoint accessibility**:
  ```bash
  echo $VLLM_ENDPOINT
  curl $VLLM_ENDPOINT
  ```

## Advanced Troubleshooting
- **Enable debug logging**:
  ```bash
  LOG_LEVEL=debug make run-worker
  ```
- **Check service dependencies**:
  ```bash
  systemctl list-dependencies gogents.target
  ```

## Getting Help
- Check project documentation
- Search GitHub issues
- Join community discussions