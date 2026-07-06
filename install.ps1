#requires -Version 7
<#
  Installs this Claude Code setup into ~/.claude.
  - Copies CLAUDE.md, statusline.ps1, hooks, agents, workflows verbatim.
  - Writes settings.json with the __HOME__ placeholder resolved to your real home path.
  - Backs up anything it would overwrite to ~/.claude/backups/dotclaude-<timestamp>/.
  - Never touches credentials, history, sessions, or memory.

  Usage:   pwsh -File ./install.ps1
           pwsh -File ./install.ps1 -DryRun     # show what would happen, change nothing
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
  'hooks/skill-forced-eval-hook.ps1',
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

# settings.json: resolve the __HOME__ placeholder, then merge-or-write.
$settingsDst = Join-Path $claudeDir 'settings.json'
$rendered    = (Get-Content (Join-Path $repo 'settings.json') -Raw) -replace '__HOME__', $homeFwd
if (Test-Path $settingsDst) {
  Say "  NOTE: existing settings.json left in place. Review dotclaude's version and merge by hand:"
  Say "        repo:    $repo/settings.json  (with __HOME__ -> $homeFwd)"
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
Say "  1. Install claude-mem plugin:   /plugin marketplace add thedotmack/claude-mem  then enable claude-mem"
Say "  2. Add chrome-devtools MCP:      claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest"
Say "  3. Install Matt Pocock skills:   see README (they are not vendored here)"
Say "  4. Restart Claude Code so settings + statusline take effect."
