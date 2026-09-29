# ============================================================
#  DSH 便携版 — 打包脚本
#  用法：
#    powershell -ExecutionPolicy Bypass -File build-package.ps1
#    powershell ... -File build-package.ps1 -NoZip        # 只出文件夹不压缩
#  产物：
#    <Out>\DSH-Portable\        绿色便携目录（解压即用）
#    <Out>\DSH-Portable.zip     分发给同学的压缩包
#  安全：
#    全程不写入任何密钥；构建后扫描整个包，发现本机 key 立即中止。
# ============================================================
# 静态检查：签名用的 PFX 密码只能以明文形式从 CI secret 传进来，PS 没有第二个入口。
# 这里是有意为之，用带理由的定向抑制，而不是放宽整条规则或整个仓库的闸门。
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'The PFX password arrives as a plaintext CI secret; PowerShell offers no other way to hand it to Get-PfxCertificate.')]
[CmdletBinding()]
param(
    [string]$Src,
    [string]$Out,
    [switch]$NoZip,
    # 可选：用 PFX 给包内 exe 做 Authenticode 签名（CI 从 secret 传入；本机可省）
    [string]$SignPfx,
    [string]$SignPfxPassword
)

# 自动定位源码根，适配两种布局：
#   ① <src>\pack\build-package.ps1（本机开发布局）→ 上一级
#   ② 仓库根目录直接就是 pack/ 的内容 → 脚本所在目录
if (-not $Src) {
    $up = Join-Path $PSScriptRoot '..'
    $Src = if (Test-Path (Join-Path $up 'node')) { (Resolve-Path $up).Path } else { $PSScriptRoot }
}
# 默认输出：当前用户「下载」目录（不硬编码任何用户名）
if (-not $Out) { $Out = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\dsh-portable' }

# 「包内容根」$PackRoot：本机开发布局是 <src>\pack；仓库布局下仓库根目录本身就是 pack 的内容
$PackRoot = if (Test-Path (Join-Path $Src 'pack\launcher')) { Join-Path $Src 'pack' } else { $Src }

$ErrorActionPreference = 'Stop'
function Say($msg, $color = 'Cyan') { Write-Host $msg -ForegroundColor $color }
function Step($n, $t) { Say ""; Say "=== [$n] $t ===" }

$Pkg = Join-Path $Out 'DSH-Portable'

# ---------- [1] 清理 ----------
Step 1 '清理输出目录'
if (Test-Path -LiteralPath $Out) {
    # node_modules 深处路径常超过 260 字符：用 \\?\ 长路径前缀原生删除（比 robocopy /MIR 快几十倍）
    & (Join-Path $PSScriptRoot 'tools\clean-dir.ps1') -Path $Out
    if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force -ErrorAction SilentlyContinue }
}
New-Item -ItemType Directory -Path $Pkg -Force | Out-Null

# ---------- [2] Node 运行时 ----------
Step 2 '复制 Node 运行时（剔除 TUI 插件 ~270MB）'
$null = robocopy "$Src\node" "$Pkg\node" /E /NFL /NDL /NJH /NJS /NP `
    /XD '@deepseek-harness-tui' 'pnpm' `
    /XF 'dsh-tui' 'dsh-tui.cmd' 'dsh-tui.ps1' 'dst' 'dst.cmd' 'dst.ps1' 'pnx' 'pnx.cmd' 'pnx.ps1' 'pnpm' 'pnpm.cmd' 'pnpm.ps1'
if ($LASTEXITCODE -ge 8) { throw "robocopy node 失败，退出码 $LASTEXITCODE" }

