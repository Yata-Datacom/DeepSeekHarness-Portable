# ============================================================
#  DSH 便携版 — 图形启动器（WinForms，无需任何依赖）
#  入口：双击 「启动 DSH.cmd」或 「DSH 启动器.vbs」
#  调试：powershell -File launcher.ps1 -Shot out.png  （渲染窗口截图后退出）
# ============================================================
param([string]$Shot = '')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'core.ps1')

Initialize-Dirs

# ---------- 图标 / 桌面快捷方式 ----------
$script:IconPath = Join-Path $script:PkgRoot 'assets\dsh-whale.ico'

function Ensure-DesktopShortcut {
    # 只在「桌面快捷方式本来就是本包建的」时重建；绝不凭空创建（不静默动用户桌面）
    try {
        if (Test-ShortcutMine) {
            Remove-Item -LiteralPath (Get-ShortcutPath) -Force -ErrorAction SilentlyContinue
            [void](New-Shortcut)
        }
    } catch { }
}

# ---------- 全局状态 ----------
$script:Starting = $false
$script:Timer = $null
$script:CurrentUrl = $null
$script:CurrentPort = $script:DefaultPort

# ---------- 窗体 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'DSH 便携版启动器  ·  DeepSeek Harness'
$form.Size = New-Object System.Drawing.Size(700, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 620)
$form.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 252)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
if (Test-Path -LiteralPath $script:IconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($script:IconPath) } catch { }
}

# 顶部标题
$title = New-Object System.Windows.Forms.Label
$title.Text = 'DeepSeek Harness'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(40, 60, 120)
$title.Location = New-Object System.Drawing.Point(20, 14)
$title.Size = New-Object System.Drawing.Size(420, 34)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = '便携版 · 免安装 · 自带运行环境 · 不修改系统设置'
$sub.ForeColor = [System.Drawing.Color]::Gray
$sub.Location = New-Object System.Drawing.Point(23, 48)
$sub.Size = New-Object System.Drawing.Size(460, 20)
$form.Controls.Add($sub)

# 检查列表
$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(20, 76)
$list.Size = New-Object System.Drawing.Size(645, 330)
$list.View = 'Details'
$list.FullRowSelect = $true
$list.GridLines = $false
$list.HeaderStyle = 'Nonclickable'
$list.MultiSelect = $false
[void]$list.Columns.Add('状态', 62)
[void]$list.Columns.Add('检查项', 120)
[void]$list.Columns.Add('说明', 440)
$form.Controls.Add($list)

# 进度条
$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(20, 414)
$bar.Size = New-Object System.Drawing.Size(645, 8)
$bar.Style = 'Continuous'
$bar.Minimum = 0
$bar.Maximum = 100
$bar.Value = 0
$form.Controls.Add($bar)

# 状态文字
$status = New-Object System.Windows.Forms.Label
$status.Text = '就绪'
$status.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 90)
$status.Location = New-Object System.Drawing.Point(20, 428)
$status.Size = New-Object System.Drawing.Size(645, 22)
$form.Controls.Add($status)

# 按钮
function New-Btn($text, $x, $w, $primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, 458)
    $b.Size = New-Object System.Drawing.Size($w, 40)
    $b.FlatStyle = 'Flat'
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    if ($primary) {
        $b.BackColor = [System.Drawing.Color]::FromArgb(64, 110, 220)
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 0
    } else {
        $b.BackColor = [System.Drawing.Color]::White
        $b.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 205)
    }
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(235, 240, 255)
    return $b
}

$btnStart = New-Btn '▶  启动 DSH' 20 150 $true
$btnCheck = New-Btn '环境自检' 180 100 $false
$btnKey = New-Btn '设置密钥' 290 100 $false
$btnData = New-Btn '数据目录' 400 100 $false
$btnStop = New-Btn '停止服务' 510 155 $false
$form.Controls.AddRange(@($btnStart, $btnCheck, $btnKey, $btnData, $btnStop))

