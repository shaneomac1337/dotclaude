# Claude Code statusline — PowerShell
# Reads session JSON from stdin, prints one colorful line with emoji segments.
# Segments: directory | git branch | model | context usage | cost | duration
# Docs: https://docs.claude.com/en/docs/claude-code/statusline

# --- config ---
# Fallback context window for computing "% full" when the model can't be detected.
# Auto-detection below bumps this to 1000000 for 1M-context model variants.
$ContextLimitDefault = 200000

# --- setup ---
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# ANSI helpers
$e     = [char]27
$reset = "$e[0m"
$dim   = "$e[2m"
function Col($code, $text) { "$e[${code}m$text$reset" }
$sep = Col '90' '  '   # dim separator

# --- read input ---
$raw = [Console]::In.ReadToEnd()
if (-not $raw) { return }
$data = $raw | ConvertFrom-Json

# Detect the real context window from the active model. 1M-context variants carry
# "[1m]" in their id (e.g. claude-opus-4-8[1m]) or "1M" in the display name.
$ContextLimit = $ContextLimitDefault
$modelStr = "$($data.model.id) $($data.model.display_name)"
if ($modelStr -match '\[1m\]|\b1m\b') { $ContextLimit = 1000000 }

$segments = @()

# --- directory ---
$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = $data.cwd }
if ($cwd) {
    $home = [Environment]::GetFolderPath('UserProfile')
    $disp = $cwd
    if ($disp.StartsWith($home)) { $disp = '~' + $disp.Substring($home.Length) }
    # keep only the last 2 path parts to stay short
    $parts = $disp -split '[\\/]' | Where-Object { $_ -ne '' }
    if ($parts.Count -gt 2) { $disp = '…/' + ($parts[-2..-1] -join '/') }
    else { $disp = $parts -join '/' }
    $segments += Col '36' "📁 $disp"   # cyan
}

# --- git branch + dirty state ---
if ($cwd) {
    $branch = (git -C "$cwd" rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $branch) {
        $dirty = (git -C "$cwd" status --porcelain 2>$null)
        if ($dirty) {
            $segments += Col '33' "🌿 $branch ✱"   # yellow = uncommitted changes
        } else {
            $segments += Col '32' "🌿 $branch"      # green = clean
        }
    }
}

# --- model ---
$model = $data.model.display_name
if ($model) { $segments += Col '35' "🧠 $model" }   # magenta

# --- context usage (from transcript) ---
$transcript = $data.transcript_path
if ($transcript -and (Test-Path $transcript)) {
    $lastUsage = $null
    foreach ($line in [System.IO.File]::ReadLines($transcript)) {
        if ($line -notmatch '"usage"') { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ($o.message.usage) { $lastUsage = $o.message.usage }
    }
    if ($lastUsage) {
        $tok = [int]$lastUsage.input_tokens +
               [int]$lastUsage.cache_read_input_tokens +
               [int]$lastUsage.cache_creation_input_tokens
        $inv = [cultureinfo]::InvariantCulture
        $pct = [math]::Round(($tok / $ContextLimit) * 100)
        if ($pct -gt 100) { $pct = 100 }
        $k   = ([math]::Round($tok / 1000, 1)).ToString($inv)
        # progress bar: fill proportional to %, color shifts as it fills
        $width  = 10
        $filled = [int][math]::Floor($pct / 100 * $width)
        if ($filled -lt 0)      { $filled = 0 }
        if ($filled -gt $width) { $filled = $width }
        $ccol = if ($pct -ge 80) { '31' } elseif ($pct -ge 50) { '33' } else { '32' }  # red / yellow / green
        $bar  = (Col $ccol ('█' * $filled)) + (Col '90' ('░' * ($width - $filled)))
        $segments += "📊 $bar " + (Col $ccol "$pct%") + (Col '90' " ${k}k")
    }
}

# --- cost + duration ---
$cost = $data.cost.total_cost_usd
if ($null -ne $cost) {
    $ic = [cultureinfo]::InvariantCulture
    $costStr = if ($cost -lt 0.01) { '$' + ([double]$cost).ToString('N4', $ic) }
               else { '$' + ([double]$cost).ToString('N2', $ic) }
    $segments += Col '33' "💰 $costStr"
}
$durMs = $data.cost.total_duration_ms
if ($durMs) {
    $sec = [int]($durMs / 1000)
    if ($sec -lt 60) { $durStr = "${sec}s" }
    else {
        $m = [int]($sec / 60); $s = $sec % 60
        $durStr = if ($m -lt 60) { "${m}m${s}s" } else { "$([int]($m/60))h$($m%60)m" }
    }
    $segments += "$dim⏱ $durStr$reset"
}

# --- emit ---
[Console]::Out.Write(($segments -join $sep))