# 清掉 node 根目录与 .bin 里的被剔除项（TUI / pnpm）
foreach ($f in @('dsh-tui', 'dsh-tui.cmd', 'dsh-tui.ps1', 'dst', 'dst.cmd', 'dst.ps1', 'pnx', 'pnx.cmd', 'pnx.ps1', 'pnpm', 'pnpm.cmd', 'pnpm.ps1')) {
    $p = Join-Path $Pkg "node\$f"
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}
$binDir = Join-Path $Pkg 'node\node_modules\.bin'
if (Test-Path -LiteralPath $binDir) {
    Get-ChildItem -LiteralPath $binDir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(dsh-tui|^dst|^pnx)' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---------- [3] 启动器 / 入口 / 说明 ----------
Step 3 '复制启动器、入口与说明文档'
foreach ($d in @('launcher', 'bin', 'config', 'logs', 'data')) {
    New-Item -ItemType Directory -Path (Join-Path $Pkg $d) -Force | Out-Null
}
Copy-Item -Path "$PackRoot\launcher\*" -Destination (Join-Path $Pkg 'launcher') -Recurse -Force
Copy-Item -Path "$PackRoot\entry\*" -Destination $Pkg -Force
Copy-Item -Path "$PackRoot\bin\*" -Destination (Join-Path $Pkg 'bin') -Force
Copy-Item -Path "$PackRoot\assets" -Destination $Pkg -Recurse -Force
Copy-Item -Path "$PackRoot\src" -Destination $Pkg -Recurse -Force

# 排错 + 架构文档：收件人遇到问题的第一站
if (Test-Path -LiteralPath (Join-Path $PackRoot 'docs')) {
    Copy-Item -Path "$PackRoot\docs" -Destination $Pkg -Recurse -Force
    Say '  已随包附带 docs\（架构 + 排错）' 'Green'
}
Copy-Item -Path "$PackRoot\README-使用说明.md" -Destination $Pkg -Force
Copy-Item -Path "$PackRoot\使用说明.txt" -Destination $Pkg -Force

# 把「环境隔离验证」脚本也放进去，任何人可自行复验
$toolDst = Join-Path $Pkg 'tools'
New-Item -ItemType Directory -Path $toolDst -Force | Out-Null
Copy-Item -Path "$PackRoot\tools\verify-isolation.ps1" -Destination $toolDst -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$PackRoot\tools\core-bridge.ps1" -Destination $toolDst -Force -ErrorAction SilentlyContinue

# ---------- [3b] 编译 exe 启动器（用系统自带 csc，免联网） ----------
Step '3b' '编译 exe 启动器（DSH 便携版.exe）'
$csc = @(
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $csc) {
    Say '  未找到 csc.exe，跳过生成 exe（可改用 启动 DSH.vbs）' 'Yellow'
} else {
    # 优先编译移植后的 C# 界面（src\Launcher.cs）；缺源码时回退到小 stub（只负责调起
    # PowerShell 启动器）。回退保证构建永不因缺文件而失败，而 VBS/CMD 入口始终可用。
    $cs = Join-Path $Pkg 'src\Launcher.cs'
    $withUi = $true
    if (-not (Test-Path -LiteralPath $cs)) {
        $cs = Join-Path $Pkg 'assets\launcher.cs'
        $withUi = $false
    }
    $ico = Join-Path $Pkg 'assets\dsh-whale.ico'
    $outExe = Join-Path $Pkg 'DSH 便携版.exe'
    if (-not (Test-Path -LiteralPath $cs)) { throw '缺少 src\Launcher.cs 与 assets\launcher.cs' }
    $cscArgs = @('/nologo', '/target:winexe', ('/out:' + $outExe))
    if ($withUi) { $cscArgs += '/r:System.Web.Extensions.dll' }
    if (Test-Path -LiteralPath $ico) { $cscArgs += ('/win32icon:' + $ico) }
    $cscArgs += $cs
    & $csc $cscArgs | Out-Null
    if (-not (Test-Path -LiteralPath $outExe)) {
        Say '  exe 编译失败（其它功能不受影响，可改用 启动 DSH.vbs）' 'Yellow'
    } else {
        $kind = if ($withUi) { 'C# 界面' } else { '回退 stub' }
        Say ("  OK 已生成 DSH 便携版.exe（{0:N0} KB，{1}，图标已嵌入）" -f ((Get-Item $outExe).Length / 1KB), $kind) 'Green'
        Remove-Item -LiteralPath $cs -Force -ErrorAction SilentlyContinue
    }
}

# ---------- [3c] 可选：给包内 exe 做代码签名 ----------
# CI 用仓库 secret 里的自签证书（PFX）签名；收件人导入配套 .cer 之后，
# Smart App Control 就会放行这个 exe。本机不传 -SignPfx 时整段跳过。
if ($SignPfx) {
    Step '3c' '代码签名（Authenticode）'
    $exes = @(Get-ChildItem -LiteralPath $Pkg -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    if ($exes.Count -eq 0) {
        Say '  包内没有 exe，跳过签名' 'Yellow'
    } else {
        if (-not (Test-Path -LiteralPath $SignPfx)) { throw "找不到签名证书：$SignPfx" }
        $cert = if ($SignPfxPassword) {
            Get-PfxCertificate -FilePath $SignPfx -Password (ConvertTo-SecureString -String $SignPfxPassword -Force -AsPlainText)
        } else {
            Get-PfxCertificate -FilePath $SignPfx
        }
        Say ("  证书: {0}" -f $cert.Subject)
        foreach ($e in $exes) {
            $sig = Set-AuthenticodeSignature -FilePath $e.FullName -Certificate $cert -HashAlgorithm SHA256
            if ($sig.Status -ne 'Valid') {
                Say ("  签名未通过（{0}）：{1}" -f $e.Name, $sig.Status) 'Yellow'
            } else {
                Say ("  OK 已签名 {0}（{1:N0} KB）" -f $e.Name, ($e.Length / 1KB)) 'Green'
            }
        }
    }
}

# ---------- [4] 独立数据目录（脱敏） ----------
Step 4 '生成独立数据目录 data\.dsh（剔除凭据 / 会话 / 机器相关数据）'
$sysDsh = Join-Path $env:USERPROFILE '.dsh'
if (-not (Test-Path -LiteralPath $sysDsh)) { throw "找不到源数据目录 $sysDsh" }
$null = robocopy $sysDsh (Join-Path $Pkg 'data\.dsh') /E /NFL /NDL /NJH /NJS /NP `
    /XD 'dsh-tui' 'sessions' 'storages' 'data' 'whale-audio' 'whale-roles' 'session_projcache' '.agent-presets' `
        "$sysDsh\profiles\node_modules" `
    /XF '.credentials.yaml' '.dshw-usage.json' '.dshw-turn.json' '.anonymous-user-id' 'workspace.json'
if ($LASTEXITCODE -ge 8) { throw "robocopy .dsh 失败，退出码 $LASTEXITCODE" }

# profiles\node_modules 被排除是有意的：那是 dsh 的「安装回退」链接区，
# 实体化会让 dsh 报 "exists and is not a symlink" 而拒绝启动。
# 缺失时 dsh 会自己重建（healProfilesModuleFallback），无需随包分发。

# ---------- [4b] 初始模板（供启动器「还原初始状态 / 强制覆盖」） ----------
Step '4b' '生成初始模板 seed\.dsh'
$seedDir = Join-Path $Pkg 'seed'
if (Test-Path -LiteralPath $seedDir) { Remove-Item -LiteralPath $seedDir -Recurse -Force -ErrorAction SilentlyContinue }
$null = robocopy (Join-Path $Pkg 'data\.dsh') (Join-Path $seedDir '.dsh') /E /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "seed 复制失败，退出码 $LASTEXITCODE" }

# ---------- [5] 密钥防泄漏 ----------
Step 5 '密钥防泄漏检查'
$mustRemove = @(
    (Join-Path $Pkg 'config\api-key.txt'),
    (Join-Path $Pkg 'data\.dsh\.credentials.yaml'),
    (Join-Path $Pkg 'data\.dsh\.anonymous-user-id'),
    (Join-Path $Pkg 'data\.dsh\.dshw-usage.json'),
    (Join-Path $Pkg 'data\.dsh\.dshw-turn.json'),
    (Join-Path $Pkg 'seed\.dsh\.credentials.yaml'),
    (Join-Path $Pkg 'seed\.dsh\.anonymous-user-id'),
    (Join-Path $Pkg 'seed\.dsh\.dshw-usage.json'),
    (Join-Path $Pkg 'seed\.dsh\.dshw-turn.json'),
    # 用户私人人设（本机 ~/.dsh/AGENTS.md）：便携包必须保持默认人设，绝不能带给同学
    (Join-Path $Pkg 'data\.dsh\AGENTS.md'),
    (Join-Path $Pkg 'data\.dsh\AGENTS.local.md'),
    (Join-Path $Pkg 'seed\.dsh\AGENTS.md'),
    (Join-Path $Pkg 'seed\.dsh\AGENTS.local.md'),
    (Join-Path $Pkg 'data\.dsh\CLAUDE.md'),
    (Join-Path $Pkg 'seed\.dsh\CLAUDE.md')
)
foreach ($f in $mustRemove) {
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force; Say "  已删除: $f" 'Yellow' }
}

# 取本机 key 作比对（只用于扫描，绝不会写进包）
$key = $null
$envFile = Join-Path $env:LOCALAPPDATA 'hermes\.env'
if (Test-Path -LiteralPath $envFile) {
    $line = Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*DEEPSEEK_API_KEY\s*=' } | Select-Object -First 1
    if ($line) { $key = ($line -replace '^\s*DEEPSEEK_API_KEY\s*=\s*', '').Trim().Trim('"').Trim("'") }
}

# 扫描范围：包自身文件 + data\.dsh 非 node_modules 部分（不含 node 运行时）
$scan = New-Object System.Collections.ArrayList
foreach ($d in @('config', 'launcher', 'bin', 'logs')) {
    $p = Join-Path $Pkg $d
    if (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { [void]$scan.Add($_) } }
}
Get-ChildItem -LiteralPath $Pkg -File -ErrorAction SilentlyContinue | ForEach-Object { [void]$scan.Add($_) }
$dshData = Join-Path $Pkg 'data\.dsh'
if (Test-Path -LiteralPath $dshData) {
    Get-ChildItem -LiteralPath $dshData -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
        ForEach-Object { [void]$scan.Add($_) }
}

$leak = @()
if ($key) {
    foreach ($f in $scan) {
        if ($f.Length -gt 8MB) { continue }
        if (Select-String -LiteralPath $f.FullName -SimpleMatch $key -Quiet -ErrorAction SilentlyContinue) { $leak += $f.FullName }
    }
}
$suspicious = @()
foreach ($f in $scan) {
    if ($f.Length -gt 8MB) { continue }
    if ($f.Extension -notin @('.json', '.yaml', '.yml', '.txt', '.env', '.ini', '.log')) { continue }
    if (Select-String -LiteralPath $f.FullName -Pattern 'sk-[A-Za-z0-9]{20,}' -Quiet -ErrorAction SilentlyContinue) { $suspicious += $f.FullName }
}

if ($leak.Count -gt 0) {
    Say "  ❌ 严重：检测到你的 API key 出现在以下文件，已中止打包！" 'Red'
    $leak | ForEach-Object { Say "     $_" 'Red' }
    throw '密钥泄漏检查未通过'
}
if ($suspicious.Count -gt 0) {
    Say "  ⚠ 发现 sk- 形态字符串（通常是文档示例，请人工确认）：" 'Yellow'
    $suspicious | ForEach-Object { Say "     $_" 'Yellow' }
}
Say '  ✓ 未发现密钥泄漏（config\api-key.txt 不存在，同学首次运行自行填写）' 'Green'

# 留一个说明占位
Set-Content -LiteralPath (Join-Path $Pkg 'config\请把密钥填在这里.txt') -Encoding UTF8 -Value @'
把你的 DeepSeek API 密钥放在本目录下的 api-key.txt 里（没有后缀的那个）。
更简单的做法：双击 "启动 DSH.vbs" → 点「设置密钥」→ 粘贴。
api-key.txt 由启动器自动创建，本文件可以删掉。
'@

# ---------- [6] 打包 ----------
if (-not $NoZip) {
    Step 6 '压缩为 zip'

    # 防呆：绝对不能在包里留符号链接/回退区。dsh 一跑就会自愈出
    # data\.dsh\profiles\node_modules 的一堆链接，而 tar 会跟进链接把目标内容
    # 一起装进去（包体积直接从 ~145MB 涨到 ~290MB）。发现就删掉重建。
    $linkArea = @(
        (Join-Path $Pkg 'data\.dsh\profiles\node_modules'),
        (Join-Path $Pkg 'seed\.dsh\profiles\node_modules')
    )
    foreach ($la in $linkArea) {
        if (Test-Path -LiteralPath $la) {
            Say "  发现回退链接区，正在清理: $la" 'Yellow'
            Get-ChildItem -LiteralPath $la -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
                ForEach-Object { try { $_.Delete() } catch { } }
            $left = @(Get-ChildItem -LiteralPath $la -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) { try { (Get-Item -LiteralPath $la -Force).Delete() } catch { } }
        }
    }
    $nLink = @(Get-ChildItem -LiteralPath $Pkg -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count
    if ($nLink -gt 0) { Say "  警告：包内仍有 $nLink 个符号链接，压缩包可能偏大" 'Yellow' }
    else { Say '  链接检查通过（0 个符号链接）' 'Green' }

    $zip = Join-Path $Out 'DSH-Portable.zip'
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path -LiteralPath $tar) {
        & $tar -a -c -f $zip -C $Out 'DSH-Portable'
        if ($LASTEXITCODE -ne 0) { throw "tar 打包失败，退出码 $LASTEXITCODE" }
    } else {
        Compress-Archive -Path $Pkg -DestinationPath $zip -CompressionLevel Optimal
    }
}

# ---------- 汇总 ----------
Say ''
Say '=== 打包完成 ===' 'Green'
$sz = (Get-ChildItem -LiteralPath $Pkg -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Say ("  目录: {0}" -f $Pkg)
Say ("  大小: {0:N0} MB" -f ($sz / 1MB))
$zip = Join-Path $Out 'DSH-Portable.zip'
if (Test-Path -LiteralPath $zip) { Say ("  压缩包: {0}  ({1:N0} MB)" -f $zip, ((Get-Item $zip).Length / 1MB)) }
Say ''
Say '  分发前请再确认：config\api-key.txt 不存在（只有占位 txt）'

# ============================================================
#  显式退出码
#  必须放在最后：打包过程中 robocopy / tar 成功时返回码是 1（"复制了文件"），
#  不是错误。GitHub Actions 会在 pwsh 步骤末尾自动追加 exit $LASTEXITCODE，
#  若不显式清零，一次完全成功的打包会被判定为失败。
#  真正的失败走上面的 throw（非 0 退出），不会被这行掩盖。
# ============================================================
exit 0
