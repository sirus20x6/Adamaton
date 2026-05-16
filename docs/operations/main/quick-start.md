# Quick Start Guide

> **⚠️ Historical document — pre-fold (gogents era).** The `./gogents.sh`
> orchestration script referenced throughout has moved to `_legacy/gogents.sh`
> and no longer reflects how this stack is deployed. Production now runs as
> docker-compose services on the Pi; see `dashboard/scripts/deploy-evo-api.sh`
> and the `pi-*` targets in the root Makefile for the current entry points.
> Kept here for context on the original pre-fold setup.

## 1. Clone the Repository
```bash
git clone https://github.com/your-org/gogents.git
cd gogents
```

## 2. Setup Services
```bash
# Setup ScyllaDB schema and Temporal
./gogents.sh setup

# Optional: View service status
./gogents.sh status
```

## 3. Start Services
```bash
# Start Temporal and Worker
./gogents.sh start

# Monitor logs in ~/.local/temporal/temporal-dev.log
```

## 4. Run Tests
```bash
# Run unit and integration tests
./gogents.sh test
```

## 5. Access Web Dashboard
Open `web/dashboard.html` in your browser

## Master Script Cheatsheet
```bash
# Start services in worker-only mode
./gogents.sh start -w

# Run only unit tests
./gogents.sh test -u

# Update Temporal version
./gogents.sh update 1.23.0

# Stop all services
./gogents.sh stop
```

> For detailed setup, see our [Installation Guide](installation.md)

**🌐 Web Dashboard**: http://localhost:9123/dashboard.html  
**📊 Performance Monitor**: http://localhost:9123/performance.html  
**🔗 REST API**: http://localhost:9123/api/v1/
