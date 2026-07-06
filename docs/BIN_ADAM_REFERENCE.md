# bin/adam reference

`bin/adam` is the Adamaton agent-coordination CLI. It manages worktrees,
branches, lockfiles, hooks, builds, deploys, and multi-host fleet rollouts.
All commands run from the umbrella root (`/thearray/git/Adamaton`).

Source: `bin/adam` (bash script; read it to verify anything not listed here).

---

## Worktree + branch coordination

### `claim <scope>/<task>`

Creates an isolated git worktree, a feature branch, and a lockfile in `.locks/`.

```bash
bin/adam claim platform/dashboard-pagination
bin/adam claim cross/llmclient-streaming
```

**scope** must be one of: `core` | `frontend` | `knowledge` | `deepresearch` |
`platform` | `delegator` | `evolve` | `cross`

**Single-component** (any scope except `cross`): the worktree is created inside
the sub-repo at `<scope>/<scope>-worktrees/<agent>-<task>`. The feature branch
is `<agent>/<task>` off `origin/main` of the sub-repo.

**Cross-component** (`cross`): the worktree is created at the umbrella level:
`worktrees/<agent>-<task>`. All 7 submodules are initialized at the umbrella's
pinned SHAs.

The command prints the worktree path — `cd` into it before editing.

Optional flag: `--paths "glob1,glob2,..."` annotates the lockfile with which
paths you are touching (used by `status --conflicts` once path-overlap
detection is implemented).

### `release <scope>/<task>`

Removes the worktree and deletes the lockfile. The feature branch is deleted
if it is already merged; otherwise a warning is printed. Use `--keep-branch`
to leave the branch unpushed, or `--force` to delete even if unmerged.

```bash
bin/adam release platform/dashboard-pagination
bin/adam release cross/llmclient-streaming --keep-branch
```

### `status [--conflicts]`

Lists all active claims from `.locks/*.json`.

```bash
bin/adam status
bin/adam status --conflicts   # prints path-overlap warning (implementation pending)
```

### `rescue`

Detects uncommitted changes on `main` in the canonical checkout and prints
recovery steps (stash, claim, cd, stash-pop). Does nothing if you are already
in a worktree or on a feature branch.

```bash
bin/adam rescue
```

### `clean [--force]`

Audits `.locks/*.json` for stale entries (worktree directory absent or claim
older than 7 days). Prints stale entries; with `--force` removes the lockfiles.

```bash
bin/adam clean
bin/adam clean --force
```

---

## Sub-repo management

### `bump <sub-repo>`

Advances the umbrella's submodule pin for `<sub-repo>` to `origin/main` HEAD,
then commits the pin change on the umbrella's `main`. This is the **only
supported way** to commit directly to umbrella `main` — the pre-commit hook
allows it when `ADAM_BUMP=1` is set (set internally by `bump`).

```bash
bin/adam bump platform
bin/adam bump core
```

Run after a sub-repo PR is merged. Then `git push origin main`.

### `pin <sub-repo>`

Prints the current umbrella SHA pin for a sub-repo.

```bash
bin/adam pin knowledge
```

### `pull`

`git pull` on the umbrella + `git submodule update --recursive --remote`.

```bash
bin/adam pull
```

---

## Environment + hooks

### `doctor`

Environment health check. Verifies:
1. `git user.name` and `user.email` are set
2. `gh` CLI is installed and authenticated
3. `go` is installed
4. All 7 submodules are initialized
5. Umbrella hooks (`pre-commit`) are installed
6. No uncommitted changes on `main` in the canonical checkout
7. No out-of-sync submodule pins

```bash
bin/adam doctor
```

### `sync-hooks`

Copies `hooks/pre-commit`, `hooks/pre-push`, and `hooks/commit-msg` into the
`.git/hooks/` of the umbrella and every submodule. Also sets
`core.hooksPath` locally in each checkout so global `core.hooksPath`
overrides in `~/.gitconfig` don't shadow them.

```bash
bin/adam sync-hooks
```

---

## Build + test

### `build <host>`

Stub that prints the Makefile targets needed to cross-compile images for
`<host>`. Currently prints instructions rather than executing them.

Valid hosts: `pi5` | `pi5-speaker` | `blackwell` | `workstation`

```bash
bin/adam build pi5
```

### `test [--scope=<sub>]`

Runs `go test -count=1 -timeout 60s ./...` across all Go modules in all (or
one) sub-repos, with `GOGENTS_SKIP_DOCKER_TESTS=1` set so testcontainer-backed
tests are skipped.