# 第二排：卸载 / 还原 / 强制覆盖
function New-Btn2($text, $x, $w) {
    $b = New-Btn $text $x $w $false
    $b.Location = New-Object System.Drawing.Point($x, 506)
    return $b
}
$btnUninst  = New-Btn2 '干净卸载…' 20 130
$btnRestore = New-Btn2 '还原初始状态' 158 130
$btnForce   = New-Btn2 '强制覆盖…' 296 130
$btnShortcut = New-Btn2 '创建桌面快捷方式' 434 130
$btnForce.ForeColor = [System.Drawing.Color]::FromArgb(170, 40, 40)
$btnForce.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(210, 150, 150)
$form.Controls.AddRange(@($btnUninst, $btnRestore, $btnForce, $btnShortcut))

$hint = New-Object System.Windows.Forms.Label
$hint.Text = '绿色便携版：不写入系统、不改 PATH / 注册表 / 用户目录；所有操作只影响本文件夹。'
$hint.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 135)
$hint.Location = New-Object System.Drawing.Point(20, 556)
$hint.Size = New-Object System.Drawing.Size(645, 20)
$form.Controls.Add($hint)

# ---------- 检查刷新 ----------
function Update-Checks {
    $list.Items.Clear()
    foreach ($c in (Get-EnvCheck)) {
        $tag = switch ($c.State) { 'ok' { '✔  正常' } 'warn' { '⚠  注意' } default { '✖  失败' } }
        $item = New-Object System.Windows.Forms.ListViewItem($tag)
        [void]$item.SubItems.Add($c.Name)
        [void]$item.SubItems.Add($c.Detail)
        switch ($c.State) {
            'ok' { $item.ForeColor = [System.Drawing.Color]::FromArgb(30, 140, 70) }
            'warn' { $item.ForeColor = [System.Drawing.Color]::FromArgb(190, 130, 0) }
            default { $item.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40) }
        }
        [void]$list.Items.Add($item)
    }
    # 注意：Where-Object 过滤到 0 个结果时返回 $null，$null.Count 会报「找不到属性 Count」—— 必须用 @() 包一层
    $bad = @($list.Items | Where-Object { $_.Text -like '✖*' }).Count
    try { $btnShortcut.Text = if (Test-ShortcutMine) { '删除桌面快捷方式' } else { '创建桌面快捷方式' } } catch { }
    if ($bad -gt 0) { $status.Text = "自检完成：有 $bad 项失败（见上表）" }
    else { $status.Text = '自检完成：全部通过，可以启动' }
}

# ---------- 启动流程 ----------
function Start-Now {
    if ($script:Starting) { return }

    # 启动前预检：环境不满足就用大白话说明，别让同学对着一串报错发呆
    $block = $null
    try { $block = Get-PreflightBlock } catch { $block = $null }
    if ($block) {
        $status.Text = '无法启动：这台电脑不满足运行要求（详见弹窗）'
        [System.Windows.Forms.MessageBox]::Show(
            "无法启动 —— 这台电脑不满足运行要求：`n`n$block`n`n需要：64 位的 Windows 10 1809 (Build 17763) / Windows 11 及以上。",
            '无法启动', 'OK', 'Error') | Out-Null
        return
    }

    $port = $script:DefaultPort

    # 端口已被本便携版占用 -> 直接开浏览器
    if (-not (Test-PortFree $port)) {
        $op = Get-ListeningPid $port
        $ours = $false
        try { $p = Get-Process -Id $op -ErrorAction Stop; if ($p.Path -eq $script:NodeExe) { $ours = $true } } catch {}
        if ($ours) {
            $url = Get-DshUrlFromLog (Join-Path $script:LogDir 'web.log')
            if ($url) { Open-WebUi $url; $status.Text = '服务已在运行，已打开界面'; return }
            $status.Text = "服务已在运行（端口 $port），但读不到 token，请先点「停止服务」再启动"
            return
        }
        # 别人的程序占用 -> 换端口
        try { $port = Get-FreePort 3081 } catch { $status.Text = $_; return }
        $status.Text = "端口 3080 被占用，改用 $port"
    }

    # 密钥只做提示，不拦截启动：没密钥也能进网页界面，随时补填
    if (-not (Test-ApiKey)) {
        $status.Text = '提示：尚未配置 DeepSeek 密钥 —— 仍可启动，进界面后随时补填'
    }

    $script:Starting = $true
    $script:CurrentPort = $port
    $bar.Style = 'Marquee'
    $status.Text = "正在启动服务（首次启动约 30-60 秒，请稍候）..."
    $btnStart.Enabled = $false

    try {
        $log = Join-Path $script:LogDir 'web.log'
        if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
        Get-DshEnv
        $dshArgs = @($script:DshBin, 'web', '--no-open', '--port', "$port")
        Start-Process -FilePath $script:NodeExe `
            -ArgumentList $dshArgs `
            -WindowStyle Hidden `
            -RedirectStandardOutput $log `
            -RedirectStandardError (Join-Path $script:LogDir 'web.err.log') | Out-Null

        $script:WaitStart = [DateTime]::Now
        $script:Timer.Start()
    } catch {
        $script:Starting = $false
        $bar.Style = 'Continuous'; $bar.Value = 0
        $btnStart.Enabled = $true
        $status.Text = "启动失败：$_"
    }
}

