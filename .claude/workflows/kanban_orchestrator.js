// kanban_orchestrator.js — agent-orchestrating Kanban Workflow
// =============================================================================
// Drives the per-project Kanban board described in docs/PROJECTS_KANBAN.md (§6).
//
//   1. A `planner` agent turns a roadmap into a board name + a list of
//      independently-claimable cards, creates the board, and seeds them into
//      the Ready column.
//   2. `parallel()` fans out one `worker` agent per ready card. Each worker
//      atomically CLAIMS its card, moves it to In Progress, does the work, and
//      COMPLETEs it (releasing on failure so the card returns to the queue).
//
// HOW THE KANBAN TOOLS ARE CALLED
// -------------------------------
// This is the key adaptation from the doc's illustrative sketch: there is NO
// `mcp.*` helper injected into the workflow body. The kanban_* MCP tools
// (kanban_create_board, kanban_add_card, kanban_list_ready_cards,
// kanban_claim_card, kanban_move_card, kanban_complete_card,
// kanban_release_card, kanban_add_comment) are invoked by the AGENTS
// THEMSELVES — each agent reaches them via ToolSearch and calls them as part
// of executing its prompt. So the orchestrator's job is to (a) shape the work
// into agent runs and (b) tell each agent, in plain language, exactly which
// tools to call and in what order. The agents return structured JSON
// (constrained by `schema`) that the next phase consumes.
//
// RUNTIME CONSTRAINTS (this Workflow runtime)
// -------------------------------------------
//   * `meta` is a pure object literal (no expressions, no function calls).
//   * Only agent() / parallel() / pipeline() / phase() / log() are used.
//   * No wall-clock (Date.now) or randomness (Math.random / crypto.randomUUID)
//     builtins — they are blocked. Worker identities and labels are derived
//     deterministically from the card's array index instead.
//   * Crash recovery for claims that never complete is handled out-of-band by
//     the delegator stale-claim sweeper (see delegator/kanban_sweeper.go), not
//     by this script.
// =============================================================================

export const meta = {
  name: "kanban_orchestrator",
  version: "1.0.0",
  description:
    "Plan a project roadmap into Kanban cards, then fan out one agent per Ready card to claim, work, and complete it.",
  args: {
    project_id: {
      type: "string",
      required: true,
      description: "evo.projects id the board is created under.",
    },
    roadmap: {
      type: "string",
      required: false,
      description:
        "Optional roadmap / goal text. When omitted, the planner infers scope from the project itself.",
    },
  },
};

