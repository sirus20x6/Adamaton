# CI/CD — keeping the worker compute racks up to date

Goal: a low-friction system where pushing to `main` on any sub-repo builds images that the fleet (pi5, pi5-speaker, blackwell) can pull in a single command.

## Architecture

```
┌─ Developer/agent ──────────────────────────────────┐
│  bin/adam claim platform/feature                   │
│  ... edit, commit, push branch ...                 │
│  → opens PR on sirus20x6/adamaton-platform         │
│  → PR CI: docker build (no push) validates         │
│  → merge to main                                   │
└──────────────────┬─────────────────────────────────┘
                   │  on push to main
                   ▼
┌─ GitHub Actions (per sub-repo) ────────────────────┐
│  .github/workflows/build.yml                       │
│  - matrix build: each Dockerfile in the sub-repo   │
│  - docker/build-push-action multi-arch (amd64+arm64) │
│  - tags: sha-<short>, main, vX.Y.Z (if tagged)     │
│  - pushes to ghcr.io/sirus20x6/adamaton-<sub>-<svc>│
└──────────────────┬─────────────────────────────────┘
                   │
                   ▼
┌─ Operator promotes via Adamaton umbrella ──────────┐
│  bin/adam fleet promote sha-abc123                 │
│  → updates deploy/{pi5,pi5-speaker,blackwell}/MANIFEST.yaml │
│  → commits to umbrella main (ADAM_BUMP=1)          │
│  → pushes                                          │
└──────────────────┬─────────────────────────────────┘
                   │
                   ▼
┌─ Fleet pull ───────────────────────────────────────┐
│  bin/adam fleet pull all                           │
│  → for each host: ssh + docker compose pull + up -d│
│  → host's MANIFEST.yaml is the source of truth     │
└────────────────────────────────────────────────────┘
```

## What runs where

| Host | Role | Image registry | Default tag |
|---|---|---|---|
| pi5 | Main stack (postgres, temporal, all backends, frontend, caddy) | ghcr.io/sirus20x6/adamaton-* | per MANIFEST.yaml (defaults `main`) |
| pi5-speaker | Replica (nano-research-worker, figure-renderer) | ghcr.io/sirus20x6/adamaton-* | per MANIFEST.yaml |
| blackwell | GPU node (vLLM, evo-worker for KernelBench, distill trainer) | ghcr.io/sirus20x6/adamaton-* | per MANIFEST.yaml |
| workstation | Dev (postgres + temporal-dev) | local builds | — |

## Image naming convention

```
ghcr.io/sirus20x6/adamaton-<sub-repo>-<service>:<tag>
```

Examples:
- `ghcr.io/sirus20x6/adamaton-knowledge-skills-rae:main`
- `ghcr.io/sirus20x6/adamaton-knowledge-r2g:sha-abc1234`
- `ghcr.io/sirus20x6/adamaton-deepresearch-nano-research:v0.2.0`
- `ghcr.io/sirus20x6/adamaton-platform-dashboard:main`
- `ghcr.io/sirus20x6/adamaton-evolve-evo-worker:sha-def5678`

Tags pushed per build:
- `sha-<short-sha>` — immutable, pin to this for reproducibility
- `main` — mutable, updated on every main push
- `vX.Y.Z` — created when a `v*` tag is pushed (manual release cadence)
- `latest` — alias of `main` (convenience)

## Per-sub-repo workflow

Each image-shipping sub-repo has `.github/workflows/build.yml` with this shape:

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
permissions:
  contents: read
  packages: write
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - service: <name>
            dockerfile: <path>
            platforms: linux/arm64
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: ${{ matrix.dockerfile }}
          platforms: ${{ matrix.platforms }}
          push: ${{ github.event_name != 'pull_request' }}
          tags: ghcr.io/sirus20x6/adamaton-<sub>-${{ matrix.service }}:sha-...
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

PR builds = no push (validate only). Main pushes = full push.

## Per-host MANIFEST.yaml

Each host's `deploy/<host>/MANIFEST.yaml` declares the desired image tag for the whole stack on that host. Single source of truth.

```yaml
# deploy/pi5/MANIFEST.yaml
host: pi5
image_tag: "main"              # or sha-abc123 to pin
services:
  - skills-rae
  - r2g
  - reindex-worker
  - skills-worker
  - reranker                   # sidecar
  - nano-research
  - nano-research-worker
  - figure-renderer            # sidecar
  - dashboard
  - plugin-host
  - dispatch-worker
  - temporal-worker
  - frontend                   # SPA served by caddy
```

`bin/adam fleet pull pi5` reads `image_tag`, sshes into pi5, runs `IMAGE_TAG=<tag> docker compose pull && up -d`.

## Workflows

### Day-to-day: promote main on all hosts

```bash
bin/adam fleet promote main           # rewrites every MANIFEST.yaml to image_tag: "main"
git push                              # umbrella commit lands
bin/adam fleet pull all               # ssh each host + docker compose pull + up
```

### Pin a known-good SHA

```bash
bin/adam fleet promote sha-abc1234    # locks every host to that exact build
git push
bin/adam fleet pull all
```

### Canary on one host first

```bash
# Edit deploy/pi5-speaker/MANIFEST.yaml manually to image_tag: "sha-new"
git commit -am "canary: pi5-speaker -> sha-new"
git push                              # uses ADAM_BUMP=1 if via bin/adam fleet promote --host
bin/adam fleet pull pi5-speaker
# observe for an hour, then promote to the rest:
bin/adam fleet promote sha-new
bin/adam fleet pull all
```

### Rollback

```bash
git log -- deploy/pi5/MANIFEST.yaml   # find the known-good SHA
bin/adam fleet promote sha-previous
bin/adam fleet pull all
```

## Watchtower? auto-pull?

Not recommended at this scale. Three hosts, weekly cadence — operator-driven `bin/adam fleet pull` is simpler than a watchtower per Pi and gives explicit rollback control. If the fleet grows past ~10 hosts, revisit.

## GHCR authentication on the Pi

Each host needs read access to ghcr.io. Two options:

1. **Public images** — if you flip the sub-repos to public, no auth needed. Simplest.
2. **PAT with `read:packages`** — store in `~/.docker/config.json` on each host. `docker login ghcr.io` with the token, once per host.

The compose's `image:` lines pull from ghcr.io; `docker compose pull` uses whatever credentials docker has cached.

## What's NOT in CI/CD yet

- **End-to-end smoke tests** post-deploy. After `bin/adam fleet pull all`, no automated check that all services are healthy. Manual: `curl localhost:9123/api/v1/system/status`. Future: a `bin/adam fleet verify` subcommand.
- **Blackwell-side image builds** for amd64. The GH Actions matrix builds linux/amd64 + linux/arm64, but the Blackwell may want CUDA-aware images that buildx can't easily produce without a self-hosted runner. For now, build amd64 images for Blackwell on the Blackwell itself via the Makefile.
- **Schema migration coordination**. If a sub-repo's image embeds a new migration, the deploy needs `docker compose run --rm <svc> migrate up` before the new container starts. Currently relies on the service's own startup migration (which most do). Document per-service.
