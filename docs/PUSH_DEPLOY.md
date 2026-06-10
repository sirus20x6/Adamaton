# Push Deploy

## What this is

Push-based replacement for the old `make pi-X` + `docker save | gzip | scp | docker load` shuffle. The workstation runs a private container registry, each Pi runs a small `deploy-agent` HTTP service, and `bin/adam ship <host> <service>` builds, pushes, and triggers a per-service restart in one command. No tarballs over wifi, no per-service ssh, no GitHub Actions arm64 matrix.

## Architecture

The workstation hosts a `registry:2` container on `10.0.4.37:5000`. Every Pi's docker daemon trusts that registry as an insecure (HTTP) source, allow-listed in `/etc/docker/daemon.json`. Each Pi runs `deploy-agent` (Go, ~250 LOC) which binds to `:9128` and is fronted by the host's existing Caddy under `/deploy/*`. The agent validates a bearer token, rewrites the matching `ADAMATON_<SVC>_TAG=` line in `~/Adamaton-deploy/image-tags.env`, then runs `docker compose pull <svc> && docker compose up -d <svc>`. On the workstation, `bin/adam ship` does build+push+POST in sequence; `bin/adam ship-self` upgrades the agent itself via ssh (the agent refuses to redeploy itself).

```
   workstation (10.0.4.37)                   pi5.lan / pi5-speaker.lan / blackwell.lan
   +-------------------------+                +----------------------------------------+
   |  bin/adam ship          |  docker push   |  Caddy :443 ---/deploy/*--> :9128      |
   |    docker buildx build  +--------------->|                                        |
   |    HTTPS POST /restart  |                |  deploy-agent (Go)                     |
   |                         |  HTTPS+bearer  |    /workdir/image-tags.env (rewrite)   |
   |  registry:2 :5000  <----+----------------+    docker compose pull/up -d           |
   |    /var/lib/registry    |  docker pull   |    /var/run/docker.sock (root-equiv)   |
   +-------------------------+                +----------------------------------------+
```

## One-time bootstrap

The fast path (recommended): `bin/adam bootstrap <host>` automates everything below from "Each Pi: trust the registry" through "Verify". Manual steps below remain authoritative for debugging or running each step in isolation.

### Quick path

```bash
# Workstation: start the registry once (still manual):
docker run -d --restart=unless-stopped --name adamaton-registry \
  -p 5000:5000 -v adamaton-registry-data:/var/lib/registry registry:2

# Workstation: bootstrap the agent on each Pi (idempotent — safe to re-run):
bin/adam bootstrap pi5
bin/adam bootstrap pi5-speaker
bin/adam bootstrap blackwell

# Workstation: switch each Pi off the bootstrap-tagged image onto a
# proper registry-tagged build:
bin/adam ship-self pi5
bin/adam ship-self pi5-speaker
bin/adam ship-self blackwell
```

What `bootstrap` does, in order:
1. `ssh <host>.lan` reachability check (must be passwordless).
2. Confirm workstation registry answers at `${WORKSTATION_IP}:5000/v2/_catalog`.
3. Idempotent `/etc/docker/daemon.json` insecure-registry edit + `systemctl restart docker` (needs `sudo` on the host).
4. Read or mint `DEPLOY_AGENT_TOKEN` on the Pi.
5. Copy `image-tags.env.example` → `image-tags.env` if absent; pin `ADAMATON_DEPLOY_AGENT_TAG=bootstrap`.
6. Build the agent locally (`--load`, arm64), `docker save | ssh docker load`.
7. Retag locally on the Pi with the registry prefix so the compose image ref resolves.
8. `docker compose up -d deploy-agent`, poll `/deploy/health` (30s).
9. Append/update `~/.adamaton/ship.env` with the token + `WORKSTATION_IP`.