```bash
bin/adam test
bin/adam test --scope=delegator
```

### `ci <target> [ref]`

Local CI runner. **GitHub Actions is banned** (operator decision 2026-07-06):
no `.github/workflows` files, no hosted or self-hosted runners. `bin/adam ci`
is the canonical CI gate — run it before merging and after bumping.

**target** = one of `core` | `frontend` | `knowledge` | `deepresearch` |
`platform` | `delegator` | `evolve` | `loopvm` | `cross` | `all`.

```bash
bin/adam ci core                    # gate core @ origin/main
bin/adam ci platform sirus20x6/foo  # gate a feature branch before merge
bin/adam ci cross                   # validate umbrella deploy configs
bin/adam ci all                     # everything, aggregated (no fail-fast)
```

**Sub-repo targets** check out `[ref]` (default: the sub-repo's `origin/main`,
after a fetch) into a **throwaway git worktree under `/tmp`** — the canonical
checkout is never touched. The worktree sits inside a synthetic sibling layout
where every *other* sub-repo is a symlink to its canonical checkout, so
`replace ../../core`-style `go.mod` paths resolve without `go.work`
(`GOWORK=off` is forced). Nested submodules (e.g. `core/contracts/lib/*`) are
initialized in the temp worktree so contract-backed tests work.

For every `go.mod` module found, three steps run: `go vet ./...`,
`go build ./...`, and `GOGENTS_SKIP_DOCKER_TESTS=1 go test ./...`.

The cgo modules `knowledge/r2g` and `knowledge/reindex` need `libztok` and are
**SKIPped by default**. Set `ZTOK_PREFIX=/path/to/ztok/prefix` (a prefix with
`include/` + `lib/` — see `docs/LOCAL_DEV.md`) to include them; the CGO
`-I`/`-L` flags are derived from it.

**`frontend`** runs `pnpm install` (automatically `--frozen-lockfile` once a
`pnpm-lock.yaml` is committed) followed by `./node_modules/.bin/vite build`.

**`cross`** validates the umbrella's deploy configuration as checked out:

- strict YAML parse of every `deploy/*/docker-compose.yml` — **rejects
  duplicate mapping keys**, which both `yaml.safe_load` and docker compose
  silently last-write-wins (a duplicate `healthcheck:` key broke a pi5 deploy
  on 2026-07-06);
- `docker compose config -q` on each compose file, from a temp copy with stub
  `.env`/`image-tags.env` and stub values for every `${VAR}` that lacks a
  default — full interpolation + schema validation without real secrets;
- `caddy validate` (via the `caddy:2-alpine` image) on `deploy/pi5/Caddyfile`;
- schema check of every `deploy/*/MANIFEST.yaml` (same validator `fleet
  promote` uses): `host` matches its directory, non-empty `image_tag`,
  non-empty string `services` list, no duplicates; services listed in the
  MANIFEST but absent from compose are a **warning** only (pi5 keeps retired
  workers allow-listed through rollback windows).

**`all`** runs every sub-repo plus `cross` with fail-fast off, aggregating
results. `[ref]` is not accepted with `all` or `cross`.

Every run ends with a `PASS`/`FAIL`/`SKIP` summary table and the path to
per-step logs; exit status is non-zero if any step failed.

---

## Single-host deploy

### `deploy <host>`

Executes `deploy/<host>/up.sh`. Used for rsync + docker compose bring-up on
a known host.

```bash
bin/adam deploy workstation
bin/adam deploy pi5
```

---

## Push-deploy (workstation registry to deploy-agent)

These subcommands require `~/.adamaton/ship.env` with `DEPLOY_AGENT_TOKEN` and
`WORKSTATION_IP`. See [docs/PUSH_DEPLOY.md](PUSH_DEPLOY.md) for one-time
setup.

### `ship <host> <service> [<service2> ...]`

