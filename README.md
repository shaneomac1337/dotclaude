# dotclaude

My [Claude Code](https://claude.com/claude-code) setup — global instructions, a statusline,
a skill-activation hook, a tiered subagent fleet, and a dev pipeline workflow.

Cross-platform, but not symmetrically:

- **Statusline** ships twice — `statusline.sh` (bash + `jq`) and `statusline.ps1`
  (PowerShell 7+). It does real path work, so each platform gets a native version.
- **Skill-eval hook** ships **once**, as `.sh`. There is deliberately **no `.ps1` twin** —
  see below. On Windows it runs through Git Bash.

Run the installer for your platform; it wires `settings.json` to the right commands.
The Markdown and JS pieces are shared.

> This repo is **curated and copied _into_ `~/.claude`** — it is deliberately **not** a clone
> of `~/.claude` itself. Credentials, chat history, sessions, and memory never live here.

## What's inside

| File | What it does |
|------|--------------|
| `CLAUDE.md` | Global behavioral guidelines — think-before-coding, simplicity, surgical changes, goal-driven execution. Distilled from Andrej Karpathy's Jan 2026 notes on LLM coding pitfalls. |
| `statusline.sh` / `statusline.ps1` | One-line statusline: `📁 dir · 🌿 branch · 🧠 model · 📊 context bar · 💰 cost · ⏱ duration`. The context bar is **1M-context-aware** (auto-detects `[1m]` model variants) and shifts green→yellow→red as it fills. |
| `hooks/skill-forced-eval-hook.sh` | `UserPromptSubmit` hook that injects a mandatory skill-activation sequence — evaluate every available skill, then actually *call* `Skill()` instead of just thinking about it. Payload is verbatim from [spences10/svelte-claude-skills](https://github.com/spences10/svelte-claude-skills/blob/main/.claude/hooks/skill-forced-eval-hook.sh). **`.sh` on every platform, Windows included.** |
| `settings.json` | Wires up the statusline and the hook. The two commands are `__STATUSLINE__` / `__HOOK_SKILL_EVAL__` placeholders that each installer resolves to the right script for the platform. |
| `agents/` | A model-tiered subagent fleet: `Explore` (Haiku, cheap read-only search), `implementer` (Sonnet), `planner` (Opus, xhigh), `code-reviewer` (Opus, high). |
| `skills/dev-pipeline/` | My own skill: a tiered **Explore → Plan → Implement → Review** pipeline (Haiku → Opus → Sonnet → Opus) that runs either as a **dynamic** background `Workflow` (`pipeline.js`) or **inline** in-session via subagents. Optionally grills you first to sharpen the task. |

## Install

**Linux / macOS** — needs `bash` and [`jq`](https://jqlang.github.io/jq/):

```bash
git clone https://github.com/<you>/dotclaude.git
cd dotclaude
./install.sh --dry-run   # preview — changes nothing
./install.sh             # copy into ~/.claude (backs up anything it overwrites)
```

An existing `~/.claude/settings.json` is backed up and then **merged** with `jq` — your own
keys survive, dotclaude wins on conflicts.

**Windows** — needs PowerShell 7+ **and [Git for Windows](https://gitforwindows.org/)** (for
Git Bash, which runs the hook):

```powershell
pwsh -File ./install.ps1 -DryRun   # preview — changes nothing
pwsh -File ./install.ps1           # copy into ~/.claude (backs up anything it overwrites)
```

There, an existing `~/.claude/settings.json` is left alone — the installer drops a resolved
copy at `~/.claude/settings.dotclaude.json` for you to merge by hand.

Both installers back up whatever they overwrite to `~/.claude/backups/dotclaude-<timestamp>/`.
Restart Claude Code afterwards so the statusline and hook take effect.

### Why the hook has no PowerShell version

Do **not** reintroduce a `.ps1` hook, even on Windows. The payload it emits is upstream text
that must stay byte-identical; a second copy is a second thing to forget to update, and that
has already gone wrong once. One file, one payload.

Git Bash's usual objection — MSYS path mangling — doesn't apply here: the hook is a bare
heredoc that takes no arguments and touches no paths. The statusline is the opposite (it does
`$HOME` prefix matching, `git -C "$cwd"`, and `-f` tests on a `C:\…` transcript path), which
is exactly why *that* one stays PowerShell on Windows.

`install.ps1` resolves `bash.exe` by absolute path under `%ProgramFiles%\Git\bin`, falling
back to deriving it from `git.exe`'s location. It deliberately does **not** trust a bare
`bash` on `PATH` — that usually resolves to **WSL's** `bash.exe` in `System32`, which can't
read a Windows-style path and would silently break the hook.

## Not included — install these yourself

Some things in my setup are third-party and aren't vendored here (licensing / they have their
own homes). Install them separately:

- **chrome-devtools MCP** (drive a real Chrome from Claude):
  ```
  claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest
  ```
- **Matt Pocock's engineering skills** — most of my `skills/` folder is his published bundle
  (`grill-*`, `writing-*`, `to-prd`, `triage`, `domain-modeling`, `codebase-design`, `teach`,
  `edit-article`, …). Install from the source rather than copying mine. See
  [Matt Pocock's skills](https://github.com/mattpocock) / the AI Hero project.
- A few Anthropic-shipped example skills (`setup-pre-commit`, `git-guardrails-claude-code`,
  `resolving-merge-conflicts`) ship with Claude Code / its plugin marketplaces.

## Security note

Nothing secret is in this repo, and the `.gitignore` blocks the usual offenders as a backstop.
Two things that live in Claude Code but must **never** be committed anywhere:

- `~/.claude/.credentials.json` — your OAuth token.
- `~/.claude.json` — may contain **MCP server tokens** (Jira/Confluence PATs, API keys) in
  plaintext. Keep it off GitHub.
