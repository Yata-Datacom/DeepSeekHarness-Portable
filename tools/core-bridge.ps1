#  core-bridge.ps1 - machine-readable front-end for core.ps1
#
#  The C# launcher talks to the logic through this file, so the logic lives in
#  exactly one place (core.ps1). Every action prints one JSON object on stdout
#  and exits 0; expected failures are reported as {"ok":false,"error":...} instead
#  of a stack trace, so the UI can show a sentence rather than a red dump.
#
#  ASCII only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, and a Chinese
#  literal used functionally then silently matches nothing.
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('version','envcheck','preflight','conflicts','uninstall-items',
                 'shortcut-state','shortcut-create','shortcut-delete','shortcut-asked-set','port-plan',
                 'key-state','set-key','url','start','stop','uninstall','restore',
                 'force-reset','data-dir','open-web')]
    [string]$Action,
    [int]$Port = 0,
    [int]$TimeoutSec = 130,
    [string]$LogPath = '',
    [string]$Keys = '',
    [string]$Url = ''
)
$ErrorActionPreference = 'Stop'
# Emit UTF-8 on stdout: PS 5.1 otherwise encodes to the console codepage (GBK),
# so a C# caller reading UTF-8 sees mojibake instead of the Chinese messages.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$here = Split-Path -Parent $PSScriptRoot
. (Join-Path $here 'launcher\core.ps1')

function Emit($obj) { $obj | ConvertTo-Json -Depth 6 }

function Fail($msg) {
    Emit ([pscustomobject]@{ ok = $false; action = $Action; error = [string]$msg })
    exit 0
}

try {
    switch ($Action) {

        'version' {
            Emit ([pscustomobject]@{ ok = $true; api = 1; pkgRoot = $script:PkgRoot })
        }

        'envcheck' {
            Emit ([pscustomobject]@{ ok = $true; checks = @(Get-EnvCheck) })
        }

        'preflight' {
            $block = Get-PreflightBlock
            Emit ([pscustomobject]@{ ok = $true; blocked = [bool]$block; message = [string]$block })
        }

        'conflicts' {
            Emit ([pscustomobject]@{
                ok = $true; items = @(Get-ConflictReport); hasConflict = [bool](Test-HasConflict)
            })
        }

        # Tells the UI which port to use before it starts anything: the default one
        # if free; if it is taken by this very bundle, the cached token URL so the
        # UI can just reopen it; otherwise the next free port.
        'port-plan' {
            if ($Port -le 0) { $Port = $script:DefaultPort }
            $busy = -not (Test-PortFree $Port)
            $ours = $false
            $url  = ''
            if ($busy) {
                $op = Get-ListeningPid $Port
                try { $p = Get-Process -Id $op -ErrorAction Stop; if ($p.Path -eq $script:NodeExe) { $ours = $true } } catch { }
                if ($ours) { $url = [string](Get-DshUrlFromLog (Join-Path $script:LogDir 'web.log')) }
            }
            $use = $Port
            if ($busy -and -not $ours) { try { $use = Get-FreePort ($Port + 1) } catch { $use = 0 } }
            Emit ([pscustomobject]@{
                ok = $true; port = $use; defaultBusy = $busy; ours = $ours; cachedUrl = $url; free = ($use -gt 0)
            })
        }

        'uninstall-items' {
            Emit ([pscustomobject]@{ ok = $true; items = @(Get-UninstallItems) })
        }

        'shortcut-state' {
            Emit ([pscustomobject]@{
                ok       = $true
                exists   = [bool](Test-ShortcutExists)
                mine     = [bool](Test-ShortcutMine)
                asked    = [bool](Test-ShortcutAsked)
                path     = (Get-ShortcutPath)
            })
        }

        'shortcut-create' {
            $r = New-Shortcut
            Emit ([pscustomobject]@{ ok = $true; result = [string]$r })
        }

        'shortcut-delete' {
            $r = Remove-Shortcut
            Emit ([pscustomobject]@{ ok = $true; result = [string]$r })
        }

        'shortcut-asked-set' { Set-ShortcutAsked; Emit ([pscustomobject]@{ ok = $true }) }

        'key-state' {
            Emit ([pscustomobject]@{ ok = $true; configured = [bool](Test-ApiKey) })
        }

        # The key arrives on stdin, never as an argument: a command line is visible
        # to every other process on the machine.
        'set-key' {
            $key = [Console]::In.ReadToEnd()
            if ($key) { $key = $key.Trim() }
            if (-not $key -or $key.Length -lt 10) { Fail 'key too short' }
            Set-ApiKey $key
            Emit ([pscustomobject]@{ ok = $true; configured = [bool](Test-ApiKey) })
        }

        'url' {
            if (-not $LogPath) { $LogPath = Join-Path $script:LogDir 'web.log' }
            Emit ([pscustomobject]@{ ok = $true; url = [string](Get-DshUrlFromLog $LogPath) })
        }

        # Blocking: returns the token URL, or an explanatory error. The caller runs
        # this on a background thread and keeps its window responsive.
        'start' {
            if ($Port -le 0) { $Port = $script:DefaultPort }
            try {
                $u = Start-DshServer -Port $Port -TimeoutSec $TimeoutSec
                Emit ([pscustomobject]@{ ok = $true; port = $Port; url = [string]$u })
            } catch { Fail $_.Exception.Message }
        }

        'stop' {
            if ($Port -le 0) { $Port = $script:DefaultPort }
            Emit ([pscustomobject]@{ ok = $true; stopped = [bool](Stop-DshServer $Port) })
        }

        'uninstall' {
            $list = @()
            if ($Keys) { $list = $Keys -split ',' | Where-Object { $_ } | ForEach-Object { $_.Trim() } }
            if ($list.Count -eq 0) { Fail 'no keys selected' }
            $res = Invoke-Uninstall $list
            Emit ([pscustomobject]@{
                ok = $true; done = @($res.Done); failed = @($res.Failed)
            })
        }

        'restore' {
            if (-not (Test-Seed)) { Fail 'no seed template in this package' }
            Invoke-RestoreSeed | Out-Null
            Emit ([pscustomobject]@{ ok = $true })
        }

        # Same as restore, but tolerates a package without seed/ (then it clears).
        'force-reset' {
            $r = @()
            if (Test-Seed) { Invoke-RestoreSeed | Out-Null; $r += 'seed' }
            else {
                if (Remove-TreeSafe $script:DshHome) { $r += 'cleared' }
                Initialize-Dirs
            }
            Emit ([pscustomobject]@{ ok = $true; steps = $r })
        }

        'data-dir' {
            Emit ([pscustomobject]@{ ok = $true; path = $script:PkgRoot })
        }

        'open-web' {
            if (-not $Url) { Fail 'no url' }
            Open-WebUi $Url
            Emit ([pscustomobject]@{ ok = $true })
        }
    }
} catch {
    Fail $_.Exception.Message
}
exit 0
