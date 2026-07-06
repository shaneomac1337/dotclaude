---
name: dev-pipeline
description: Tiered plan→explore→implement→review pipeline (Haiku explores, Opus plans, Sonnet implements, Opus reviews). On invocation, optionally grills the user first for a sharp understanding, then asks whether to run as a dynamic background Workflow or as inline in-session delegation. Use when the user wants to build/implement a feature or fix through the tiered pipeline. Pass the task as args.
---

# dev-pipeline

A tiered build pipeline — **Explore → Plan → Implement → Review** — that can run two ways:

- **Dynamic** — a background `Workflow` script (`pipeline.js`). Deterministic control flow, headless agents, output kept out of the main context. Best for larger fan-out, repeatable runs, and keeping the conversation clean.
- **Inline** — the same four tiers, but delegated *in this session* via the `Agent` tool. You stay in the loop, see each step, and can steer between tiers. Best for smaller tasks and when the user wants visibility/control.

Both use the same model tiering: **Haiku** explores (cheap, parallel, read-only), **Opus** plans, **Sonnet** implements, **Opus** reviews (judge ≥ implementer).

## Step 1 — Resolve the task, grill preference, and mode

1. **Task**: take it from `args`. Accept either a bare string or `{ task: "..." }`. Strip any flags out of the string. If no task is given, ask the user what to build and stop until you have it.
2. **Honor explicit flags** without asking about that choice:
   - Mode: `--dynamic` / `dynamic` / `--workflow` → Dynamic · `--inline` / `inline` / `--session` → Inline
   - Grill: `--grill` → grill first · `--no-grill` → skip grilling
3. For whatever wasn't set by a flag, **ask with a single `AskUserQuestion` call** (both questions in one prompt so it's one interaction):
   - Question `"Grill first?"` — **Yes, grill first** ("Interview me to sharpen the task before building — best understanding, fewer wrong turns.") · **No, go straight in** ("Skip the interview and start the pipeline now.")
   - Question `"Run mode"` — **Dynamic (background workflow)** ("Runs pipeline.js headless in the background. Deterministic, parallel, output stays out of the main context. Good for bigger or repeatable tasks.") · **Inline (in-session)** ("I run the four tiers here via subagents. You see each step and can steer between tiers. Good for smaller tasks you want to watch.")

Then do Step 1.5 if grilling was chosen, otherwise go to Step 2.

## Step 1.5 — Grill first (optional)

If grilling was chosen, invoke the **`grilling`** skill (`Skill(grilling)`) focused on this task: interview the user one question at a time, looking up facts in the codebase rather than asking, until you reach a confirmed shared understanding. Do **not** start building until they confirm.

When grilling concludes, **distill the outcome into a sharpened task brief** — the refined objective plus any constraints, decisions, and scope boundaries that surfaced. Use that brief (not the raw original string) as `<task>` everywhere in Step 2. In Dynamic mode, pass the full brief as the workflow's `task` arg so the headless run inherits everything the grilling established.

## Step 2a — Dynamic mode

Call the `Workflow` tool with:

- `scriptPath`: the `pipeline.js` file **in this skill's own directory** (alongside this SKILL.md). On this machine that resolves to `__HOME__\.claude\skills\dev-pipeline\pipeline.js`.
- `args`: `{ task: "<the resolved task>" }`

The workflow returns a summary with the task count and any items flagged `changes-needed`. Relay that back to the user — don't dump raw agent transcripts. If items need changes, offer to address them (either another dynamic pass or inline fixes).

## Step 2b — Inline mode

Run the four tiers yourself using the `Agent` tool, mapping each tier to the matching agent type in the fleet. Report a one-line status as each tier completes.

1. **Explore** (read-only, cheap, parallel). Spawn **two `Explore` agents in one message** so they run concurrently:
   - Agent A: "Read-only. Locate the files, functions, and configs relevant to this task and summarize concisely how the area works now, with `path:line` refs. Do NOT edit. Task: `<task>`"
   - Agent B: "Read-only. Find existing tests, naming conventions, and any prior/similar implementations relevant to this task, so an implementer can match the codebase. Do NOT edit. Task: `<task>`"
   - Combine their findings into a short context block.

2. **Plan** (Opus architect). Spawn one `planner` agent: "Produce an ordered implementation plan broken into well-scoped tasks a Sonnet implementer can execute without re-deriving context. Each task needs a clear objective, the files it touches, and how to verify it. GOAL: `<task>`. EXPLORATION FINDINGS: `<context>`." Get back an ordered task list. If it returns no tasks, report that and stop.

3. **Implement** (Sonnet). For each planned task, spawn an `implementer` agent: "Implement ONLY this task, matching the codebase's style and adding/updating tests. Run tests if possible and report the real result. TASK: `<task JSON>`. OVERALL GOAL: `<task>`." If the plan's tasks are independent, you may run implementers in parallel; if they touch **overlapping files**, run them sequentially (or use `isolation: 'worktree'`) to avoid clobbering.

4. **Review** (Opus, judge ≥ implementer). For each implemented task, spawn a `code-reviewer` agent: "Rigorously review this change for correctness (logic, edge cases, error handling, security) then quality. Give concrete findings as file + failure scenario + fix. If clean, verdict 'pass'. TASK: `<objective>`. VERIFY BY: `<verification>`. WHAT THE IMPLEMENTER REPORTED: `<impl result>`." Run reviews as each implementation lands.

Finish with a short summary: tasks done, review verdicts, and anything flagged `changes-needed`. Offer to fix flagged items.

## Notes

- **Same working tree** in both modes: parallel implementers on overlapping files can conflict. The planner is told to scope tasks so they don't overlap; when they do, serialize or isolate.
- The dynamic engine lives at `pipeline.js` in this folder. Keep the two paths behaviorally aligned when editing either.
