#!/usr/bin/env bash
#
# Installs this Claude Code setup into ~/.claude on Linux/macOS.
#   - Copies CLAUDE.md, statusline.sh, hooks, agents, and skills verbatim.
#   - Writes settings.json with the __STATUSLINE__ / __HOOK_SKILL_EVAL__ placeholders
#     resolved to the shell scripts in your real home path.
#   - Backs up anything it would overwrite to ~/.claude/backups/dotclaude-<timestamp>/.
#   - Never touches credentials, history, sessions, or memory.
#
# Usage:   ./install.sh
#          ./install.sh --dry-run     # show what would happen, change nothing
#
# Windows counterpart: install.ps1
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
claude_dir="$HOME/.claude"
dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

command -v jq >/dev/null || { echo "error: jq is required (statusline + settings merge). Install it first." >&2; exit 1; }

files=(
  CLAUDE.md
  statusline.sh
  hooks/skill-forced-eval-hook.sh
  agents/Explore.md
  agents/code-reviewer.md
  agents/implementer.md
  agents/planner.md
  skills/dev-pipeline/pipeline.js
  skills/dev-pipeline/SKILL.md
)

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$claude_dir/backups/dotclaude-$stamp"

echo "Installing dotclaude -> $claude_dir$([ "$dry_run" = 1 ] && echo '   [DRY RUN]')"

for rel in "${files[@]}"; do
  src="$repo/$rel"
  dst="$claude_dir/$rel"
  if [ ! -f "$src" ]; then echo "  skip (missing in repo): $rel"; continue; fi

  if [ -f "$dst" ]; then
    echo "  backup + copy: $rel"
    if [ "$dry_run" = 0 ]; then
      mkdir -p "$(dirname "$backup_dir/$rel")"
      cp -p "$dst" "$backup_dir/$rel"
    fi
  else
    echo "  copy: $rel"
  fi
  if [ "$dry_run" = 0 ]; then
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    case "$rel" in *.sh) chmod +x "$dst" ;; esac
  fi
done

# settings.json: resolve the command placeholders to the installed shell scripts,
# then merge into any existing settings (repo values win on conflicting keys).
settings_dst="$claude_dir/settings.json"
rendered="$(sed \
  -e "s|__STATUSLINE__|$claude_dir/statusline.sh|" \
  -e "s|__HOOK_SKILL_EVAL__|$claude_dir/hooks/skill-forced-eval-hook.sh|" \
  "$repo/settings.json")"

if [ -f "$settings_dst" ]; then
  echo "  backup + merge: settings.json (existing keys kept, dotclaude wins on conflicts)"
  if [ "$dry_run" = 0 ]; then
    mkdir -p "$backup_dir"
    cp -p "$settings_dst" "$backup_dir/settings.json"
    merged="$(jq -s '.[0] * .[1]' "$settings_dst" <(printf '%s' "$rendered"))"
    printf '%s\n' "$merged" > "$settings_dst"
  fi
else
  echo "  write: settings.json"
  if [ "$dry_run" = 0 ]; then
    mkdir -p "$claude_dir"
    printf '%s\n' "$rendered" > "$settings_dst"
  fi
fi

echo
echo "Done. Next steps (not automated — see README):"
echo "  1. Optional: claude-mem plugin   /plugin marketplace add thedotmack/claude-mem   then enable claude-mem"
echo "  2. Optional: chrome-devtools MCP  claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest"
echo "  3. Install Matt Pocock skills:    see README (they are not vendored here)"
echo "  4. Restart Claude Code so settings + statusline take effect."
