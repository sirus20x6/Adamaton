# Deploy

## Hosts

| Host | Role | Compose |
|---|---|---|
| **pi5** | Main stack: postgres, temporal, knowledge backends, deepresearch, platform, frontend, caddy | `deploy/pi5/docker-compose.yml` |
| **pi5-speaker** | Replica: nano-research-worker, figure-renderer | `deploy/pi5-speaker/docker-compose.yml` |
| **blackwell** | GPU node: vLLM, evo-worker (KernelBench), distill trainer | `deploy/blackwell/compose-*.yml` |
| **workstation** | Local dev: postgres + temporal-dev only | `deploy/workstation/docker-compose.yml` |

## Bring-up

```bash
bin/adam deploy <host>
```

This runs `deploy/<host>/up.sh`, which:

1. Reads the umbrella's current submodule pins.
2. For each image that ships on `<host>`: cross-compiles the binary on the workstation, builds the arm64/amd64 OCI image, rsyncs the tar (wifi-friendly per `pi_caddy_bind_mount_inode` lesson).
3. rsyncs the host-specific compose/Caddyfile/.env from `deploy/<host>/` to `<host>:~/Adamomaton-deploy/`.
4. SSH-execs `docker compose up -d && docker compose ps`.

Image tags use the umbrella SHA: `adamomaton-platform:<umbrella-sha-short>`. Every deploy is reproducible from one ref. `latest` is updated only by `bin/adam deploy --promote`.

## Per-host quickstart

### Pi #1 (pi5)

First-time setup:
- SSH key from workstation already trusted (`~/.ssh/authorized_keys`)
- Docker + docker compose installed
- Postgres data volume preserved across deploys

Routine:
```bash
bin/adam deploy pi5
```

### Pi #2 (pi5-speaker)

Prereqs: Pi #1 exposes `postgres:5432`, `temporal:7233`, `skills-rae:7376` on `0.0.0.0` (one-time per `nano-research/deploy/pi-replica/expose_pi1_ports.sh` in the evo archive, ported to `deploy/pi5/scripts/`).

Routine:
```bash
bin/adam deploy pi5-speaker
```

### Blackwell

Prereqs: vLLM running with `--enable-lora` (for distill LoRA hot-swaps); ssh key trusted; `/path/to/checkpoints/` directory exists.

Routine:
```bash
bin/adam deploy blackwell
```

### Workstation (dev)

```bash
bin/adam deploy workstation
# brings up local postgres + temporal-dev
# does not start any worker containers — run `go run ./cmd/<worker>` from each submodule for foreground dev
```

## Rollback

Every umbrella commit is a deploy ref. To revert pi5 to a known-good state:

```bash
# At the umbrella, find the good SHA:
git log --oneline -- deploy/pi5/

# Roll the umbrella back:
git checkout <good-sha>
bin/adam deploy pi5

# Or use the explicit rollback flag (same effect):
bin/adam deploy pi5 --rollback=<good-sha>
```

The `--rollback` form leaves the umbrella's HEAD unchanged and ships the older deploy/ + image tags directly.

## Troubleshooting

### Caddy doesn't pick up new frontend bundle

Per the `pi_caddy_bind_mount_inode` memory: `mv newfile oldfile` on the host pins the OLD inode in the bind-mounted frontend container. Fix:

```bash
ssh pi5 'cd ~/Adamomaton-deploy && docker compose restart frontend'
```

Not `caddy reload` — Caddy itself is fine; the bind-mount file handle is the problem.

### Cross-compile cache misses

`make pi-<sub>` runs the Go cross-compile in a Docker context with cgo enabled. Cache lives at `~/.cache/adam-cross/`. Clear with:

```bash
rm -rf ~/.cache/adam-cross/
```

### Submodule SHA mismatch on Pi

The Pi's `Adamomaton-deploy/` only contains the deploy/ files, not the source tree. If `docker compose pull` reports the wrong tag, the umbrella's pin was updated but `bin/adam deploy` was never re-run — re-run it.
