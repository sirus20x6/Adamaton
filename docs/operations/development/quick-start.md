1. **Setup Environment**:
   ```bash
   cd /thearray/gogents
   chmod +x scripts/setup-dev.sh init-git.sh
   ./scripts/setup-dev.sh
   ```

2. **Configure**:
   ```bash
   # Edit .env with your GitHub token and service endpoints
   vim .env
   source .env
   ```

3. **Build & Run**:
   ```bash
   make build
   make run-worker
   
   # In another terminal:
   make run-starter ARGS="--pr 123 --owner myorg --repo myrepo"
   ```
