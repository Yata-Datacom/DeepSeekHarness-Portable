# ============================================================
#  Unit tests for launcher/core.ps1  (Pester 5)
#
#  These cover the "returns data, touches nothing" half of core.ps1:
#  every function here can be pointed at a scratch package root and
#  asserted on without starting anything.
#
#  ASCII only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
#  and a Chinese literal used functionally silently matches nothing.
#  The product's Chinese user-facing strings are therefore matched
#  structurally (ASCII substrings / property names), never literally.
#
#  Run:  Invoke-Pester -Path tests -Output Detailed
# ============================================================

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'launcher\core.ps1')

    # never let the host's own key leak into an assertion
    $env:DEEPSEEK_API_KEY = $null

    # scratch package root - nothing here may touch the real one
    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('dsh-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    foreach ($d in @('config', 'logs', 'data\.dsh\profiles\web', 'seed')) {
        New-Item -ItemType Directory -Path (Join-Path $script:Root $d) -Force | Out-Null
    }
    # repoint every path core.ps1 derived from its own location
    $script:PkgRoot = $script:Root
    $script:CfgDir  = Join-Path $script:Root 'config'
    $script:KeyFile = Join-Path $script:CfgDir 'api-key.txt'
    $script:LogDir  = Join-Path $script:Root 'logs'
    $script:DshHome = Join-Path $script:Root 'data\.dsh'
    $script:PrfDir  = Join-Path $script:DshHome 'profiles\web'
    $script:NodeDir = Join-Path $script:Root 'node'
    $script:NodeExe = Join-Path $script:NodeDir 'node.exe'
    $script:DshBin  = Join-Path $script:NodeDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
    $script:DefaultPort = 3098          # never assume 3080 is ours on a build agent
}

AfterAll {
    if ($script:Root -and (Test-Path -LiteralPath $script:Root)) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'API key handling' {
    It 'is invalid when nothing is configured' {
        Remove-Item -LiteralPath $script:KeyFile -Force -ErrorAction SilentlyContinue
        Test-ApiKey | Should -BeFalse
    }
    It 'rejects a key that is too short' {
        Set-ApiKey 'sk-short'
        Test-ApiKey | Should -BeFalse
    }
    It 'rejects a long string without the sk- prefix' {
        Set-ApiKey ('x' * 40)
        Test-ApiKey | Should -BeFalse
    }
    It 'accepts an sk- key of at least 20 chars' {
        Set-ApiKey ('sk-' + 'a' * 30)
        Test-ApiKey | Should -BeTrue
    }
    It 'reads the key back verbatim' {
        Set-ApiKey 'sk-roundtrip-0123456789'
        Get-ApiKey | Should -Be 'sk-roundtrip-0123456789'
    }
}

Describe 'Port helpers' {
    It 'reports a port that nothing listens on as free' {
        Test-PortFree 3097 | Should -BeTrue
    }
    It 'reports a port that is being listened on as busy' {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 3097)
        $l.Start()
        try {
            Test-PortFree 3097 | Should -BeFalse
            Get-ListeningPid 3097 | Should -BeGreaterThan 0
        } finally { $l.Stop() }
    }
    It 'returns the first free port in the requested window' {
        Get-FreePort -Start 3090 -Max 3096 | Should -Be 3090
    }
    It 'throws when the whole window is occupied' {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 3095)
        $l.Start()
        try {
            { Get-FreePort -Start 3095 -Max 3095 } | Should -Throw
        } finally { $l.Stop() }
    }
}

Describe 'Get-DshUrlFromLog' {
    It 'returns null for a missing file' {
        Get-DshUrlFromLog (Join-Path $script:Root 'nope.log') | Should -BeNullOrEmpty
    }
    It 'returns null when the log has no token url' {
        $f = Join-Path $script:Root 'plain.log'
        Set-Content -LiteralPath $f -Value 'dsh web: starting up' -Encoding ASCII
        Get-DshUrlFromLog $f | Should -BeNullOrEmpty
    }
    It 'extracts the token url' {
        $f = Join-Path $script:Root 'web.log'
        Set-Content -LiteralPath $f -Encoding ASCII -Value @(
            'booting',
            'dsh web: http://127.0.0.1:3080/?token=AbC-123_xyz',
            'ready')
        Get-DshUrlFromLog $f | Should -Be 'http://127.0.0.1:3080/?token=AbC-123_xyz'
    }
}

