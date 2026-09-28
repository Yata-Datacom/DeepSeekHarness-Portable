# ============================================================
#  DSH Portable - CI prepare step
#
#  1) writes a pristine $DshHome from ci-profile/ (committed profile config)
#  2) installs pnpm and runs `pnpm install --frozen-lockfile`
#     -> the profile's deps are reproduced EXACTLY from the committed lockfile
#  3) builds the staging layout build-package.ps1 expects:
#         staging\node  -> junction to the Node install dir (holds dsh)
#         staging\pack  -> junction to the repo root (= pack/ content)
#
#  Usage: pwsh -File tools/ci-prepare.ps1 [-PnpmVersion 10]
#
#  NOTE: ASCII only on purpose - Windows PowerShell 5.1 reads a BOM-less
#        .ps1 as ANSI and would mangle non-ASCII characters.
# ============================================================
param(
    [string]$RepoRoot    = (Split-Path $PSScriptRoot -Parent),
    [string]$DshHome     = (Join-Path $env:USERPROFILE '.dsh'),
    [string]$Staging     = (Join-Path (Split-Path $PSScriptRoot -Parent) 'staging'),
    [string]$PnpmVersion = '10'
)
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "[ci-prepare] $m" }

# ---------- 1) profile config ----------
$src    = Join-Path $RepoRoot 'ci-profile'
$dstWeb = Join-Path $DshHome 'profiles\web'
New-Item -ItemType Directory -Path $dstWeb -Force | Out-Null
foreach ($f in @('package.json','pnpm-lock.yaml','cordis.yml','cordis.patch.yml','pnpm-workspace.yaml')) {
    Copy-Item -LiteralPath (Join-Path $src "web\$f") -Destination (Join-Path $dstWeb $f) -Force
}
Copy-Item -LiteralPath (Join-Path $src 'settings.yaml') -Destination (Join-Path $DshHome 'settings.yaml') -Force
Say "profile config -> $dstWeb"

# ---------- 2) pnpm ----------
Say "installing pnpm@$PnpmVersion"
& npm install -g "pnpm@$PnpmVersion" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "npm install -g pnpm failed (exit $LASTEXITCODE)" }

Push-Location $dstWeb
try {
    Say 'pnpm install --frozen-lockfile'
    & pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { throw "pnpm install --frozen-lockfile failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }
Say 'profile deps installed from the lockfile'

# ---------- 3) staging layout ----------
if (Test-Path -LiteralPath $Staging) {
    Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $Staging -Force | Out-Null

$nodeDir = Split-Path (Get-Command node).Source -Parent
New-Item -ItemType Junction -Path (Join-Path $Staging 'node') -Target $nodeDir | Out-Null
New-Item -ItemType Junction -Path (Join-Path $Staging 'pack') -Target $RepoRoot | Out-Null
Say "staging: node -> $nodeDir"
Say "staging: pack -> $RepoRoot"

# ---------- 4) sanity ----------
$dshPkg = Join-Path $nodeDir 'node_modules\@deepseek-ai\dsh\package.json'
if (-not (Test-Path -LiteralPath $dshPkg)) {
    throw "dsh is not installed inside the Node dir ($dshPkg). Set npm prefix to the Node dir first."
}
$v = (Get-Content -LiteralPath $dshPkg -Raw | ConvertFrom-Json).version
Say "dsh $v found in the Node dir"
Say 'READY'
