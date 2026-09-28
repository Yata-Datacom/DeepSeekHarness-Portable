# ============================================================
#  DSH 便携版 — 核心逻辑（环境检测 / 启动 / 配置）
#  被 launcher.ps1 引用，也可单独当命令行工具用：
#     powershell -ExecutionPolicy Bypass -File core.ps1 -Check
# ============================================================
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------- 路径（全部相对本包，绝不写系统目录） ----------
$script:PkgRoot  = Split-Path -Parent $PSScriptRoot
if (-not $script:PkgRoot) { $script:PkgRoot = $PSScriptRoot }
$script:NodeDir  = Join-Path $script:PkgRoot 'node'
$script:NodeExe  = Join-Path $script:NodeDir 'node.exe'
$script:NpmCmd   = Join-Path $script:NodeDir 'npm.cmd'
$script:DshBin   = Join-Path $script:NodeDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$script:DataDir  = Join-Path $script:PkgRoot 'data'
$script:DshHome  = Join-Path $script:DataDir '.dsh'
$script:CfgDir   = Join-Path $script:PkgRoot 'config'
$script:KeyFile  = Join-Path $script:CfgDir 'api-key.txt'
$script:LogDir   = Join-Path $script:PkgRoot 'logs'
$script:PrfDir   = Join-Path $script:DshHome 'profiles\web'
$script:IconPath = Join-Path $script:PkgRoot 'assets\dsh-whale.ico'
$script:DefaultPort = 3080