# ---------- 轮询定时器 ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 900
$script:Timer = $timer
$timer.Add_Tick({
    $log = Join-Path $script:LogDir 'web.log'
    $url = Get-DshUrlFromLog $log
    if ($url) {
        $timer.Stop()
        $script:CurrentUrl = $url
        $bar.Style = 'Continuous'; $bar.Value = 100
        $script:Starting = $false
        $btnStart.Enabled = $true
        $status.Text = '启动成功，正在打开界面...'
        Open-WebUi $url
        $status.Text = "已启动：$url"
        return
    }
    $el = ([DateTime]::Now - $script:WaitStart).TotalSeconds
    $status.Text = "正在启动服务... 已等待 $([int]$el) 秒"
    if ($el -gt 150) {
        $timer.Stop()
        $script:Starting = $false
        $bar.Style = 'Continuous'; $bar.Value = 0
        $btnStart.Enabled = $true
        $err = ''
        if (Test-Path -LiteralPath (Join-Path $script:LogDir 'web.err.log')) {
            $err = (Get-Content -LiteralPath (Join-Path $script:LogDir 'web.err.log') -Tail 6) -join "`n"
        }
        $status.Text = '启动超时'
        [System.Windows.Forms.MessageBox]::Show("启动超过 150 秒仍未就绪。`n`n错误输出：`n$err", '启动超时', 'OK', 'Error') | Out-Null
    }
})

# ---------- 事件 ----------
$btnStart.Add_Click({ Start-Now })

$btnCheck.Add_Click({
    $status.Text = '正在自检...'
    $form.Refresh()
    Update-Checks
})

$btnKey.Add_Click({
    $kf = New-Object System.Windows.Forms.Form
    $kf.Text = '设置 DeepSeek API 密钥'
    $kf.Size = New-Object System.Drawing.Size(480, 220)
    $kf.StartPosition = 'CenterParent'
    $kf.FormBorderStyle = 'FixedDialog'
    $kf.MaximizeBox = $false; $kf.MinimizeBox = $false
    $kf.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $lb = New-Object System.Windows.Forms.Label
    $lb.Text = "粘贴你的 DeepSeek API 密钥（sk- 开头），只保存在本文件夹的`nconfig\api-key.txt 里，不会上传任何地方。"
    $lb.Location = New-Object System.Drawing.Point(16, 14)
    $lb.Size = New-Object System.Drawing.Size(440, 40)
    $kf.Controls.Add($lb)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(16, 60)
    $tb.Size = New-Object System.Drawing.Size(440, 26)
    $tb.UseSystemPasswordChar = $true
    $existing = Get-ApiKey
    if ($existing) { $tb.Text = $existing }
    $kf.Controls.Add($tb)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = '显示密钥'
    $chk.Location = New-Object System.Drawing.Point(16, 92)
    $chk.Size = New-Object System.Drawing.Size(100, 24)
    $chk.Add_CheckedChanged({ $tb.UseSystemPasswordChar = -not $chk.Checked })
    $kf.Controls.Add($chk)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = '保存'; $ok.Location = New-Object System.Drawing.Point(250, 128); $ok.Size = New-Object System.Drawing.Size(100, 32)
    $ok.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.Location = New-Object System.Drawing.Point(360, 128); $cancel.Size = New-Object System.Drawing.Size(96, 32)
    $cancel.DialogResult = 'Cancel'
    $kf.Controls.AddRange(@($ok, $cancel))
    $kf.AcceptButton = $ok; $kf.CancelButton = $cancel

    if ($kf.ShowDialog($form) -eq 'OK') {
        $v = $tb.Text.Trim()
        if ($v.Length -lt 10) { $status.Text = '密钥太短，未保存' }
        else {
            Set-ApiKey $v
            $status.Text = '密钥已保存到 config\api-key.txt'
            Update-Checks
        }
    }
})