Builds a Docker image from the service's Dockerfile (looked up from the
internal `ship_service_spec` table in `bin/adam`), pushes it to the
workstation registry (`${WORKSTATION_IP}:5000`), and POSTs a restart request
to the deploy-agent on `<host>`. Then polls `/status` until the new SHA tag is
confirmed (60-second timeout, with a warning if the tag doesn't appear).

Refuses to build if the sub-repo has uncommitted changes. Tags the image as
both `sha-<short-HEAD>` and `main`.

```bash
bin/adam ship pi5 r2g
bin/adam ship pi5 dashboard plugin-host dispatch-worker
bin/adam ship pi5 adamaton-worker-full
```

### `ship-self <host>`

Builds the deploy-agent image, pushes it to the workstation registry, and
restarts the agent on `<host>` via ssh (the agent can't restart itself over
HTTP). Polls `/health` until the new tag is healthy.

```bash
bin/adam ship-self pi5
```

### `sync-compose <host>`

`scp`s `deploy/<host>/docker-compose.yml` (and `.env.example`, `Caddyfile`,
`deploy/health/topology.yml` if present) to `<host>:~/Adamaton-deploy/`. Run
when compose-file changes (new env vars, new service blocks) need to reach the
host. The operator must manually `docker compose up -d --force-recreate
--no-deps <svc>` after to pick up the new env.

```bash
bin/adam sync-compose pi5
```

### `bootstrap <host>`

One-shot first-deploy of the deploy-agent on a fresh host. Idempotent. Steps:
1. SSH reachability check
2. Workstation registry reachability
3. Allow-list workstation registry in `/etc/docker/daemon.json` (may `sudo`)
4. Rsync `deploy/<host>/` to `<host>:~/Adamaton-deploy/`
5. Generate or reuse `DEPLOY_AGENT_TOKEN`
6. Initialize `image-tags.env`
7. Build and stream the bootstrap deploy-agent image to the host via `docker save | ssh docker load`
8. `docker compose up -d deploy-agent` + health check

```bash
bin/adam bootstrap pi5
```

---

## Fleet management

### `fleet status`

Prints the `image_tag` and service list from each host's `deploy/<host>/MANIFEST.yaml`.

```bash
bin/adam fleet status
```

### `fleet pull <host|all>`

SSH + `docker compose pull && up -d` on one host or all fleet hosts, using each
host's MANIFEST `image_tag`.

```bash
bin/adam fleet pull pi5
bin/adam fleet pull all
```

### `fleet promote <sha-or-tag> [--dry-run]`

Updates every `deploy/*/MANIFEST.yaml` `image_tag` field to the given tag and
commits the changes to umbrella `main` via `ADAM_BUMP=1`.

Before mutating anything, every MANIFEST is validated (same validator as
`bin/adam ci cross`): schema sanity (`host` matches directory, non-empty
`image_tag`, non-empty string `services` list, no duplicates) plus a
cross-check that each listed service exists in the host's
`docker-compose.yml` (missing services warn — pi5 intentionally keeps retired
workers allow-listed during rollback windows). A schema error on **any** host
aborts the promote before any file is touched.

`--dry-run` prints the would-be `image_tag` change per host and exits without
modifying files or committing.

```bash
bin/adam fleet promote sha-abc1234 --dry-run   # preview
bin/adam fleet promote sha-abc1234             # validate + edit + commit
```

---

## Subcommand index

| Subcommand | Purpose |
|------------|---------|
| `claim <scope>/<task>` | Create worktree + branch + lockfile |
| `release <scope>/<task>` | Remove worktree + lockfile; delete branch if merged |
| `status [--conflicts]` | List active claims |
| `rescue` | Recover from accidental main edits |
| `clean [--force]` | Audit and remove stale lockfiles |
| `doctor` | Environment health check |
| `sync-hooks` | Install hooks into all checkouts |
| `bump <sub>` | Advance umbrella submodule pin (only supported main commit) |
| `pin <sub>` | Show current umbrella SHA pin |
| `pull` | Pull umbrella + all submodules |
| `build <host>` | Print cross-compile instructions for a host |
| `test [--scope=<sub>]` | Run go test across sub-repos (no docker) |
| `ci <target> [ref]` | Local CI: vet/build/test a sub-repo at a ref, validate deploy configs (`cross`), or both (`all`) |
| `deploy <host>` | Run `deploy/<host>/up.sh` |
| `ship <host> <svc...>` | Build + push image(s) + restart via deploy-agent |
| `ship-self <host>` | Build + push deploy-agent image; restart via ssh |
| `sync-compose <host>` | scp compose files to host |
| `bootstrap <host>` | One-shot deploy-agent first install on a fresh host |
| `fleet status` | Show image_tag per host |
| `fleet pull <host\|all>` | SSH + compose pull + up on fleet host(s) |
| `fleet promote <tag> [--dry-run]` | Validate + bulk-update MANIFEST.yaml image_tag |