After bootstrap, the agent is running on a **locally-loaded** image with tag `bootstrap` — not in the registry. Run `bin/adam ship-self <host>` to switch onto a registry-tagged build so subsequent `bin/adam ship` calls (which only know how to pull from the registry) can update it.

### Manual bootstrap

If you want to drive each step by hand (debugging the agent, custom on-host paths, etc.):

### Workstation: start the registry

```bash
docker run -d --restart=unless-stopped \
  --name adamaton-registry \
  -p 5000:5000 \
  -v adamaton-registry-data:/var/lib/registry \
  registry:2

# Verify it answers:
curl http://10.0.4.37:5000/v2/_catalog
# -> {"repositories":[]}
```

### Each Pi: trust the registry over HTTP

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{ "insecure-registries": ["10.0.4.37:5000"] }
JSON
sudo systemctl restart docker
```

The workstation's own docker daemon also needs this entry if you'll ever `docker pull` locally; not required for `bin/adam ship` which only pushes.

### Each Pi: seed `image-tags.env`

```bash
cd ~/Adamaton-deploy
cp image-tags.env.example image-tags.env
```

Every service line defaults to `main`. The agent rewrites individual lines on every push.

### Each Pi: mint a deploy-agent token

```bash
echo "DEPLOY_AGENT_TOKEN=$(openssl rand -hex 32)" >> ~/Adamaton-deploy/.env
# Print it so you can stash it on the workstation:
grep ^DEPLOY_AGENT_TOKEN ~/Adamaton-deploy/.env
```

Save the value somewhere safe. It's distinct from `EVO_API_TOKEN` and cannot be re-derived.

### Workstation: bootstrap the agent image (chicken-and-egg)

The agent can't pull itself the first time. Build locally, save, scp, load:

```bash
cd /thearray/git/Adamaton/platform/deploy-agent
docker buildx build --platform linux/arm64 \
  -t 10.0.4.37:5000/adamaton-deploy-agent:bootstrap \
  -t 10.0.4.37:5000/adamaton-deploy-agent:main \
  --push .

# Pre-seed every Pi's local docker cache so the first compose-up doesn't
# need network to the registry:
for host in pi5 pi5-speaker blackwell; do
  docker save 10.0.4.37:5000/adamaton-deploy-agent:main \
    | ssh "$host" 'docker load'
done
```

### Each Pi: bring the agent up

```bash
ssh pi5 'cd ~/Adamaton-deploy && docker compose up -d deploy-agent'
```

### Workstation: stash credentials for `bin/adam ship`

```bash
mkdir -p ~/.adamaton
cat >> ~/.adamaton/ship.env <<'EOF'
WORKSTATION_IP=10.0.4.37
DEPLOY_AGENT_TOKEN=<paste the token you minted on the Pi>
EOF
chmod 600 ~/.adamaton/ship.env
```

Each Pi has its own token in v1; if you reuse the same token across hosts you only need one entry. Otherwise add `DEPLOY_AGENT_TOKEN_PI5=`, `DEPLOY_AGENT_TOKEN_PI5_SPEAKER=`, etc. (`bin/adam ship` checks the per-host var first, then falls back to `DEPLOY_AGENT_TOKEN`).

### Verify

```bash
# Unauthenticated liveness:
curl -k https://pi5.lan/deploy/health
# -> ok

# Authenticated services list:
source ~/.adamaton/ship.env
curl -k -H "Authorization: Bearer $DEPLOY_AGENT_TOKEN" \
  https://pi5.lan/deploy/health
