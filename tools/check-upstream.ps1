#  check-upstream.ps1 - is anything we pin now behind upstream?
#
#  deps.json is the build manifest; this compares it against the registries and
#  prints any drift. Exit 1 when something moved, so a scheduled workflow can
#  open an issue. ASCII only (PS 5.1 reads a BOM-less .ps1 as ANSI).
#
#  usage: powershell -ExecutionPolicy Bypass -File tools/check-upstream.ps1 [-Json]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = Split-Path -Parent $PSScriptRoot
$deps = Get-Content -LiteralPath (Join-Path $repoRoot 'deps.json') -Raw | ConvertFrom-Json

function Get-NpmLatest([string]$Name) {
    try {
        $u = 'https://registry.npmjs.org/' + ($Name -replace '/', '%2f') + '/latest'
        $r = Invoke-RestMethod -Uri $u -TimeoutSec 25 -UseBasicParsing
        return [string]$r.version
    } catch {
        return ''
    }
}

# deps.json uses npm range prefixes like ^; strip them for comparison
function Clean-Ver([string]$V) { return ($V -replace '^[\^~>=<\s]+', '').Trim() }

$rows = New-Object System.Collections.ArrayList
function Add-Row($kind, $name, $pinned, $latest, $note) {
    $stale = ($latest -ne '' -and $latest -ne $pinned)
    [void]$rows.Add([pscustomobject]@{
        Kind = $kind; Name = $name; Pinned = $pinned; Latest = $latest
        Stale = $stale; Note = $note
    })
}

Add-Row 'runtime' 'node' $deps.node '' 'checked by hand: nodejs.org'

$dPin = Clean-Ver $deps.dsh.version
$dLat = Get-NpmLatest $deps.dsh.name
Add-Row 'core' $deps.dsh.name $dPin $dLat ''

foreach ($p in $deps.plugins.web) {
    $pin = Clean-Ver $p.version
    $lat = Get-NpmLatest $p.name
    $note = $p.source
    if ($p.source -eq 'git') {
        $note = 'git-hosted (' + $p.repo + '); the npm mirror is compared here'
    }
    Add-Row 'plugin' $p.name $pin $lat $note
}

$stale = @($rows | Where-Object { $_.Stale })
$unreachable = @($rows | Where-Object { $_.Latest -eq '' -and $_.Name -ne 'node' })

if ($Json) {
    [pscustomobject]@{
        staleCount = $stale.Count
        unreachableCount = $unreachable.Count
        rows = @($rows)
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ''
    Write-Host ('{0,-8} {1,-28} {2,-12} {3,-12} {4}' -f 'KIND', 'PACKAGE', 'PINNED', 'LATEST', 'STATUS')
    Write-Host ('-' * 92)
    foreach ($r in $rows) {
        $st = 'ok'
        if ($r.Stale) { $st = 'STALE' }
        elseif ($r.Latest -eq '' -and $r.Name -ne 'node') { $st = 'unreachable' }
        if ($r.Name -eq 'node') { $st = 'manual' }
        Write-Host ('{0,-8} {1,-28} {2,-12} {3,-12} {4}' -f $r.Kind, $r.Name, $r.Pinned, $r.Latest, $st)
    }
    Write-Host ''
    Write-Host ("stale: {0}   unreachable: {1}" -f $stale.Count, $unreachable.Count)
}

# upstream being unreachable is NOT 'no drift': a weekly check that silently passes
# whenever the registry is down would never notice real staleness.
if ($stale.Count -gt 0 -or $unreachable.Count -gt 0) { exit 1 }
exit 0
