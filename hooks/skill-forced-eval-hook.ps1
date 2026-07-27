# UserPromptSubmit hook: force skill ACTIVATION, not just evaluation.
# Stdout is injected into the model's context for this turn.
# Wired in ~/.claude/settings.json under hooks.UserPromptSubmit.
# PowerShell (not bash) on purpose: immune to Git Bash path mangling on Windows.
# Windows twin of skill-forced-eval-hook.sh — keep the two payloads in sync.
#
# The payload below is verbatim from spences10/svelte-claude-skills:
# https://github.com/spences10/svelte-claude-skills/blob/main/.claude/hooks/skill-forced-eval-hook.sh
@'
INSTRUCTION: MANDATORY SKILL ACTIVATION SEQUENCE

Step 1 - EVALUATE (do this in your response):
For each skill in <available_skills>, state: [skill-name] - YES/NO - [reason]

Step 2 - ACTIVATE (do this immediately after Step 1):
IF any skills are YES → Use Skill(skill-name) tool for EACH relevant skill NOW
IF no skills are YES → State "No skills needed" and proceed

Step 3 - IMPLEMENT:
Only after Step 2 is complete, proceed with implementation.

CRITICAL: You MUST call Skill() tool in Step 2. Do NOT skip to implementation.
The evaluation (Step 1) is WORTHLESS unless you ACTIVATE (Step 2) the skills.

Example of correct sequence:
- research: NO - not a research task
- svelte5-runes: YES - need reactive state
- sveltekit-structure: YES - creating routes

[Then IMMEDIATELY use Skill() tool:]
> Skill(svelte5-runes)
> Skill(sveltekit-structure)

[THEN and ONLY THEN start implementation]
'@