$btnData.Add_Click({ Start-Process explorer.exe $script:PkgRoot })

$btnStop.Add_Click({
    if (Stop-DshServer $script:CurrentPort) { $status.Text = '服务已停止' }
    else { $status.Text = '没有由本便携版启动的服务' }
})

# ---------- 干净卸载 ----------
$btnUninst.Add_Click({
    $items = @(Get-UninstallItems)
    $uf = New-Object System.Windows.Forms.Form
    $uf.Text = '干净卸载 —— 只清理本便携版自己的文件'
    $uf.Size = New-Object System.Drawing.Size(620, 430)
    $uf.StartPosition = 'CenterParent'
    $uf.FormBorderStyle = 'FixedDialog'
    $uf.MaximizeBox = $false; $uf.MinimizeBox = $false
    $uf.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = "勾选要清理的项目。`n绝对不动系统里的东西：不改 PATH、不动 %USERPROFILE%\.dsh、不卸载任何已装软件。"
    $tip.Location = New-Object System.Drawing.Point(14, 10)
    $tip.Size = New-Object System.Drawing.Size(580, 42)
    $uf.Controls.Add($tip)

    $clist = New-Object System.Windows.Forms.CheckedListBox
    $clist.Location = New-Object System.Drawing.Point(14, 56)
    $clist.Size = New-Object System.Drawing.Size(580, 250)
    $clist.CheckOnClick = $true
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $txt = if ($it.Exists) { "$($it.Name)  ——  $($it.Detail)" } else { "$($it.Name)  ——  （不存在，跳过）" }
        [void]$clist.Items.Add($txt, $it.Exists)
    }
    $uf.Controls.Add($clist)

    $okU = New-Object System.Windows.Forms.Button
    $okU.Text = '执行清理'; $okU.Location = New-Object System.Drawing.Point(360, 322); $okU.Size = New-Object System.Drawing.Size(110, 34)
    $noU = New-Object System.Windows.Forms.Button
    $noU.Text = '取消'; $noU.Location = New-Object System.Drawing.Point(484, 322); $noU.Size = New-Object System.Drawing.Size(110, 34)
    $noU.DialogResult = 'Cancel'
    $uf.Controls.AddRange(@($okU, $noU))
    $uf.CancelButton = $noU

    $okU.Add_Click({
        $chosen = @()
        foreach ($idx in $clist.CheckedIndices) { $chosen += $items[$idx].Key }
        if ($chosen.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('没有勾选任何项目。', '提示', 'OK', 'Information') | Out-Null
            return
        }
        $warn = "将清理 $(($chosen | ForEach-Object { $_ }) -join '、')。"
        if ($chosen -contains 'data')   { $warn += "`n`n· 会删除全部会话记录、工作区、主题设置" }
        if ($chosen -contains 'key')    { $warn += "`n`n· 会删除已保存的 API 密钥，下次要重新填" }
        if ($chosen -contains 'folder') { $warn += "`n`n· 会删除整个便携版文件夹，无法恢复" }
        if ([System.Windows.Forms.MessageBox]::Show($warn + "`n`n确定继续吗？", '确认清理', 'YesNo', 'Warning') -ne 'Yes') { return }
        $res = Invoke-Uninstall $chosen
        $msg = '已清理：' + ($res.Done -join '、')
        if ($res.Failed.Count -gt 0) { $msg += "`n`n未能清理：`n" + ($res.Failed -join "`n") }
        [System.Windows.Forms.MessageBox]::Show($msg, '清理完成', 'OK', 'Information') | Out-Null
        $uf.Close()
    })
    [void]$uf.ShowDialog($form)
    Update-Checks
})

