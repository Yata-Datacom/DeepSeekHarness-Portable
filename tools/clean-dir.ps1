param([Parameter(Mandatory=$true)][string]$Path)

# 删除目录（node_modules 深处路径常超 260 字符，且可能含 dsh 建的符号链接）
# 三级回退：长路径原生删除 -> Git 的 rm（对链接最宽容）-> robocopy 镜像空目录

$lp = '\\?\' + $Path
if (-not [System.IO.Directory]::Exists($lp)) { Write-Host '  目录不存在，跳过'; exit 0 }

# --- 1) 长路径原生删除（最快） ---
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    [System.IO.Directory]::Delete($lp, $true)
    $sw.Stop()
    Write-Host ("  已删除（原生），耗时 {0}s" -f [int]$sw.Elapsed.TotalSeconds)
    exit 0
} catch {
    $first = ($_.Exception.Message -split "`n")[0]
    Write-Host ("  原生删除受阻：{0}" -f $first) -ForegroundColor DarkYellow
}

# --- 2) 回退：Git 自带 rm（MSYS 对长路径与符号链接都很宽容） ---
$rm = @(
    "$env:ProgramFiles\Git\usr\bin\rm.exe",
    "${env:ProgramFiles(x86)}\Git\usr\bin\rm.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($rm) {
    $posix = '/' + ($Path -replace '\\', '/' -replace ':', '')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $rm -rf -- $posix 2>$null
    $sw.Stop()
    if (-not [System.IO.Directory]::Exists($lp)) {
        Write-Host ("  已删除（git rm），耗时 {0}s" -f [int]$sw.Elapsed.TotalSeconds)
        exit 0
    }
    Write-Host '  git rm 未能完全删除，改用 robocopy 镜像' -ForegroundColor DarkYellow
}

# --- 3) 最后手段：robocopy 镜像空目录 ---
$empty = Join-Path $env:TEMP ("dsh-empty-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $empty -Force | Out-Null
$null = robocopy $empty $Path /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1
Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
if ([System.IO.Directory]::Exists($lp)) {
    Write-Host '  警告：目录未能完全清空' -ForegroundColor Red
    exit 1
}
Write-Host '  已删除（robocopy）'
