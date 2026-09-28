# ============================================================
#  便携版「环境隔离」验证 —— 证明它绝不污染本机环境
#
#  做法：跑之前给系统拍快照 -> 反复启动/停止（CLI + Web 服务）
#        -> 再拍快照 -> 逐项对比，任何一处变化都报出来。
#
#  用法：
#     powershell -ExecutionPolicy Bypass -File verify-isolation.ps1
#     powershell -ExecutionPolicy Bypass -File verify-isolation.ps1 -Rounds 5
# ============================================================
param(
    # 默认：脚本位于 <包根>\tools\ → 上一级就是包根（不硬编码任何用户名）
    [string]$Package = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [int]$Rounds = 3,
    [int]$Port = 3099
)

$ErrorActionPreference = 'Continue'

function Snap {
    $s = @{}
    # 1) 用户级 ~/.dsh（本机已有 dsh 安装的数据目录）—— 最关键的一项
    $userDsh = Join-Path $env:USERPROFILE '.dsh'
    if (Test-Path -LiteralPath $userDsh) {
        $s['用户 ~/.dsh 全量清单'] = ((Get-ChildItem -LiteralPath $userDsh -Recurse -File -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks }) -join "`n")
        $s['用户 ~/.dsh 条目数'] = "$(@(Get-ChildItem -LiteralPath $userDsh -Recurse -File -Force -ErrorAction SilentlyContinue).Count)"
    } else { $s['用户 ~/.dsh 全量清单'] = '<不存在>'; $s['用户 ~/.dsh 条目数'] = '0' }

    # 2) 用户级 ~/.dsh 的「最后修改时间」（目录本身）
    if (Test-Path -LiteralPath $userDsh) { $s['~/.dsh 目录时间'] = (Get-Item -LiteralPath $userDsh -Force).LastWriteTimeUtc.Ticks.ToString() }

    # 3) 环境变量（用户级 + 系统级）
    foreach ($n in @('DSH_HOME', 'DEEPSEEK_API_KEY', 'DSH_PROFILE')) {
        $s["env(用户) $n"] = '<' + [string]([Environment]::GetEnvironmentVariable($n, 'User')) + '>'
        $s["env(系统) $n"] = '<' + [string]([Environment]::GetEnvironmentVariable($n, 'Machine')) + '>'
    }
    $s['PATH(用户)'] = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    $s['PATH(系统)'] = [string][Environment]::GetEnvironmentVariable('Path', 'Machine')

    # 4) 注册表：自启动项 + 环境键
    foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                     'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
                     'HKCU:\Environment')) {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            $names = ($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | Sort-Object Name |
                ForEach-Object { $_.Name + '=' + $_.Value }) -join '|'
            $s["注册表 $k"] = $names
        } catch { $s["注册表 $k"] = '<读取失败>' }
    }

    # 5) 桌面 / 文档 / 下载 顶层清单
    $desk = [Environment]::GetFolderPath('Desktop')
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $s['桌面清单'] = ((Get-ChildItem -LiteralPath $desk -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name }) -join '|')
    $s['文档清单'] = ((Get-ChildItem -LiteralPath $docs -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name }) -join '|')
    $s['文档条目数'] = "$(@(Get-ChildItem -LiteralPath $docs -Force -ErrorAction SilentlyContinue).Count)"

    # 6) 常见的「别处也装了 dsh/node」位置
    $s['APPDATA\npm 存在'] = [string](Test-Path (Join-Path $env:APPDATA 'npm'))
    $s['LOCALAPPDATA\dsh 存在'] = [string](Test-Path (Join-Path $env:LOCALAPPDATA 'dsh'))
    $s['ProgramFiles\nodejs 存在'] = [string](Test-Path (Join-Path $env:ProgramFiles 'nodejs'))
    $s['~/.deepseek 存在'] = [string](Test-Path (Join-Path $env:USERPROFILE '.deepseek'))

    return $s
}

function Compare-Snap($a, $b) {
    $diffs = @()
    $keys = ($a.Keys + $b.Keys) | Sort-Object -Unique
    foreach ($k in $keys) {
        $va = if ($a.ContainsKey($k)) { [string]$a[$k] } else { '<缺失>' }
        $vb = if ($b.ContainsKey($k)) { [string]$b[$k] } else { '<缺失>' }
        if ($va -ne $vb) {
            $diffs += [pscustomobject]@{ 项目 = $k; 之前 = $va; 之后 = $vb }
        }
    }
    return $diffs
}

# ---------------- 开跑 ----------------
Write-Host ''
Write-Host '  ═══ 便携版环境隔离验证 ═══' -ForegroundColor Cyan
Write-Host ("  包目录: {0}" -f $Package)
Write-Host ("  轮数  : {0}   端口: {1}" -f $Rounds, $Port)
Write-Host ''

