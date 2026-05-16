# /thearray/gogents/docs/main/prerequisites.md
## Prerequisites

### System Requirements
- **NixOS 23.x+** (tested and optimized for NixOS)
- **Go 1.20+** for development and building
- **8GB+ RAM** (16GB recommended for production)
- **20GB+ disk space** for logs and temporary files
- **sudo privileges** for systemd service installation

### External Services
- **vLLM Server** - Local or remote LLM backend
  - NVIDIA GPU with 8GB+ VRAM (24GB+ recommended)
  - CUDA 11.8+ drivers
  - Model: Llama 3.1, CodeLlama, or compatible
- **GitHub Token** - For PR access and automation
  - Scopes: `pulls:read`, `pulls:write`, `issues:write`
- **Temporal Server** - Workflow orchestration (included in setup)

### Optional Components
- **Gitea Server** - For self-hosted secure review
- **Reverse Proxy** - nginx/Traefik for production deployment
- **Monitoring Stack** - Prometheus/Grafana for observability