function Initialize-Dirs {
    foreach ($d in @($script:DataDir, $script:DshHome, $script:CfgDir, $script:LogDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Get-DshEnv {
    # 设置当前进程的环境变量，供随后的 dsh 子进程继承。
    # 注意：末尾不要 return $env —— StrictMode 下取 $env 会报「检索不到变量 $env」。
    $env:DEEPSEEK_API_KEY = Get-ApiKey
    $env:DSH_HOME = $script:DshHome
    $env:NO_COLOR = '1'
}

# ---------- API Key ----------
function Get-ApiKey {
    if (Test-Path -LiteralPath $script:KeyFile) {
        $k = (Get-Content -LiteralPath $script:KeyFile -Raw -ErrorAction SilentlyContinue)
        if ($k) { return $k.Trim() }
    }
    if ($env:DEEPSEEK_API_KEY) { return $env:DEEPSEEK_API_KEY }
    return $null
}

function Set-ApiKey([string]$Key) {
    Initialize-Dirs
    Set-Content -LiteralPath $script:KeyFile -Value $Key.Trim() -Encoding ASCII -NoNewline
}

function Test-ApiKey {
    $k = Get-ApiKey
    if (-not $k) { return $false }
    return ($k.Length -ge 20 -and $k.StartsWith('sk-'))
}

# ---------- 端口 ----------
function Test-PortFree([int]$Port) {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return (-not $c)
}

function Get-ListeningPid([int]$Port) {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return [int]$c.OwningProcess }
    return 0
}

function Get-FreePort([int]$Start = 3080, [int]$Max = 3200) {
    for ($p = $Start; $p -le $Max; $p++) { if (Test-PortFree $p) { return $p } }
    throw "找不到可用端口（$Start-$Max 都被占用）"
}

# ---------- 环境检测 ----------
function Get-EnvCheck {
    $r = New-Object System.Collections.ArrayList
    function Add-Check($name, $state, $detail) {
        [void]$r.Add([pscustomobject]@{ Name = $name; State = $state; Detail = $detail })
    }

    # 1 系统
    # 坑：Environment.OSVersion 在 Windows 11 上仍谎报 10.0（微软的兼容性伪装），
    #     必须查注册表 CurrentBuildNumber（>=22000 才是 Win11）。
    $cv = $null
    try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { }
    $osv = [System.Environment]::OSVersion.Version
    if ($cv) {
        $build = 0
        [void][int]::TryParse(('' + $cv.CurrentBuildNumber), [ref]$build)
        if ($build -eq 0) { [void][int]::TryParse(('' + $cv.CurrentBuild), [ref]$build) }
        $pname = '' + $cv.ProductName
        $disp = '' + $cv.DisplayVersion
        $ubr = '' + $cv.UBR
        # 部分 Win11 镜像里 ProductName 仍写 Windows 10，按 build 号纠正
        if ($build -ge 22000 -and $pname -like 'Windows 10*') { $pname = $pname -replace '^Windows 10', 'Windows 11' }
        $verText = "$pname"
        if ($disp) { $verText += " $disp" }
        $verText += " (Build $build"
        if ($ubr) { $verText += ".$ubr" }
        $verText += ')'
        if ($build -ge 17763) { Add-Check '系统版本' 'ok' $verText }
        elseif ($build -ge 10240) { Add-Check '系统版本' 'fail' "版本过低：$verText`n自带 Node.js 22 需要 Windows 10 1809 (Build 17763) 及以上" }
        else { Add-Check '系统版本' 'fail' "需要 Windows 10 1809 及以上，当前 $verText" }
    } elseif ($osv.Major -ge 10) {
        Add-Check '系统版本' 'ok' "Windows $($osv.Major).$($osv.Minor) (Build $($osv.Build))"
    } else { Add-Check '系统版本' 'fail' "需要 Windows 10 1809 及以上，当前 $osv" }

    if ([System.Environment]::Is64BitOperatingSystem) { Add-Check '系统架构' 'ok' '64 位' }
    else { Add-Check '系统架构' 'fail' '需要 64 位系统' }

    # 2 磁盘空间（本包所在盘）
    try {
        $drive = (Get-Item -LiteralPath $script:PkgRoot).PSDrive.Name
        $free = (Get-PSDrive -Name $drive).Free
        $freeGB = [math]::Round($free / 1GB, 1)
        if ($freeGB -ge 2) { Add-Check '磁盘空间' 'ok' "$drive 盘剩余 ${freeGB} GB" }
        else { Add-Check '磁盘空间' 'warn' "$drive 盘仅剩 ${freeGB} GB，建议留 2 GB 以上" }
    } catch { Add-Check '磁盘空间' 'warn' "无法读取" }

    # 3 目录可写
    try {
        $probe = Join-Path $script:PkgRoot ".write-test-$([guid]::NewGuid().ToString('N').Substring(0,6))"
        Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force
        Add-Check '目录可写' 'ok' '本包目录可读写'
    } catch { Add-Check '目录可写' 'fail' '本包目录不可写，请解压到 D 盘或桌面等位置' }

    # 4 Node 运行时（同时验证 x64 架构是否真能执行）
    if (Test-Path -LiteralPath $script:NodeExe) {
        try {
            $v = (& $script:NodeExe --version 2>&1 | Select-Object -First 1)
            if (('' + $v) -match '^v\d+\.') { Add-Check 'Node 运行时' 'ok' "自带 Node $v（免安装，不动系统）" }
            else { Add-Check 'Node 运行时' 'fail' ("node.exe 返回异常：" + $v) }
        } catch { Add-Check 'Node 运行时' 'fail' 'node.exe 无法运行：可能是 32 位系统 / 被杀毒隔离 / 解压不完整' }
    } else { Add-Check 'Node 运行时' 'fail' '缺少 node\node.exe，请重新解压完整包' }

    # 5 dsh 本体
    if (Test-Path -LiteralPath $script:DshBin) {
        try {
            $vs = (& $script:NodeExe $script:DshBin --version 2>&1 | Select-Object -First 1)
            Add-Check 'DSH 本体' 'ok' "dsh $vs"
        } catch { Add-Check 'DSH 本体' 'fail' 'dsh 启动失败' }
    } else { Add-Check 'DSH 本体' 'fail' '缺少 dsh 安装文件' }

    # 6 插件
    if (Test-Path -LiteralPath (Join-Path $script:PrfDir 'package.json')) {
        $pk = Get-Content -LiteralPath (Join-Path $script:PrfDir 'package.json') -Raw
        $names = @()
        foreach ($p in @('dsh-whale-widget', 'gal-view', 'open-sea-skin')) { if ($pk -match [regex]::Escape($p)) { $names += $p } }
        if ($names.Count -gt 0) { Add-Check '已装插件' 'ok' ($names -join ' + ') }
        else { Add-Check '已装插件' 'warn' '未检测到插件（不影响使用）' }
    } else { Add-Check '已装插件' 'warn' '插件目录缺失（不影响使用）' }

    # 7 API Key
    if (Test-ApiKey) { Add-Check 'DeepSeek 密钥' 'ok' '已配置' }
    else { Add-Check 'DeepSeek 密钥' 'warn' '未配置 —— 点「设置密钥」填一次即可' }

    # 8 端口
    $busy = -not (Test-PortFree $script:DefaultPort)
    if ($busy) {
        $op = Get-ListeningPid $script:DefaultPort
        $ours = $false
        try { $proc = Get-Process -Id $op -ErrorAction Stop; if ($proc.Path -eq $script:NodeExe) { $ours = $true } } catch {}
        if ($ours) { Add-Check '端口 3080' 'ok' '本便携版服务已在运行' }
        else { Add-Check '端口 3080' 'warn' "被其它程序占用（PID $op），将自动改用其它端口" }
    } else { Add-Check '端口 3080' 'ok' '空闲' }

    # 9 冲突检测（只读，绝不修改）
    $conf = @(Get-ConflictReport)
    $hard = @($conf | Where-Object { $_.Severity -eq 'conflict' })
    if ($hard.Count -gt 0) {
        Add-Check '冲突检测' 'warn' ($hard[0].Detail + "（默认不覆盖；如需重置请用「强制覆盖」）")
    } elseif ($conf.Count -gt 0) {
        Add-Check '冲突检测' 'ok' ('无冲突 · ' + $conf[0].Detail)
    } else {
        Add-Check '冲突检测' 'ok' '未发现任何冲突'
    }

    # 10 Smart App Control（Win11 会拦未签名程序）
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
        if ($v -eq 0) { Add-Check '安全策略' 'ok' 'Smart App Control 已关闭' }
        elseif ($v -eq 1) { Add-Check '安全策略' 'warn' 'Smart App Control 开启：若被拦截，在 设置→隐私和安全性→Windows 安全中心→应用和浏览器控制 中允许本程序' }
        else { Add-Check '安全策略' 'ok' '评估模式' }
    } catch { Add-Check '安全策略' 'ok' '未启用 Smart App Control' }

    return $r
}

# ---------- 启动前预检（致命问题 → 大白话解释 + 拦住启动） ----------
function Get-PreflightBlock {
    $reasons = @()
    $build = 0
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        [void][int]::TryParse(('' + $cv.CurrentBuildNumber), [ref]$build)
        if ($build -eq 0) { [void][int]::TryParse(('' + $cv.CurrentBuild), [ref]$build) }
    } catch { }

    if ($build -gt 0 -and $build -lt 17763) {
        $reasons += "● 系统版本太旧（当前 Build $build）。`n  需要 Windows 10 1809 (Build 17763) 或更高。`n  本包自带的 Node.js 22 不支持 Win7 / 8 / 8.1 和早期 Win10。"
    } elseif ($build -eq 0 -and [System.Environment]::OSVersion.Version.Major -lt 10) {
        $reasons += "● 系统版本太旧。需要 Windows 10 1809 及以上。"
    }

    if (-not [System.Environment]::Is64BitOperatingSystem) {
        $reasons += "● 系统是 32 位。`n  本包自带的是 64 位 Node.js，无法在 32 位系统上运行，请换一台 64 位电脑。"
    }

    if (-not (Test-Path -LiteralPath $script:NodeExe)) {
        $reasons += "● 缺少 node\node.exe。压缩包可能没解压完整，请重新解压。"
    } else {
        $nodeOk = $false
        try {
            $v = (& $script:NodeExe --version 2>&1 | Select-Object -First 1)
            if (('' + $v) -match '^v\d+\.') { $nodeOk = $true }
        } catch { }
        if (-not $nodeOk) {
            $reasons += "● 自带的 node.exe 无法运行。常见原因：`n  1) 系统是 32 位（本包是 64 位）`n  2) 被杀毒软件 / Windows 安全中心隔离了 —— 请把整个文件夹加入白名单后重新解压`n  3) 解压不完整，建议删掉重新解压一次"
        }
    }

    if (-not (Test-Path -LiteralPath $script:DshBin)) {
        $reasons += "● 缺少 dsh 本体文件（node\node_modules\@deepseek-ai\dsh），请重新解压完整包。"
    }

    try {
        $probe = Join-Path $script:PkgRoot ".write-test-$([guid]::NewGuid().ToString('N').Substring(0,6))"
        Set-Content -LiteralPath $probe -Value 'x' -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force
    } catch {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        $reasons += "● 本包目录不可写。`n  请解压到 D 盘、桌面等可写位置，不要放在 C:\Program Files 这类受保护目录。"
    }

    if ($reasons.Count -gt 0) { return ($reasons -join "`n`n") }
    return $null
}