Describe 'Get-UninstallItems' {
    BeforeAll { $script:Items = @(Get-UninstallItems) }
    It 'offers the five expected cleanup targets' {
        $script:Items.Count | Should -Be 5
        ($script:Items.Key -join ',') | Should -Be 'shortcut,key,data,logs,folder'
    }
    It 'reports existence per item without deleting anything' {
        foreach ($i in $script:Items) { $i.PSObject.Properties.Name | Should -Contain 'Exists' }
        Test-Path -LiteralPath $script:Root | Should -BeTrue
    }
}

Describe 'Get-ConflictReport' {
    It 'never reports a hard conflict in a pristine scratch package' {
        $c = @(Get-ConflictReport)
        @($c | Where-Object { $_.Severity -eq 'conflict' }).Count | Should -Be 0
        foreach ($i in $c) { $i.Severity | Should -BeIn @('info', 'conflict') }
    }
    It 'explains that a pre-existing package data dir is kept, not overwritten' {
        Set-Content -LiteralPath (Join-Path $script:DshHome 'marker.txt') -Value 'x' -Encoding ASCII
        $c = @(Get-ConflictReport)
        @($c | Where-Object { $_.Detail -match 'data' }).Count | Should -BeGreaterThan 0
    }
    It 'flags a foreign listener on the default port as a conflict' {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $script:DefaultPort)
        $l.Start()
        try {
            $c = @(Get-ConflictReport)
            @($c | Where-Object { $_.Severity -eq 'conflict' }).Count | Should -BeGreaterThan 0
        } finally { $l.Stop() }
    }
}

Describe 'Test-Seed' {
    It 'is false when the pristine template is missing' {
        Test-Seed | Should -BeFalse
    }
    It 'is true once seed\.dsh exists' {
        New-Item -ItemType Directory -Path (Join-Path $script:Root 'seed\.dsh') -Force | Out-Null
        Test-Seed | Should -BeTrue
    }
}

Describe 'Get-EnvCheck' {
    BeforeAll {
        # a profile whose package.json lists the three shipped plugins
        $pj = Join-Path $script:PrfDir 'package.json'
        Set-Content -LiteralPath $pj -Encoding UTF8 -Value (@{
            name = 'dsh-profile-web'
            dependencies = @{
                'dsh-whale-galgame' = '0.4.1'
                'dsh-whale-widget'  = '0.3.11'
                'open-sea-skin'     = '1.2.3'
            }
        } | ConvertTo-Json -Depth 5)
    }
    It 'returns structured checks with valid states' {
        $checks = @(Get-EnvCheck)
        $checks.Count | Should -BeGreaterThan 5
        foreach ($c in $checks) {
            $c.PSObject.Properties.Name | Should -Contain 'Name'
            $c.PSObject.Properties.Name | Should -Contain 'State'
            $c.State | Should -BeIn @('ok', 'warn', 'fail')
        }
    }
    It 'detects the shipped plugins from the profile package.json' {
        $c = @(Get-EnvCheck | Where-Object { $_.Name -match 'plugin' -or $_.Detail -match 'open-sea-skin' })
        @($c | Where-Object { $_.Detail -match 'open-sea-skin' }).Count | Should -BeGreaterThan 0
    }
    It 'warns (not fails) when the API key is absent' {
        Remove-Item -LiteralPath $script:KeyFile -Force -ErrorAction SilentlyContinue
        # the check is named with Chinese text; build it from code points so this
        # file stays pure ASCII (PS 5.1 would misread a literal as ANSI and match nothing)
        $keyName = [string]([char]0x5BC6) + [string]([char]0x94A5)
        $c = @(Get-EnvCheck | Where-Object { $_.Name -like ('*' + $keyName + '*') })
        $c.Count | Should -BeGreaterThan 0
        @($c | Where-Object { $_.State -eq 'fail' }).Count | Should -Be 0
    }
    It 'fails the node runtime check when node.exe is absent' {
        $c = @(Get-EnvCheck | Where-Object { $_.State -eq 'fail' -and $_.Detail -match 'node' })
        $c.Count | Should -BeGreaterThan 0
    }
}