export default async function ({ agent, parallel, pipeline, phase, log, args }) {
  const projectId = args.project_id;
  const roadmap =
    args.roadmap && args.roadmap.trim().length > 0
      ? args.roadmap.trim()
      : "(no explicit roadmap provided — infer a sensible set of discrete work items from the project)";

  // ---------------------------------------------------------------------------
  // Phase 1 — PLAN. The planner creates the board and seeds the Ready column,
  // then reports the board/column/card IDs the worker phase needs.
  // ---------------------------------------------------------------------------
  const planResult = await phase("plan", async () => {
    const planner = agent("planner", {
      schema: {
        board_id: "string",
        ready_column_id: "string",
        in_progress_column_id: "string",
        board_name: "string",
        cards: [
          {
            id: "string",
            title: "string",
            body: "string",
            priority: "string",
            difficulty: "string",
          },
        ],
      },
    });

    return planner.run(
      [
        `You are the Kanban planner for project "${projectId}".`,
        "",
        "ROADMAP / GOAL:",
        roadmap,
        "",
        "Break the goal into a set of DISCRETE, INDEPENDENTLY-CLAIMABLE cards.",
        "Each card must be workable on its own with no ordering dependency on a",
        "sibling card (cards run in parallel). For every card pick a budget-router",
        "priority (immediate|normal|background) and difficulty (trivial|easy|",
        "medium|hard|expert) so the card self-describes how it should be routed.",
        "",
        "Then use the kanban_* MCP tools (find them via ToolSearch) to persist the",
        "board. Call them in EXACTLY this order:",
        "",
        `  1. kanban_create_board { project_id: "${projectId}", name: <board_name> }`,
        "     -> returns { board, columns }. The response seeds 5 columns:",
        "        Backlog, Ready, In Progress, Review, Done. Note the board id,",
        "        the Ready column id (is_ready=true), and the In Progress column id.",
        "  2. For EACH card, kanban_add_card { board_id, column_id: <Ready column id>,",
        "        title, body, priority, difficulty } -> returns the created Card.",
        "     The body MUST be a complete, self-contained task brief: a worker",
        "     agent with no other context will execute it verbatim.",
        "  3. kanban_list_ready_cards { board_id } to read back the seeded cards.",
        "",
        "Return JSON matching the schema: board_id, ready_column_id,",
        "in_progress_column_id, board_name, and cards[] (each with the id returned",
        "by kanban_add_card / kanban_list_ready_cards, plus title, body, priority,",
        "difficulty). The card ids MUST be the real ids the API assigned.",
      ].join("\n"),
    );
  });

  const cards = Array.isArray(planResult.cards) ? planResult.cards : [];
  log(
    `planner produced board "${planResult.board_name}" (${planResult.board_id}) with ${cards.length} ready card(s)`,
  );

  if (cards.length === 0) {
    return {
      board: planResult.board_id,
      board_name: planResult.board_name,
      results: [],
      note: "planner produced no cards; nothing to fan out",
    };
  }

  // ---------------------------------------------------------------------------
  // Phase 2 — WORK. One worker agent per Ready card, all in parallel. Each
  // worker owns the full claim -> move -> work -> complete/release lifecycle for
  // its single card. Labels are derived from the array INDEX (deterministic; no
  // randomness builtin) so each worker is individually identifiable in logs.
  // ---------------------------------------------------------------------------
  const results = await phase("work", async () => {
    return parallel(
      cards.map((card, index) => async () => {
        // Deterministic, collision-free per-worker identity. Used both as the
        // agent label and as the agent_id passed to kanban_claim_card.
        const slot = index + 1;
        const label = `worker-${slot}`;
        const agentId = `claude-code-${planResult.board_id}-${slot}`;

        const worker = agent(label, {
          schema: {
            card_id: "string",
            outcome: "string", // one of: completed | skipped | failed
            summary: "string",
            result_task_id: "string",
            pr_url: "string",
            detail: "string",
          },
        });

        log(`${label}: dispatching for card ${card.id} — ${card.title}`);

        return worker.run(
          [
            `You are Kanban ${label} (agent_id "${agentId}"). You own exactly ONE`,
            `card on board ${planResult.board_id}. Drive its full lifecycle using`,
            "the kanban_* MCP tools (find them via ToolSearch). Follow these steps",
            "precisely and DO NOT touch any other card.",
            "",
            "CARD:",
            `  id:         ${card.id}`,
            `  title:      ${card.title}`,
            `  priority:   ${card.priority}`,
            `  difficulty: ${card.difficulty}`,
            "  body:",
            indent(card.body, "    "),
            "",
            "LIFECYCLE — execute in order, stop early only on the claim guard:",
            "",
            `  1. CLAIM: kanban_claim_card { card_id: "${card.id}", agent_id: "${agentId}" }`,
            "     - On success it returns a claim_token. KEEP IT — every later call",
            "       needs it.",
            "     - On a 409 / already-claimed error, another worker beat you to it.",
            '       STOP and return { outcome: "skipped", detail: "already claimed" }.',
            "",
            "  2. MOVE to In Progress: kanban_move_card {",
            `        card_id: "${card.id}", target_column_id: "${planResult.in_progress_column_id}",`,
            "        claim_token: <token> }",
            "",
            "  3. WORK: actually perform the task described in the card body. For",
            "     non-trivial coding work prefer delegating to a CLI agent via the",
            "     delegate_task tool (the budget router routes by the card's",
            `     priority="${card.priority}" and difficulty="${card.difficulty}"),`,
            "     then poll get_task_status / get_task_result. Capture the resulting",
            "     task id and any PR url it produced.",
            "",
            "  4a. ON SUCCESS — COMPLETE: kanban_complete_card {",
            `        card_id: "${card.id}", claim_token: <token>,`,
            "        result_summary: <one-line summary>,",
            "        result_task_id: <delegate_task id, if any>,",
            "        result_pr_url: <PR url, if any> }",
            '      Return { outcome: "completed", ... } with the summary and ids.',
            "",
            "  4b. ON FAILURE (the work errored, not the claim) — RELEASE so the card",
            "      returns to the queue for a retry: kanban_release_card {",
            `        card_id: "${card.id}", claim_token: <token> }`,
            '      Return { outcome: "failed", detail: <what went wrong> }.',
            "",
            "Always set card_id in your returned JSON to your card's id.",
          ].join("\n"),
        );
      }),
    );
  });

  // ---------------------------------------------------------------------------
  // Summary. pipeline() chains the deterministic reduction over results so the
  // run's final value is a compact, machine-readable tally.
  // ---------------------------------------------------------------------------
  const summary = await pipeline(
    results,
    (rs) => rs.filter((r) => r && r.outcome === "completed").length,
    (completed) => ({
      board: planResult.board_id,
      board_name: planResult.board_name,
      total_cards: cards.length,
      completed,
      results,
    }),
  );

  log(
    `done: ${summary.completed}/${summary.total_cards} card(s) completed on board ${summary.board}`,
  );
  return summary;
}

// indent prefixes every line of `text` with `prefix`. Deterministic helper —
// no builtins. Used to lay the card body into the worker prompt readably.
function indent(text, prefix) {
  const body = typeof text === "string" ? text : String(text || "");
  return body
    .split("\n")
    .map((line) => prefix + line)
    .join("\n");
}