# ---------- 启动 / 停止 ----------
function Get-DshUrlFromLog([string]$LogPath) {
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }
    $t = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue
    if (-not $t) { return $null }
    $m = [regex]::Match($t, 'http://127\.0\.0\.1:(\d+)/\?token=([A-Za-z0-9_\-]+)')
    if ($m.Success) { return $m.Value }
    return $null
}

function Start-DshServer([int]$Port = 3080, [int]$TimeoutSec = 120) {
    Initialize-Dirs
    if (-not (Test-Path -LiteralPath $script:NodeExe)) { throw '缺少 node\node.exe' }
    $log = Join-Path $script:LogDir 'web.log'
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

    Get-DshEnv
    $dshArgs = @($script:DshBin, 'web', '--no-open', '--port', "$Port")
    Start-Process -FilePath $script:NodeExe -ArgumentList $dshArgs -WindowStyle Hidden `
        -RedirectStandardOutput $log `
        -RedirectStandardError (Join-Path $script:LogDir 'web.err.log') | Out-Null

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        Start-Sleep -Milliseconds 800
        if (Get-DshUrlFromLog $log) { return (Get-DshUrlFromLog $log) }
        if (-not (Test-PortFree $Port)) {
            # 端口已监听但还没打印 token，再等一会
            if ($sw.Elapsed.TotalSeconds -gt 30) {
                $u = Get-DshUrlFromLog $log
                if ($u) { return $u }
            }
        }
    }
    $tail = ''
    if (Test-Path -LiteralPath $log) { $tail = (Get-Content -LiteralPath $log -Tail 12) -join "`n" }
    throw "启动超时（${TimeoutSec}s）。日志尾部：`n$tail"
}

