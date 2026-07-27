#!/usr/bin/env bash
# Claude Code statusline — bash + jq (Linux/macOS twin of statusline.ps1)
# Reads session JSON from stdin, prints one colorful line with emoji segments.
# Segments: directory | git branch | model | context usage | cost | duration
# Docs: https://docs.claude.com/en/docs/claude-code/statusline

# --- config ---
# Fallback context window for computing "% full" when the model can't be detected.
# Auto-detection below bumps this to 1000000 for 1M-context model variants.
CONTEXT_LIMIT_DEFAULT=200000

# Force '.' as the decimal separator regardless of the user's locale.
export LC_NUMERIC=C

# ANSI helpers
esc=$'\033'
reset="${esc}[0m"
dim="${esc}[2m"
col() { printf '%s[%sm%s%s' "$esc" "$1" "$2" "$reset"; }
sep="$(col 90 '  ')"   # dim separator

# --- read input ---
raw="$(cat)"
[ -n "$raw" ] || exit 0

# Split on 0x1F (unit separator), not tab: tab is IFS-whitespace, so bash would
# collapse consecutive tabs and shift every field left whenever one comes back empty.
IFS=$'\x1f' read -r cwd model_name model_id transcript cost dur_ms < <(
  printf '%s' "$raw" | jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.model.id // ""),
    (.transcript_path // ""),
    (.cost.total_cost_usd // ""),
    (.cost.total_duration_ms // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null
)

# Detect the real context window from the active model. 1M-context variants carry
# "[1m]" in their id (e.g. claude-opus-4-8[1m]) or "1M" in the display name.
context_limit=$CONTEXT_LIMIT_DEFAULT
model_str="$model_id $model_name"
shopt -s nocasematch
if [[ "$model_str" == *"[1m]"* || "$model_str" =~ (^|[^a-z0-9])1m([^a-z0-9]|$) ]]; then
  context_limit=1000000
fi
shopt -u nocasematch

segments=()

# --- directory ---
if [ -n "$cwd" ]; then
  disp="$cwd"
  case "$disp" in "$HOME"*) disp="~${disp#"$HOME"}" ;; esac
  # keep only the last 2 path parts to stay short
  IFS='/' read -r -a parts <<< "$disp"
  clean=()
  for p in "${parts[@]}"; do [ -n "$p" ] && clean+=("$p"); done
  n=${#clean[@]}
  if [ "$n" -gt 2 ]; then
    disp="…/${clean[n-2]}/${clean[n-1]}"
  else
    disp="$(IFS='/'; printf '%s' "${clean[*]}")"
  fi
  segments+=("$(col 36 "📁 $disp")")   # cyan
fi

# --- git branch + dirty state ---
if [ -n "$cwd" ]; then
  branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
      segments+=("$(col 33 "🌿 $branch ✱")")   # yellow = uncommitted changes
    else
      segments+=("$(col 32 "🌿 $branch")")     # green = clean
    fi
  fi
fi

# --- model ---
[ -n "$model_name" ] && segments+=("$(col 35 "🧠 $model_name")")   # magenta

# --- context usage (from transcript) ---
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  tok="$(
    grep '"usage"' "$transcript" 2>/dev/null | tac | jq -Rr '
      fromjson? | (try .message.usage catch empty) | select(. != null)
      | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
    ' 2>/dev/null | head -n1
  )"
  if [ -n "$tok" ] && [ "$tok" -gt 0 ] 2>/dev/null; then
    pct=$(( tok * 100 / context_limit ))
    [ "$pct" -gt 100 ] && pct=100
    k="$(awk -v t="$tok" 'BEGIN { printf "%.1f", t/1000 }')"
    # progress bar: fill proportional to %, color shifts as it fills
    width=10
    filled=$(( pct * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    if   [ "$pct" -ge 80 ]; then ccol=31   # red
    elif [ "$pct" -ge 50 ]; then ccol=33   # yellow
    else                         ccol=32   # green
    fi
    full=""; empty=""
    for ((i=0; i<filled; i++)); do full+="█"; done
    for ((i=filled; i<width; i++)); do empty+="░"; done
    segments+=("📊 $(col "$ccol" "$full")$(col 90 "$empty") $(col "$ccol" "${pct}%")$(col 90 " ${k}k")")
  fi
fi

# --- cost + duration ---
if [ -n "$cost" ]; then
  if awk -v c="$cost" 'BEGIN { exit !(c < 0.01) }'; then
    cost_str="\$$(awk -v c="$cost" 'BEGIN { printf "%.4f", c }')"
  else
    cost_str="\$$(awk -v c="$cost" 'BEGIN { printf "%.2f", c }')"
  fi
  segments+=("$(col 33 "💰 $cost_str")")
fi

if [ -n "$dur_ms" ] && [ "${dur_ms%.*}" -gt 0 ] 2>/dev/null; then
  sec=$(( ${dur_ms%.*} / 1000 ))
  if [ "$sec" -lt 60 ]; then
    dur_str="${sec}s"
  else
    m=$(( sec / 60 )); s=$(( sec % 60 ))
    if [ "$m" -lt 60 ]; then dur_str="${m}m${s}s"; else dur_str="$(( m / 60 ))h$(( m % 60 ))m"; fi
  fi
  segments+=("${dim}⏱ ${dur_str}${reset}")
fi

# --- emit ---
out=""
for i in "${!segments[@]}"; do
  [ "$i" -gt 0 ] && out+="$sep"
  out+="${segments[i]}"
done
printf '%s' "$out"
