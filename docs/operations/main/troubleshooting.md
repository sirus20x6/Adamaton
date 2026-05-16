# Troubleshooting

> **⚠️ Historical document — pre-fold (ScyllaDB-backed Temporal era).**
> Production now runs Temporal as a docker-compose service on the Pi backed
> by Postgres. The `./reset-and-setup-schema.sh` script and `make temporal-*`
> targets referenced below target the old Scylla setup and have been retired
> to `_legacy/`. Kept here for historical context.

## Common Issues

### Temporal Connection Issues
If you encounter Temporal connection problems:

```bash
# Check Temporal status
make temporal-status

# Restart Temporal
make temporal-restart

# Reset schema if needed (LEGACY — Scylla-era)
./_legacy/reset-and-setup-schema.sh
```

### Build Issues
If builds fail:

```bash
# Clean and rebuild
make clean
make deps
make build
```

### Agent Registration Issues
If Gitea agents aren't working:

```bash
# Re-register agents
./scripts/register-gitea-agents.sh

# Check agent status
make agent-summary
```

### Performance Issues
If the system is slow:

```bash
# Check system resources
make health-check

# Monitor performance
make performance-monitor
```

For more detailed troubleshooting, see the consolidated troubleshooting guide in `docs/consolidated-troubleshooting.md`.