function Stop-DshServer([int]$Port = 3080) {
    # 注意：变量不能叫 $pid —— 那是 PowerShell 只读自动变量（当前进程 ID），赋值会报错
    $procId = Get-ListeningPid $Port
    if ($procId -gt 0) {
        try {
            $proc = Get-Process -Id $procId -ErrorAction Stop
            if ($proc.Path -eq $script:NodeExe) { Stop-Process -Id $procId -Force; return $true }
            return $false
        } catch { return $false }
    }
    return $false
}

function Open-WebUi([string]$Url) {
    # 优先用 Edge 的应用窗口（像桌面软件），失败则回退默认浏览器
    $edge = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($edge) {
        Start-Process -FilePath $edge -ArgumentList "--app=$Url", '--window-size=1500,950' | Out-Null
    } else {
        Start-Process $Url | Out-Null
    }
}

# ---------- 桌面快捷方式（可选：绝不静默创建，绝不覆盖别人的） ----------
function Get-ShortcutPath { return (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH 便携版.lnk') }

function Test-ShortcutExists { return (Test-Path -LiteralPath (Get-ShortcutPath)) }

# 桌面那个同名快捷方式是不是本包建的？
function Test-ShortcutMine {
    $lnk = Get-ShortcutPath
    if (-not (Test-Path -LiteralPath $lnk)) { return $false }
    try {
        $t = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath
        if (-not $t) { return $false }
        return ($t -like (Join-Path $script:PkgRoot '*'))
    } catch { return $false }
}

function New-Shortcut {
    $lnk = Get-ShortcutPath
    if (Test-Path -LiteralPath $lnk) {
        if (Test-ShortcutMine) { return 'exists' }
        throw "桌面上已有同名快捷方式（指向别处），未做任何改动。请先改名或删除它。"
    }
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $exe = Join-Path $script:PkgRoot 'DSH 便携版.exe'
    if (Test-Path -LiteralPath $exe) { $s.TargetPath = $exe }
    else { $s.TargetPath = Join-Path $script:PkgRoot '启动 DSH.vbs' }
    $s.WorkingDirectory = $script:PkgRoot
    if (Test-Path -LiteralPath $script:IconPath) { $s.IconLocation = $script:IconPath + ',0' }
    $s.Description = 'DeepSeek Harness 便携版（双击启动）'
    $s.Save()
    return 'created'
}

function Remove-Shortcut {
    $lnk = Get-ShortcutPath
    if (-not (Test-Path -LiteralPath $lnk)) { return 'none' }
    if (-not (Test-ShortcutMine)) { throw '桌面那个快捷方式不是本包创建的，未删除' }
    Remove-Item -LiteralPath $lnk -Force
    return 'removed'
}

function Test-ShortcutAsked { return (Test-Path -LiteralPath (Join-Path $script:CfgDir '.shortcut-asked')) }
function Set-ShortcutAsked {
    Initialize-Dirs
    Set-Content -LiteralPath (Join-Path $script:CfgDir '.shortcut-asked') -Value '1' -Encoding ASCII
}

# ---------- 安全删除（长路径 + 符号链接，三级回退） ----------
function Remove-TreeSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $abs = (Resolve-Path -LiteralPath $Path).Path
    $lp = '\\?\' + $abs

    # 1) 长路径原生删除
    try {
        [System.IO.Directory]::Delete($lp, $true)
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
    } catch { }

    # 2) Git 的 rm（对符号链接最宽容）
    $rm = @("$env:ProgramFiles\Git\usr\bin\rm.exe", "${env:ProgramFiles(x86)}\Git\usr\bin\rm.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($rm) {
        $posix = '/' + ($abs -replace '\\', '/' -replace ':', '')
        & $rm -rf -- $posix 2>$null
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
    }

    # 3) robocopy 镜像空目录
    $empty = Join-Path $env:TEMP ("dsh-empty-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $null = robocopy $empty $Path /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
    return (-not (Test-Path -LiteralPath $Path))
}

# ---------- 冲突检测（只读：绝不修改任何东西） ----------
function Get-ConflictReport {
    $r = New-Object System.Collections.ArrayList
    function Add-C($kind, $sev, $detail, $path) {
        [void]$r.Add([pscustomobject]@{ Kind = $kind; Severity = $sev; Detail = $detail; Path = $path })
    }

    # 包内已有数据（默认保留，不覆盖）
    if (Test-Path -LiteralPath $script:DshHome) {
        $n = @(Get-ChildItem -LiteralPath $script:DshHome -Force -ErrorAction SilentlyContinue).Count
        if ($n -gt 0) { Add-C '包内已有数据' 'info' "data\.dsh 已有 $n 项（历史会话 / 工作区 / 主题设置原样保留，本次不覆盖）" $script:DshHome }
    }
    if (Test-Path -LiteralPath $script:KeyFile) {
        Add-C '已有密钥' 'info' 'config\api-key.txt 已存在，不会被覆盖' $script:KeyFile
    }

    # 桌面快捷方式冲突
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH 便携版.lnk'
    if (Test-Path -LiteralPath $lnk) {
        try {
            $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath
            $mine = Join-Path $script:PkgRoot '*'
            if ($target -and ($target -notlike $mine)) {
                Add-C '桌面快捷方式冲突' 'conflict' "桌面已有同名快捷方式，但它指向别处：$target —— 默认不覆盖" $lnk
            } else {
                Add-C '桌面快捷方式' 'info' '已存在且指向本包，不会重复创建' $lnk
            }
        } catch { }
    }

    # 系统里已有的 dsh（永不改动）
    $sysHome = Join-Path $env:USERPROFILE '.dsh'
    if (Test-Path -LiteralPath $sysHome) {
        Add-C '系统已有 dsh' 'info' "发现 $sysHome —— 本便携版只用包内 data\.dsh，绝不读写它" $sysHome
    }
    if (Get-Command dsh -ErrorAction SilentlyContinue) {
        Add-C '系统已有 dsh' 'info' 'PATH 里有 dsh 命令 —— 本便携版不修改 PATH、不动注册表' ''
    }

    # 端口冲突
    if (-not (Test-PortFree $script:DefaultPort)) {
        $op = Get-ListeningPid $script:DefaultPort
        $ours = $false
        try { $p = Get-Process -Id $op -ErrorAction Stop; if ($p.Path -eq $script:NodeExe) { $ours = $true } } catch { }
        if ($ours) { Add-C '端口占用' 'info' '本便携版的服务已在运行' '' }
        else { Add-C '端口冲突' 'conflict' "3080 被其它程序占用（PID $op）—— 默认不抢占，会自动改用其它端口" '' }
    }
    return $r
}

function Test-HasConflict {
    return (@(Get-ConflictReport | Where-Object { $_.Severity -eq 'conflict' }).Count -gt 0)
}

# ---------- 干净卸载（只清理本包自己的东西） ----------
function Get-UninstallItems {
    $r = New-Object System.Collections.ArrayList
    function Add-I($key, $name, $detail, $path) {
        [void]$r.Add([pscustomobject]@{
            Key    = $key
            Name   = $name
            Detail = $detail
            Path   = $path
            Exists = (Test-Path -LiteralPath $path)
        })
    }
    Add-I 'shortcut' '桌面快捷方式' '桌面上的「DSH 便携版」' (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DSH 便携版.lnk')
    Add-I 'key' '已保存的 API 密钥' 'config\api-key.txt' $script:KeyFile
    Add-I 'data' '软件数据（会话 / 工作区 / 主题）' 'data\.dsh' $script:DshHome
    Add-I 'logs' '运行日志' 'logs\' $script:LogDir
    Add-I 'folder' '整个便携版文件夹（程序本体）' '本包目录（关闭启动器后自动删除）' $script:PkgRoot
    return $r
}

function Invoke-Uninstall([string[]]$Keys) {
    $done = New-Object System.Collections.ArrayList
    $fail = New-Object System.Collections.ArrayList

    # 先停掉本便携版的服务，否则文件被 node.exe 占用
    try { Stop-DshServer $script:DefaultPort | Out-Null } catch { }

    if ($Keys -contains 'shortcut') {
        try {
            if (Test-ShortcutExists) {
                if (Test-ShortcutMine) { Remove-Item -LiteralPath (Get-ShortcutPath) -Force; [void]$done.Add('桌面快捷方式') }
                else { [void]$fail.Add('桌面快捷方式不是本包创建的，已跳过') }
            }
        } catch { [void]$fail.Add("桌面快捷方式：$($_.Exception.Message)") }
    }
    if ($Keys -contains 'key') {
        try {
            if (Test-Path -LiteralPath $script:KeyFile) { Remove-Item -LiteralPath $script:KeyFile -Force; [void]$done.Add('已保存的 API 密钥') }
        } catch { [void]$fail.Add("密钥：$($_.Exception.Message)") }
    }
    if ($Keys -contains 'logs') {
        if (Remove-TreeSafe $script:LogDir) { [void]$done.Add('运行日志') } else { [void]$fail.Add('日志目录未能删除') }
    }
    if ($Keys -contains 'data') {
        if (Remove-TreeSafe $script:DshHome) { [void]$done.Add('软件数据') } else { [void]$fail.Add('数据目录未能删除') }
    }
    if ($Keys -contains 'folder') {
        # 程序自己在运行，删不掉自己 —— 交给后台进程等本进程退出后再删
        $pkg = $script:PkgRoot
        $d = Join-Path $env:TEMP ("dsh-selfdel-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.ps1')
        $body = @"
Start-Sleep -Seconds 5
`$lp = '\\?\' + '$pkg'
try { [System.IO.Directory]::Delete(`$lp, `$true) } catch { cmd /c rd /s /q "$pkg" }
"@
        Set-Content -LiteralPath $d -Value $body -Encoding UTF8
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $d) -WindowStyle Hidden | Out-Null
        [void]$done.Add('整个文件夹（关闭启动器后自动删除）')
    }
    Initialize-Dirs
    return [pscustomobject]@{ Done = $done; Failed = $fail }
}

# ---------- 初始模板还原（只动本包 data\.dsh） ----------
function Test-Seed { return (Test-Path -LiteralPath (Join-Path $script:PkgRoot 'seed\.dsh')) }

function Invoke-RestoreSeed {
    $seed = Join-Path $script:PkgRoot 'seed\.dsh'
    if (-not (Test-Path -LiteralPath $seed)) { throw '本包没有初始模板（seed\.dsh），无法还原' }
    try { Stop-DshServer $script:DefaultPort | Out-Null } catch { }
    if (Test-Path -LiteralPath $script:DshHome) {
        if (-not (Remove-TreeSafe $script:DshHome)) { throw '无法清空 data\.dsh（可能有程序占用）' }
    }
    New-Item -ItemType Directory -Path $script:DshHome -Force | Out-Null
    $null = robocopy $seed $script:DshHome /E /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "模板复制失败（robocopy 退出码 $LASTEXITCODE）" }
    return $true
}

# ---------- 命令行自检 ----------
if ($MyInvocation.InvocationName -ne '.' -and $args -contains '-Check') {
    Write-Host ''
    Write-Host '  DSH 便携版 — 环境自检' -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 46))
    $bad = 0
    foreach ($c in (Get-EnvCheck)) {
        $tag = switch ($c.State) { 'ok' { '[ OK ]' } 'warn' { '[WARN]' } default { '[FAIL]' } }
        $col = switch ($c.State) { 'ok' { 'Green' } 'warn' { 'Yellow' } default { 'Red' } }
        if ($c.State -eq 'fail') { $bad++ }
        Write-Host ("  $tag ") -ForegroundColor $col -NoNewline
        Write-Host ("{0,-12} {1}" -f $c.Name, $c.Detail)
    }
    Write-Host ''
    if ($bad -eq 0) { Write-Host '  自检通过，可以启动。' -ForegroundColor Green }
    else { Write-Host "  有 $bad 项失败，请按提示处理。" -ForegroundColor Red }
    exit $bad
}
