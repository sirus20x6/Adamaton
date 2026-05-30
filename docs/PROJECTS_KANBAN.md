# Projects, Persistent Terminals & Agent-Orchestrating Kanban

> Design doc for three linked dashboard features. Authored 2026-05-30.
> Status: **approved direction, Phase 1 in progress.**

A **project** is a host folder — usually a git repo, sometimes a nested git
worktree or submodule. Everything in this feature hangs off a `project_id`:
the file-tree browser, the persistent terminals, and the per-project Kanban
board used for agent orchestration.

## Locked decisions

These were chosen by the operator on 2026-05-30; the rest of the doc assumes them.

1. **Terminal backend: real `tmux`** (not in-process `creack/pty`). The shell
   lives in the tmux server, so a session survives a page reload, a network
   drop, *and* an apiserver restart/crash. Gated behind `PTY_BACKEND={tmux|none}`
   so deploys without tmux degrade gracefully.
2. **Kanban store: platform `evo` schema, apiserver-owned. The delegator MCP
   tools reach it through the apiserver REST API**, not by writing Postgres
   directly. One owner for all dashboard data; the atomic card-claim lives in
   the apiserver handler. The MCP tools are thin REST clients.
3. **Orchestration: a Claude Code Workflow script** (deterministic JS fan-out —
   `parallel()` / `agent()` with JSON schemas) is the orchestrator brain.
   Durable state lives in Postgres; crash recovery is a **stale-claim sweep**,
   not Temporal. Temporal stays the executor substrate under `delegate_task`
   and continues to own schedules/PR-review/batch.
4. **Card model: a dedicated `evo.kanban_cards` table**, distinct from
   `delegator.tasks`. A *card* is "work to be done" (may spawn 0..N tasks); a
   *task* is "a CLI invocation that ran". Linked by `result_task_id`.

## 1. Architecture overview

One spine, ownership split by what each concern is *tied to*:

- **platform owns projects + files + terminals** — things tied to the host
  filesystem and the dashboard.
- **platform also owns the kanban store + REST API** — see decision 2.
- **delegator owns the kanban MCP tools** (REST clients) and the orchestration
  Workflow — things tied to agents.
- **frontend renders all of it.**

```
                    ┌──────────────── frontend (React SPA) ────────────────┐
                    │ Projects nav · file-tree · xterm.js · Kanban board    │
                    └───────┬───────────────────┬──────────────────┬───────┘
                            │ REST              │ WS (terminals)   │ REST (kanban)
                    ┌───────▼───────────────────▼──────────────────▼───────┐
                    │      platform/dashboard/apiserver  (gorilla/mux)      │
                    │  projects · file-tree · tmux bridge · kanban CRUD     │
                    └───────┬───────────────────────────────┬──────────────┘
                            │ pgxpool (evo schema)           │ exec tmux
                    ┌───────▼────────┐               ┌───────▼───────┐
                    │   Postgres     │               │  tmux server  │
                    │ evo.projects   │               │ (host process)│
                    │ evo.terminal_* │               └───────────────┘
                    │ evo.kanban_*   │
                    └───────▲────────┘
                            │ REST (kanban_* tools)
                    ┌───────┴────────────────────────┐
                    │   delegator-mcp  +  Claude Code │
                    │   Workflow orchestrator         │
                    └─────────────────────────────────┘
```

The visual board column (`column_id`/`position`) is tracked **separately** from
orchestration state (`claim_status`/`claimed_by`/`claim_token`). A card can sit
in "In Progress" with `claim_status='failed'`. The UI reads the column; the
orchestrator reads `claim_status`. The **Ready** column (`is_ready=true`) is the
contract between the two worlds — cards there are what `kanban_list_ready_cards`
returns.

## 2. Data model

All three features live in the platform-owned **`evo`** schema. Migrations go in
`evolve/evolve/store/migrations/` (the evo-schema owner); the apiserver
reads/writes but does **not** run these migrations on boot.