# ---------- 还原初始状态 ----------
$btnRestore.Add_Click({
    if (-not (Test-Seed)) {
        [System.Windows.Forms.MessageBox]::Show('本包没有初始模板（seed\.dsh），无法还原。', '无模板', 'OK', 'Warning') | Out-Null
        return
    }
    $m = "将把 data\.dsh 还原成刚解压时的状态：`n`n  · 现有会话记录、工作区、主题设置会被替换`n  · 已保存的 API 密钥不受影响`n  · 系统里的东西完全不动`n`n继续吗？"
    if ([System.Windows.Forms.MessageBox]::Show($m, '还原初始状态', 'YesNo', 'Warning') -ne 'Yes') { return }
    $status.Text = '正在还原...'
    $form.Refresh()
    try {
        Invoke-RestoreSeed | Out-Null
        $status.Text = '已还原到初始状态（插件与主题已恢复）'
    } catch { $status.Text = "还原失败：$_" }
    Update-Checks
})

# ---------- 强制覆盖（三重确认） ----------
$btnForce.Add_Click({
    $conf = @(Get-ConflictReport | Where-Object { $_.Severity -eq 'conflict' })
    $detail = if ($conf.Count -gt 0) { ($conf | ForEach-Object { '  · ' + $_.Detail }) -join "`n" } else { '  · 当前没有检测到硬冲突' }

    # 1/3
    $m1 = "强制覆盖 = 重置本便携版的数据：`n`n  · data\.dsh（会话 / 工作区 / 主题设置）`n  · 桌面快捷方式`n`n当前检测到的冲突：`n$detail`n`n本操作【不会】碰系统里的 dsh、PATH、注册表、用户目录。`n`n（第 1/3 次确认）继续吗？"
    if ([System.Windows.Forms.MessageBox]::Show($m1, '强制覆盖 · 1/3', 'YesNo', 'Warning') -ne 'Yes') { return }

    # 2/3
    $m2 = "第 2/3 次确认：`n`ndata\.dsh 里的现有会话记录、工作区、主题设置会被【永久删除】，无法恢复。`n`n确定要继续吗？"
    if ([System.Windows.Forms.MessageBox]::Show($m2, '强制覆盖 · 2/3', 'YesNo', 'Warning') -ne 'Yes') { return }

    # 3/3 手动输入
    $cf = New-Object System.Windows.Forms.Form
    $cf.Text = '强制覆盖 · 3/3'
    $cf.Size = New-Object System.Drawing.Size(470, 230)
    $cf.StartPosition = 'CenterParent'
    $cf.FormBorderStyle = 'FixedDialog'
    $cf.MaximizeBox = $false; $cf.MinimizeBox = $false
    $cf.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = '最后一次确认：请在下面输入「覆盖」两个字。'
    $l1.Location = New-Object System.Drawing.Point(16, 16)
    $l1.Size = New-Object System.Drawing.Size(430, 24)
    $cf.Controls.Add($l1)

    $t1 = New-Object System.Windows.Forms.TextBox
    $t1.Location = New-Object System.Drawing.Point(16, 48)
    $t1.Size = New-Object System.Drawing.Size(430, 26)
    $cf.Controls.Add($t1)

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = '执行内容：清空并按包内初始模板还原 data\.dsh，重建桌面快捷方式。'
    $l2.ForeColor = [System.Drawing.Color]::Gray
    $l2.Location = New-Object System.Drawing.Point(16, 82)
    $l2.Size = New-Object System.Drawing.Size(430, 36)
    $cf.Controls.Add($l2)

    $okF = New-Object System.Windows.Forms.Button
    $okF.Text = '确认覆盖'; $okF.Location = New-Object System.Drawing.Point(216, 138); $okF.Size = New-Object System.Drawing.Size(110, 32)
    $okF.DialogResult = 'OK'
    $noF = New-Object System.Windows.Forms.Button
    $noF.Text = '取消'; $noF.Location = New-Object System.Drawing.Point(336, 138); $noF.Size = New-Object System.Drawing.Size(110, 32)
    $noF.DialogResult = 'Cancel'
    $cf.Controls.AddRange(@($okF, $noF))
    $cf.AcceptButton = $okF; $cf.CancelButton = $noF

    if ($cf.ShowDialog($form) -ne 'OK') { return }
    if ($t1.Text.Trim() -ne '覆盖') {
        [System.Windows.Forms.MessageBox]::Show('输入不匹配，已取消（未做任何改动）。', '已取消', 'OK', 'Information') | Out-Null
        return
    }

    $status.Text = '正在强制覆盖...'
    $form.Refresh()
    $r = @()
    try {
        if (Test-Seed) { Invoke-RestoreSeed | Out-Null; $r += 'data\.dsh 已按初始模板还原' }
        else {
            if (Remove-TreeSafe $script:DshHome) { $r += 'data\.dsh 已清空（本包无初始模板）' }
            Initialize-Dirs
        }
        try {
            if (Test-ShortcutMine) { [void](New-Shortcut); $r += '桌面快捷方式已重建' }
            else { $r += '桌面快捷方式保持原样（你当初没创建）' }
        } catch { $r += '桌面快捷方式未处理' }
        $status.Text = '强制覆盖完成：' + ($r -join '；')
    } catch { $status.Text = "强制覆盖失败：$_" }
    Update-Checks
})

