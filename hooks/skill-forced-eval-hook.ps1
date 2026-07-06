# UserPromptSubmit hook: force skill ACTIVATION, not just evaluation.
# Stdout is injected into the model's context for this turn. Fires on every prompt;
# the model itself skips the ceremony on trivial/conversational turns (see Exception).
# Wired in ~/.claude/settings.json under hooks.UserPromptSubmit.
# PowerShell (not bash) on purpose: immune to Git Bash path mangling on Windows.
@'
SKILL CHECK — do this before implementing or acting on a task request:

1. Consider the skills available to your Skill tool. Name ONLY the ones that match
   this request — one line each: [skill] — why it applies. Do not roll-call the
   others. If none match, say nothing about skills and proceed.
2. For each matched skill, call Skill(name) NOW — before writing code or taking
   action. Evaluation without the Skill() call accomplishes nothing.
3. Implement only after the matched skills are loaded.

Exception: skip this entirely on trivial or conversational turns (greetings,
acknowledgements, one-line factual questions) — just answer directly.
'@