```sql
-- evo.projects  (015_projects.up.sql)
CREATE TABLE evo.projects (
    id               TEXT PRIMARY KEY,                       -- slug
    path             TEXT NOT NULL UNIQUE,                   -- absolute host path
    display_name     TEXT NOT NULL,
    type             TEXT NOT NULL DEFAULT 'git-repo',       -- git-repo|worktree|submodule|folder
    git_remote       TEXT,
    parent_id        TEXT REFERENCES evo.projects(id) ON DELETE SET NULL,  -- nesting
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ
);
CREATE INDEX projects_parent_idx ON evo.projects (parent_id);

-- evo.terminal_sessions  (016_terminals.up.sql)
CREATE TABLE evo.terminal_sessions (
    id            TEXT PRIMARY KEY,                          -- = tmux session name
    project_id    TEXT NOT NULL REFERENCES evo.projects(id) ON DELETE CASCADE,
    tmux_session  TEXT NOT NULL,
    title         TEXT NOT NULL DEFAULT 'shell',
    command       TEXT NOT NULL DEFAULT 'bash',
    cwd           TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'live',              -- live|dead
    cols          INT  NOT NULL DEFAULT 120,
    rows          INT  NOT NULL DEFAULT 40,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at      TIMESTAMPTZ
);
CREATE INDEX terminal_sessions_project_idx ON evo.terminal_sessions (project_id, status);

-- evo.kanban_boards / _columns / _cards / _comments  (017_kanban.up.sql)
CREATE TABLE evo.kanban_boards (
    id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES evo.projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL, created_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE evo.kanban_columns (
    id TEXT PRIMARY KEY, board_id TEXT NOT NULL REFERENCES evo.kanban_boards(id) ON DELETE CASCADE,
    name TEXT NOT NULL, position INT NOT NULL, is_ready BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE evo.kanban_cards (
    id TEXT PRIMARY KEY,
    column_id TEXT NOT NULL REFERENCES evo.kanban_columns(id) ON DELETE CASCADE,
    board_id  TEXT NOT NULL REFERENCES evo.kanban_boards(id)  ON DELETE CASCADE,  -- denormalized
    title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
    priority   TEXT NOT NULL DEFAULT 'normal',   -- immediate|normal|background (budget router)
    difficulty TEXT NOT NULL DEFAULT 'medium',   -- trivial..expert (budget router)
    position INT NOT NULL,
    claim_status TEXT NOT NULL DEFAULT 'unclaimed', -- unclaimed|claimed|done|failed
    claimed_by TEXT, claim_token UUID, claimed_at TIMESTAMPTZ,
    result_task_id TEXT, result_summary TEXT, result_pr_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX cards_column_idx ON evo.kanban_cards (column_id, position);
CREATE INDEX cards_claim_idx  ON evo.kanban_cards (board_id, claim_status, claimed_at);
CREATE TABLE evo.kanban_comments (
    id TEXT PRIMARY KEY, card_id TEXT NOT NULL REFERENCES evo.kanban_cards(id) ON DELETE CASCADE,
    author TEXT NOT NULL, text TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## 3. Backend plan (platform apiserver)

New endpoints register under the `/api/v1` subrouter in `setupRoutes()`
(`server.go`), inherit `authMiddleware`, and use the `sendJSON` helper. New file
`platform/dashboard/apiserver/projects_endpoints.go` with
`registerProjectsEndpoints(api *mux.Router)`, mirroring `datasets_endpoints.go`
(wire types, timeout-bounded `evoPool` queries, nil-pool guard).

**Projects + file-tree:**

| Verb | Path | Notes |
|------|------|-------|
| GET    | `/api/v1/projects` | list incl. `parent_id` |
| POST   | `/api/v1/projects` | `{path}`; stat, detect git/worktree/submodule, derive name + remote |
| GET    | `/api/v1/projects/{id}` | one |
| DELETE | `/api/v1/projects/{id}` | unregister (does not touch files) |
| GET    | `/api/v1/projects/{id}/tree?path=&depth=1` | `os.ReadDir`, depth ≤ 3, lazy per dir |
| GET    | `/api/v1/projects/{id}/file?path=` | contents; binary-detect; refuse > ~1 MB |

Every `path` param is `filepath.Clean`'d, symlink-resolved, and rejected if it
escapes the project root (TOCTOU/traversal guard).

**Persistent terminals (tmux + websocket):**

| Verb | Path | Notes |
|------|------|-------|
| GET     | `/api/v1/projects/{id}/terminals` | live sessions |
| POST    | `/api/v1/projects/{id}/terminals` | `tmux new-session -d -s <id> -x C -y R -c <path> <cmd>`; insert row |
| GET(WS) | `/api/v1/terminals/{sid}/ws` | upgrade; **attach** to existing tmux session |
| POST    | `/api/v1/terminals/{sid}/resize` | `tmux resize-window` (or WS control frame) |
| DELETE  | `/api/v1/terminals/{sid}` | `tmux kill-session`; mark dead |

Persistence mechanism: shell runs in the tmux server (separate long-lived
process); the apiserver holds only a websocket + a tmux pipe. On WS connect the
bridge runs `tmux capture-pane -p -e -S -<scrollback>` (replay screen+history)
then `tmux pipe-pane` (live stream); input flows client → `tmux send-keys`. On
apiserver boot a reconciler runs `tmux ls`, marks vanished sessions `dead`, and
leaves live ones attachable. A ~60s reaper kills tmux sessions for deleted
projects. Adds `gorilla/websocket` to `platform/dashboard/go.mod`; auth on
upgrade via token query param (browsers can't set WS headers).

**Kanban CRUD + atomic claim** (REST, also called by the MCP tools):

| Verb | Path |
|------|------|
| GET/POST | `/api/v1/projects/{id}/kanban/boards` |
| GET | `/api/v1/kanban/boards/{bid}` (board + columns + cards) |
| POST | `/api/v1/kanban/boards/{bid}/cards` |
| GET | `/api/v1/kanban/boards/{bid}/ready` (unclaimed cards in the `is_ready` column) |
| POST | `/api/v1/kanban/cards/{cid}/claim` — **atomic**: `pg_advisory_xact_lock(hashtext(cid))` then `UPDATE … SET claim_status='claimed', claim_token=gen_random_uuid() WHERE claim_status='unclaimed'`; returns token or 409 |
| POST | `/api/v1/kanban/cards/{cid}/move` · `/complete` · `/release` · `/comment` (token-gated) |

## 4. MCP plan (delegator)

Add a `kanban_*` tool group to the **existing** `delegator-mcp` binary
(`delegator/mcp/cmd/delegator-mcp/`), registered via `mcp.AddTool()` like the
current `delegate_task` tools (`main.go:446+`). Optionally split into
`kanban_tools.go` with `registerKanbanTools()`, mirroring `context_tools.go`.
The tools are **thin REST clients** of the apiserver (decision 2); base URL from
`KANBAN_API_URL` (default the local apiserver). No DB code in the MCP server.

| Tool | Calls |
|------|-------|
| `kanban_create_board` | POST …/kanban/boards (seeds Backlog/Ready/In Progress/Review/Done) |
| `kanban_list_boards` | GET …/kanban/boards |
| `kanban_add_card` | POST …/boards/{bid}/cards |
| `kanban_list_ready_cards` | GET …/boards/{bid}/ready |
| `kanban_claim_card` | POST …/cards/{cid}/claim → returns `claim_token` |
| `kanban_move_card` | POST …/cards/{cid}/move (token) |
| `kanban_add_comment` | POST …/cards/{cid}/comment |
| `kanban_complete_card` | POST …/cards/{cid}/complete (token, attaches result) |
| `kanban_release_card` | POST …/cards/{cid}/release (token) |

## 5. Frontend plan

**Dynamic Projects nav.** Refactor the static `NAV` array + `NavList` in
`src/components/layout/Layout.tsx`. `src/api/projects.ts` (`useProjects()`
react-query → `GET /evo-api/api/v1/projects`, the Caddy proxy onto the
apiserver — same base every other `src/api/*.ts` module uses); render a
collapsible `ProjectsNavSection` mapping projects to indented `NavLink`s to
`/projects/:id`. The top-level "Projects" header links to a `Projects.tsx` list
page (modeled on `Datasets.tsx`) with a register dialog.

**Routes** (lazy + Suspense in `App.tsx`):
`/projects` → `Projects.tsx`; `/projects/:projectId` → `ProjectDetail.tsx`
(file-tree left, content/terminal right); `/projects/:projectId/kanban` →
`ProjectKanban.tsx`.

**File tree** — `src/api/fileTree.ts` (`useFileTree(projectId, path)`, lazy per
dir), `FileTreePanel.tsx` recursive with lucide icons; click a file → `?file=`
preview pane.

**Persistent terminal** — add `@xterm/xterm` + `@xterm/addon-fit` (scoped
packages; old `xterm`/`@types/xterm` are deprecated). `TerminalWindow.tsx`
mounts `xterm.Terminal`, opens a WS to `/evo-api/api/v1/terminals/{id}/ws`,
reconnect via the `api/ws.ts` backoff; on reconnect the **server replays the
tmux buffer** so the client just re-renders. `useTerminalStore.ts` (zustand,
localStorage) tracks which terminals are open so the tab set survives reloads
(sessions themselves survive server-side). Floating panel via framer-motion
(already a dep). Confirm the vite `/evo-api` proxy has `ws: true`.

**Kanban board** — add `@dnd-kit/core` + `/sortable` + `/utilities`
(React-19-safe; avoid `react-beautiful-dnd`). `src/api/kanban.ts`
(`useKanbanBoard`, `useMoveCard`, `useCreateCard`); `KanbanBoard.tsx` horizontal
columns + sortable cards, **optimistic move with rollback on error**. Cards show
priority/difficulty badges + a "claimed by agent" indicator so human and agent
activity are legible on one board.

## 6. Orchestration plan

Hybrid: **Claude Code Workflow = brain, Postgres kanban = durable queue,
`delegate_task` = executor.** Card lifecycle:

```
unclaimed ──claim──▶ claimed ──complete──▶ done
                        ├──release / stale-timeout──▶ unclaimed
                        └──fail──────────────────────▶ failed ──reopen──▶ unclaimed
```

Atomic claim lives in the apiserver `/claim` handler (advisory lock + guarded
UPDATE). A stale-claim sweep (small worker or MCP-side cron) flips `claimed`
cards older than ~30m back to `unclaimed` — handles crashed subagents.

Orchestrator flow: a planner agent calls `kanban_create_board` then one
`kanban_add_card` per work item (setting `priority`/`difficulty` so each card
self-describes its budget-router routing). Workers fan out, each claims a card
atomically, runs the work (often itself a `delegate_task`), then
`kanban_complete_card` with `result_summary` + `result_task_id`/`result_pr_url`.

Illustrative `.claude/workflows/kanban_orchestrator.js`:

```javascript
export default async function ({ agent, parallel, mcp, input }) {
  const { project_id } = input;
  const planner = agent("planner", { schema: { board_name: "string",
    cards: [{ title: "string", body: "string", priority: "string", difficulty: "string" }] } });
  const plan = await planner.run(`Plan a roadmap for ${project_id}; break it into ` +
    `discrete, independently-claimable cards.`);

  const board = await mcp.kanban_create_board({ project_id, name: plan.board_name });
  const ready = board.columns.find(c => c.is_ready);
  for (const c of plan.cards) await mcp.kanban_add_card({ board_id: board.id, column_id: ready.id, ...c });

  const cards = await mcp.kanban_list_ready_cards({ board_id: board.id });
  const results = await parallel(cards.map(card => async () => {
    const agentId = `claude-code-${crypto.randomUUID()}`;
    const claim = await mcp.kanban_claim_card({ card_id: card.id, agent_id: agentId });
    if (claim.error) return { card: card.id, skipped: "already claimed" };
    const worker = agent("worker", { schema: { summary: "string", pr_url: "string" } });
    try {
      await mcp.kanban_move_card({ card_id: card.id, claim_token: claim.claim_token,
        target_column_id: board.columns.find(c => c.name === "In Progress").id });
      const out = await worker.run(card.body);       // worker may call delegate_task
      await mcp.kanban_complete_card({ card_id: card.id, claim_token: claim.claim_token,
        result_summary: out.summary, result_pr_url: out.pr_url });
      return { card: card.id, summary: out.summary };
    } catch (e) {
      await mcp.kanban_release_card({ card_id: card.id, claim_token: claim.claim_token });
      return { card: card.id, error: String(e) };
    }
  }));
  return { board: board.id, results };
}
```

## 7. Phased delivery

Each phase is independently shippable + demoable. Claim scopes use
`bin/adam claim <scope>/<task>`.

| # | Phase | Sub-repos | Claim scope |
|---|-------|-----------|-------------|
| 1 | Projects registry + dynamic sidebar nav + list page | platform, frontend | `cross/projects-registry` |
| 2 | File-tree browser | platform, frontend | `cross/file-tree` |
| 3 | Persistent terminals (xterm.js + tmux bridge) | platform, frontend | `cross/persistent-terminals` |
| 4 | Kanban store + apiserver REST API + board UI | platform, frontend | `cross/kanban` |
| 5 | Kanban MCP tools (REST clients) | delegator | `delegator/kanban-mcp` |
| 6 | Orchestration Workflow + stale-claim sweep | delegator, repo root | `delegator/kanban-orchestrator` |
| 7 | Hardening (reconnect edge cases, scrollback, comments UI, tree virtualization) | per sub-repo | as needed |

> Note: because the kanban store is apiserver-owned and the MCP tools are REST
> clients (decision 2), the apiserver kanban API (Phase 4) must land before the
> MCP tools (Phase 5).

## 8. Open follow-ups

- **Project registration:** manual `POST /projects` only (Phase 1), or
  auto-discovery scanning a configured root like `/thearray/git`? Manual first;
  revisit auto-discovery in Phase 7.
- **tmux in the container:** the platform image must include `tmux` for the
  terminal feature; document in `platform/CLAUDE.md` and the relevant deploy
  Dockerfile when Phase 3 lands.
- **WS auth:** finalize the token-via-query-param scheme against the existing
  `authMiddleware` when Phase 3 lands.