# ---------- 桌面快捷方式（可选） ----------
$btnShortcut.Add_Click({
    try {
        if (Test-ShortcutMine) {
            $r = [System.Windows.Forms.MessageBox]::Show(
                "要删除桌面上的「DSH 便携版」快捷方式吗？`n`n只删这一个快捷方式，不影响程序本体和你的聊天数据。",
                '删除桌面快捷方式', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            [void](Remove-Shortcut)
            $status.Text = '已删除桌面快捷方式'
        } else {
            $res = New-Shortcut
            if ($res -eq 'created') { $status.Text = '已在桌面创建快捷方式' }
            else { $status.Text = '桌面已有指向本包的快捷方式' }
        }
    } catch { $status.Text = "操作未完成：$_" }
    Update-Checks
})

$form.Add_Shown({
    $status.Text = '正在自检...'
    $form.Refresh()
    try { Update-Checks } catch { $status.Text = "自检出错：$($_.Exception.Message)" }

    # 启动前预检：不满足就当场讲清楚（截图模式跳过弹窗）
    $block = $null
    try { $block = Get-PreflightBlock } catch { $block = $null }
    if ($block) {
        $status.Text = '环境不满足运行要求 —— 点「启动 DSH」可看到详细原因'
        if (-not $Shot) {
            [System.Windows.Forms.MessageBox]::Show(
                "这台电脑目前无法运行本便携版：`n`n$block`n`n（本包需要：64 位的 Windows 10 1809 / Windows 11 及以上）",
                '环境检查未通过', 'OK', 'Warning') | Out-Null
        }
    }

    # 首次运行问一次：要不要桌面快捷方式（不静默创建）；-Shot 截图模式跳过，避免卡住
    if (-not $Shot -and -not (Test-ShortcutAsked)) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "要不要在桌面放一个启动快捷方式？`n`n不创建也完全不影响使用，`n以后随时可以在启动器里点「创建桌面快捷方式」。",
            '快捷方式（可选）', 'YesNo', 'Question')
        if ($r -eq 'Yes') {
            try {
                if ((New-Shortcut) -eq 'created') { $status.Text = '已在桌面创建快捷方式' }
                else { $status.Text = '桌面已有指向本包的快捷方式' }
            } catch { $status.Text = "未创建：$_" }
        } else {
            $status.Text = '已跳过桌面快捷方式（随时可在启动器里创建）'
        }
        Set-ShortcutAsked
        Update-Checks
    }

    if ($Shot) {
        try {
            $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
            $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        } catch {
            try { Set-Content -LiteralPath ($Shot + '.err.txt') -Value ("$($_.Exception.GetType().Name): $($_.Exception.Message)") -Encoding UTF8 } catch { }
        }
        $form.Close()
    }
})

[void]$form.ShowDialog()
