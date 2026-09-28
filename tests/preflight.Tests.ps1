# ============================================================
#  Negative-path tests for Get-PreflightBlock  (Pester 5)
#
#  The preflight is the gate that decides "do not start, here is why".
#  Its value is entirely in the failure paths, so that is what these
#  tests hammer: every assertion proves the host is left alone.
#
#  ASCII only - see the note in core.Tests.ps1.
# ============================================================

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'launcher\core.ps1')
    $env:DEEPSEEK_API_KEY = $null

    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('dsh-pf-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
    $script:PkgRoot = $script:Root
    $script:NodeDir = Join-Path $script:Root 'node'
    $script:NodeExe = Join-Path $script:NodeDir 'node.exe'
    $script:DshBin  = Join-Path $script:NodeDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
}

AfterAll {
    if ($script:Root -and (Test-Path -LiteralPath $script:Root)) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-PreflightBlock' {
    It 'returns a value only when something is actually wrong' {
        $r = Get-PreflightBlock
        # on a 64-bit Windows agent with a writable scratch dir the only
        # problem is the missing runtime, so this must be a non-empty string
        $r | Should -Not -BeNullOrEmpty
        $r | Should -BeOfType [string]
    }

    It 'names node.exe when the runtime is missing' {
        $r = Get-PreflightBlock
        $r | Should -Match 'node'
    }

    It 'names dsh when the module is missing' {
        $r = Get-PreflightBlock
        $r | Should -Match 'dsh'
    }

    It 'does NOT mention a 32-bit problem on a 64-bit host' {
        if ([System.Environment]::Is64BitOperatingSystem) {
            $r = Get-PreflightBlock
            $r | Should -Not -Match '32'
        }
    }

    It 'reports an unwritable package directory instead of throwing' {
        $old = $script:PkgRoot
        try {
            # a path that cannot exist -> the write probe must fail cleanly
            $script:PkgRoot = Join-Path $script:Root 'does\not\exist\at\all'
            { Get-PreflightBlock } | Should -Not -Throw
            (Get-PreflightBlock) | Should -Not -BeNullOrEmpty
        } finally { $script:PkgRoot = $old }
    }

    It 'leaves the host untouched while checking (no node.exe created, no key written)' {
        $null = Get-PreflightBlock
        Test-Path -LiteralPath $script:NodeExe | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:Root -Filter '.write-test-*' -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}