# -> ok  (the bearer check also succeeds; 401 means token mismatch)
```

## Day-to-day usage

Build + push + restart one service:

```bash
bin/adam ship pi5 dashboard
```

Ship multiple services to the same host in one invocation (they run in sequence; each waits for the agent to confirm the new tag is live):

```bash
bin/adam ship pi5 dashboard plugin-host
```

Ship a service to the pi5-speaker replica:

```bash
bin/adam ship pi5-speaker nano-research-worker
```

Self-update the agent itself (ssh-based; the agent can't restart itself without cutting the connection mid-call):

```bash
bin/adam ship-self pi5
```

Note that `bin/adam ship pi5 deploy-agent` is rejected at the agent with `400 deploy-agent self-update must use ssh` -- this is intentional.

### Inception caveat: a stale deploy-agent will silently ship to OLD logic

The running agent isn't refreshed by anything except `bin/adam ship-self` (it intentionally can't restart itself mid-call). So if you change deploy-agent code and merge it, `bin/adam ship pi5 evo-api` will still go through the *previous* agent until you `bin/adam ship-self pi5`. Symptom seen in practice: a service's tag gets updated in `image-tags.env` and `docker compose pull` succeeds, but the container is never recreated -- because the running agent predates the `--force-recreate` flag added in commit `8567bb87`. The fix is in the source, but only ships to the host via `ship-self`.

Rule of thumb: any merged deploy-agent change requires `bin/adam ship-self <host>` for every host before the next regular `bin/adam ship` to that host will behave per the new logic. `docker ps --filter name=deploy-agent --format '{{.Status}}'` tells you when the agent was last refreshed -- if it's been "Up N hours" since before your deploy-agent merge, you're still running the old binary.

## Reading status

| Endpoint | Method | What it returns |
|---|---|---|
| `/deploy/health` | GET | `ok` (unauth liveness) |
| `/deploy/services` | GET | MANIFEST allow-list + host name |
| `/deploy/status?service=X` | GET | `docker compose ps X --format json` |
| `/deploy/restart?service=X&tag=Y` | POST | Bump tag, pull, restart |
| `/deploy/restart-all?tag=Y` | POST | Same for every MANIFEST service (slow) |

```bash
source ~/.adamaton/ship.env
H="Authorization: Bearer $DEPLOY_AGENT_TOKEN"

# What's currently running for `dashboard`:
curl -k -H "$H" "https://pi5.lan/deploy/status?service=dashboard"

# Everything this host's agent will accept:
curl -k -H "$H" "https://pi5.lan/deploy/services"
```

## Rollback (manual, v1)

There is no `bin/adam rollback` yet. The agent only knows the tag a caller supplies, and `bin/adam ship` always derives the tag from the workstation's current submodule HEAD. To roll back:

```bash
# 1. Find the good SHA in the sub-repo:
git -C platform log --oneline -- dashboard/

# 2. Check out that SHA in the sub-repo (NOT the umbrella):
git -C platform checkout <old-sha>

# 3. Re-ship; this rebuilds the image from the old code and pushes a fresh tag:
bin/adam ship pi5 dashboard

# 4. Restore platform's HEAD when you're done:
git -C platform checkout main
```

Caveat: this rebuilds from old source rather than re-pointing the agent at a tag already in the registry. Both work, but the rebuild is slower and burns a new SHA. A future `bin/adam rollback pi5 dashboard <tag>` that POSTs `/deploy/restart` directly with a pre-existing registry tag is tracked under Future improvements.

## Registry garbage collection

Weekly, on the workstation:

```bash
docker exec adamaton-registry \
  bin/registry garbage-collect /etc/docker/registry/config.yml
```

By default this only sweeps unreferenced blobs from deleted manifests; it does NOT delete old tags. To actually reclaim disk after retagging:

```bash
docker exec adamaton-registry \
  bin/registry garbage-collect --delete-untagged \
  /etc/docker/registry/config.yml
