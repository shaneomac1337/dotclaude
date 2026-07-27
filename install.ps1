#requires -Version 7
<#
  Installs this Claude Code setup into ~/.claude.
  - Copies CLAUDE.md, statusline.ps1, hooks, agents, workflows verbatim.
  - Writes settings.json with the __STATUSLINE__ / __HOOK_SKILL_EVAL__ placeholders
    resolved to pwsh invocations of the .ps1 scripts in your real home path.
  - Backs up anything it would overwrite to ~/.claude/backups/dotclaude-<timestamp>/.
  - Never touches credentials, history, sessions, or memory.

  Usage:   pwsh -File ./install.ps1
           pwsh -File ./install.ps1 -DryRun     # show what would happen, change nothing

  Linux/macOS counterpart: install.sh
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$repo      = $PSScriptRoot
$claudeDir = Join-Path $HOME '.claude'
# Forward slashes so the path works inside the JSON command string on all platforms.
$homeFwd   = ($HOME -replace '\\', '/')

$files = @(
  'CLAUDE.md',
  'statusline.ps1',
  'hooks/skill-forced-eval-hook.sh',
  'agents/Explore.md',
  'agents/code-reviewer.md',
  'agents/implementer.md',
  'agents/planner.md',
  'skills/dev-pipeline/pipeline.js',
  'skills/dev-pipeline/SKILL.md'
)

$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $claudeDir "backups/dotclaude-$stamp"

function Say($m) { Write-Host $m }

Say "Installing dotclaude -> $claudeDir$(if ($DryRun) { '   [DRY RUN]' })"

foreach ($rel in $files) {
  $src = Join-Path $repo $rel
  $dst = Join-Path $claudeDir ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
  if (-not (Test-Path $src)) { Say "  skip (missing in repo): $rel"; continue }

  $dstParent = Split-Path $dst -Parent
  if (Test-Path $dst) {
    $bak = Join-Path $backupDir $rel
    Say "  backup + copy: $rel"
    if (-not $DryRun) {
      New-Item -ItemType Directory -Force (Split-Path $bak -Parent) | Out-Null
      Copy-Item $dst $bak -Force
    }
  } else {
    Say "  copy: $rel"
  }
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force $dstParent | Out-Null
    Copy-Item $src $dst -Force
  }
}

# The hook runs through Git Bash even on Windows — there is deliberately no .ps1 twin,
# so the injected payload can never drift between platforms. Resolve bash.exe by absolute
# path: a bare `bash` on PATH usually hits WSL's System32 bash, which cannot read a
# Windows-style path. The statusline stays PowerShell — it does real path work.
$pf   = $env:ProgramFiles
$pf86 = ${env:ProgramFiles(x86)}
$bash = @(
  $(if ($pf)   { Join-Path $pf   'Git/bin/bash.exe' })
  $(if ($pf86) { Join-Path $pf86 'Git/bin/bash.exe' })
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bash) {
  # Fall back to deriving it from wherever git.exe lives (…/Git/cmd/git.exe -> …/Git/bin/bash.exe).
  $gitCmd = (Get-Command git -ErrorAction SilentlyContinue).Source
  if ($gitCmd) {
    $candidate = Join-Path (Split-Path (Split-Path $gitCmd -Parent) -Parent) 'bin/bash.exe'
    if (Test-Path $candidate) { $bash = $candidate }
  }
}
if (-not $bash) {
  Say "  WARNING: Git Bash (bash.exe) not found — the skill-eval hook needs it."
  Say "           Install Git for Windows, then fix hooks.UserPromptSubmit in settings.json by hand."
  $bash = 'bash'
}
$bashFwd = ($bash -replace '\\', '/')

# settings.json: resolve the command placeholders, then merge-or-write.
$settingsDst = Join-Path $claudeDir 'settings.json'
$rendered    = (Get-Content (Join-Path $repo 'settings.json') -Raw) `
  -replace '__STATUSLINE__',      "pwsh -NoProfile -File $homeFwd/.claude/statusline.ps1" `
  -replace '__HOOK_SKILL_EVAL__', "\`"$bashFwd\`" \`"$homeFwd/.claude/hooks/skill-forced-eval-hook.sh\`""
if (Test-Path $settingsDst) {
  Say "  NOTE: existing settings.json left in place. Review dotclaude's version and merge by hand:"
  Say "        repo:    $repo/settings.json  (with placeholders -> $homeFwd/.claude/...)"
  Say "        current: $settingsDst"
  $preview = Join-Path $claudeDir 'settings.dotclaude.json'
  if (-not $DryRun) { Set-Content -Path $preview -Value $rendered -Encoding utf8 }
  Say "        wrote resolved copy to: $preview"
} else {
  Say "  write: settings.json"
  if (-not $DryRun) { Set-Content -Path $settingsDst -Value $rendered -Encoding utf8 }
}

Say ""
Say "Done. Next steps (not automated — see README):"
Say "  1. Optional: chrome-devtools MCP: claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest"
Say "  2. Install Matt Pocock skills:   see README (they are not vendored here)"
Say "  3. Restart Claude Code so settings + statusline take effect."