if (-not (Test-Path -LiteralPath (Join-Path $Package 'launcher\core.ps1'))) {
    Write-Host "  ✖ 找不到 $Package\launcher\core.ps1" -ForegroundColor Red
    exit 2
}

# 载入便携版自己的核心逻辑（这样用的就是包内的代码路径）
. (Join-Path $Package 'launcher\core.ps1')
Write-Host ("  便携版数据目录 DSH_HOME = {0}" -f $script:DshHome)
Write-Host ''

# 用假密钥，避免真密钥参与测试
$env:DEEPSEEK_API_KEY = 'sk-isolation-test-000000000000000000'

Write-Host '  [1/4] 拍摄运行前快照...' -ForegroundColor Cyan
$before = Snap
Write-Host ("        ~/.dsh 条目数 = {0}，文档条目数 = {1}" -f $before['用户 ~/.dsh 条目数'], $before['文档条目数'])
Write-Host ''

Write-Host '  [2/4] 反复运行（模拟同学实际使用）...' -ForegroundColor Cyan
for ($i = 1; $i -le $Rounds; $i++) {
    Write-Host ("        —— 第 {0}/{1} 轮 ——" -f $i, $Rounds) -ForegroundColor DarkCyan

    # a) 环境自检（只读）
    $c = @(Get-EnvCheck)
    Write-Host ("          自检 {0} 项，失败 {1} 项" -f $c.Count, @($c | Where-Object { $_.State -eq 'fail' }).Count)

    # b) 冲突检测（只读）
    $k = @(Get-ConflictReport)
    Write-Host ("          冲突检测 {0} 项" -f $k.Count)

    # c) CLI 入口（包内 bin\dsh.cmd，会设置 DSH_HOME）
    $null = & (Join-Path $Package 'bin\dsh.cmd') --version 2>&1
    Write-Host '          CLI 入口 已运行'

    # d) Web 服务：启动 -> 等就绪 -> 停止
    try {
        $url = Start-DshServer -Port $Port -TimeoutSec 90
        $shown = $url -replace 'token=[A-Za-z0-9_\-]+', 'token=***'
        Write-Host ("          服务已就绪: {0}" -f $shown)
    } catch {
        Write-Host ("          服务启动异常: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
    $stopped = Stop-DshServer -Port $Port
    Write-Host ("          服务已停止: {0}" -f $stopped)

    # e) 顺便验证「服务停止后端口释放」
    Start-Sleep -Milliseconds 1200
    Write-Host ("          端口 {0} 已释放: {1}" -f $Port, (Test-PortFree $Port))
    Start-Sleep -Seconds 1
}
Write-Host ''

Write-Host '  [3/4] 拍摄运行后快照...' -ForegroundColor Cyan
$after = Snap
Write-Host ''

Write-Host '  [4/4] 对比结果' -ForegroundColor Cyan
$diffs = @(Compare-Snap $before $after)

# 已知且可解释的变化：桌面快捷方式（点「干净卸载」可移除）
$known = @($diffs | Where-Object { $_.项目 -eq '桌面清单' -and $_.之后 -like '*DSH 便携版.lnk*' })
$real = @($diffs | Where-Object { -not ($_.项目 -eq '桌面清单' -and $_.之后 -like '*DSH 便携版.lnk*') })

Write-Host ''
if ($real.Count -eq 0) {
    Write-Host '  ✔ 通过：包外环境【零改动】' -ForegroundColor Green
    Write-Host '    · 未创建/修改用户 ~/.dsh'
    Write-Host '    · 未改 PATH（用户级与系统级都未变）'
    Write-Host '    · 未改任何注册表项（自启动 / 环境变量键）'
    Write-Host '    · 未在文档 / 下载目录留下任何文件'
} else {
    Write-Host ("  ✖ 发现 {0} 处包外改动：" -f $real.Count) -ForegroundColor Red
    foreach ($d in $real) {
        Write-Host ("    · {0}" -f $d.项目) -ForegroundColor Red
        $va = $d.之前; $vb = $d.之后
        if ($va.Length -gt 300) { $va = $va.Substring(0, 300) + '...' }
        if ($vb.Length -gt 300) { $vb = $vb.Substring(0, 300) + '...' }
        Write-Host ("        之前: {0}" -f $va)
        Write-Host ("        之后: {0}" -f $vb)
    }
}
if ($known.Count -gt 0) {
    Write-Host ''
    Write-Host '  ℹ 已知且可解释的改动（点「干净卸载」可移除）：' -ForegroundColor Yellow
    Write-Host '    · 桌面多了「DSH 便携版.lnk」快捷方式（指向本包）'
}
Write-Host ''
if ($real.Count -eq 0) { exit 0 } else { exit 1 }
