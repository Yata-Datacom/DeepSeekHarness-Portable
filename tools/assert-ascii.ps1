# ============================================================
#  assert-ascii.ps1 - a shipped script must be ASCII-only or BOM-marked
#
#  Why: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI. A Chinese
#  literal used functionally then silently matches nothing, while the
#  surrounding output still looks perfectly fine - a bug that survives
#  visual inspection. Two ways to be safe:
#    1) keep the file pure ASCII (build any needed CJK from code points), or
#    2) write a UTF-8 BOM so 5.1 decodes the file as UTF-8.
#  A script that has non-ASCII bytes and no BOM is a latent bug: fail it.
#
#  usage: powershell -ExecutionPolicy Bypass -File tools/assert-ascii.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$targets = @()
# .cmd/.bat are read by cmd.exe, which cannot decode UTF-16 at all - they must be
# pure ASCII. .vbs is read by WSH in the ANSI code page (a BOM-less UTF-8 .vbs with
# Chinese in it fails to compile), so it may be ASCII or carry a UTF-16/UTF-8 BOM.
foreach ($pat in @('*.ps1', '*.psm1', '*.vbs', '*.cmd', '*.bat')) {
    $targets += Get-ChildItem -Path $repoRoot -Recurse -Filter $pat -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\|\\.git\\|\\out\\|\\staging\\' }
}

$bad = @()
foreach ($f in $targets) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $ext = $f.Extension.ToLowerInvariant()
    $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $hasUtf16Bom = ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)))
    if ($hasUtf8Bom) { continue }
    if ($hasUtf16Bom) {
        if ($ext -eq '.cmd' -or $ext -eq '.bat') {
            $bad += ("{0}  (UTF-16 BOM, but cmd.exe cannot decode UTF-16 - keep .cmd/.bat pure ASCII)" -f $f.FullName.Substring($repoRoot.Length + 1))
        }
        continue
    }
    $n = 0
    foreach ($b in $bytes) {
        if ($b -lt 0x20 -or $b -gt 0x7E) { if ($b -ne 0x0A -and $b -ne 0x0D -and $b -ne 0x09) { $n++ } }
    }
    if ($n -gt 0) {
        $bad += ("{0}  ({1} non-ASCII byte(s), no BOM)" -f $f.FullName.Substring($repoRoot.Length + 1), $n)
    }
}

if ($bad.Count -gt 0) {
    Write-Host 'FAIL - add a UTF-8 BOM or keep these files pure ASCII:' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Red }
    exit 1
}
Write-Host ("OK - {0} script(s) are ASCII-only or BOM-marked" -f $targets.Count) -ForegroundColor Green
exit 0
