export const meta = {
  name: 'dev-pipeline',
  description: 'Tiered plan→explore→implement→review pipeline: Haiku explores, Opus plans, Sonnet implements, Opus reviews. Pass the task via args.',
  phases: [
    { title: 'Explore', detail: 'Haiku agents map the relevant code (cheap, parallel)', model: 'haiku' },
    { title: 'Plan', detail: 'Opus architect produces a scoped task breakdown', model: 'opus' },
    { title: 'Implement', detail: 'Sonnet implements each task', model: 'sonnet' },
    { title: 'Review', detail: 'Opus verifies each change (judge >= implementer)', model: 'opus' },
  ],
}

// ---- input ----
// Invoke with args: { task: "add rate limiting to the upload endpoint" }
// (a bare string also works)
const task = (args && args.task) ? args.task : args
if (!task || typeof task !== 'string') {
  log('No task provided. Pass args: { task: "<what to build>" }')
  return { error: 'no task provided' }
}
log(`Pipeline task: ${task}`)

// ---- schemas ----
const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'One-paragraph approach summary' },
    tasks: {
      type: 'array',
      description: 'Ordered, well-scoped implementation tasks',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          objective: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          verification: { type: 'string', description: 'How to confirm this task is done' },
        },
        required: ['id', 'objective', 'verification'],
      },
    },
  },
  required: ['summary', 'tasks'],
}

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'changes-needed'] },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
          summary: { type: 'string' },
          file: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'summary'],
      },
    },
  },
  required: ['verdict'],
}

// ---- Phase 1: Explore (Haiku, cheap + parallel, read-only) ----
phase('Explore')
const exploreAngles = [
  `Read-only exploration. Locate the files, functions, and configs relevant to this task and summarize concisely how the area currently works (use path:line refs). Do NOT edit anything. Task: ${task}`,
  `Read-only exploration. Find existing tests, naming conventions, and any prior/similar implementations relevant to this task, so an implementer can match the codebase. Do NOT edit. Task: ${task}`,
]
const exploreResults = await parallel(exploreAngles.map((q, i) => () =>
  agent(q, { label: `explore:${i + 1}`, phase: 'Explore', model: 'haiku', effort: 'low' })
))
const context = exploreResults.filter(Boolean).join('\n\n---\n\n')
log(`Exploration gathered from ${exploreResults.filter(Boolean).length} agent(s).`)

// ---- Phase 2: Plan (Opus at max effort — decomposition drives everything) ----
phase('Plan')
const plan = await agent(
  `You are a senior software architect. Produce an ordered implementation plan, broken into well-scoped tasks that a Sonnet implementer can execute without re-deriving context. Each task needs a clear objective, the files it touches, and how to verify it.\n\nGOAL: ${task}\n\nEXPLORATION FINDINGS:\n${context || '(none gathered)'}`,
  { label: 'plan', phase: 'Plan', model: 'opus', effort: 'xhigh', schema: PLAN_SCHEMA }
)
if (!plan || !plan.tasks || !plan.tasks.length) {
  log('Planner returned no tasks; stopping.')
  return { plan }
}
log(`Plan: ${plan.tasks.length} task(s). ${plan.summary}`)

// ---- Phase 3+4: Implement each task (Sonnet), then Review it (Opus) ----
// Pipeline: each task is reviewed as soon as its implementation completes.
// NOTE: agents run against the SAME working tree. If your tasks edit overlapping
// files, add `isolation: 'worktree'` to the implement stage and merge results
// yourself — otherwise keep tasks non-overlapping (the planner is told to scope them).
const outcomes = await pipeline(
  plan.tasks,
  (t) => agent(
    `You are a focused implementer on Sonnet. Implement ONLY this task, matching the codebase's style and adding/updating tests. Run tests if possible and report the real result.\n\nTASK: ${JSON.stringify(t)}\n\nOVERALL GOAL: ${task}`,
    { label: `impl:${t.id}`, phase: 'Implement', model: 'sonnet', effort: 'medium' }
  ),
  (implResult, t) => agent(
    `You are a rigorous code reviewer on Opus — a quality gate at least as capable as the implementer. Review the change for correctness (logic, edge cases, error handling, security) then quality. Give concrete findings with file + failure scenario + fix. If clean, verdict "pass".\n\nTASK: ${t.objective}\nVERIFY BY: ${t.verification}\n\nWHAT THE IMPLEMENTER REPORTED:\n${implResult || '(no output)'}`,
    { label: `review:${t.id}`, phase: 'Review', model: 'opus', effort: 'high', schema: REVIEW_SCHEMA }
  ).then((review) => ({ task: t, review }))
)

const results = outcomes.filter(Boolean)
const needChanges = results.filter(r => r.review && r.review.verdict === 'changes-needed')
log(`Done. ${results.length} task(s) reviewed; ${needChanges.length} need changes.`)

return {
  task,
  summary: plan.summary,
  tasks: plan.tasks.length,
  needChanges: needChanges.map(r => ({ id: r.task.id, objective: r.task.objective, findings: r.review.findings })),
  results,
}