```

GC is only safe when the registry is read-only. For a thorough sweep, edit the registry config to set `storage.maintenance.readonly.enabled: true`, restart, run GC, then revert. For a casual weekly cron during a known-idle window, running it live is fine -- worst case a concurrent push races and you re-push.

## Troubleshooting

**`buildx: failed to push: no basic auth credentials`** -- the workstation's docker daemon doesn't have `10.0.4.37:5000` in its `insecure-registries`. Even though buildx is pushing locally, the daemon validates the target. Add the same `/etc/docker/daemon.json` block on the workstation and restart docker.

**`tls: failed to verify certificate: x509: certificate signed by unknown authority`** (workstation calling the agent) -- the Pi's Caddy uses a self-signed local CA. `bin/adam ship` already passes `--insecure` to curl; if you're calling the endpoints by hand use `curl -k`.

**`service not in allow-list`** -- the host's `MANIFEST.yaml` doesn't list that service. Edit `deploy/<host>/MANIFEST.yaml`, add the service to the `services:` list, redeploy the manifest to the Pi (rsync or whatever `bin/adam deploy` uses), then `docker compose up -d deploy-agent` to make the agent reload it. The manifest is read once at agent boot.

**`deploy-agent self-update must use ssh`** -- you tried `bin/adam ship <host> deploy-agent`. Use `bin/adam ship-self <host>` instead.

**`exec format error` in a RUN step of an arm64 build** -- the qemu binfmt handler isn't registered (it clears on every workstation reboot). `bin/adam ship`/`ship-self`/`bootstrap` now self-heal this via `ensure_binfmt` before any cross-arch buildx; if you hit it from a hand-rolled buildx call, run `docker run --privileged --rm tonistiigi/binfmt --install arm64`.

**`docker compose pull` fails inside the agent after a successful `bin/adam ship`** -- the Pi can't reach the workstation registry. Check from the Pi: `curl http://10.0.4.37:5000/v2/_catalog`. Common causes: workstation rebooted and the registry didn't come back (it has `--restart=unless-stopped`, so check with `docker ps -a`); Pi's `daemon.json` was reverted; firewall in between.

**Agent returns 200 but the new tag never shows up in `/deploy/status`** -- known v1 sharp edge: the agent writes the tag BEFORE confirming the pull succeeded. If the pull failed, `image-tags.env` now references a tag that doesn't exist. Re-ship to repair; the next push overwrites the line.

## Security notes

- The bearer token is **root on the Pi**. The agent mounts `/var/run/docker.sock`, so anyone with the token can do anything docker can. Treat it like an ssh private key.
- The token is **distinct from `EVO_API_TOKEN`**. They authorise different surfaces; do not unify them.
- The registry runs **plain HTTP, LAN-only**. Do not expose `10.0.4.37:5000` to the public internet. If you ever need TLS, front it with Caddy + a real cert; do not just open the port.
- Caddy provides TLS + a stable hostname; the agent itself binds in-network on `:9128` and is unreachable from outside the host's docker network without going through Caddy.
- Service names and tags are **regex-validated** (`^[a-zA-Z0-9_-]{1,64}$` and `^[a-zA-Z0-9._-]{1,128}$`) before reaching `docker compose`, so a malicious query string can't shell-inject. Token compare is constant-time.
- One deploy at a time: a mutex inside the agent serialises every compose op. A 5-minute timeout protects against a stuck pull.

## Future improvements

- **Rollback to an existing registry tag** -- `bin/adam rollback <host> <service> <tag>` that POSTs `/deploy/restart` directly without rebuilding. Needs a tag-history endpoint on the registry side.
- **Audit log on the agent** -- append-only journal of every `/restart` call (who, what, when, success/failure, compose output tail) to `/workdir/deploy-agent.log` for post-hoc forensics.
- **Replace HTTP registry with Caddy-fronted TLS** -- removes the `insecure-registries` requirement on every Pi and makes off-LAN access conceivable. Requires deciding on a cert source (local CA vs ACME via DNS challenge).
- **Per-service token scoping** -- one token grants restart on every allow-listed service. A capability-style token that only authorises one service would shrink the blast radius of a leak.
- **Pull-then-commit ordering** -- write the new tag to `image-tags.env` only after `docker compose pull` succeeds, so a failed pull leaves the file pointing at a working tag. Trivial reorder; deferred from v1 to keep the agent small.
