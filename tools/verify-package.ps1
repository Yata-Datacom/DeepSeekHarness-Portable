# ============================================================
#  DSH Portable - built package integrity check
#
#  Runs against <repo>\out\DSH-Portable (or -Pkg <path>).
#  This is the "do not trust the build" gate: it re-checks the
#  invariants that previously bit us, on the real artifact.
#
#  Exit code 0 = all good, 1 = something is wrong.
#
#  NOTE: ASCII only, on purpose. Windows PowerShell 5.1 reads a
#  BOM-less .ps1 as ANSI, so non-ASCII string literals (including
#  Get-ChildItem -Filter patterns such as '*\u8bf4\u660e*') silently
#  stop matching. Localized filenames are therefore detected with a
#  non-ASCII regex instead of a literal.
# ============================================================
param(
    [string]$Pkg = (Join-Path (Split-Path $PSScriptRoot -Parent) 'out\DSH-Portable')
)
$ErrorActionPreference = 'Stop'
$fail = @()
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  OK   {0}" -f $name) -ForegroundColor Green }
    else { Write-Host ("  FAIL {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail += $name }
}
function Has($p) { Test-Path -LiteralPath $p }

Write-Host "verifying: $Pkg"
if (-not (Has $Pkg)) { Write-Host "  FATAL: package not found" -ForegroundColor Red; exit 1 }

# ---------- 1) top-level layout ----------
foreach ($d in @('node', 'launcher', 'bin', 'assets', 'config', 'data\.dsh', 'seed\.dsh', 'tools')) {
    Check "dir $d" (Has (Join-Path $Pkg $d))
}
Check "entry start-dsh.cmd"       (Has (Join-Path $Pkg 'start-dsh.cmd'))
Check "entry .vbs present"        (@(Get-ChildItem -LiteralPath $Pkg -Filter '*.vbs' -ErrorAction SilentlyContinue).Count -ge 1)
Check "launcher .exe present"     (@(Get-ChildItem -LiteralPath $Pkg -Filter '*.exe' -ErrorAction SilentlyContinue).Count -ge 1)
Check "readme .md present"        (@(Get-ChildItem -LiteralPath $Pkg -Filter '*.md' -ErrorAction SilentlyContinue).Count -ge 1)
# localized (non-ASCII) doc filenames, e.g. the Chinese quick-start
Check "localized doc present"     (@(Get-ChildItem -LiteralPath $Pkg -File -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Name -match '[^\x20-\x7E]' }).Count -ge 1)

# ---------- 2) runtime ----------
Check "node\node.exe"             (Has (Join-Path $Pkg 'node\node.exe'))
Check "dsh module present"        (Has (Join-Path $Pkg 'node\node_modules\@deepseek-ai\dsh\package.json'))
Check "bin\dsh.cmd"               (Has (Join-Path $Pkg 'bin\dsh.cmd'))

# ---------- 3) the 3 plugins must be inside the packaged profile ----------
$pm = Join-Path $Pkg 'data\.dsh\profiles\web\node_modules'
foreach ($plugin in @('dsh-whale-widget', 'open-sea-skin', 'dsh-whale-galgame')) {
    Check "plugin $plugin" (Has (Join-Path $pm $plugin))
}
Check "profile package.json"      (Has (Join-Path $Pkg 'data\.dsh\profiles\web\package.json'))
Check "profile lockfile"          (Has (Join-Path $Pkg 'data\.dsh\profiles\web\pnpm-lock.yaml'))

# ---------- 4) seed mirrors data (restore target) ----------
foreach ($plugin in @('dsh-whale-galgame', 'dsh-whale-widget', 'open-sea-skin')) {
    Check "seed has $plugin" (Has (Join-Path $Pkg "seed\.dsh\profiles\web\node_modules\$plugin"))
}
Check "seed settings.yaml"        (Has (Join-Path $Pkg 'seed\.dsh\settings.yaml'))

# ---------- 5) leak / privacy gates ----------
foreach ($f in @('config\api-key.txt',
                 'data\.dsh\.credentials.yaml', 'seed\.dsh\.credentials.yaml',
                 'data\.dsh\AGENTS.md',        'seed\.dsh\AGENTS.md',
                 'data\.dsh\.dshw-turn.json',  'seed\.dsh\.dshw-turn.json',
                 'data\.dsh\.dshw-usage.json', 'seed\.dsh\.dshw-usage.json',
                 'data\.dsh\.anonymous-user-id')) {
    Check "absent: $f" (-not (Has (Join-Path $Pkg $f)))
}
Check "config placeholder kept"   (@(Get-ChildItem -LiteralPath (Join-Path $Pkg 'config') -ErrorAction SilentlyContinue).Count -ge 1)

# ---------- 6) no symlinks / reparse points anywhere (tar would follow them) ----------
$links = @(Get-ChildItem -LiteralPath $Pkg -Recurse -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
Check "0 reparse points" ($links.Count -eq 0) ("found $($links.Count)")
if ($links.Count -gt 0) { $links | Select-Object -First 5 | ForEach-Object { Write-Host "       $($_.FullName)" } }

# ---------- 7) no live API key text in the small config/launcher files ----------
$pat = 'sk-[A-Za-z0-9]{20,}'
$hits = @()
foreach ($d in @('config', 'launcher', 'bin', 'entry')) {
    $p = Join-Path $Pkg $d
    if (Has $p) {
        Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Length -lt 4MB -and (Select-String -LiteralPath $_.FullName -Pattern $pat -Quiet -ErrorAction SilentlyContinue)) {
                $hits += $_.FullName
            }
        }
    }
}
Check "no sk- key material" ($hits.Count -eq 0) ($hits -join '; ')

# ---------- summary ----------
$size  = (Get-ChildItem -LiteralPath $Pkg -Recurse -File -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum
$files = @(Get-ChildItem -LiteralPath $Pkg -Recurse -File -Force -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host ("package: {0:N1} MB, {1} files" -f ($size / 1MB), $files)
if ($fail.Count -gt 0) {
    Write-Host ("VERIFY FAILED: {0} check(s)" -f $fail.Count) -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "VERIFY PASSED - all checks green" -ForegroundColor Green
exit 0
